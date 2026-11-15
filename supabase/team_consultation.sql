-- Additive team consultation v1. Existing tracker and legacy plan records are preserved.
create table public.team_consultations (
 id uuid primary key default gen_random_uuid(),
 participant_id uuid not null unique references public.participants(id),
 purpose text not null check(length(purpose) between 1 and 4000),
 coordinator_user_id uuid not null references auth.users(id),
 coordinator_label text not null default 'Alex — Whiz Kids Therapy',
 due_date date,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table private.consultation_names (
 email text primary key,
 display_name text not null
);
revoke all on private.consultation_names from public, anon, authenticated;
alter table private.consultation_names enable row level security;

-- The private helper checks both the authenticated caller and participant membership.
create function private.consultation_access(cid uuid, writing boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists (
 select 1 from public.team_consultations c join public.participant_access a on a.participant_id=c.participant_id
 where c.id=cid and c.active and a.user_id=auth.uid() and a.can_view and (not writing or a.can_write));
$$;
revoke all on function private.consultation_access(uuid,boolean) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.consultation_access(uuid,boolean) to authenticated;
alter table public.team_consultations enable row level security;
create policy consultation_read on public.team_consultations for select to authenticated using(private.consultation_access(id));
create policy consultation_coordinate on public.team_consultations for update to authenticated
 using(coordinator_user_id=auth.uid() and private.consultation_access(id,true))
 with check(coordinator_user_id=auth.uid() and private.consultation_access(id,true));
revoke all on public.team_consultations from anon,authenticated;
grant select on public.team_consultations to authenticated;
grant update(purpose,due_date) on public.team_consultations to authenticated;

create table public.consultation_contributions (
 id uuid primary key default gen_random_uuid(),
 consultation_id uuid not null references public.team_consultations(id),
 kind text not null check(kind in ('priority','incident','support','proposal','comment','attachment')),
 parent_id uuid references public.consultation_contributions(id),
 author_id uuid not null references auth.users(id),
 author_label text not null,
 author_role text not null,
 payload jsonb not null check(jsonb_typeof(payload)='object' and octet_length(payload::text)<=100000),
 revision integer not null default 1,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index consultation_contributions_list on public.consultation_contributions(consultation_id,created_at);
create index consultation_contributions_parent on public.consultation_contributions(parent_id);
create index consultation_contributions_author on public.consultation_contributions(author_id);
create table public.consultation_revisions (
 contribution_id uuid not null references public.consultation_contributions(id),
 consultation_id uuid not null references public.team_consultations(id),
 revision integer not null,
 author_id uuid not null,
 author_label text not null,
 author_role text not null,
 payload jsonb not null,
 saved_at timestamptz not null default now(),
 primary key(contribution_id,revision)
);
create index consultation_revisions_consultation on public.consultation_revisions(consultation_id);
alter table public.consultation_contributions enable row level security;
alter table public.consultation_revisions enable row level security;
create policy contribution_read on public.consultation_contributions for select to authenticated using(private.consultation_access(consultation_id));
create policy contribution_create on public.consultation_contributions for insert to authenticated with check(author_id=auth.uid() and private.consultation_access(consultation_id,true));
create policy contribution_edit_own on public.consultation_contributions for update to authenticated
 using(author_id=auth.uid() and kind<>'attachment' and private.consultation_access(consultation_id,true))
 with check(author_id=auth.uid() and private.consultation_access(consultation_id,true));
create policy revisions_read on public.consultation_revisions for select to authenticated using(private.consultation_access(consultation_id));
revoke all on public.consultation_contributions,public.consultation_revisions from anon,authenticated;
grant select,insert on public.consultation_contributions to authenticated;
grant update(payload) on public.consultation_contributions to authenticated;
grant select on public.consultation_revisions to authenticated;

-- Runs only as a trigger; identity and timestamps cannot be supplied by a browser.
create function private.consultation_stamp() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.consultation_access(new.consultation_id,true) then raise exception 'Not authorised'; end if;
 if tg_op='UPDATE' then
  if old.author_id<>auth.uid() or old.kind='attachment' then raise exception 'Only your own responses can be revised'; end if;
  new.id:=old.id; new.consultation_id:=old.consultation_id; new.kind:=old.kind; new.parent_id:=old.parent_id;
  new.author_id:=old.author_id; new.author_label:=old.author_label; new.author_role:=old.author_role;
  new.created_at:=old.created_at; new.revision:=old.revision+1;
 else
  new.author_id:=auth.uid(); new.created_at:=now(); new.revision:=1;
  select coalesce(n.display_name,split_part(u.email,'@',1)),a.access_role into new.author_label,new.author_role
   from auth.users u join public.participant_access a on a.user_id=u.id
   join public.team_consultations c on c.participant_id=a.participant_id
   left join private.consultation_names n on n.email=lower(u.email)
   where u.id=auth.uid() and c.id=new.consultation_id;
 end if;
 new.updated_at:=now();
 if new.parent_id is not null and not exists(select 1 from public.consultation_contributions p where p.id=new.parent_id and p.consultation_id=new.consultation_id) then raise exception 'Reply must belong to this consultation'; end if;
 if new.kind='attachment' and not exists (
  select 1 from storage.objects o where o.bucket_id='consultation-reports' and o.name=new.payload->>'path'
   and split_part(o.name,'/',1)=new.consultation_id::text and split_part(o.name,'/',2)=auth.uid()::text
 ) then raise exception 'Upload the report before sharing it'; end if;
 return new;
end $$;
create function private.consultation_audit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or new.author_id<>auth.uid() or not private.consultation_access(new.consultation_id,true) then raise exception 'Not authorised'; end if;
 insert into public.consultation_revisions(contribution_id,consultation_id,revision,author_id,author_label,author_role,payload,saved_at)
 values(new.id,new.consultation_id,new.revision,new.author_id,new.author_label,new.author_role,new.payload,new.updated_at);
 return new;
end $$;
revoke all on function private.consultation_stamp(),private.consultation_audit() from public,anon,authenticated;
create trigger consultation_stamp before insert or update on public.consultation_contributions for each row execute function private.consultation_stamp();
create trigger consultation_audit after insert or update on public.consultation_contributions for each row execute function private.consultation_audit();

create function public.save_consultation_contribution(p_consultation uuid,p_kind text,p_payload jsonb,p_id uuid default null,p_expected_revision integer default null,p_parent uuid default null)
returns public.consultation_contributions language plpgsql security invoker set search_path='' as $$
declare result public.consultation_contributions;
begin
 if p_id is null then
  insert into public.consultation_contributions(consultation_id,kind,payload,parent_id,author_id,author_label,author_role)
  values(p_consultation,p_kind,p_payload,p_parent,auth.uid(),'','') returning * into result;
 else
  update public.consultation_contributions set payload=p_payload
  where id=p_id and consultation_id=p_consultation and kind=p_kind and author_id=auth.uid() and revision=p_expected_revision
  returning * into result;
  if not found then raise exception 'Response has changed or is not editable. Reload it before saving.'; end if;
 end if;
 return result;
end $$;
revoke all on function public.save_consultation_contribution(uuid,text,jsonb,uuid,integer,uuid) from public,anon;
grant execute on function public.save_consultation_contribution(uuid,text,jsonb,uuid,integer,uuid) to authenticated;

-- Only the roster for an authorised consultation is returned, never the user directory.
create function private.consultation_roster(cid uuid)
returns table(user_id uuid,display_name text,access_role text,can_write boolean,invitation_status text)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.consultation_access(cid) then raise exception 'Not authorised'; end if;
 return query
 select a.user_id,coalesce(n.display_name,split_part(u.email,'@',1)),a.access_role,a.can_write,'Active'::text
 from public.team_consultations c join public.participant_access a on a.participant_id=c.participant_id
 join auth.users u on u.id=a.user_id left join private.consultation_names n on n.email=lower(u.email)
 where c.id=cid and a.can_view
 union all
 select null::uuid,coalesce(n.display_name,split_part(p.email,'@',1)),p.access_role,p.can_write,'Invited — awaiting sign-in'::text
 from public.team_consultations c join private.pending_participant_access p on p.participant_id=c.participant_id
 left join private.consultation_names n on n.email=lower(p.email)
 where c.id=cid and p.can_view and not exists (
 select 1 from auth.users u join public.participant_access a on a.user_id=u.id and a.participant_id=p.participant_id where lower(u.email)=lower(p.email));
end $$;
revoke all on function private.consultation_roster(uuid) from public,anon;
grant execute on function private.consultation_roster(uuid) to authenticated;
create function public.consultation_roster(p_consultation uuid)
returns table(user_id uuid,display_name text,access_role text,can_write boolean,invitation_status text)
language sql stable security invoker set search_path='' as $$ select * from private.consultation_roster(p_consultation); $$;
revoke all on function public.consultation_roster(uuid) from public,anon;
grant execute on function public.consultation_roster(uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('consultation-reports','consultation-reports',false,10485760,array['application/pdf','image/jpeg','image/png','application/vnd.openxmlformats-officedocument.wordprocessingml.document']);
create function private.consultation_file_access(object_name text,writing boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.team_consultations c
 where c.id::text=split_part(object_name,'/',1) and private.consultation_access(c.id,writing)
 and (not writing or split_part(object_name,'/',2)=auth.uid()::text));
$$;
revoke all on function private.consultation_file_access(text,boolean) from public,anon;
grant execute on function private.consultation_file_access(text,boolean) to authenticated;
create policy consultation_report_insert on storage.objects for insert to authenticated
 with check(bucket_id='consultation-reports' and private.consultation_file_access(name,true));
create policy consultation_report_read on storage.objects for select to authenticated
 using(bucket_id='consultation-reports' and private.consultation_file_access(name));
-- No UPDATE or DELETE policy: shared report originals cannot be overwritten or removed.
