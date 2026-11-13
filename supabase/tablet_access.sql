-- A tablet can read its assigned hub and save snapshots, but cannot change configuration or access grants.
alter table public.participant_access drop constraint participant_access_access_role_check;
alter table public.participant_access add constraint participant_access_access_role_check check(access_role in ('clinician','parent','school','allied_health','tablet'));
alter table private.pending_participant_access drop constraint pending_participant_access_access_role_check;
alter table private.pending_participant_access add constraint pending_participant_access_access_role_check check(access_role in ('clinician','parent','school','allied_health','tablet'));
create policy pat_tablet_hub_read on public.pat_hubs for select to authenticated using (
 exists(select 1 from public.participant_access a where a.participant_id=pat_hubs.participant_id and a.user_id=(select auth.uid()) and a.can_view and a.access_role='tablet')
);
create or replace function private.pat_save_tablet_snapshot(p_participant_id uuid,p_expected_revision bigint,p_snapshot jsonb,p_audio jsonb) returns jsonb language plpgsql security definer set search_path='' as $
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
end $;
revoke all on function private.pat_save_tablet_snapshot(uuid,bigint,jsonb,jsonb) from public,anon,authenticated;
grant execute on function private.pat_save_tablet_snapshot(uuid,bigint,jsonb,jsonb) to authenticated;
create or replace function public.pat_save_snapshot(p_participant_id uuid,p_expected_revision bigint,p_snapshot jsonb,p_audio jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare current_revision bigint; next_revision bigint;
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 if not exists(select 1 from public.participant_access a where a.participant_id=p_participant_id and a.user_id=auth.uid() and a.can_view and a.can_write and a.access_role in ('parent','clinician')) then return private.pat_save_tablet_snapshot(p_participant_id,p_expected_revision,p_snapshot,p_audio); end if;
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
