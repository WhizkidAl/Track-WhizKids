# Email-code sign-in: implementation and release checks

15 November 2026.

`index.html` and `action-plan.html` now use `email-code-auth.js` for request/verify. Six or eight numeric characters are validated as text so leading zeros survive. Requests retain first-time signup for pending authorised users; this does not grant participant access. Existing Supabase participant policies remain the authority. No permanent/shared PIN was introduced.

The previous Action Plan regex matched a literal backslash followed by d characters, rejecting numeric OTPs. Both pages now use the tested shared validator. Request failures restore controls; repeated clicks are blocked while a request runs; successful sends impose a local 60-second resend cooldown. Server rate limits still apply. Status is announced to assistive technology. Auth callbacks defer participant queries until the callback returns to avoid the documented Supabase callback deadlock.

## Required hosted configuration

The available Supabase connector does not expose Auth email-template configuration. Its live configuration was not verified or changed here. The Action Plan's prior code UI alone is not proof that emails contain codes.

In the existing tracker project, verify that the Magic Link email template includes `{{ .Token }}` and email OTP length matches the emails being sent (six or eight). Check the first-time confirmation/signup template as well if enabled. Keep a compatible `{{ .ConfirmationURL }}` link if other pages in this project still rely on email links (`portable-access.html` does). Do not replace the global template with a code-only message until all affected clients have code entry. My Base/PAT has a separate project and is outside this change.

Example email content to adapt in the dashboard:

```html
<h2>Your Whiz Kids sign-in code</h2>
<p>Enter this one-time code in the tracker or Action Plan:</p>
<p style="font-size:28px;letter-spacing:6px"><strong>{{ .Token }}</strong></p>
<p>Use the newest email. Do not share this code.</p>
<p>For pages that request a sign-in link: <a href="{{ .ConfirmationURL }}">Sign in</a>.</p>
```

Do not state a fixed expiry until the project's actual configured expiry is checked. Confirm SMTP delivery and permitted redirect URLs. Do not send test codes to school participants without a deliberate test arrangement.

## Verification

Run `node --test tests/email-code-auth.test.cjs` (or `npm run test:auth`). Covers valid/invalid codes, leading zero, pending-user request semantics, cooldown, duplicate in-flight requests, API/network failures, rendering and both page integrations/syntax.

Before claiming end-to-end readiness: request a code to a controlled authorised mailbox; open email on a second device; enter it in the requesting page; verify only assigned participants load. Repeat for first-time pending access and the Action Plan. Check invalid/expired codes, resend, sign-out/reopen and a successful save using test data. A code verifies mailbox control, not participant authorisation. No real mailbox or physical iOS/Android test was performed in this change.

Rollback: restore the prior two HTML files and remove the shared script include together. Retain both token and compatible link in the email template while mixed clients exist.

Sources: [Supabase passwordless email](https://supabase.com/docs/guides/auth/auth-email-passwordless), [auth callback guidance](https://supabase.com/docs/reference/javascript/auth-onauthstatechange), [callback deadlock troubleshooting](https://supabase.com/kb/troubleshooting/why-is-my-supabase-api-call-not-returning-PGzXw0).
