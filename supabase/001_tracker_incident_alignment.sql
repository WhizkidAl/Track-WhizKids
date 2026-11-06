-- Whiz Kids Track
-- One-time schema adjustment for the shared participation/regulation tracker.
-- Safe to run once in the Supabase SQL editor.

alter table public.incidents
  add column if not exists occurred boolean not null default true;

alter table public.incidents
  add column if not exists school_incident_process_status text;

update public.incidents
set school_incident_process_status =
  case
    when school_incident_process_completed is true then 'Completed'
    when school_incident_process_completed is false then 'To be completed'
    else null
  end
where school_incident_process_status is null;

create unique index if not exists incidents_tracker_day_unique
  on public.incidents(tracker_day_id);
