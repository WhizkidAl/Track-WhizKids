-- Once periods exist, contributors can save only scheduled sections/dates.
-- The coordinator retains correction access; period setup never removes old data.
create or replace function private.check_tracker_schedule() returns trigger language plpgsql security definer set search_path='' as $$
declare pid uuid; dt date; p private.tracker_periods;
begin
 if tg_table_name='tracker_days' then pid:=new.participant_id;dt:=new.tracking_date;
 else select participant_id,tracking_date into pid,dt from public.tracker_days where id=new.tracker_day_id; end if;
 if private.tracker_owner(pid) or not exists(select 1 from private.tracker_periods where participant_id=pid) then return new; end if;
 select * into p from private.tracker_periods where participant_id=pid and dt between start_date and end_date;
 if p.id is null or not (extract(isodow from dt)::integer=any(p.weekdays)) or dt=any(p.excluded_dates) then raise exception 'No monitoring is scheduled for this date'; end if;
 if tg_table_name='school_checkpoints' and not ((to_jsonb(new)->>'checkpoint')=any(p.checkpoints)) then raise exception 'This school checkpoint is not scheduled'; end if;
 if tg_table_name='tracker_days' then
  if not p.home_expected and coalesce(new.sleep,new.breakfast,new.home_morning,new.medication_status,new.parent_comment,new.morning_completed_by) is not null then raise exception 'The home section is not scheduled'; end if;
 end if;
 return new;
end; $$;
revoke all on function private.check_tracker_schedule() from public,anon,authenticated;
create trigger enforce_tracker_schedule before insert or update on public.tracker_days for each row execute function private.check_tracker_schedule();
create trigger enforce_checkpoint_schedule before insert or update on public.school_checkpoints for each row execute function private.check_tracker_schedule();
create trigger enforce_incident_schedule before insert or update on public.incidents for each row execute function private.check_tracker_schedule();
