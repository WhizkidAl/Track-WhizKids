# Reusable tracker dashboard

Open `tracker-admin.html` directly or follow **Tracker completion & analysis** from `admin.html`. Coordinator ownership is separate from an Action Plan, so a new client can use the tracker without a consultation. Only explicitly provisioned tracker administrators may create clients. Creation gives access only to that administrator; team access is then configured for that client. No email is sent by access setup.

The initial owner/administrator seed comes from existing consultation coordinators. Other practice-tool participants are not silently enrolled as trackers. No client is created by application startup, demo code or the migration.

## Completion and analysis

The date-by-section table shows four home context answers and school participation/regulation ratings, optional entered names, latest saved accounts and timestamps. Complete requires all four home context values or both school ratings. A name or blank saved row alone is not complete. Older records retain their existing latest-save metadata; full section history is captured prospectively in an internal audit table. Previous versions of older records cannot be reconstructed.

Analysis includes independent participation/regulation distributions per checkpoint, weekly regulation counts/rates, grouped morning-context observations, reported support effects and incident coverage. Each calculation shows its available-data denominator. Missing ratings are never counted as settled. Context denominators include only days with that context answer and a school rating. This is descriptive association, not causal or clinical inference. Strategy effects can reflect several strategies used together. Unknown or missing effects do not enter the known-effect denominator.

## Periods and schedules

Each client can have non-overlapping named periods with start/end dates, selected weekdays, excluded dates, an optional home section and one to three school checks. One check means end of day; two means before lunch and end of day; three adds mid-morning. Gaps between periods are pauses. Historical data are retained. Excluded dates handle holidays or known non-attendance. Future and current-day gaps are not counted as past missing sections.

No historical dates are inferred. Until a period is explicitly configured, all three legacy school checkpoints remain available and missing-day totals are unset. The old fixed 15-day progress target is hidden because it was not configured per client. The database rejects contributor saves outside configured schedules; coordinators retain database correction access. The tracker screen displays only the scheduled school checkpoints and disables unscheduled sections. Monitoring dates are calendar dates in Perth time.

## Access and storage

New internal tables live in the private schema with RLS enabled and no direct client grants. Public invoker wrappers call narrow private functions that check authenticated coordinator ownership and current participant view membership. School, parent and allied-health members can read their assigned schedule but cannot use the administrator endpoints. Audit rows capture the server-authenticated actor, time and saved snapshot. The original tracker edit permissions remain in place; this release does not convert tracker entries into immutable submissions.

Apply `supabase/tracker_management.sql`, then `supabase/tracker_schedule_guard.sql` and `supabase/tracker_assigned_clients.sql`. These are additive and do not change existing clinical records or configure client dates. Member access changes are specific to the selected client. Existing consultation-specific permission overrides remain separate. The tracker participant selector lists assigned tracker clients, excluding participants who belong only to other tools.

## Validation

- `node --test tests/tracker-analysis.test.cjs tests/email-code-auth.test.cjs`
- `node tests/tracker-admin-browser.cjs`
- `node tests/tracker-readonly-browser.cjs`
- Existing consultation and coordinator-dashboard browser checks.
- Run `tests/tracker-management-rollback.sql` through a trusted database connection. It creates a tracker only within a rolled-back transaction and verifies ownership, school access denial, excluded dates, checkpoint schedules, saved attribution and retained versions.

Browser checks cover multiple clients, period settings, read-only access, empty/error states, sign-out clearing, safe rendering, mobile width and CSV formula escaping. No synthetic client or test entry is retained. Clinical artifacts and screenshots stay in ignored `private/`.
