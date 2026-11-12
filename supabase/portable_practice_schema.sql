-- Application code only. Participant data is provisioned separately.
create table public.pat_hubs (
 participant_id uuid primary key references public.participants(id),
 configuration jsonb not null default '{}'::jsonb,
 snapshot jsonb,
 audio jsonb not null default '{}'::jsonb,
 revision bigint not null default 0,
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id),
 check(snapshot is null or (snapshot->>'version'='4' and jsonb_typeof(snapshot->'entries')='array')),
 check(jsonb_typeof(configuration)='object' and jsonb_typeof(audio)='object')
);
create table public.pat_hub_history (
 id bigint generated always as identity primary key,
 participant_id uuid not null references public.participants(id),
 revision bigint not null,
 snapshot jsonb not null,
 changed_at timestamptz not null default now(),
 changed_by uuid references auth.users(id),
 unique(participant_id,revision)
);
create table public.pat_activity_records (
 participant_id uuid not null references public.participants(id),
 record_id text not null,
 activity_id text not null,
 activity_date date not null,
 outcome text not null check(outcome in ('finished','stopped','help')),
 approval_status text not null check(approval_status in ('pending','approved','rejected')),
 observed_engagement_minutes numeric,
 support_level text,
 payload jsonb not null,
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id),
 primary key(participant_id,record_id)
);
create index pat_activity_records_participant_date on public.pat_activity_records(participant_id,activity_date);
alter table public.pat_hubs enable row level security;
alter table public.pat_hub_history enable row level security;
alter table public.pat_activity_records enable row level security;
revoke all on public.pat_hubs,public.pat_hub_history,public.pat_activity_records from anon,authenticated;
grant select,insert,update on public.pat_hubs to authenticated;
grant select,insert on public.pat_hub_history to authenticated;
grant usage on sequence public.pat_hub_history_id_seq to authenticated;
grant select,insert,update on public.pat_activity_records to authenticated;
create policy pat_hub_read on public.pat_hubs for select to authenticated using (
 exists(select 1 from public.participant_access a where a.participant_id=pat_hubs.participant_id and a.user_id=(select auth.uid()) and a.can_view and a.access_role in ('parent','clinician'))
);
create policy pat_hub_insert on public.pat_hubs for insert to authenticated with check (
 exists(select 1 from public.participant_access a where a.participant_id=pat_hubs.participant_id and a.user_id=(select auth.uid()) and a.can_view and a.can_write and a.access_role in ('parent','clinician'))
);
create policy pat_hub_update on public.pat_hubs for update to authenticated using (
 exists(select 1 from public.participant_access a where a.participant_id=pat_hubs.participant_id and a.user_id=(select auth.uid()) and a.can_view and a.can_write and a.access_role in ('parent','clinician'))
) with check (
 exists(select 1 from public.participant_access a where a.participant_id=pat_hubs.participant_id and a.user_id=(select auth.uid()) and a.can_view and a.can_write and a.access_role in ('parent','clinician'))
);
create policy pat_record_read on public.pat_activity_records for select to authenticated using (
 exists(select 1 from public.participant_access a where a.participant_id=pat_activity_records.participant_id and a.user_id=(select auth.uid()) and a.can_view)
);
create policy pat_record_insert on public.pat_activity_records for insert to authenticated with check (
 exists(select 1 from public.participant_access a where a.participant_id=pat_activity_records.participant_id and a.user_id=(select auth.uid()) and a.can_view and a.can_write and a.access_role in ('parent','clinician'))
);
create policy pat_record_update on public.pat_activity_records for update to authenticated using (
 exists(select 1 from public.participant_access a where a.participant_id=pat_activity_records.participant_id and a.user_id=(select auth.uid()) and a.can_view and a.can_write and a.access_role in ('parent','clinician'))
) with check (
 exists(select 1 from public.participant_access a where a.participant_id=pat_activity_records.participant_id and a.user_id=(select auth.uid()) and a.can_view and a.can_write and a.access_role in ('parent','clinician'))
);
create policy pat_history_read on public.pat_hub_history for select to authenticated using (
 exists(select 1 from public.participant_access a where a.participant_id=pat_hub_history.participant_id and a.user_id=(select auth.uid()) and a.can_view and a.access_role in ('parent','clinician'))
);
create policy pat_history_insert on public.pat_hub_history for insert to authenticated with check (
 exists(select 1 from public.participant_access a where a.participant_id=pat_hub_history.participant_id and a.user_id=(select auth.uid()) and a.can_view and a.can_write and a.access_role in ('parent','clinician'))
);
create function private.pat_hub_audit() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.snapshot is not null and (TG_OP='INSERT' or new.snapshot is distinct from old.snapshot or new.audio is distinct from old.audio) then
  insert into public.pat_hub_history(participant_id,revision,snapshot,changed_by) values(new.participant_id,new.revision,new.snapshot,new.updated_by);
  insert into public.pat_activity_records(participant_id,record_id,activity_id,activity_date,outcome,approval_status,observed_engagement_minutes,support_level,payload,updated_by)
  select new.participant_id,e->>'id',e->>'activity',(e->>'date')::date,e->>'outcome',e->>'status',nullif(e->>'engagementMinutes','')::numeric,e->>'supportLevel',e,new.updated_by
  from jsonb_array_elements(new.snapshot->'entries') e
  on conflict(participant_id,record_id) do update set activity_id=excluded.activity_id,activity_date=excluded.activity_date,outcome=excluded.outcome,approval_status=excluded.approval_status,observed_engagement_minutes=excluded.observed_engagement_minutes,support_level=excluded.support_level,payload=excluded.payload,updated_by=excluded.updated_by,updated_at=now();
 end if;
 return new;
end $$;
create trigger pat_hub_audit after insert or update on public.pat_hubs for each row execute function private.pat_hub_audit();
create function public.pat_save_snapshot(p_participant_id uuid,p_expected_revision bigint,p_snapshot jsonb,p_audio jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare current_revision bigint; next_revision bigint;
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 if not exists(select 1 from public.participant_access a where a.participant_id=p_participant_id and a.user_id=auth.uid() and a.can_view and a.can_write and a.access_role in ('parent','clinician')) then raise exception 'Family editing permission required' using errcode='42501'; end if;
 select revision into current_revision from public.pat_hubs where participant_id=p_participant_id for update;
 if not found then raise exception 'No accessible hub' using errcode='42501'; end if;
 if current_revision<>p_expected_revision then
  if exists(select 1 from public.pat_hubs where participant_id=p_participant_id and snapshot=p_snapshot and audio=p_audio) then return jsonb_build_object('conflict',false,'duplicate',true,'revision',current_revision,'saved_at',now()); end if;
  return jsonb_build_object('conflict',true,'revision',current_revision);
 end if;
 if p_snapshot->>'version' is distinct from '4' or jsonb_typeof(p_snapshot->'entries') is distinct from 'array' or jsonb_typeof(p_audio) is distinct from 'object' then raise exception 'Invalid snapshot'; end if;
 next_revision=current_revision+1;
 update public.pat_hubs set snapshot=p_snapshot,audio=p_audio,revision=next_revision,updated_by=auth.uid(),updated_at=now() where participant_id=p_participant_id;
 return jsonb_build_object('conflict',false,'revision',next_revision,'saved_at',now());
end $$;
revoke all on function public.pat_save_snapshot(uuid,bigint,jsonb,jsonb) from public,anon;
grant execute on function public.pat_save_snapshot(uuid,bigint,jsonb,jsonb) to authenticated;

-- Server-only import staging. Deliberately no browser policies or grants.
create table private.pat_import_buffer(participant_id uuid primary key references public.participants(id),payload text not null default '' check(length(payload)<=40000000));
alter table private.pat_import_buffer enable row level security;
revoke all on private.pat_import_buffer from public,anon,authenticated;
