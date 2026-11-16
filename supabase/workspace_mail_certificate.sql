create table private.workspace_mail_configuration(singleton boolean primary key default true check(singleton),client_id text not null,tenant_id text not null,thumbprint text not null,secret_id uuid not null,expires_on date not null);
alter table private.workspace_mail_configuration enable row level security;
revoke all on private.workspace_mail_configuration from public,anon,authenticated;
create function private.workspace_mail_configuration() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service access required' using errcode='42501';end if;
 return coalesce((select jsonb_build_object('clientId',c.client_id,'tenantId',c.tenant_id,'thumbprint',c.thumbprint,'privateKey',v.decrypted_secret) from private.workspace_mail_configuration c join vault.decrypted_secrets v on v.id=c.secret_id where c.expires_on>current_date),'{}'::jsonb);
end$$;
create function public.workspace_mail_configuration() returns jsonb language sql stable security invoker set search_path='' as $$select private.workspace_mail_configuration()$$;
revoke all on function private.workspace_mail_configuration(),public.workspace_mail_configuration() from public,anon,authenticated;
grant execute on function private.workspace_mail_configuration(),public.workspace_mail_configuration() to service_role;
