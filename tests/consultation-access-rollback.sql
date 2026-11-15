-- Run as a transaction and always roll back: no fixtures survive.
begin;
create temporary table consultation_test_state as
 select c.id as cid,c.coordinator_user_id as coordinator,
 (select a.user_id from public.participant_access a where a.participant_id=c.participant_id and a.user_id<>c.coordinator_user_id and a.can_write limit 1) as colleague,
 c.participant_id as pid,gen_random_uuid() as outsider,null::uuid as entry
 from public.team_consultations c limit 1;
grant select,update on consultation_test_state to authenticated,anon;
select set_config('request.jwt.claims',json_build_object('sub',coordinator,'role','authenticated')::text,true) from consultation_test_state;
set local role authenticated;
do $$ declare s record; row public.consultation_contributions; n integer; begin
 select * into s from consultation_test_state;
 if (select count(*) from public.team_consultations)<>1 then raise exception 'Expected one consultation'; end if;
 if (select count(*) from public.consultation_roster(s.cid))<2 then raise exception 'Roster missing'; end if;
 select * into row from public.save_consultation_contribution(s.cid,'priority','{"answers":{"test":"original"}}');
 if row.author_id<>s.coordinator or row.revision<>1 then raise exception 'Attribution failed'; end if;
 update consultation_test_state set entry=row.id;
 perform public.save_consultation_contribution(s.cid,'priority','{"answers":{"test":"revised"}}',row.id,1);
 if (select count(*) from public.consultation_revisions where contribution_id=row.id)<>2 then raise exception 'History not atomic'; end if;
 begin
  perform public.save_consultation_contribution(s.cid,'priority','{"answers":{"test":"stale"}}',row.id,1);
  raise exception 'Stale save unexpectedly succeeded' using errcode='ZX001';
 exception when sqlstate 'P0001' then null; end;
 begin delete from public.consultation_revisions where contribution_id=row.id; raise exception 'History delete allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',colleague,'role','authenticated')::text,true) from consultation_test_state;
set local role authenticated;
do $$ declare s record; r public.consultation_contributions; n integer; begin
 select * into s from consultation_test_state;
 if (select count(*) from public.consultation_contributions where id=s.entry)<>1 then raise exception 'Shared contribution not visible'; end if;
 update public.consultation_contributions set payload='{}' where id=s.entry; get diagnostics n=row_count;
 if n<>0 then raise exception 'Could edit another author'; end if;
 begin perform public.save_consultation_contribution(s.cid,'priority','{}',s.entry,2);raise exception 'Other author edit succeeded' using errcode='ZX001';exception when sqlstate 'P0001' then null;end;
 begin update public.team_consultations set purpose='Unauthorized scope change' where id=s.cid;get diagnostics n=row_count;if n<>0 then raise exception 'Contributor changed purpose';end if;end;
 select * into r from public.save_consultation_contribution(s.cid,'comment','{"answers":{"comment":"reply"}}',null,null,s.entry);
 if r.author_id<>s.colleague then raise exception 'Wrong reply attribution'; end if;
 -- The browser cannot forge the author fields even via direct INSERT.
 insert into public.consultation_contributions(consultation_id,kind,payload,author_id,author_label,author_role)
 values(s.cid,'comment','{}',s.coordinator,'Forged name','admin') returning * into r;
 if r.author_id<>s.colleague or r.author_label='Forged name' then raise exception 'Author spoofing allowed';end if;
 insert into storage.objects(bucket_id,name) values('consultation-reports',s.cid::text||'/'||s.colleague::text||'/rollback-test.pdf');
 begin insert into storage.objects(bucket_id,name) values('consultation-reports',s.cid::text||'/'||s.coordinator::text||'/wrong-owner.pdf');raise exception 'Wrong upload owner allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
update public.participant_access a set can_write=false from consultation_test_state s where a.participant_id=s.pid and a.user_id=s.colleague;
set local role authenticated;
do $$ declare s record;begin
 select * into s from consultation_test_state;
 if (select count(*) from public.consultation_contributions)<1 then raise exception 'Viewer cannot read';end if;
 begin perform public.save_consultation_contribution(s.cid,'comment','{}');raise exception 'Viewer wrote' using errcode='ZX001';exception when sqlstate 'P0001' then null;when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',outsider,'role','authenticated')::text,true) from consultation_test_state;
set local role authenticated;
do $$ declare s record;begin
 select * into s from consultation_test_state;
 if (select count(*) from public.team_consultations)<>0 or (select count(*) from public.consultation_contributions)<>0 or (select count(*) from public.consultation_revisions)<>0 then raise exception 'Outsider read data';end if;
 if exists(select 1 from storage.objects where bucket_id='consultation-reports') then raise exception 'Outsider read reports';end if;
 begin perform public.consultation_roster(s.cid);raise exception 'Outsider read roster' using errcode='ZX001';exception when sqlstate 'P0001' then null;end;
end $$;
reset role;
set local role anon;
do $$ begin begin perform 1 from public.team_consultations;raise exception 'Anonymous read allowed';exception when insufficient_privilege then null;end;end $$;
reset role;
select 'PASS: identity, own edits, immutable audit, stale edit rejection, roster, read-only/outsider/anonymous access, purpose ownership and report paths' as result;
rollback;
