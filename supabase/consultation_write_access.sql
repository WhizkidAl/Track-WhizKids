-- Explicit consultation-only write permissions; tracker membership remains required.
create table private.consultation_write_overrides (
 consultation_id uuid not null references public.team_consultations(id) on delete cascade,
 email text not null check(email=lower(email)),
 can_write boolean not null,
 primary key(consultation_id,email)
);
alter table private.consultation_write_overrides enable row level security;
revoke all on private.consultation_write_overrides from public,anon,authenticated;
create or replace function private.consultation_access(cid uuid, writing boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists (
 select 1 from public.team_consultations c
 join public.participant_access a on a.participant_id=c.participant_id
 join auth.users u on u.id=a.user_id
 left join private.consultation_write_overrides w on w.consultation_id=c.id and w.email=lower(u.email)
 where c.id=cid and c.active and a.user_id=auth.uid() and a.can_view
 and (not writing or coalesce(w.can_write,a.can_write)));
$$;
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
 where c.id=cid and a.can_view
 union all
 select null::uuid,coalesce(n.display_name,split_part(p.email,'@',1)),p.access_role,coalesce(w.can_write,p.can_write),'Invited — awaiting sign-in'::text
 from public.team_consultations c join private.pending_participant_access p on p.participant_id=c.participant_id
 left join private.consultation_names n on n.email=lower(p.email)
 left join private.consultation_write_overrides w on w.consultation_id=c.id and w.email=lower(p.email)
 where c.id=cid and p.can_view and not exists (
 select 1 from auth.users u join public.participant_access a on a.user_id=u.id and a.participant_id=p.participant_id where lower(u.email)=lower(p.email));
end $$;
