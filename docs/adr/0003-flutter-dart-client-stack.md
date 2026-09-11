---
status: accepted
---

# Use Flutter/Dart with Drift, Riverpod, and Material 3 for the client

Chain will use one Flutter/Dart client for mobile-first delivery, with desktop support following in the same codebase. The client will use Drift/SQLite for its offline cache, Riverpod for explicit state management, and Material 3 as the component foundation with custom design tokens for Chain's visual language. Supabase PostgreSQL, Auth, and RLS remain the cloud boundary established by ADR 0001. This combination keeps Focus Session and National Focus state transitions testable while preserving one cross-platform client; the final screen composition and visual details remain open until the UI prototype is validated.

## Considered options

- Separate native clients: rejected for the first version because duplicated state and synchronization behavior would slow validation of the core loop.
- React Native/TypeScript: not selected because the repository and current delivery direction already target Flutter/Dart.
- A simple key-value local store: rejected because tasks, chains, tree nodes, snapshots, and failure records require relational local queries and transactional updates.
- A fully uncustomized Material UI: rejected because the product needs its own visual language even while using Material 3 as a reliable cross-platform foundation.
