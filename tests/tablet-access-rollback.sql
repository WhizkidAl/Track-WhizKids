do $$
declare test_uid uuid:=gen_random_uuid(); parent_uid uuid:=gen_random_uuid(); target_pid uuid; oldrev bigint; result jsonb; affected integer;
 snapshot jsonb:='{"version":4,"entries":[{"id":"tablet-setup-test","activity":"setup-test","date":"2026-11-13","outcome":"finished","status":"pending"}]}'::jsonb;
begin
 select participant_id,revision into target_pid,oldrev from public.pat_hubs limit 1;
 insert into auth.users(id,email,email_confirmed_at,aud,role) values(test_uid,'tablet-check@example.invalid',now(),'authenticated','authenticated'),(parent_uid,'parent-check@example.invalid',now(),'authenticated','authenticated');
 insert into public.participant_access(participant_id,user_id,access_role,can_view,can_write) values(target_pid,test_uid,'tablet',true,true),(target_pid,parent_uid,'parent',true,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',test_uid,'role','authenticated')::text,true);
 perform set_config('role','authenticated',true);
 if not exists(select 1 from public.pat_hubs where participant_id=target_pid) then raise exception 'Tablet read denied'; end if;
 result:=public.pat_save_snapshot(target_pid,oldrev,snapshot,'{}');
 if result->>'conflict'<>'false' then raise exception 'Tablet save failed'; end if;
 if not exists(select 1 from public.pat_activity_records where participant_id=target_pid and record_id='tablet-setup-test') then raise exception 'Tablet record missing'; end if;
 result:=public.pat_save_snapshot(target_pid,oldrev,snapshot,'{}');
 if result->>'duplicate'<>'true' then raise exception 'Retry not idempotent'; end if;
 result:=public.pat_save_snapshot(target_pid,oldrev,'{"version":4,"entries":[]}','{}');
 if result->>'conflict'<>'true' then raise exception 'Conflict not detected'; end if;
 update public.pat_hubs set configuration='{}' where participant_id=target_pid;
 get diagnostics affected=row_count;
 if affected<>0 then raise exception 'Tablet changed configuration'; end if;
 begin perform public.pat_allow_parent(target_pid,'unauthorised@example.invalid'); raise exception 'Tablet granted parent access'; exception when insufficient_privilege then null; end;
 begin insert into public.participant_access(participant_id,user_id,access_role,can_view,can_write) values(target_pid,test_uid,'parent',true,true); raise exception 'Tablet changed roles'; exception when insufficient_privilege then null; end;
 begin perform public.pat_save_snapshot(gen_random_uuid(),0,snapshot,'{}'); raise exception 'Tablet saved unrelated hub'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',parent_uid,'role','authenticated')::text,true);
 result:=public.pat_save_snapshot(target_pid,oldrev+1,'{"version":4,"entries":[]}','{}');
 if result->>'conflict'<>'false' then raise exception 'Parent save failed'; end if;
 perform public.pat_allow_parent(target_pid,'invited-parent@example.invalid');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
 if exists(select 1 from public.pat_hubs where participant_id=target_pid) then raise exception 'Unrelated user read allowed'; end if;
 begin perform public.pat_save_snapshot(target_pid,oldrev,snapshot,'{}'); raise exception 'Unrelated user save allowed'; exception when insufficient_privilege then null; end;
end $$;

