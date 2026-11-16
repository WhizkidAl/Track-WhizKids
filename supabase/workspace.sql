-- Unified coordinator setup. Existing memberships and contributions are retained.
create table private.workspace_tools (
 participant_id uuid primary key references public.participants(id),
 tracker boolean not null default true, plan boolean not null default false,
 opened boolean not null default false
);
create table private.workspace_permissions (
 participant_id uuid references public.participants(id), email text not null,
 tracker_view boolean not null, plan_view boolean not null,
 primary key(participant_id,email), check(email=lower(email))
);
create table private.workspace_reviews (
 id uuid primary key default gen_random_uuid(), participant_id uuid not null references public.participants(id),
 tool text not null check(tool in ('tracker','plan')), revision integer not null,
 proposal jsonb not null, deadline date not null, created_at timestamptz not null default now(),
 unique(participant_id,tool,revision), check(jsonb_typeof(proposal)='object'), check(length(proposal::text)<20000)
);
create table private.workspace_responses (
 id bigint generated always as identity primary key, review_id uuid not null references private.workspace_reviews(id),
 user_id uuid not null references auth.users(id), decision text not null check(decision in ('agree','changes','decline')),
 suggestion text not null default '', created_at timestamptz not null default clock_timestamp(), check(length(suggestion)<=4000)
);
alter table private.workspace_tools enable row level security;
alter table private.workspace_permissions enable row level security;
alter table private.workspace_reviews enable row level security;
alter table private.workspace_responses enable row level security;
revoke all on private.workspace_tools,private.workspace_permissions,private.workspace_reviews,private.workspace_responses from public,anon,authenticated;
insert into private.workspace_tools select o.participant_id,true,exists(select 1 from public.team_consultations c where c.participant_id=o.participant_id),true from private.tracker_owners o;

create function private.workspace_access(pid uuid,tool_name text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.participant_access a join auth.users u on u.id=a.user_id
 left join private.workspace_permissions p on p.participant_id=a.participant_id and p.email=lower(u.email)
 left join private.workspace_tools t on t.participant_id=a.participant_id
 where a.participant_id=pid and a.user_id=auth.uid() and a.can_view
 and case when tool_name='tracker' then coalesce(t.tracker,true) and coalesce(p.tracker_view,true)
 when tool_name='plan' then coalesce(t.plan,true) and coalesce(p.plan_view,true) else false end);
$$;
revoke all on function private.workspace_access(uuid,text) from public,anon;
grant execute on function private.workspace_access(uuid,text) to authenticated;
create policy workspace_tracker_scope on public.tracker_days as restrictive for all to authenticated using(private.workspace_access(participant_id,'tracker')) with check(private.workspace_access(participant_id,'tracker'));
create policy workspace_reflection_scope on public.tracker_reflections as restrictive for all to authenticated using(private.workspace_access(participant_id,'tracker')) with check(private.workspace_access(participant_id,'tracker'));
create function private.workspace_writable(pid uuid) returns boolean language sql stable security definer set search_path='' as $$ select private.tracker_owner(pid) or coalesce((select opened from private.workspace_tools where participant_id=pid),true); $$;
revoke all on function private.workspace_writable(uuid) from public,anon;
grant execute on function private.workspace_writable(uuid) to authenticated;
create policy workspace_tracker_open_insert on public.tracker_days as restrictive for insert to authenticated with check(private.workspace_writable(participant_id));
create policy workspace_tracker_open_update on public.tracker_days as restrictive for update to authenticated using(private.workspace_writable(participant_id)) with check(private.workspace_writable(participant_id));
create policy workspace_checkpoint_open on public.school_checkpoints as restrictive for all to authenticated using(exists(select 1 from public.tracker_days d where d.id=tracker_day_id and private.workspace_writable(d.participant_id))) with check(exists(select 1 from public.tracker_days d where d.id=tracker_day_id and private.workspace_writable(d.participant_id)));
create policy workspace_incident_open on public.incidents as restrictive for all to authenticated using(exists(select 1 from public.tracker_days d where d.id=tracker_day_id and private.workspace_writable(d.participant_id))) with check(exists(select 1 from public.tracker_days d where d.id=tracker_day_id and private.workspace_writable(d.participant_id)));
create policy workspace_reflection_open on public.tracker_reflections as restrictive for insert to authenticated with check(private.workspace_writable(participant_id));
create or replace function private.consultation_access(cid uuid,writing boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.team_consultations c join public.participant_access a on a.participant_id=c.participant_id join auth.users u on u.id=a.user_id
 left join private.consultation_write_overrides w on w.consultation_id=c.id and w.email=lower(u.email)
 where c.id=cid and c.active and a.user_id=auth.uid() and private.workspace_access(c.participant_id,'plan') and (not writing or (coalesce(w.can_write,a.can_write) and private.workspace_writable(c.participant_id))));
$$;
create or replace function private.tracker_assigned_clients() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name) order by p.display_name),'[]'::jsonb) from public.participants p join private.tracker_owners o on o.participant_id=p.id where p.active and private.workspace_access(p.id,'tracker');
$$;

create function private.workspace_save_client(p_name text,p_tracker boolean,p_plan boolean,p_purpose text,p_participant uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare pid uuid:=p_participant;
begin
 if not p_tracker and not p_plan then raise exception 'Choose Tracker, Action Plan, or both'; end if;
 if p_plan and length(trim(p_purpose)) not between 1 and 2000 then raise exception 'Set a focused purpose for the Action Plan'; end if;
 if pid is null then pid:=private.tracker_create_client(p_name);
 elsif not private.tracker_owner(pid) then raise exception 'Coordinator access required' using errcode='42501'; end if;
 insert into private.workspace_tools(participant_id,tracker,plan) values(pid,p_tracker,p_plan) on conflict(participant_id) do update set tracker=excluded.tracker,plan=excluded.plan;
 if p_plan then
 insert into public.team_consultations(participant_id,purpose,coordinator_user_id,coordinator_label) values(pid,trim(p_purpose),auth.uid(),coalesce(private.tracker_actor(auth.uid()),'Coordinator')) on conflict(participant_id) do nothing;
 end if;
 return pid;
end $$;

create function private.workspace_team(p_participant uuid,p_members jsonb) returns void language plpgsql security definer set search_path='' as $$
declare m jsonb; cid uuid; address text;
begin
 if not private.tracker_owner(p_participant) then raise exception 'Coordinator access required' using errcode='42501'; end if;
 if jsonb_typeof(p_members)<>'array' or jsonb_array_length(p_members) not between 1 and 50 then raise exception 'Add between 1 and 50 people'; end if;
 select id into cid from public.team_consultations where participant_id=p_participant;
 for m in select value from jsonb_array_elements(p_members) loop
  address:=lower(trim(m->>'email'));
  if m->>'tracker' not in ('none','read','write') or m->>'plan' not in ('none','read','write') or (m->>'tracker'='none' and m->>'plan'='none') then raise exception 'Choose access for each person'; end if;
  if m->>'plan'<>'none' and cid is null then raise exception 'Enable an Action Plan before adding its team'; end if;
  perform private.tracker_set_member(p_participant,address,coalesce(nullif(trim(m->>'name'),''),split_part(address,'@',1)),m->>'role',m->>'tracker'='write');
  insert into private.workspace_permissions values(p_participant,address,m->>'tracker'<>'none',m->>'plan'<>'none') on conflict(participant_id,email) do update set tracker_view=excluded.tracker_view,plan_view=excluded.plan_view;
  if cid is not null then insert into private.consultation_write_overrides values(cid,address,m->>'plan'='write') on conflict(consultation_id,email) do update set can_write=excluded.can_write; end if;
 end loop;
end $$;

create function private.workspace_data(p_participant uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; cid uuid;
begin
 if not private.tracker_owner(p_participant) then raise exception 'Coordinator access required' using errcode='42501'; end if;
 select id into cid from public.team_consultations where participant_id=p_participant;
 select jsonb_build_object('tools',coalesce((select to_jsonb(t) from private.workspace_tools t where participant_id=p_participant),'{"tracker":true,"plan":false}'::jsonb),
 'consultation',(select jsonb_build_object('id',id,'purpose',purpose) from public.team_consultations where id=cid),
 'team',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('tracker',case when coalesce(p.tracker_view,true) then case when x.can_write then 'write' else 'read' end else 'none' end,'plan',case when cid is null or not coalesce(p.plan_view,true) then 'none' when coalesce(w.can_write,x.can_write) then 'write' else 'read' end))
 from (select a.user_id,private.tracker_actor(a.user_id) as name,lower(u.email) as email,a.access_role,a.can_write from public.participant_access a join auth.users u on u.id=a.user_id where a.participant_id=p_participant and a.can_view
 union all select null::uuid,coalesce(n.display_name,split_part(a.email,'@',1)),lower(a.email),a.access_role,a.can_write from private.pending_participant_access a left join private.consultation_names n on n.email=lower(a.email) where a.participant_id=p_participant and a.can_view and not exists(select 1 from auth.users u join public.participant_access pa on pa.user_id=u.id where lower(u.email)=lower(a.email) and pa.participant_id=p_participant)) x
 left join private.workspace_permissions p on p.participant_id=p_participant and p.email=x.email left join private.consultation_write_overrides w on w.consultation_id=cid and w.email=x.email),'[]'::jsonb),
 'reviews',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('responses',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('name',private.tracker_actor(a.user_id))) from private.workspace_responses a where a.review_id=r.id),'[]'::jsonb)) order by r.created_at desc) from private.workspace_reviews r where participant_id=p_participant),'[]'::jsonb)) into result;
 return result;
end $$;

create function private.workspace_publish_review(p_participant uuid,p_tool text,p_proposal jsonb,p_deadline date) returns uuid language plpgsql security definer set search_path='' as $$
declare rid uuid;
begin
 if not private.tracker_owner(p_participant) then raise exception 'Coordinator access required' using errcode='42501'; end if;
 if p_deadline<current_date then raise exception 'Choose a future review date'; end if;
 perform pg_advisory_xact_lock(hashtext(p_participant::text));
 insert into private.workspace_reviews(participant_id,tool,revision,proposal,deadline) select p_participant,p_tool,coalesce(max(revision),0)+1,p_proposal,p_deadline from private.workspace_reviews where participant_id=p_participant and tool=p_tool returning id into rid;
 return rid;
end $$;
create function private.workspace_review(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r private.workspace_reviews;
begin
 select * into r from private.workspace_reviews where id=p_id;
 if r.id is null or not private.workspace_access(r.participant_id,r.tool) then raise exception 'This review is not assigned to your email' using errcode='42501'; end if;
 return to_jsonb(r)||jsonb_build_object('client',(select display_name from public.participants where id=r.participant_id),'current',not exists(select 1 from private.workspace_reviews where participant_id=r.participant_id and tool=r.tool and revision>r.revision),'responses',coalesce((select jsonb_agg(jsonb_build_object('name',private.tracker_actor(user_id),'decision',decision,'suggestion',suggestion,'created_at',created_at,'mine',user_id=auth.uid()) order by created_at desc) from private.workspace_responses where review_id=r.id),'[]'::jsonb));
end $$;
create function private.workspace_respond(p_id uuid,p_decision text,p_suggestion text) returns void language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 r:=private.workspace_review(p_id);
 if not (r->>'current')::boolean then raise exception 'This proposal has been replaced. Please use the newest review invitation'; end if;
 if p_decision='changes' and length(trim(p_suggestion))=0 then raise exception 'Add your suggested changes'; end if;
 insert into private.workspace_responses(review_id,user_id,decision,suggestion) values(p_id,auth.uid(),p_decision,trim(coalesce(p_suggestion,'')));
end $$;

create function public.workspace_save_client(p_name text,p_tracker boolean,p_plan boolean,p_purpose text,p_participant uuid default null) returns uuid language sql security invoker set search_path='' as $$select private.workspace_save_client(p_name,p_tracker,p_plan,p_purpose,p_participant)$$;
create function public.workspace_team(p_participant uuid,p_members jsonb) returns void language sql security invoker set search_path='' as $$select private.workspace_team(p_participant,p_members)$$;
create function public.workspace_data(p_participant uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.workspace_data(p_participant)$$;
create function public.workspace_publish_review(p_participant uuid,p_tool text,p_proposal jsonb,p_deadline date) returns uuid language sql security invoker set search_path='' as $$select private.workspace_publish_review(p_participant,p_tool,p_proposal,p_deadline)$$;
create function public.workspace_review(p_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.workspace_review(p_id)$$;
create function public.workspace_respond(p_id uuid,p_decision text,p_suggestion text) returns void language sql security invoker set search_path='' as $$select private.workspace_respond(p_id,p_decision,p_suggestion)$$;
create function private.workspace_open(p_participant uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.tracker_owner(p_participant) then raise exception 'Coordinator access required' using errcode='42501'; end if;
 if exists(select 1 from private.workspace_tools where participant_id=p_participant and tracker) and not exists(select 1 from private.tracker_periods where participant_id=p_participant) then raise exception 'Set the agreed monitoring dates before opening the tracker'; end if;
 update private.workspace_tools set opened=true where participant_id=p_participant;
end $$;
create function public.workspace_open(p_participant uuid) returns void language sql security invoker set search_path='' as $$select private.workspace_open(p_participant)$$;
revoke all on function private.workspace_open(uuid),public.workspace_open(uuid) from public,anon;
grant execute on function private.workspace_open(uuid),public.workspace_open(uuid) to authenticated;
do $$declare f record;begin for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('private','public') and p.proname in ('workspace_save_client','workspace_team','workspace_data','workspace_publish_review','workspace_review','workspace_respond') loop execute format('revoke all on function %s from public,anon',f.signature);execute format('grant execute on function %s to authenticated',f.signature);end loop;end$$;

create or replace function private.consultation_roster(cid uuid)
returns table(user_id uuid,display_name text,access_role text,can_write boolean,invitation_status text)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.consultation_access(cid) then raise exception 'Not authorised'; end if;
 return query
 select a.user_id,coalesce(n.display_name,split_part(u.email,'@',1)),a.access_role,coalesce(w.can_write,a.can_write),'Active'::text
 from public.team_consultations c join public.participant_access a on a.participant_id=c.participant_id
 join auth.users u on u.id=a.user_id left join private.consultation_names n on n.email=lower(u.email)
 left join private.consultation_write_overrides w on w.consultation_id=c.id and w.email=lower(u.email)
 where c.id=cid and a.can_view and not exists(select 1 from private.workspace_permissions wp where wp.participant_id=c.participant_id and wp.email=lower(u.email) and not wp.plan_view)
 union all
 select null::uuid,coalesce(n.display_name,split_part(p.email,'@',1)),p.access_role,coalesce(w.can_write,p.can_write),'Invited — awaiting sign-in'::text
 from public.team_consultations c join private.pending_participant_access p on p.participant_id=c.participant_id
 left join private.consultation_names n on n.email=lower(p.email)
 left join private.consultation_write_overrides w on w.consultation_id=c.id and w.email=lower(p.email)
 where c.id=cid and p.can_view and not exists(select 1 from private.workspace_permissions wp where wp.participant_id=c.participant_id and wp.email=lower(p.email) and not wp.plan_view) and not exists (
 select 1 from auth.users u join public.participant_access a on a.user_id=u.id and a.participant_id=p.participant_id where lower(u.email)=lower(p.email));
end $$;

-- Per-period home questions: omitted questions do not count as incomplete.
alter table private.tracker_periods add column home_fields text[] not null default array['sleep','breakfast','home_morning','medication_status'] check(home_fields <@ array['sleep','breakfast','home_morning','medication_status']);
create function private.workspace_save_period(p_participant uuid,p_label text,p_start date,p_end date,p_checkpoints text[],p_weekdays integer[],p_home boolean,p_excluded date[],p_home_fields text[],p_id uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare rid uuid;
begin
 if not private.tracker_owner(p_participant) then raise exception 'Coordinator access required' using errcode='42501'; end if;
 if p_home and cardinality(p_home_fields)=0 then raise exception 'Choose a home question or turn off the home section'; end if;
 rid:=private.tracker_save_period(p_participant,p_label,p_start,p_end,p_checkpoints,p_weekdays,p_home,p_excluded,p_id);
 update private.tracker_periods set home_fields=p_home_fields where id=rid;
 return rid;
end $$;
create function public.workspace_save_period(p_participant uuid,p_label text,p_start date,p_end date,p_checkpoints text[],p_weekdays integer[],p_home boolean,p_excluded date[],p_home_fields text[],p_id uuid default null) returns uuid language sql security invoker set search_path='' as $$select private.workspace_save_period(p_participant,p_label,p_start,p_end,p_checkpoints,p_weekdays,p_home,p_excluded,p_home_fields,p_id)$$;
revoke all on function private.workspace_save_period(uuid,text,date,date,text[],integer[],boolean,date[],text[],uuid),public.workspace_save_period(uuid,text,date,date,text[],integer[],boolean,date[],text[],uuid) from public,anon;
grant execute on function private.workspace_save_period(uuid,text,date,date,text[],integer[],boolean,date[],text[],uuid),public.workspace_save_period(uuid,text,date,date,text[],integer[],boolean,date[],text[],uuid) to authenticated;
