-- Tracker selection excludes participants belonging only to other tools.
create function private.tracker_assigned_clients() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name) order by p.display_name)
 from public.participants p join private.tracker_owners o on o.participant_id=p.id join public.participant_access a on a.participant_id=p.id and a.user_id=auth.uid() where p.active and a.can_view),'[]'::jsonb);
end; $$;
create function public.tracker_assigned_clients() returns jsonb language sql stable security invoker set search_path='' as $$ select private.tracker_assigned_clients(); $$;
revoke all on function private.tracker_assigned_clients(),public.tracker_assigned_clients() from public,anon;
grant execute on function private.tracker_assigned_clients(),public.tracker_assigned_clients() to authenticated;
