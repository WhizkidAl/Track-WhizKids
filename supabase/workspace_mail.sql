create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;
create table private.workspace_mail_connections(user_id uuid primary key references auth.users(id),email text not null,secret_id uuid not null,connected_at timestamptz not null default now());
create table private.workspace_mail_states(state text primary key,user_id uuid not null references auth.users(id),verifier text not null,expires_at timestamptz not null default now()+interval '10 minutes');
create table private.workspace_mail_jobs(id uuid primary key,participant_id uuid not null references public.participants(id),user_id uuid not null references auth.users(id),recipients text[] not null,subject text not null,body text not null,send_at timestamptz not null,status text not null default 'scheduled' check(status in ('scheduled','sending','accepted','failed','uncertain','cancelled')),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),detail text);
create table private.workspace_mail_worker(secret text not null);
insert into private.workspace_mail_worker values(gen_random_uuid()::text||gen_random_uuid()::text);
alter table private.workspace_mail_connections enable row level security;
alter table private.workspace_mail_states enable row level security;
alter table private.workspace_mail_jobs enable row level security;
alter table private.workspace_mail_worker enable row level security;
revoke all on private.workspace_mail_connections,private.workspace_mail_states,private.workspace_mail_jobs,private.workspace_mail_worker from public,anon,authenticated;
create index workspace_mail_due on private.workspace_mail_jobs(send_at) where status='scheduled';

create function private.workspace_mail_recipients(pid uuid,addresses text[]) returns boolean language sql stable security definer set search_path='' as $$
 select cardinality(addresses) between 1 and 50 and not exists(select 1 from unnest(addresses) address where not exists(select 1 from public.participant_access a join auth.users u on u.id=a.user_id where a.participant_id=pid and a.can_view and lower(u.email)=lower(address)) and not exists(select 1 from private.pending_participant_access a where a.participant_id=pid and a.can_view and lower(a.email)=lower(address)));
$$;
revoke all on function private.workspace_mail_recipients(uuid,text[]) from public,anon,authenticated;
create function private.workspace_mail_service(p_op text,p_actor uuid,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid;pid uuid;addresses text[];jid uuid;rowdata private.workspace_mail_jobs;state_row private.workspace_mail_states;result jsonb;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service access required' using errcode='42501';end if;
 if p_op='worker_secret' then return jsonb_build_object('secret',(select secret from private.workspace_mail_worker limit 1));end if;
 if p_op='take_state' then delete from private.workspace_mail_states where state=p_data->>'state' and expires_at>now() returning * into state_row;return to_jsonb(state_row);end if;
 if p_op='claim' then
  update private.workspace_mail_jobs set status='uncertain',detail='The send did not finish reporting its result. Check Sent Items before sending again.',updated_at=now() where status='sending' and updated_at<now()-interval '10 minutes';
  with due as(select id from private.workspace_mail_jobs where status='scheduled' and send_at<=now() order by send_at for update skip locked limit 5),claimed as(update private.workspace_mail_jobs j set status='sending',updated_at=now() from due where j.id=due.id returning j.*) select coalesce(jsonb_agg(to_jsonb(claimed)),'[]'::jsonb) into result from claimed;return result;
 end if;
 if p_op='finish' then update private.workspace_mail_jobs set status=p_data->>'status',detail=left(p_data->>'detail',500),updated_at=now() where id=(p_data->>'id')::uuid and status='sending';return '{}'::jsonb;end if;
 if p_op='validate_job' then select * into rowdata from private.workspace_mail_jobs where id=(p_data->>'id')::uuid and status='sending';return jsonb_build_object('valid',rowdata.id is not null and exists(select 1 from private.tracker_owners o join public.participant_access a on a.participant_id=o.participant_id and a.user_id=o.user_id join public.participants p on p.id=o.participant_id where o.participant_id=rowdata.participant_id and o.user_id=rowdata.user_id and a.can_view and p.active) and private.workspace_mail_recipients(rowdata.participant_id,rowdata.recipients));end if;
 if p_actor is null or not exists(select 1 from private.tracker_administrators where user_id=p_actor) then raise exception 'Coordinator access required' using errcode='42501';end if;
 if p_op='status' then return jsonb_build_object('connected',exists(select 1 from private.workspace_mail_connections where user_id=p_actor),'email',(select email from auth.users where id=p_actor));end if;
 if p_op='state' then
  delete from private.workspace_mail_states where expires_at<now();
  insert into private.workspace_mail_states(state,user_id,verifier) values(p_data->>'state',p_actor,p_data->>'verifier');return '{}'::jsonb;
 end if;
 if p_op='token' then return (select jsonb_build_object('refresh_token',v.decrypted_secret,'email',c.email) from private.workspace_mail_connections c join vault.decrypted_secrets v on v.id=c.secret_id where c.user_id=p_actor);end if;
 if p_op='connect' then
  if lower(p_data->>'email') is distinct from (select lower(email) from auth.users where id=p_actor) then raise exception 'Use the same Whiz Kids mailbox as your coordinator email';end if;
  if length(p_data->>'refresh_token')<20 then raise exception 'Microsoft did not supply a refresh token';end if;
  select secret_id into sid from private.workspace_mail_connections where user_id=p_actor for update;
  if sid is null then select vault.create_secret(p_data->>'refresh_token') into sid;else perform vault.update_secret(sid,p_data->>'refresh_token');end if;
  insert into private.workspace_mail_connections values(p_actor,lower(p_data->>'email'),sid,now()) on conflict(user_id) do update set email=excluded.email,secret_id=excluded.secret_id,connected_at=excluded.connected_at;
  return '{}'::jsonb;
 end if;
 pid:=(p_data->>'participant_id')::uuid;
 if not exists(select 1 from private.tracker_owners o join public.participant_access a on a.participant_id=o.participant_id and a.user_id=o.user_id where o.participant_id=pid and o.user_id=p_actor and a.can_view) then raise exception 'Client coordinator access required' using errcode='42501';end if;
 if p_op='list' then return coalesce((select jsonb_agg(jsonb_build_object('id',id,'recipients',recipients,'subject',subject,'send_at',send_at,'status',status,'detail',detail) order by created_at desc) from (select * from private.workspace_mail_jobs where participant_id=pid and user_id=p_actor order by created_at desc limit 50) j),'[]'::jsonb);end if;
 if p_op='cancel' then update private.workspace_mail_jobs set status='cancelled',updated_at=now() where id=(p_data->>'id')::uuid and participant_id=pid and user_id=p_actor and status='scheduled';if not found then raise exception 'This email has already started sending or is no longer scheduled';end if;return '{}'::jsonb;end if;
 if p_op='queue' then
  if not exists(select 1 from private.workspace_mail_connections where user_id=p_actor) then raise exception 'Connect your Microsoft mailbox first';end if;
  select array_agg(distinct lower(trim(value))) into addresses from jsonb_array_elements_text(p_data->'recipients');
  if not coalesce(private.workspace_mail_recipients(pid,addresses),false) then raise exception 'Recipients must be on this client’s authorised team';end if;
  if length(trim(p_data->>'subject')) not between 1 and 250 or length(trim(p_data->>'body')) not between 1 and 50000 then raise exception 'Add a subject and email body';end if;
  if (p_data->>'send_at')::timestamptz>now()+interval '1 year' or (p_data->>'send_at')::timestamptz<now()-interval '2 minutes' then raise exception 'Choose a send time within the next year';end if;
  jid:=(p_data->>'id')::uuid;
  insert into private.workspace_mail_jobs(id,participant_id,user_id,recipients,subject,body,send_at) values(jid,pid,p_actor,addresses,p_data->>'subject',p_data->>'body',(p_data->>'send_at')::timestamptz) on conflict(id) do nothing;
  select * into rowdata from private.workspace_mail_jobs where id=jid;
  if rowdata.user_id<>p_actor or rowdata.participant_id<>pid then raise exception 'Email identifier already in use';end if;
  return jsonb_build_object('id',rowdata.id,'status',rowdata.status);
 end if;
 raise exception 'Unknown mail operation';
end $$;
create function public.workspace_mail_service(p_op text,p_actor uuid,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.workspace_mail_service(p_op,p_actor,p_data)$$;
revoke all on function private.workspace_mail_service(text,uuid,jsonb),public.workspace_mail_service(text,uuid,jsonb) from public,anon,authenticated;
grant usage on schema private to service_role;
grant execute on function private.workspace_mail_service(text,uuid,jsonb),public.workspace_mail_service(text,uuid,jsonb) to service_role;

create function private.dispatch_workspace_mail() returns void language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from private.workspace_mail_jobs where (status='scheduled' and send_at<=now()) or (status='sending' and updated_at<now()-interval '10 minutes')) then
 perform net.http_post(url:='https://fplfahemudvbeqqcmvbe.supabase.co/functions/v1/workspace-mail/worker',headers:=jsonb_build_object('Content-Type','application/json','x-worker-secret',(select secret from private.workspace_mail_worker limit 1)),body:='{}'::jsonb);
 end if;
end $$;
revoke all on function private.dispatch_workspace_mail() from public,anon,authenticated;
select cron.schedule('workspace-mail-outbox','* * * * *','select private.dispatch_workspace_mail()');
