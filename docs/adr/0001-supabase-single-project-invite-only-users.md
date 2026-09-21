---
status: accepted
---

# Use one Supabase project with invite-only, per-user isolation

Pacta will use one Supabase project to support multiple users, without introducing an App-level organization or workspace model. Supabase Auth identifies each user, every business record is owned by `user_id`, and Row Level Security is the authoritative isolation boundary. Registration is invite-only and administrative actions are handled through trusted server code. This keeps the open-source project inexpensive and simple to self-deploy, while accepting that all users share the project's resource quota and that RLS must be tested as a security-critical boundary.

## Considered options

- One Supabase project with per-user RLS: selected for low operational cost and simple phone/desktop synchronization.
- One database or project per user: rejected as unnecessary operational complexity for the intended scale.
- GitHub repositories as user databases: rejected because Git history is not an appropriate transactional user-data store.
- Public registration: rejected for the shared instance because the project has finite shared capacity.

## Registration eligibility clarification — 2026-09-14

Administrators add a specified email address or phone number to a registration allowlist in the administration interface. The operator informs users externally; the App sends no invitation email, SMS, verification code, or invitation link. Users register with an approved identifier and a password, then log in using that identifier and password. The server checks registration eligibility, rejects unapproved identifiers and duplicate registration, and marks successfully consumed eligibility as used. Unused eligibility does not expire by default and may be revoked by an administrator. Revoking unused eligibility is distinct from suspending a registered user. Eligibility checks do not verify actual ownership of the email address or phone number. Forgotten passwords are reset by an administrator after manual verification; there is no email or SMS recovery flow. The term invite-only refers to administrator-issued registration eligibility, not an App-operated messaging or ownership-verification system. This replaces earlier email-invitation proposals without changing per-user isolation or trusted-server administration.
