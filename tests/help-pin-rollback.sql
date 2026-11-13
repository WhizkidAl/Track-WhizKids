do $$
declare tablet_uid uuid:=gen_random_uuid(); parent_uid uuid:=gen_random_uuid(); target_pid uuid; rev bigint; result jsonb; event_id uuid:=gen_random_uuid(); hash text:='sha256:'||repeat('a',64); salt text:=repeat('b',32);
begin
 select participant_id,revision into target_pid,rev from public.pat_hubs where snapshot is not null limit 1;
 insert into auth.users(id,email,email_confirmed_at,aud,role) values(tablet_uid,'help-check@example.invalid',now(),'authenticated','authenticated'),(parent_uid,'pin-check@example.invalid',now(),'authenticated','authenticated');
 insert into public.participant_access(participant_id,user_id,access_role,can_view,can_write) values(target_pid,tablet_uid,'tablet',true,true),(target_pid,parent_uid,'parent',true,true);
 if not exists(select 1 from private.pat_notification_preferences where participant_id=target_pid) then insert into private.pat_notification_preferences values(target_pid,'parent@example.invalid',true); end if;
 -- Service entrypoint authorises ownership and creates one durable, idempotent request.
 result:=public.pat_prepare_help(tablet_uid,target_pid,event_id,'show','Test activity');
 if result->>'status'<>'queued' then raise exception 'Help not queued'; end if;
 result:=public.pat_prepare_help(tablet_uid,target_pid,event_id,'show','Test activity');
 if result->>'id'<>event_id::text then raise exception 'Help retry not idempotent'; end if;
 result:=public.pat_prepare_help(tablet_uid,target_pid,gen_random_uuid(),'break','Test activity');
 if result->>'rate_limited'<>'true' then raise exception 'Help not rate limited'; end if;
 begin perform public.pat_prepare_help(gen_random_uuid(),target_pid,gen_random_uuid(),'show','Test activity'); raise exception 'Unrelated sender accepted'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',tablet_uid,'role','authenticated')::text,true);
 perform set_config('role','authenticated',true);
 begin perform public.pat_prepare_help(tablet_uid,target_pid,event_id,'show','Test activity'); raise exception 'Tablet bypassed mail service'; exception when insufficient_privilege then null; end;
 begin perform public.pat_set_family_pin(target_pid,rev,hash,salt); raise exception 'Tablet reset PIN'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',parent_uid,'role','authenticated')::text,true);
 result:=public.pat_set_family_pin(target_pid,rev,hash,salt);
 if result->>'conflict'<>'false' then raise exception 'Parent PIN failed'; end if;
 result:=public.pat_set_family_pin(target_pid,rev,hash,salt);
 if result->>'conflict'<>'true' then raise exception 'PIN conflict missed'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',tablet_uid,'role','authenticated')::text,true);
 result:=public.pat_save_snapshot(target_pid,rev+1,'{"version":4,"entries":[],"pin":"overwritten","salt":"changed"}','{}');
 if result->>'conflict'<>'false' then raise exception 'Tablet save failed'; end if;
 if not exists(select 1 from public.pat_hubs where participant_id=target_pid and snapshot->>'pin'=hash and snapshot->>'salt'=salt) then raise exception 'Tablet replaced protected PIN'; end if;
end $$;
