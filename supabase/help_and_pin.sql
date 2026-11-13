create table private.pat_notification_preferences(
 participant_id uuid primary key references public.participants(id),
 parent_email text not null check(parent_email=lower(parent_email)),
 enabled boolean not null default true
);
alter table private.pat_notification_preferences enable row level security;
revoke all on private.pat_notification_preferences from public,anon,authenticated;
create table private.pat_help_requests(
 id uuid primary key,
 participant_id uuid not null references public.participants(id),
 requested_by uuid not null references auth.users(id),
 kind text not null check(kind in ('help','show','time','another','break')),
 activity text not null default '',
 recipient text not null,
 status text not null default 'queued' check(status in ('queued','sent','failed')),
 created_at timestamptz not null default now(),
 sent_at timestamptz,
 provider_id text,
 error_code text
);
create index pat_help_recent on private.pat_help_requests(participant_id,created_at);
alter table private.pat_help_requests enable row level security;
revoke all on private.pat_help_requests from public,anon,authenticated;
create function public.pat_prepare_help(p_user_id uuid,p_participant_id uuid,p_request_id uuid,p_kind text,p_activity text) returns jsonb language plpgsql security definer set search_path='' as $$
declare prefs private.pat_notification_preferences; existing private.pat_help_requests; label text;
begin
 if not exists(select 1 from public.participant_access a join auth.users u on u.id=a.user_id where a.user_id=p_user_id and a.participant_id=p_participant_id and a.can_view and a.can_write and a.access_role in ('tablet','parent','clinician') and u.email_confirmed_at is not null) then raise exception 'Workspace access required' using errcode='42501'; end if;
 if p_kind not in ('help','show','time','another','break') or length(p_activity)>180 then raise exception 'Invalid help request'; end if;
 select * into prefs from private.pat_notification_preferences where participant_id=p_participant_id and enabled;
 if not found then raise exception 'Parent email is not connected'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_participant_id::text,0));
 select * into existing from private.pat_help_requests where id=p_request_id;
 if found then
  if existing.participant_id<>p_participant_id or existing.requested_by<>p_user_id or existing.kind<>p_kind or existing.activity<>p_activity then raise exception 'Request identity mismatch' using errcode='42501'; end if;
  return jsonb_build_object('id',existing.id,'recipient',existing.recipient,'participant_label',(select display_name from public.participants where id=p_participant_id),'kind',existing.kind,'activity',existing.activity,'status',existing.status,'sent_at',existing.sent_at);
 end if;
 if exists(select 1 from private.pat_help_requests where participant_id=p_participant_id and created_at>now()-interval '60 seconds') or (select count(*) from private.pat_help_requests where participant_id=p_participant_id and created_at>now()-interval '1 hour')>=10 then return jsonb_build_object('rate_limited',true); end if;
 select display_name into label from public.participants where id=p_participant_id;
 insert into private.pat_help_requests(id,participant_id,requested_by,kind,activity,recipient) values(p_request_id,p_participant_id,p_user_id,p_kind,p_activity,prefs.parent_email);
 return jsonb_build_object('id',p_request_id,'recipient',prefs.parent_email,'participant_label',label,'kind',p_kind,'activity',p_activity,'status','queued');
end $$;
revoke all on function public.pat_prepare_help(uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.pat_prepare_help(uuid,uuid,uuid,text,text) to service_role;
create function public.pat_finish_help(p_request_id uuid,p_sent boolean,p_provider_id text default null,p_error_code text default null) returns void language sql security definer set search_path='' as $$
 update private.pat_help_requests set status=case when p_sent then 'sent' else 'failed' end,sent_at=case when p_sent then now() else null end,provider_id=left(p_provider_id,100),error_code=left(p_error_code,100) where id=p_request_id;
$$;
revoke all on function public.pat_finish_help(uuid,boolean,text,text) from public,anon,authenticated;
grant execute on function public.pat_finish_help(uuid,boolean,text,text) to service_role;
create function public.pat_set_family_pin(p_participant_id uuid,p_expected_revision bigint,p_pin_hash text,p_salt text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare h public.pat_hubs;
begin
 if auth.uid() is null or not exists(select 1 from public.participant_access a where a.user_id=auth.uid() and a.participant_id=p_participant_id and a.can_view and a.can_write and a.access_role in ('parent','clinician')) then raise exception 'Parent or clinician account required' using errcode='42501'; end if;
 if p_pin_hash is null or p_salt is null or p_pin_hash !~ '^sha256:[a-f0-9]{64}$' or p_salt !~ '^[a-f0-9]{32}$' then raise exception 'Invalid PIN protection'; end if;
 select * into h from public.pat_hubs where participant_id=p_participant_id for update;
 if not found or h.snapshot is null then raise exception 'Open My Base before setting a PIN'; end if;
 if h.revision<>p_expected_revision then return jsonb_build_object('conflict',true,'revision',h.revision); end if;
 update public.pat_hubs set snapshot=jsonb_set(jsonb_set(snapshot,'{pin}',to_jsonb(p_pin_hash)),'{salt}',to_jsonb(p_salt)),revision=revision+1,updated_at=now(),updated_by=auth.uid() where participant_id=p_participant_id;
 return jsonb_build_object('conflict',false,'revision',h.revision+1);
end $$;
revoke all on function public.pat_set_family_pin(uuid,bigint,text,text) from public,anon;
grant execute on function public.pat_set_family_pin(uuid,bigint,text,text) to authenticated;

create or replace function private.pat_save_tablet_snapshot(p_participant_id uuid,p_expected_revision bigint,p_snapshot jsonb,p_audio jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare current_revision bigint; next_revision bigint; protected_pin jsonb; protected_salt jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 if not exists(select 1 from public.participant_access a where a.participant_id=p_participant_id and a.user_id=auth.uid() and a.can_view and a.can_write and a.access_role='tablet') then raise exception 'Tablet editing permission required' using errcode='42501'; end if;
 select revision,coalesce(snapshot->'pin',configuration->'approval'->'pin'),coalesce(snapshot->'salt',configuration->'approval'->'salt') into current_revision,protected_pin,protected_salt from public.pat_hubs where participant_id=p_participant_id for update;
 if not found then raise exception 'No accessible hub' using errcode='42501'; end if;
 if protected_pin is not null then p_snapshot=jsonb_set(p_snapshot,'{pin}',protected_pin); end if;
 if protected_salt is not null then p_snapshot=jsonb_set(p_snapshot,'{salt}',protected_salt); end if;
 if current_revision<>p_expected_revision then
  if exists(select 1 from public.pat_hubs where participant_id=p_participant_id and snapshot=p_snapshot and audio=p_audio) then return jsonb_build_object('conflict',false,'duplicate',true,'revision',current_revision,'saved_at',now()); end if;
  return jsonb_build_object('conflict',true,'revision',current_revision);
 end if;
 if p_snapshot->>'version' is distinct from '4' or jsonb_typeof(p_snapshot->'entries') is distinct from 'array' or jsonb_typeof(p_audio) is distinct from 'object' then raise exception 'Invalid snapshot'; end if;
 next_revision=current_revision+1;
 update public.pat_hubs set snapshot=p_snapshot,audio=p_audio,revision=next_revision,updated_by=auth.uid(),updated_at=now() where participant_id=p_participant_id;
 return jsonb_build_object('conflict',false,'revision',next_revision,'saved_at',now());
end $$;
