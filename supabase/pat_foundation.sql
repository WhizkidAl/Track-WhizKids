create schema if not exists private;
revoke all on schema private from public,anon;
create table public.participants(
 id uuid primary key default gen_random_uuid(),
 display_name text not null,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.participant_access(
 participant_id uuid not null references public.participants(id),
 user_id uuid not null references auth.users(id),
 access_role text not null check(access_role in ('clinician','parent','school','allied_health')),
 can_view boolean not null default true,
 can_write boolean not null default false,
 created_at timestamptz not null default now(),
 primary key(participant_id,user_id)
);
create index participant_access_user_id on public.participant_access(user_id);
create table private.pending_participant_access(
 participant_id uuid not null references public.participants(id),
 email text not null check(email=lower(email)),
 access_role text not null check(access_role in ('clinician','parent','school','allied_health')),
 can_view boolean not null default true,
 can_write boolean not null default false,
 created_at timestamptz not null default now(),
 primary key(participant_id,email)
);
alter table public.participants enable row level security;
alter table public.participant_access enable row level security;
alter table private.pending_participant_access enable row level security;
revoke all on public.participants,public.participant_access from public,anon,authenticated;
revoke all on private.pending_participant_access from public,anon,authenticated;
grant select on public.participants,public.participant_access to authenticated;
create policy pat_view_own_access on public.participant_access for select to authenticated using(user_id=(select auth.uid()));
create policy pat_view_assigned_participant on public.participants for select to authenticated using(
 exists(select 1 from public.participant_access a where a.participant_id=participants.id and a.user_id=(select auth.uid()) and a.can_view)
);
-- Only the auth.users trigger can attach the pre-authorised email's access.
create function private.pat_attach_pending_access() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is not null and auth.uid()<>new.id then raise exception 'Account identity mismatch' using errcode='42501'; end if;
 insert into public.participant_access(participant_id,user_id,access_role,can_view,can_write)
 select p.participant_id,new.id,p.access_role,p.can_view,p.can_write
 from private.pending_participant_access p where p.email=lower(new.email)
 on conflict(participant_id,user_id) do update set access_role=excluded.access_role,can_view=excluded.can_view,can_write=excluded.can_write;
 return new;
end $$;
revoke all on function private.pat_attach_pending_access() from public,anon,authenticated;
create trigger pat_attach_pending_access after insert on auth.users for each row execute function private.pat_attach_pending_access();
-- Family access is granted explicitly by an authorised parent or clinician.
create function private.pat_allow_parent(p_participant_id uuid,p_email text) returns void language plpgsql security definer set search_path='' as $$
declare target_email text=lower(trim(p_email));
begin
 if auth.uid() is null or not exists(select 1 from public.participant_access a where a.participant_id=p_participant_id and a.user_id=auth.uid() and a.can_view and a.can_write and a.access_role in ('parent','clinician')) then raise exception 'Family access permission required' using errcode='42501'; end if;
 if target_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(target_email)>254 then raise exception 'Enter one valid email address'; end if;
 insert into private.pending_participant_access(participant_id,email,access_role,can_view,can_write) values(p_participant_id,target_email,'parent',true,true)
 on conflict(participant_id,email) do update set can_view=true,can_write=true;
 insert into public.participant_access(participant_id,user_id,access_role,can_view,can_write)
 select p_participant_id,u.id,'parent',true,true from auth.users u where lower(u.email)=target_email
 on conflict(participant_id,user_id) do update set can_view=true,can_write=true,access_role=case when participant_access.access_role='clinician' then 'clinician' else 'parent' end;
end $$;
revoke all on function private.pat_allow_parent(uuid,text) from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.pat_allow_parent(uuid,text) to authenticated;
create function public.pat_allow_parent(p_participant_id uuid,p_email text) returns void language sql security invoker set search_path='' as $$select private.pat_allow_parent(p_participant_id,p_email)$$;
revoke all on function public.pat_allow_parent(uuid,text) from public,anon;
grant execute on function public.pat_allow_parent(uuid,text) to authenticated;
