-- Read-only coordinator overview. No clinical response bodies are returned.
create function public.consultation_dashboard(p_consultation uuid)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare c public.team_consultations; result jsonb;
begin
 select * into c from public.team_consultations where id=p_consultation;
 if c.id is null or c.coordinator_user_id is distinct from auth.uid() or not private.consultation_access(c.id) then
  raise exception 'Coordinator access required' using errcode='42501';
 end if;
 select jsonb_build_object(
  'team',coalesce((select jsonb_agg(to_jsonb(r)) from public.consultation_roster(c.id) r),'[]'::jsonb),
  'contributions',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'author_id',r.author_id,'author_label',r.author_label,'kind',r.kind,'revision',r.revision,'created_at',r.created_at,'updated_at',r.updated_at,'incident_status',case when r.kind='incident' then r.payload->'answers'->>'Incident contribution' end)) from public.consultation_contributions r where r.consultation_id=c.id),'[]'::jsonb),
  'activity',coalesce((select jsonb_agg(jsonb_build_object('contribution_id',r.contribution_id,'author_label',r.author_label,'kind',v.kind,'revision',r.revision,'saved_at',r.saved_at)) from public.consultation_revisions r join public.consultation_contributions v on v.id=r.contribution_id where r.consultation_id=c.id),'[]'::jsonb),
  'tracker',coalesce((select jsonb_agg(jsonb_build_object('date',d.tracking_date,'home',d.morning_completed_by is not null,'school', (select count(*) from public.school_checkpoints s where s.tracker_day_id=d.id and (s.participation is not null or s.regulation is not null)))) from public.tracker_days d where d.participant_id=c.participant_id),'[]'::jsonb)
 ) into result;
 return result;
end; $$;
revoke all on function public.consultation_dashboard(uuid) from public,anon;
grant execute on function public.consultation_dashboard(uuid) to authenticated;
