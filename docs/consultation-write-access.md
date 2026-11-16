# Separate consultation and tracker writing

Apply `supabase/consultation_write_access.sql` after the team consultation migration. A private, consultation-specific email override can allow or deny consultation writing independently of tracker `participant_access.can_write`. Existing members without an override retain their current access.

An override never grants membership: the authenticated user must still have `can_view` participant access and the consultation must be active. The lookup uses the email from the server-owned auth record, not user metadata. Pending invitations use the same override when displaying the consultation roster, and the existing signup trigger attaches tracker membership on first sign-in. Revoking participant view access also revokes consultation access.

The private override table has RLS enabled and no client grants. Only trusted administration can configure it. Tracker policies are unchanged. The existing consultation helper continues to protect contributions, revisions and report storage; the roster reports consultation permissions to the frontend and dashboard.

Validation used a rollback transaction: a member with tracker writing disabled could read tracker data, could not update tracker days or school checkpoints, could submit and revise their own consultation response, and appeared as a contributor in the consultation roster. No test responses or temporary permission changes survived. Clinical content and real access assignments are held only in the database, never in this repository.
