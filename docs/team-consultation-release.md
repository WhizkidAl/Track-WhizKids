# Shared Team Consultation

Implemented 16 November 2026. Replaces the old Action Plan page with the agreed consultation template; it does not alter tracker submission rules.

## Behaviour

The dropdown is populated from active `team_consultations` visible to the signed-in account, not the general participant directory. A participant is not added to a consultation merely because a record exists elsewhere in the database. A single consultation is selected automatically.

The coordinator sets the purpose. Contributor identity is assigned by the server from the signed-in account and existing access list. The roster includes active viewers/contributors and pending invitations, filtered to this consultation's participant. The private name lookup supplies human-readable labels, with an email-name fallback for new invitations; it grants no access.

Each priority, incident account, existing-support contribution, suggestion, comment or report is a separate record. Authors may revise their own text contributions. The database records each version in the same transaction as the save. Other contributors cannot replace it. Updates use an expected revision so an old tab cannot silently overwrite a newer revision. Parent references stay within the same consultation.

Team responses refresh every ten seconds while the page is visible, or on request. Refreshing the response list does not replace unfinished forms. This is polling, not character-by-character co-editing. Save is required to share a contribution. No emails or notifications are sent by this feature.

Reports use the private `consultation-reports` bucket: PDF/DOCX/JPEG/PNG, maximum 10 MB. Access requires current participant membership, and uploads use a consultation/user/random-file path. Downloads use authenticated requests, not public links. Original reports cannot be overwritten or deleted by the contributor UI. A failed metadata save after an upload can leave an unlisted private object; retain the original file and retry, with administrator cleanup if required.

Existing tracker and old shared-plan rows remain untouched. The new consultation does not automatically turn previous shared answers into attributed individual contributions.

## Mock run

Open `action-plan.html?mock=1` and sign in as the consultation coordinator. The same forms and team context are shown, but practice responses, revision history and file previews exist only in that browser tab's memory. They are not uploaded or shared, and are lost on refresh/close. A persistent banner and a Clear practice button distinguish it from the live consultation. Other roles cannot use this coordinator-only practice view.

No sample child names, participant IDs, team email addresses or clinical records are embedded in public source. Consultation configuration and directory labels are stored privately in the database.

## Validation

- `node --test tests/email-code-auth.test.cjs`: 9 passing auth checks, including six/eight-digit codes and leading zeros.
- `node tests/consultation-browser.cjs`: Chromium tests using synthetic accounts and a stubbed service cover the roster, conditional categories, incident non-contribution responses, proposals, own edits/history, replies, failed-save recovery, preserved drafts, escaped user text, mock uploads and mobile width. Requires Playwright and a Chrome executable; this workspace used its bundled Playwright runtime.
- `tests/consultation-access-rollback.sql`: run against the hosted database inside a transaction that is rolled back. Checks identity attribution, own-only edits, immutable history, stale revisions, viewer/outsider/anonymous restrictions, coordinator-only purpose changes and report path ownership.
- The security advisor reported no new exposed-table vulnerability. The private name table intentionally has RLS and no direct-read policy; only the gated roster helper reads it. The pre-existing private import-buffer informational finding and leaked-password-protection warning were not changed by this release. [Supabase RLS advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) and [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

The actual team mailbox sign-in was previously confirmed by the user. A real school-report upload and the user's own mock walkthrough remain user acceptance checks; no real clinical responses or reports were created during testing.

## Deployment and rollback

Apply `supabase/team_consultation.sql` before publishing `action-plan.html`, `consultation.js` and `consultation.css`. Create a consultation only for an explicitly selected existing participant and coordinator. No setup/bootstrap personal data belongs in a public migration.

Revert the three frontend files together to restore the old UI if necessary. Keep the new database tables and report bucket to preserve any submitted data; do not drop them as part of a frontend rollback. Existing tracker and other practice pages do not depend on the new consultation tables.
