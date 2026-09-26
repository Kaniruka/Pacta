---
status: accepted
---

# Use one Supabase project with invite-only, per-user isolation

Pacta uses one Supabase project to support multiple users without introducing an App-level organization or workspace model. Supabase Auth identifies each user, every business record is owned by user_id, and Row Level Security is the authoritative isolation boundary. Registration eligibility is issued by administrators and enforced by trusted server code. This keeps the open-source project inexpensive and simple to self-deploy, while accepting that all users share the project's resource quota and that RLS must be tested as a security-critical boundary.

## Considered options

- One Supabase project with per-user RLS: selected for low operational cost and simple mobile/desktop synchronization.
- One database or project per user: rejected as unnecessary operational complexity for the intended scale.
- GitHub repositories as user databases: rejected because Git history is not an appropriate transactional user-data store.
- Public registration: rejected for the shared instance because the project has finite shared capacity.

## Registration and password access — 2026-09-22

Email is the sole registration and password-login identifier. Administrators grant and revoke email registration eligibility; a successful registration consumes one unused eligibility in the same transaction. The App does not send invitation or verification messages and does not verify email ownership. Forgotten passwords are reset by an administrator after manual identity verification. This policy retains per-user isolation and trusted-server administration.
