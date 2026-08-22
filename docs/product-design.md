# Chain App - Project Design

Status: working baseline captured from the design discussion on 2026-08-22.

## 1. Product intent

Chain is a cross-platform, open-source app for improving self-regulation. It is intended for personal use and small invite-only groups rather than a commercial public SaaS product.

The product should help a user move from:

```text
deadline / unfinished work
        -> concrete task
        -> low-friction focus start
        -> bounded focus session
        -> positive feedback
        -> longer-term focus-chain or focus-tree progress
```

The app is based on the supplied CTDP/RSIP ideas, but treats those ideas as product-design hypotheses rather than medical or clinically validated claims.

## 2. Product model

### 2.1 Focus Chains

A Focus Chain turns repeated bounded focus sessions into a visible progression. The chain should support:

- an explicit focus trigger or start protocol;
- a clearly defined session unit;
- a completion rule that can be inspected before starting;
- local failure handling instead of automatic destruction of all progress;
- a visible history of completed nodes.

The product should preserve the useful CTDP ideas of lowering start resistance and making the session boundary explicit, without requiring users to understand the original mathematical terminology.

### 2.2 National Focus Tree

The National Focus Tree models gradual changes in the user's daily system. Nodes should be small enough to survive a poor day, and the tree should support branching, reinforcement, backtracking, and controlled recovery.

The tree is not a conventional achievement badge system. A node represents a rule or action that changes the conditions under which later actions become easier.

### 2.3 Tasks and deadlines

The App owns the To-do experience. A first version should keep the model deliberately small:

- title;
- deadline;
- estimated duration;
- priority;
- status;
- linked Focus Chain or National Focus Tree node;
- optional notes.

The task list exists to feed the focus loop, not to become a general-purpose project-management suite.

### 2.4 Device calendars

Device calendars are read-only scheduling constraints in the initial design.

- iOS reads selected calendars through EventKit.
- Android reads selected calendars through the platform Calendar Provider.
- The App normalizes the result into Calendar Blocks.
- The cloud stores only the minimum information needed for cross-device planning.
- The desktop client reads the normalized blocks from the cloud instead of requiring a second platform-specific calendar integration.

The initial UI needs an agenda or time-axis view, not a complete Outlook/Apple Calendar replacement. It should show fixed blocks, available focus windows, and approaching deadlines.

The first version does not integrate Microsoft To Do, Outlook, Microsoft Graph, or bidirectional calendar editing.

### 2.5 GitHub

GitHub is not the App database and is not a monitor for a developer's repository. Any GitHub integration remains deferred until the core focus loop has been validated. If reintroduced, its role must be defined as an optional evidence or feedback channel rather than a requirement for using the App.

## 3. Accounts and access

The App uses one Supabase project to serve multiple users. It does not create an App-level organization or workspace model.

- Supabase Auth identifies the user.
- Every business row is associated with `user_id`.
- Row Level Security ensures that a user can only read or modify their own rows.
- A separate `app_admins` table identifies the administrator account(s).
- A separate invitation table controls who may register.

The administrator should have an in-App user-management screen for:

- adding an invited email;
- sending or resending an invitation;
- reviewing pending invitations;
- viewing active users and last activity;
- suspending or restoring users;
- purging users after the retention period.

The invitation flow must be enforced server-side or by a Supabase Auth hook. Hiding registration controls in the client is not sufficient.

## 4. User lifecycle

The expected lifecycle is:

```text
invited -> active -> suspended -> purge_pending -> deleted
                    ^             |
                    |-------------+
```

- `invited`: an administrator has approved an email but the account is not active yet;
- `active`: normal access and participation;
- `suspended`: access is denied while data is retained for recovery;
- `purge_pending`: the retention window has elapsed and deletion is queued;
- `deleted`: App data and authentication account have been removed.

When capacity becomes constrained, the administrator may suspend long-inactive users first. Suspension should not immediately destroy data. Purge is irreversible and must be an explicit, server-side action.

## 5. Persistence and synchronization

The cloud backend is required for phone/desktop synchronization. The recommended baseline is:

```text
Flutter client
  ├── local SQLite/Drift cache
  ├── local notifications
  └── sync client
          ↓
Supabase Auth + Postgres + RLS
```

The cloud is the shared source of truth. Each device keeps a local cache for offline use and synchronizes when the App starts, resumes, or regains connectivity.

Recommended data groups:

- `profiles`: user identity, lifecycle status, and activity timestamps;
- `tasks`: App-owned tasks;
- `calendar_blocks`: normalized external calendar constraints;
- `focus_chains` and `focus_nodes`: chain definitions and progression;
- `national_focus_nodes`: focus-tree definitions and state;
- `focus_sessions`: append-oriented history of focus attempts and outcomes;
- `sync_metadata`: device cursors, versions, or synchronization timestamps.

For the first version, simple field-level last-write-wins behavior is acceptable for editable task metadata. Focus-session history should be append-oriented, and deletions should be represented carefully so another device does not resurrect deleted data.

## 6. Security and privacy

- All exposed tables require RLS.
- The client uses only the publishable/anonymous key.
- Secret/service-role keys are restricted to Edge Functions or other trusted server environments.
- Invitation, suspension, purge, and other administrative operations run through trusted server code.
- Calendar synchronization should default to selected calendars and minimum necessary fields.
- The App should not store calendar descriptions, attendees, or locations unless a later feature explicitly requires them.

## 7. MVP boundary

The first useful version should contain:

1. Supabase Auth with invite-only registration;
2. per-user task list;
3. Focus Chain creation and focus-session execution;
4. a minimal National Focus Tree;
5. read-only mobile system-calendar import;
6. deadline reminders and local notifications;
7. phone/desktop synchronization;
8. administrator user lifecycle controls.

The first version should not contain:

- Microsoft ecosystem integration;
- full bidirectional calendar synchronization;
- shared organization data;
- a general project-management suite;
- GitHub as a database;
- public unrestricted registration;
- a full calendar replacement.

## 8. Open decisions

- Exact Focus Session rules and failure semantics;
- exact National Focus Tree node types and transition rules;
- how much calendar detail is stored in the cloud;
- notification behavior across devices;
- conflict resolution beyond the first synchronization model;
- whether GitHub returns as an optional evidence/feedback integration;
- the final Supabase schema and migration strategy.
