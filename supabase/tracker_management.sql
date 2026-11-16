-- Tracker administration is independent of whether an Action Plan exists.
create table private.tracker_administrators(user_id uuid primary key references auth.users(id));
create table private.tracker_owners(participant_id uuid primary key references public.participants(id),user_id uuid not null references auth.users(id));
insert into private.tracker_administrators select distinct coordinator_user_id from public.team_consultations on conflict do nothing;
insert into private.tracker_owners select participant_id,coordinator_user_id from public.team_consultations on conflict do nothing;
create table private.tracker_periods(
 id uuid primary key default gen_random_uuid(), participant_id uuid not null references public.participants(id),
 label text not null check(length(label) between 1 and 120),start_date date not null,end_date date not null,
 checkpoints text[] not null,weekdays integer[] not null default array[1,2,3,4,5],home_expected boolean not null default true,
 excluded_dates date[] not null default '{}',created_at timestamptz not null default now(),
 check(end_date>=start_date and end_date-start_date<=730),
 check(cardinality(checkpoints) between 1 and 3 and checkpoints <@ array['mid_morning','pre_lunch','end_of_day']),
 check(cardinality(weekdays) between 1 and 7 and weekdays <@ array[1,2,3,4,5,6,7])
);
create index tracker_periods_participant on private.tracker_periods(participant_id,start_date);
create table private.tracker_save_history(
 id bigint generated always as identity primary key,participant_id uuid not null references public.participants(id),
 tracking_date date not null,section text not null,actor_id uuid references auth.users(id),saved_at timestamptz not null default clock_timestamp(),
 operation text not null,snapshot jsonb not null
);
create index tracker_save_history_participant on private.tracker_save_history(participant_id,tracking_date);
alter table private.tracker_administrators enable row level security;
alter table private.tracker_owners enable row level security;
alter table private.tracker_periods enable row level security;
alter table private.tracker_save_history enable row level security;
revoke all on private.tracker_administrators,private.tracker_owners,private.tracker_periods,private.tracker_save_history from public,anon,authenticated;

create function private.tracker_owner(pid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from private.tracker_owners o join public.participant_access a on a.participant_id=o.participant_id and a.user_id=o.user_id where o.participant_id=pid and o.user_id=auth.uid() and a.can_view);
$$;
create function private.tracker_actor(uid uuid) returns text language sql stable security definer set search_path='' as $$
 select coalesce(n.display_name,split_part(u.email,'@',1)) from auth.users u left join private.consultation_names n on n.email=lower(u.email) where u.id=uid;
$$;
revoke all on function private.tracker_owner(uuid),private.tracker_actor(uuid) from public,anon,authenticated;

create function private.capture_tracker_save() returns trigger language plpgsql security definer set search_path='' as $$
declare pid uuid; dt date; section_name text;
begin
 if tg_table_name='tracker_days' then
  if tg_op='INSERT' and coalesce(new.sleep,new.breakfast,new.home_morning,new.medication_status,new.parent_comment,new.morning_completed_by) is null then return new; end if;
  if tg_op='UPDATE' and row(new.sleep,new.breakfast,new.home_morning,new.medication_status,new.parent_comment,new.morning_completed_by) is not distinct from row(old.sleep,old.breakfast,old.home_morning,old.medication_status,old.parent_comment,old.morning_completed_by) then return new; end if;
  pid:=new.participant_id;dt:=new.tracking_date;section_name:='home';
 else
  select participant_id,tracking_date into pid,dt from public.tracker_days where id=new.tracker_day_id;
  section_name:=case when tg_table_name='school_checkpoints' then to_jsonb(new)->>'checkpoint' else 'incident' end;
 end if;
 insert into private.tracker_save_history(participant_id,tracking_date,section,actor_id,operation,snapshot) values(pid,dt,section_name,auth.uid(),tg_op,to_jsonb(new));
 return new;
end; $$;
revoke all on function private.capture_tracker_save() from public,anon,authenticated;
create trigger tracker_section_history after insert or update on public.tracker_days for each row execute function private.capture_tracker_save();
create trigger checkpoint_section_history after insert or update on public.school_checkpoints for each row execute function private.capture_tracker_save();
create trigger incident_section_history after insert or update on public.incidents for each row execute function private.capture_tracker_save();

create function private.tracker_admin_clients() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 return jsonb_build_object('can_create',exists(select 1 from private.tracker_administrators where user_id=auth.uid()),'clients',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from private.tracker_owners o join public.participants p on p.id=o.participant_id where p.active and private.tracker_owner(p.id)),'[]'::jsonb));
end; $$;
create function private.tracker_create_client(p_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare pid uuid;
begin
 if auth.uid() is null or not exists(select 1 from private.tracker_administrators where user_id=auth.uid()) then raise exception 'Tracker administrator required' using errcode='42501'; end if;
 if length(trim(p_name)) not between 1 and 120 then raise exception 'Enter a client display name (1–120 characters)'; end if;
 insert into public.participants(display_name) values(trim(p_name)) returning id into pid;
 insert into public.participant_access(participant_id,user_id,access_role,can_view,can_write) values(pid,auth.uid(),'clinician',true,true);
 insert into private.tracker_owners values(pid,auth.uid());
 return pid;
end; $$;
create function private.tracker_save_period(p_participant uuid,p_label text,p_start date,p_end date,p_checkpoints text[],p_weekdays integer[],p_home boolean,p_excluded date[] default '{}',p_id uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if not private.tracker_owner(p_participant) then raise exception 'Tracker coordinator required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtext(p_participant::text));
 if p_id is not null and not exists(select 1 from private.tracker_periods where id=p_id and participant_id=p_participant) then raise exception 'Period not found'; end if;
 if exists(select 1 from private.tracker_periods where participant_id=p_participant and (p_id is null or id<>p_id) and start_date<=p_end and end_date>=p_start) then raise exception 'Monitoring periods cannot overlap; end the earlier period first'; end if;
 if exists(select 1 from unnest(p_excluded) d where d<p_start or d>p_end) then raise exception 'Excluded dates must fall within this period'; end if;
 if p_id is null then
 insert into private.tracker_periods(participant_id,label,start_date,end_date,checkpoints,weekdays,home_expected,excluded_dates) values(p_participant,trim(p_label),p_start,p_end,p_checkpoints,p_weekdays,p_home,coalesce(p_excluded,'{}')) returning id into result;
 else
 update private.tracker_periods set label=trim(p_label),start_date=p_start,end_date=p_end,checkpoints=p_checkpoints,weekdays=p_weekdays,home_expected=p_home,excluded_dates=coalesce(p_excluded,'{}') where id=p_id returning id into result;
 end if;
 return result;
end; $$;
create function private.tracker_schedule(p_participant uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.participant_access where participant_id=p_participant and user_id=auth.uid() and can_view) then raise exception 'Participant access required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(p) order by start_date) from private.tracker_periods p where participant_id=p_participant),'[]'::jsonb);
end; $$;
create function private.tracker_admin_data(p_participant uuid,p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.tracker_owner(p_participant) then raise exception 'Tracker coordinator required' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>730 then raise exception 'Choose a date range of up to two years'; end if;
 return jsonb_build_object(
 'periods',private.tracker_schedule(p_participant),
 'days',coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('saved_by',private.tracker_actor(d.updated_by),'checkpoints',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('saved_by',private.tracker_actor(s.updated_by))) from public.school_checkpoints s where s.tracker_day_id=d.id),'[]'::jsonb),'incidents',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('saved_by',private.tracker_actor(i.updated_by))) from public.incidents i where i.tracker_day_id=d.id),'[]'::jsonb)) order by tracking_date) from public.tracker_days d where d.participant_id=p_participant and d.tracking_date between p_from and p_to),'[]'::jsonb),
 'history',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'date',h.tracking_date,'section',h.section,'author',private.tracker_actor(h.actor_id),'saved_at',h.saved_at,'operation',h.operation,'snapshot',h.snapshot) order by h.saved_at desc) from private.tracker_save_history h where h.participant_id=p_participant and h.tracking_date between p_from and p_to),'[]'::jsonb),
 'team',coalesce((select jsonb_agg(t) from (select a.user_id,private.tracker_actor(a.user_id) as name,u.email,a.access_role,a.can_write from public.participant_access a join auth.users u on u.id=a.user_id where a.participant_id=p_participant and a.can_view union all select null::uuid,coalesce(n.display_name,split_part(p.email,'@',1)),p.email,p.access_role,p.can_write from private.pending_participant_access p left join private.consultation_names n on n.email=lower(p.email) where p.participant_id=p_participant and p.can_view and not exists(select 1 from auth.users u join public.participant_access a on a.user_id=u.id where lower(u.email)=lower(p.email) and a.participant_id=p.participant_id)) t),'[]'::jsonb));
end; $$;

-- Setting access does not send an email or grant access to other clients.
create function private.tracker_set_member(p_participant uuid,p_email text,p_name text,p_role text,p_write boolean) returns void language plpgsql security definer set search_path='' as $$
declare email_value text:=lower(trim(p_email)); uid uuid;
begin
 if not private.tracker_owner(p_participant) then raise exception 'Tracker coordinator required' using errcode='42501'; end if;
 if email_value !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(email_value)>254 or length(trim(p_name)) not between 1 and 120 then raise exception 'Enter a valid email and display name'; end if;
 if p_role not in ('parent','school','allied_health') then raise exception 'Choose parent, school or allied health'; end if;
 select id into uid from auth.users where lower(email)=email_value;
 if uid=auth.uid() then raise exception 'Your coordinator access cannot be changed here'; end if;
 delete from private.pending_participant_access where participant_id=p_participant and lower(email)=email_value and email<>email_value;
 insert into private.pending_participant_access(participant_id,email,access_role,can_view,can_write) values(p_participant,email_value,p_role,true,p_write) on conflict(participant_id,email) do update set access_role=excluded.access_role,can_view=true,can_write=excluded.can_write;
 -- Names may already be shared across tools; do not overwrite an existing label.
 insert into private.consultation_names(email,display_name) values(email_value,trim(p_name)) on conflict do nothing;
 if uid is not null then insert into public.participant_access(participant_id,user_id,access_role,can_view,can_write) values(p_participant,uid,p_role,true,p_write) on conflict(participant_id,user_id) do update set access_role=excluded.access_role,can_view=true,can_write=excluded.can_write; end if;
end; $$;

-- Narrow invoker API wrappers; private functions enforce all authorisation.
create function public.tracker_admin_clients() returns jsonb language sql security invoker set search_path='' as $$ select private.tracker_admin_clients(); $$;
create function public.tracker_create_client(p_name text) returns uuid language sql security invoker set search_path='' as $$ select private.tracker_create_client(p_name); $$;
create function public.tracker_save_period(p_participant uuid,p_label text,p_start date,p_end date,p_checkpoints text[],p_weekdays integer[],p_home boolean,p_excluded date[] default '{}',p_id uuid default null) returns uuid language sql security invoker set search_path='' as $$ select private.tracker_save_period(p_participant,p_label,p_start,p_end,p_checkpoints,p_weekdays,p_home,p_excluded,p_id); $$;
create function public.tracker_schedule(p_participant uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select private.tracker_schedule(p_participant); $$;
create function public.tracker_admin_data(p_participant uuid,p_from date,p_to date) returns jsonb language sql stable security invoker set search_path='' as $$ select private.tracker_admin_data(p_participant,p_from,p_to); $$;
create function public.tracker_set_member(p_participant uuid,p_email text,p_name text,p_role text,p_write boolean) returns void language sql security invoker set search_path='' as $$ select private.tracker_set_member(p_participant,p_email,p_name,p_role,p_write); $$;
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.proname in ('tracker_admin_clients','tracker_create_client','tracker_save_period','tracker_schedule','tracker_admin_data','tracker_set_member') loop
 execute format('revoke all on function %s from public,anon',f.signature);
 execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;
