# PAT @ Whiz Kids portable access to therapy

This module connects the child interface to Supabase authentication, participant access rules and durable activity records. It follows the repository boundary: application code in GitHub, participant configuration and records in Supabase, and formal documents with their existing owners.

## Current implementation status

The dedicated PAT @ Whiz Kids Supabase project is created in Sydney. Its foundation and portable-hub schemas are installed. Authorised save, structured record creation, history, version conflict and unrelated-account denial were checked in a transaction that was rolled back. No test activity records remain.

The project destination is selected. Private participant configuration import and actual account assignment are paused pending explicit approval. The incomplete import buffer was cleared. This branch is not a published replacement for the existing child app.

## Files

- `portable-practice.html`: parent sign-in and authenticated child workspace.
- `portable-practice-cloud.js`: connection status, private local journal, serialised saves and conflict handling.
- `portable-practice-app.html`: child interface template. No participant configuration or personalised images are embedded.
- `portable-practice-sw.js`: caches application files only. Supabase responses are not cached by the service worker.
- `portable-practice.webmanifest`: Home screen metadata.
- `supabase/portable_practice_schema.sql`: database tables, policies, audit trigger and save function.

## Data and permissions

Apply `supabase/pat_foundation.sql` before `supabase/portable_practice_schema.sql` on a fresh PAT project. Do not apply the foundation to an existing Track database.

`pat_hubs` holds the private configuration, current snapshot and family recordings. Its rows are limited to authorised parents and clinicians with view access. Saving also requires write permission.

`pat_activity_records` makes feedback, approval status, dates, observed engagement and support available as structured records. The full record retains task details, child feedback and coin corrections. Authorised team members with participant view access can read these activity records.

`pat_hub_history` retains state snapshots. It is limited to authorised parents and clinicians. No anonymous read or save permission is granted. The browser uses only the publishable key. No server secret or participant credential belongs in Git.

The parent PIN remains a local interface control within an already authorised session. Supabase authentication and row policies provide the access boundary.

## Saving and interrupted connections

The interface distinguishes saved-to-cloud from saved-here-and-waiting. It keeps pending changes in a private IndexedDB journal and retries after connectivity returns. An unavailable local journal is reported rather than represented as a successful offline save.

Each save supplies the revision it started from. A newer server revision returns a conflict. The app retains the local copy, pauses automatic writes, and offers a private backup download before loading the cloud version. It does not silently merge coin approvals or replace another device's changes.

Browser data deletion before a pending change syncs can still lose that pending change. Successfully synced data is independent of the original device. Full backups remain available.

## Initial migration

1. Confirm approval to import the participant’s private configuration and assign the named accounts. The destination is the dedicated PAT @ Whiz Kids project in Sydney.
2. Provision the private hub configuration outside Git, with participant access assigned to verified accounts.
3. In Supabase Authentication URL Configuration, set the published PAT page as the Site URL and an allowed redirect URL. This dashboard step is not complete. Sign in to the PAT app with a pre-authorised clinician account, then use Family connection to allow the verified parent email. First sign-in creates the account; matching pending permissions attach automatically. Load the module using that authorised parent account on the child device. Do not leave a clinician account with access to other participants signed in on the child's tablet.
4. Make a Full backup in the old child app. Restore it in the connected app, then confirm the cloud saved status and record totals.
5. Keep the old backup until records, routines, settings and family recordings are checked.
6. Publish the reviewed code and add the stable page to the device's Home screen. Lock the Home screen layout if appropriate for the family.

Do not substitute a generated empty record for an existing tablet record. The source HTML does not contain that tablet's accumulated activity history.

## Animation apps

The family connection panel and creative choices link to the official Google Play pages:

- OctoStudio: https://play.google.com/store/apps/details?id=edu.mit.octostudio
- Stop Motion Studio: https://play.google.com/store/apps/details?id=com.cateater.stopmotionstudio

Install on the Android tablet. If an app is already installed, use Google Play's Open button or its Android Home screen icon. Opening a store link does not prove an installation completed. This module does not claim to install an Android package remotely or guarantee a native launcher deep link.

## Verification limits

Cloud queue, offline retention, retry, conflicting revisions, edits during an in-flight save, cross-participant guarding, escaping and public-source privacy were checked using the actual application scripts in DOM tests. Database access rules and save behaviour were checked in the live project within a rollback transaction. Parent access attachment, parent invitations and unauthorised-access denial were also tested in a rollback transaction in the new PAT project. Tablet installation and end-to-end family sign-in remain device checks; authentication redirect configuration and private participant migration are not complete.
