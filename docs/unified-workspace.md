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

**Send and schedule controls are deliberately disabled.** The datetime control is only a proposed send time; it is not an outbox or a scheduled job. No Microsoft application registration, mailbox grant, token storage, scheduler, or delivery worker has been installed by this change. Connected assistant Outlook tools are not credentials that the public website can reuse.

Before enabling those controls, provision an application with delegated Mail.Send access to the coordinator mailbox, a server-side OAuth callback with durable encrypted refresh-token storage, and an authenticated outbox worker. Validate recipients against the selected client's authorised team at queue and send time. Record Microsoft acceptance separately from delivery, avoid automatic retries after an ambiguous send result, provide cancellation before dispatch, and verify scheduling with the browser closed. Obtain the mailbox owner's consent before granting access. Do not send a test to a real team without explicit approval.

## Verification

- `tests/workspace-browser.cjs`: responsive navigation, arbitrary checkpoints, optional medication, bulk team, template, client creation, sign-out clearing.
- `tests/workspace-rollback.sql`: creation, independent tool access, preparation gate, immutable responses, version replacement, owner-only changes, explicit activation; entire test rolls back.
- Existing tracker reader/writer, consultation form/history, and email-code tests remain applicable.
- `supabase/workspace.sql`, then `supabase/workspace_followup.sql` are the migration order. Private tables intentionally have RLS with no direct client policies; gated functions provide access.
