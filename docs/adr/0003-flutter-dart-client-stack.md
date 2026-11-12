---
status: accepted
---

# Use Flutter/Dart with Drift, Riverpod, and Material 3 for the client

Pacta will use one Flutter/Dart client with Android 15 and Windows 11 both included in the first implementation and acceptance round. Both clients provide the core business capabilities and offline operation; the currently committed platform scope is Android and Windows only, with minimum versions for earlier systems subject to compatibility validation. The client will use Drift/SQLite for its offline cache, Riverpod for explicit state management, and Material 3 as the component foundation with custom design tokens for Pacta's visual language. Supabase PostgreSQL, Auth, and RLS remain the cloud boundary established by ADR 0001. This combination keeps Focus Session and National Focus state transitions testable while preserving one cross-platform client; current page composition and visual rules are maintained in the [product design](../product-design.md#25-core-screen-information-architecture) and [UI guide](../agents/ui.md#页面章节入口).

## Considered options

- Separate native clients: rejected for the first version because duplicated state and synchronization behavior would slow validation of the core loop.
- React Native/TypeScript: not selected because the repository and current delivery direction already target Flutter/Dart.
- A simple key-value local store: rejected because tasks, chains, tree nodes, snapshots, and failure records require relational local queries and transactional updates.
- A fully uncustomized Material UI: rejected because the product needs its own visual language even while using Material 3 as a reliable cross-platform foundation.

## Delivery scope clarification — 2026-09-12 (platform scope superseded below)

历史：当日确认 Android 15 / Windows 11 同轮验收，取代桌面随后交付；当时未排除其他平台。9月14日的下节决定将承诺范围明确收窄为 Android/Windows，其余栈选择保持有效。

## Committed platform scope — 2026-09-14

The currently committed platforms are Android and Windows only. Initial acceptance is on Android 15 and Windows 11 with equal core features and offline capabilities. Minimum support for earlier OS versions will be determined by compatibility validation, without advance promises. iOS, macOS, Linux, and Web are outside the committed scope and require a separate future decision. This supersedes the earlier open-ended platform scope, while retaining the Flutter/Dart stack and the initial acceptance pair.
