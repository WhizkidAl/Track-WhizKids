# Whiz Kids Track

Shared browser-based tracking tools for Whiz Kids Therapy.

## Architecture
- This repository contains application code only.
- Supabase provides authentication, participant access control and structured tracker data.
- Participant-identifiable data is not stored in GitHub.
- Access to records is enforced through Supabase Row Level Security.

## First module
Whole-Day Participation & Regulation Tracker.

## Planned public address
`track.whizkidstherapy.com`

## Security boundary
GitHub = code.
Supabase = structured app data and permissions.
SharePoint / Halaxy = formal clinical/document record as appropriate.
