-- Read access remains available during preparation; only submission is paused.
drop policy workspace_checkpoint_open on public.school_checkpoints;
drop policy workspace_incident_open on public.incidents;
create policy workspace_checkpoint_open_insert on public.school_checkpoints as restrictive for insert to authenticated with check(exists(select 1 from public.tracker_days d where d.id=tracker_day_id and private.workspace_writable(d.participant_id)));
create policy workspace_checkpoint_open_update on public.school_checkpoints as restrictive for update to authenticated using(exists(select 1 from public.tracker_days d where d.id=tracker_day_id and private.workspace_writable(d.participant_id))) with check(exists(select 1 from public.tracker_days d where d.id=tracker_day_id and private.workspace_writable(d.participant_id)));
create policy workspace_incident_open_insert on public.incidents as restrictive for insert to authenticated with check(exists(select 1 from public.tracker_days d where d.id=tracker_day_id and private.workspace_writable(d.participant_id)));
create policy workspace_incident_open_update on public.incidents as restrictive for update to authenticated using(exists(select 1 from public.tracker_days d where d.id=tracker_day_id and private.workspace_writable(d.participant_id))) with check(exists(select 1 from public.tracker_days d where d.id=tracker_day_id and private.workspace_writable(d.participant_id)));
create function private.workspace_status(p_participant uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.workspace_access(p_participant,'tracker') and not private.workspace_access(p_participant,'plan') then raise exception 'Assigned access required' using errcode='42501';end if;
 return jsonb_build_object('opened',private.workspace_writable(p_participant));
end $$;
create function public.workspace_status(p_participant uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.workspace_status(p_participant)$$;
revoke all on function private.workspace_status(uuid),public.workspace_status(uuid) from public,anon;
grant execute on function private.workspace_status(uuid),public.workspace_status(uuid) to authenticated;

create or replace function private.consultation_roster(cid uuid)
returns table(user_id uuid,display_name text,access_role text,can_write boolean,invitation_status text)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.consultation_access(cid) then raise exception 'Not authorised'; end if;
 return query
 select a.user_id,coalesce(n.display_name,split_part(u.email,'@',1)),a.access_role,(coalesce(w.can_write,a.can_write) and private.workspace_writable(c.participant_id)),'Active'::text
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

