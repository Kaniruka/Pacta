---
status: accepted
---

# Use one Supabase project with invite-only, per-user isolation

Chain will use one Supabase project to support multiple users, without introducing an App-level organization or workspace model. Supabase Auth identifies each user, every business record is owned by `user_id`, and Row Level Security is the authoritative isolation boundary. Registration is invite-only and administrative actions are handled through trusted server code. This keeps the open-source project inexpensive and simple to self-deploy, while accepting that all users share the project's resource quota and that RLS must be tested as a security-critical boundary.

## Considered options

- One Supabase project with per-user RLS: selected for low operational cost and simple phone/desktop synchronization.
- One database or project per user: rejected as unnecessary operational complexity for the intended scale.
- GitHub repositories as user databases: rejected because Git history is not an appropriate transactional user-data store.
- Public registration: rejected for the shared instance because the project has finite shared capacity.
