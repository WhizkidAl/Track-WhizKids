# My Base portable practice

This module connects the child interface to Supabase authentication, participant access rules and durable activity records. It follows the repository boundary: application code in GitHub, participant configuration and records in Supabase, and formal documents with their existing owners.

## Current implementation status

The database schema is installed. Authorised save, structured record creation, history, version conflict and unrelated-account denial were checked in a transaction that was rolled back. No test activity records remain.

Private configuration import is paused pending confirmation of the destination project. The incomplete import buffer was cleared. This branch is not a published replacement for the existing child app.

## Files

- `portable-practice.html`: parent sign-in and authenticated child workspace.
- `portable-practice-cloud.js`: connection status, private local journal, serialised saves and conflict handling.
- `portable-practice-app.html`: child interface template. No participant configuration or personalised images are embedded.
- `portable-practice-bridge.js`: source for the bridge embedded in the app template.
- `portable-practice-sw.js`: caches application files only. Supabase responses are not cached by the service worker.
- `portable-practice.webmanifest`: Home screen metadata.
- `supabase/portable_practice_schema.sql`: database tables, policies, audit trigger and save function.

## Data and permissions

`pat_hubs` holds the private configuration, current snapshot and family recordings. Its rows are limited to authorised parents and clinicians with view access. Saving also requires write permission.

`pat_activity_records` makes feedback, approval status, dates, observed engagement and support available as structured records. The full record retains task details, child feedback and coin corrections. Authorised team members with participant view access can read these activity records.

`pat_hub_history` retains state snapshots. It is limited to authorised parents and clinicians. No anonymous read or save permission is granted. The browser uses only the publishable key. No server secret or participant credential belongs in Git.

The parent PIN remains a local interface control within an already authorised session. Supabase authentication and row policies provide the access boundary.

## Saving and interrupted connections

The interface distinguishes saved-to-cloud from saved-here-and-waiting. It keeps pending changes in a private IndexedDB journal and retries after connectivity returns. An unavailable local journal is reported rather than represented as a successful offline save.

Each save supplies the revision it started from. A newer server revision returns a conflict. The app retains the local copy, pauses automatic writes, and offers a private backup download before loading the cloud version. It does not silently merge coin approvals or replace another device's changes.

Browser data deletion before a pending change syncs can still lose that pending change. Successfully synced data is independent of the original device. Full backups remain available.

## Initial migration

1. Confirm the exact Supabase destination before importing private configuration.
2. Provision the private hub configuration outside Git, with participant access assigned to verified accounts.
3. Load the module using an authorised parent account on the child device. Do not leave a clinician account with access to other participants signed in on the child's tablet.
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

Cloud queue, offline retention, retry, conflicting revisions, edits during an in-flight save, cross-participant guarding, escaping and public-source privacy were checked using the actual application scripts in DOM tests. Database access rules and save behaviour were checked in the live project within a rollback transaction. Tablet installation and end-to-end family sign-in remain device checks; private configuration migration is not complete.
