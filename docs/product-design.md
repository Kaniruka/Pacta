# Chain App - Project Design

Status: working baseline captured from the design discussion on 2026-08-22.

## 1. Product intent

Chain is a cross-platform, open-source app for improving self-regulation. It is intended for personal use with invite-only access rather than as a commercial public SaaS product or shared workspace.

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

- selecting an appropriate focus practice according to the user's current state, available uninterrupted time, and task fit;
- user selection of the Focus Chain according to their current state;
- selecting Tasks from the current chain mode's eligible task pool;
- binding the main Focus Chain to a Focus Marker that the user activates outside the App;
- supporting a manually invoked Trigger Signal without requiring the App to detect the real-world action;
- supporting an Appointment Chain as a delayed-start path into a Focus Chain;
- using a fixed 15-minute Appointment Chain window before the user must manually trigger the immediate-start flow;
- an explicit focus trigger or start protocol;
- a clearly defined session unit with a countdown boundary;
- a completion rule that can be inspected before starting;
- requiring the session to run to the countdown boundary by default;
- allowing pause or early termination only through a Precedent Rule exception;
- applying a Precedent Rule when an ambiguous exception is encountered;
- requiring an interruption decision: discard the current progress with a brief Failure Reason, or preserve it by creating or selecting a Precedent Rule;
- failure when the user does not sustain a session successfully;
- failure when the user actively abandons a session;
- resetting only the selected chain's current maximum consecutive record to zero after either kind of failure;
- retaining the session history and a short user-entered reason for failure or abandonment;
- allowing abandonment to remain distinct in records while being grouped with failure in filtered views;
- a visible history of system-generated completed nodes, with one Focus Node appended whenever a Focus Session completes normally or through a Precedent Rule-approved exception; users may add notes but cannot create nodes manually;

The product should preserve the useful CTDP ideas of lowering start resistance and making the session boundary explicit, without requiring users to understand the original mathematical terminology.

The current candidate selection table is:

| Situation | Focus practice | Typical duration |
| --- | --- | --- |
| High energy, enough time, quiet environment, high confidence of success | Elite Focus Chain (精锐链) | 45–60 minutes |
| Ordinary state but stable enough to work | Regular Focus Chain (普通链) | 20–30 minutes |
| Tired, easily interrupted, or unsuitable for long concentration | Regular Short Chain (普通短链) | 10–15 minutes |
| Almost unable to start; only testing the current state | Recon Practice (侦查练习) applied to a concrete Goal Task | 5 minutes |

This table is a selection aid, not a decision that every row is an independent chain. Regular Short Chain shares Regular Focus Chain progress. Recon Practice is an execution method applied to an existing Goal Task; it has no independent App entity, chain, node, or history record. The listed durations are suggestions only: the user chooses the actual Focus Session countdown, and Elite or Regular classification never determines the timer length. If the user proceeds from the probe into focused work, they explicitly start a normal Focus Session for that Task.

Failure reasons begin as required short free-text summaries when the user fails or abandons a session. A few words are sufficient initially, and the user can edit the reason later. No empty “暂时无法总结” path is provided. Later, optional structured categories or tags may be added for aggregate statistics, trend analysis, and comparison with National Focus Tree failure reasons, while preserving the original text. Fine-grained filtering by reason is not a core interaction because early users will not have enough records for it to be useful.

Once started, a Focus Session continues while the App is in the background. A persistent notification keeps the countdown visible and active for tasks that require the user to operate the phone. The countdown is a boundary and progress cue, not the sole measure of completion.

The CTDP-derived signal model is intentionally human-operated: a user may perform an Appointment Chain signal and open the corresponding flow, or perform an immediate-start signal and open the Focus Chain directly. The App does not listen for or verify snaps, gestures, or other physical markers.

The Appointment Chain window is fixed at 15 minutes in the first version. The App may show the remaining window and notify the user, but it does not detect the signal or start the Focus Chain automatically.

### 2.2 National Focus Tree

The National Focus Tree models gradual changes in the user's daily system. Nodes should be small enough to survive a poor day, and the tree should support branching, reinforcement, backtracking, and controlled recovery.

The tree is not a conventional achievement badge system. A node represents a rule or action that changes the conditions under which later actions become easier. The tree reflects the user's current state and can inform which Focus Chain is appropriate, but the user still explicitly selects the chain; the App does not automatically switch or block a choice. It is not a Goal or Task classification. In the first version, users create National Focus Cards in a Card Library and place them into the tree as National Focus Nodes. Each card occupies only one tree position at a time. Users manually light nodes, then complete one National Focus Daily Confirmation after each 04:00 boundary and before the next 04:00. That action confirms every node eligible from the previous National Focus Day in one batch; newly activated cards require individual confirmation before joining a later batch. The user may exclude a card from the batch when it is no longer valid compared with yesterday; exclusion clears its current maximum consecutive record and extinguishes its child cards without creating separate child failure logs. Moving a card directly between tree branches preserves its current and historical records. The App may recommend adding at most one new card per day, but this recommendation never blocks the user. Missing a single daily confirmation window invalidates the current National Focus state: the complete tree structure and state are snapshotted first, all current maximum consecutive records and the batch eligibility set are cleared, historical maximum records are retained, and the next cycle starts from zero. The system records “missed daily confirmation” as the invalidation reason, which the user may edit later. A node is never individually failed automatically by a deadline or inactivity. When a node fails because it is not lit at the boundary, the failed node remains visible in the tree with its current maximum consecutive record cleared and its historical maximum record retained; its child cards remain in the tree marked as extinguished, and its parent is not affected. Only the failed node receives a Failure Reason; extinguished child cards do not create separate failure logs. The user may edit the current tree in place, remove cards into the Card Library, or create new cards and manually attach them to any branch. Removing a card into the Card Library starts a reversible removal state without immediately clearing its current maximum consecutive record or current tree history. A card referenced by any failure snapshot can only be soft-deleted and restored to the Card Library; it has no current tree relationship while there. A card with no snapshot reference may be permanently deleted. The App does not automatically split or generate replacement cards. New cards are new nodes and do not inherit the failed node's current record. Each National Focus Card also has a persistent Internalization Progress value in addition to its current and historical maximum consecutive records. Each National Focus failure log stores the immutable snapshot alongside the reason, so later card removal or restructuring cannot change the log. National Focus Tree nodes do not have their own countdown; timing remains the responsibility of Focus Sessions. Complex inheritance remains deferred RSIP mechanics.

Users manually light and extinguish National Focus Nodes. The National Focus Day runs from 04:00 to the next 04:00. Extinguishing changes the visible state but does not immediately clear the node's current maximum consecutive record; if the user lights it again before the boundary, the record is preserved. At the boundary, a node that is not lit is recorded as failed, its current maximum consecutive record is cleared, and its historical maximum record and Internalization Progress are retained. Extinguishing a parent cascades the extinguished state to child cards without removing them. Explicitly removing a card is a separate action: it starts a reversible removal state, and only if the card remains out of the tree at the boundary is it recorded as failed and cleared. Moving a card directly between branches preserves its current and historical records. National Focus failure logs preserve the tree snapshot from the failure moment, so reviewing a log does not depend on the current tree after later restructuring. A shared reason vocabulary or cross-domain analysis with Focus Sessions is a later design decision.

Internalization Progress is derived from the card's cumulative successful National Focus Day count. Let `S` be that count; each successful National Focus Daily Confirmation increases `S` by one for each eligible card. The derived score is `I = 100 * (1 - exp(-S / 60))`, where `60` is the initial global calibration constant in successful days. The score approaches 100 asymptotically, so three successful days cannot reach the highest familiarity range. Failure, extinguishing, moving to the Card Library, and restoration preserve `S`; `I` is derived from `S`. A newly created card starts with `S = 0`, and neither value is manually editable. The UI may derive qualitative labels from the continuous score, but those labels are presentation only and do not define a fixed number of levels. The 04:00 boundary opens the confirmation window but does not confirm nodes automatically. When a node reaches the 04:00 boundary without being lit, the system pre-fills its Failure Reason as “04:00 时未保持点亮”; the user may edit it later. A parent may mark children extinguished immediately, but those children are not formally failed until the boundary, and they cannot be lit independently while the parent remains extinguished.

Newly placed cards start extinguished and require manual lighting. Relighting a failed card on a later day starts its current maximum consecutive record at zero while retaining its historical maximum record and Internalization Progress. Relighting a parent does not relight its extinguished children; each child requires separate manual lighting.

National Focus Cards use lightweight structured fields for a Trigger Condition and Action, with optional Scope and Exception Notes. These fields describe the user's rule but are not automatically evaluated by the App. The first version keeps parent-child behavior strict and does not model a separate National Focus Group or tolerance quota. It also excludes Water-tight Compartment freeze exceptions, policy strengthening levels, and automatic post-failure redesign suggestions. Failure reasons and tree snapshots remain available for later reflection and future recommendation features.

### 2.3 Tasks and deadlines

The App owns the To-do experience. A first version should keep the model deliberately small:

- a Goal grouping multiple executable Tasks; the first version uses only a two-level Goal -> Task hierarchy, without nested child Tasks, and every Task in a Goal is required;
- title;
- deadline;
- estimated duration;
- accumulated Focus Progress from completed Focus Sessions;
- Task Chain Classification as Elite, Regular, or explicitly both;
- priority;
- status;
- optional notes.

The task list exists to feed the focus loop, not to become a general-purpose project-management suite. A Goal may contain both Elite and Regular Tasks, and all of its Tasks are required in the first version. The user explicitly selects a Focus Chain, and the App presents Tasks eligible for that chain mode. If the selected Elite Focus Chain has no available Tasks, the App may suggest the Regular Focus Chain as a fallback but does not switch automatically. The selected Focus Session then records progress against the Task while the chain records the session node. Recon Practice is only a user-selected way to approach one of those existing Tasks; it does not create a separate task or record.

Task completion remains separate from Focus Session completion. A normal countdown ending, or an exception-approved pause or early termination, records a completed Focus Session and appends one Focus Node. Only completed sessions contribute their actual elapsed focus time to Task Focus Progress; elapsed time from failed or abandoned sessions is retained in history but contributes no Task progress. Neither session completion nor Focus Progress automatically completes the Task. A Task becomes complete only through explicit user confirmation, and a Goal becomes complete when all of its Tasks are explicitly complete.

### 2.4 Device calendars

Device calendars are read-only scheduling constraints in the initial design.

- iOS reads selected calendars through EventKit.
- Android reads selected calendars through the platform Calendar Provider.
- The App normalizes the result into Calendar Blocks.
- The cloud stores only the minimum information needed for cross-device planning.
- The desktop client reads the normalized blocks from the cloud instead of requiring a second platform-specific calendar integration.

The initial UI needs an agenda or time-axis view, not a complete Outlook/Apple Calendar replacement. It should show fixed blocks, available focus windows, and approaching deadlines.

The first version does not integrate Microsoft To Do, Outlook, Microsoft Graph, or bidirectional calendar editing.

### 2.5 Core screen information architecture

The accepted mobile-first shell uses four primary destinations: **Board**, **National Focus Tree**, **Focus Chain**, and **My**. The Board is the user's first landing surface: it shows the App-owned Task list first, then combines Focus Chain progress, National Focus status, and Recent Focus Activity. It is not a separate general-purpose project-management suite, and there is no standalone To-do navigation destination.

The National Focus Tree is a dedicated structural canvas. Its relevant actions are daily confirmation, opening the Card Library, and attaching an existing Card Library card to the tree. The tree's `Simple` view shows node icons and structure; its `Detailed` view adds card text, dates, records, and state. Creating a new National Focus Card begins in the Card Library's secondary page, not from the tree's attach action.

The Focus Chain destination is the setup surface for one Focus Session. Selecting a task opens a secondary task-picker page where Elite, Regular, and Both classifications are filters; they are not separate primary pages. Appointment Chain and immediate-start flows remain available here. Precedent Rule management is a Focus Chain-specific expansion menu, while profile and global settings remain under My.

After a Focus Session begins, the App enters a dedicated Session surface. A Session normally completes only when its countdown reaches zero; there is no manual completion action. Pause, continue, early termination, and abandonment enter the applicable Precedent Rule or Failure Reason flow, with a return-to-session option. Background execution remains supported by persistent notification.

The validated throwaway reference is [pacta-own-shell-v4.html](../prototype/pacta-own-shell-v4.html); it is a visual and interaction reference, not production Flutter code.

## 3. Users and access

The App uses one Supabase project to serve multiple users. It does not create an App-level organization or workspace model.

- Supabase Auth identifies the user.
- Every business row is associated with `user_id`.
- Row Level Security ensures that a user can only read or modify their own rows.
- A separate `app_admins` table identifies the administrator identities.
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

- `invited`: an administrator has approved an email but the authentication identity is not active yet;
- `active`: normal access and participation;
- `suspended`: access is denied while data is retained for recovery;
- `purge_pending`: the retention window has elapsed and deletion is queued;
- `deleted`: App data and the authentication identity have been removed.

When capacity becomes constrained, the administrator may suspend long-inactive users first. Suspension should not immediately destroy data. Purge is irreversible and must be an explicit, server-side action.

## 5. Persistence and synchronization

The cloud backend is required for phone/desktop synchronization. The accepted client baseline is:

```text
Flutter/Dart client
  ├── Riverpod state management
  ├── local Drift/SQLite cache
  ├── local notifications
  ├── Material 3 foundation + custom design tokens
  └── sync client
          ↓
Supabase Auth + PostgreSQL + RLS
```

The cloud is the shared source of truth. Each device keeps a local cache for offline use and synchronizes when the App starts, resumes, or regains connectivity. Mobile is the first-priority client experience; desktop follows in the same Flutter/Dart codebase rather than becoming a separate client. Material 3 supplies the cross-platform component foundation, while the product's final visual language and screen composition remain subject to UI prototyping.

Recommended data groups:

- `profiles`: user identity, lifecycle status, and activity timestamps;
- `goals`: broader outcomes grouping related Tasks;
- `tasks`: App-owned tasks;
- `calendar_blocks`: normalized external calendar constraints;
- `focus_chains` and `focus_nodes`: chain definitions and progression;
- `national_focus_nodes`: current focus-tree definitions and state, including soft-deletion state for snapshot-referenced cards;
- `national_focus_failure_records`: append-oriented failure logs with brief reasons and complete tree snapshots;
- `focus_sessions`: append-oriented history of focus attempts, outcomes, and failure reasons;
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
- public unrestricted registration;
- a full calendar replacement.

## 8. Open decisions

- how free-text Failure Reasons should later become optional structured categories or tags;
- exact National Focus Tree node types and transition rules;
- how much calendar detail is stored in the cloud;
- notification behavior across devices;
- conflict resolution beyond the first synchronization model;
- responsive layout, production component inventory, and exact Material 3 token mapping;
- the final Supabase schema and migration strategy.
