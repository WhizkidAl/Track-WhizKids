# Coordinator workspace

`tracker-admin.html` is the unified entry point. Old `admin.html` bookmarks redirect there.

- New client dialog creates Tracker, Action Plan, or both in one transaction.
- Existing clients and contributions remain unchanged. New clients begin in preparation; only the coordinator can contribute until explicitly opened. Tracker activation requires a monitoring period.
- Team paste accepts up to 50 unique emails; each row has independent tool access. Saving team access does not send email.
- Any subset of the three school checkpoints is supported. Home questions are configurable per monitoring period, including medication. Completion analysis uses the questions configured for that period.
- Reviews are immutable proposal versions with append-only responses. Agreement is to a version, and a replaced version cannot receive new replies. The coordinator reviews replies and separately confirms the final configuration. Review choices do not automatically reconfigure the Action Plan forms.
- Existing tracker permissions remain authoritative, with restrictive per-tool policies. Consultation write overrides retain the read-only tracker / Action Plan contributor distinction.

## Invitations: remaining mailbox work

The composer adapts the approved short template to the client, enabled tools, selected recipients and review links. It includes the verified text signature; inline signature graphics are not reproduced. It does not claim an initial contribution exists for a new client.

The Microsoft outbox is now implemented in workspace-mail.js, the workspace-mail Edge Function and private mail tables. Sending remains disabled until the coordinator connects their mailbox. App registration is complete; the tenant blocks client secrets, so certificate registration and delegated mailbox consent are the remaining setup steps. No mailbox consent or live send is implied by registering the app.

Scheduled jobs run server-side every minute using pg_cron and pg_net. Private keys and refresh tokens are encrypted in Supabase Vault, accessible only through service-role-only functions. The Edge Function validates the Supabase user before coordinator operations; the worker has a separate random credential; OAuth uses one-use state, PKCE and short-lived PS256 certificate assertions. Recipients are checked against the client's authorised team when queued and again before sending. Repeated queue requests with the same identifier are idempotent. A timeout after dispatch becomes uncertain and is not automatically retried. Microsoft acceptance is shown separately from delivery. A scheduled job can be cancelled before the worker claims it.

No real invitation was sent during implementation. Unit tests simulate Microsoft responses; rollback-only SQL checks exercise recipient restrictions, idempotency and cancellation. A real connected-mailbox send/schedule smoke test remains pending explicit user approval. The private certificate key is never in the public repository. Rotate its certificate before expiry; the server disables the connection configuration after expiry.

## Verification

- `tests/workspace-browser.cjs`: responsive navigation, arbitrary checkpoints, optional medication, bulk team, template, client creation, sign-out clearing.
- `tests/workspace-rollback.sql`: creation, independent tool access, preparation gate, immutable responses, version replacement, owner-only changes, explicit activation; entire test rolls back.
- Existing tracker reader/writer, consultation form/history, and email-code tests remain applicable.
- `supabase/workspace.sql`, then `supabase/workspace_followup.sql` are the migration order. Private tables intentionally have RLS with no direct client policies; gated functions provide access.

Mail migration order: workspace_mail.sql, then workspace_mail_certificate.sql. Deploy supabase/functions/workspace-mail/index.ts with its handler.mjs; JWT gateway verification is disabled because OAuth callbacks are unauthenticated, but all coordinator and worker routes enforce their own authentication.
