# Coordinator dashboard

Open `admin.html` and sign in with the consultation coordinator's authorised email. The Action Plan also shows a coordinator link. Only active consultations assigned to that coordinator are listed. The dashboard RPC independently rejects non-coordinators and checks current participant membership.

The dashboard is read-only. It shows all-time team contribution status, pending invitations, explicit incident knowledge responses, and saved-version activity filtered by Perth calendar dates. It also counts tracker dates, home sections marked complete and school checkpoints with at least one rating. Reports are included in new-contribution counts and also broken out separately. It does not infer submission targets, completion percentages or overdue participants from missing data. The requested contribution date is displayed when set. Refresh explicitly reloads current data; a failed refresh clears old results.

Private mock responses never enter these totals. Patient drafts and review artifacts remain in ignored `private/` and must not be committed. The dashboard source contains no client configuration or clinical response text.

Apply `supabase/consultation_dashboard.sql` before deploying. It is additive and creates a security-invoker function with a coordinator check; existing table RLS still applies. Anonymous execution is revoked. No existing contributions, invitations or tracker records are changed.

Validation: `node tests/dashboard-browser.cjs`, `node tests/consultation-browser.cjs`, and `node --test tests/email-code-auth.test.cjs`. Browser tests need Playwright and a local Chrome executable. Live read-only checks verified coordinator access, school/outsider rejection and revoked anonymous execution. Date filters count saved revisions rather than guessing the date on which an incident occurred. Only current versions are used for all-time team status.
