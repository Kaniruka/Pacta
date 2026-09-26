# Pacta — First-version Product Specification

Synthesized from the local requirements conversation records and confirmed decisions through 2026-09-22. Implementation tickets T01–T27 are closed. The current local verification and remaining platform evidence are recorded below.

## Problem Statement

The App needs to turn the user's current state and available work into one clear next action while preserving the distinction between Tasks, Focus Chains, Focus Sessions, and the National Focus Tree. The first screen must show what should be done now, but the execution flow must not collapse into a generic task manager, an automatic habit tracker, or a timer with misleading completion controls.

The App also needs to preserve the user's deliberate protocols: Elite and Regular are task classifications and user-selected Focus Chain modes; entry signals are human-performed, while the end of preparation automatically starts the configured Focus Session; National Focus is manually maintained between fixed daily National Focus Checkpoints (04:00 Beijing time); and interruptions require an explicit Precedent Rule or a recorded failure reason.

## Solution

Build a mobile-first four-destination application shell:

1. **Board** is the first landing surface. It shows the App-owned Task list first, then combines Focus Progress, current National Focus status, and Recent Focus Activity.
2. **National Focus Tree** is a structural tree canvas with daily confirmation, Card Library, and attach-card actions.
3. **Focus Chain** is the setup surface for selecting a Task, filtering Tasks by Task Chain Classification in a secondary task-picker, setting the current Focus Chain Mode and user-chosen countdown, and starting appointment preparation or a Focus Session.
4. **My** contains personal records and profile/global settings.

Starting a Focus Session moves the user to a dedicated countdown surface. A Session has no manual completion action: normal completion occurs only when the countdown reaches zero. Pause, early termination, and abandonment enter the applicable Precedent Rule or Failure Reason flow with an option to return to the Session. Continue resumes the existing approved pause without another rule selection or confirmation. The countdown continues in the background; a persistent notification exposes its state. Process recovery follows the timing rules below.

## User Stories

### Application shell and Board

1. As a user, I want the App to open on a Board, so that I immediately see what I should do next.
2. As a user, I want the primary navigation to contain Board, National Focus Tree, Focus Chain, and My, so that each major responsibility has one clear home.
3. As a user, I want today's executable Tasks shown before statistics, so that progress data does not hide the next action.
4. As a user, I want a Goal's Tasks shown with their estimated duration and Focus Chain classification, so that I can choose a feasible action.
5. As a user, I want to enter Focus Chain setup from a Task on the Board, so that I do not have to reconstruct the task context.
6. As a user, I want the Board to show accumulated Focus Progress, National Focus status, and Recent Focus Activity together, so that I can understand today's state without opening a separate data dashboard.
7. As a user, I want the Board to show a National Focus confirmation reminder, so that I remember the confirmation window ending at the next National Focus Checkpoint.
8. As a user, I want to open the National Focus Tree from its Board summary, so that I can inspect the underlying branches when the summary is insufficient.
9. As a user, I want the Board to remain a focused execution surface, so that it does not become a general project-management suite.

### Task selection and Focus Chain setup

10. As a user, I want to enter Focus Chain setup without seeing separate Elite and Regular primary pages, so that chain selection remains one focused flow.
11. As a user, I want a secondary task-picker to filter Tasks by Elite, Regular, Both, or all eligible classifications, so that I can choose a Task appropriate to my current state.
12. As a user, I want the selected Task's Goal, estimated duration, and accumulated Focus Progress shown before starting, so that I know what the Session contributes to.
13. As a user, I want the current Elite or Regular mode shown and switchable in the duration settings, inheriting the mode list I came from or my last selection when entering from all Tasks, without a separate chain-selection or pairing page.
14. As a user, I want chain classifications to help me find appropriate Tasks without imposing a separate start-time chain choice.
15. As a user, I want to choose the countdown duration myself, so that Elite or Regular classification does not secretly determine Session length.
16. As a user, I want to see the Appointment Signal and Immediate-start Signal as human-operated protocol instructions, so that I understand the App does not detect physical signals.
17. As a user, I want to start fixed 15-minute appointment preparation, with the Task and focus duration configured beforehand, so that its end automatically starts my Focus Session without another click or signal.
18. As a user, I want to start a Focus Session immediately when I am ready, so that confidence can bypass the Appointment Chain.
19. As a user, I want to select an existing shared Precedent Rule when handling a focus interruption, so that I can use a permission without opening rule management.

### Focus Session

20. As a user, I want starting a Session to open a dedicated countdown page, so that execution is not mixed with task selection or the National Focus Tree.
21. As a user, I want the countdown to be the visible boundary for the current commitment, so that I can see elapsed and remaining time.
22. As a user, I want the Session page to provide only Pause, Early Termination, Abandon, and the current Continue action, so that there is no misleading manual completion button.
23. As a user, I want a Session to be recorded as normally completed only when its countdown reaches zero, so that ending early cannot be mistaken for normal completion.
24. As a user, I want backgrounding the App to leave the Session active, so that a routine device operation does not cause an automatic failure.
25. As a user, I want a persistent notification to keep the countdown available while the App is in the background, so that I can return to the Session without losing state.
26. As a user, I want Pause to require selecting or creating a Precedent Rule I judge applicable, or returning to the countdown, so that pausing does not become a default escape hatch.
27. As a user, I want Continue after an exception-controlled pause to resume the same Focus Session and its remaining countdown without counting paused time, so that a pause does not create a second Session or duplicate progress. Continue uses the retained pause-rule revision without another rule selection or confirmation.
28. As a user, I want Early Termination to require selecting or creating a Precedent Rule I judge applicable, or returning to the countdown, so that early exit is clearly exceptional.
29. As a user, I want “放弃本次专注” to request a brief Failure Reason and settle failure only when confirmed; before confirmation I may return to the normally running countdown. Exception-approved completion is the separate Early Termination operation.
30. As a user, I want a short Failure Reason to be required when I confirm abandonment of a Session, so that I can reflect on what happened.
31. As a user, I want to edit a Failure Reason later, so that a few words entered under pressure can become a useful reflection.
32. As a user, I want an approved pause or early termination to retain the applicable rule revision, so that history distinguishes a resumable pause from completion by an approved early termination. A pause does not settle progress or append a Focus Node.
33. As a user, I want a normally completed or Precedent Rule-approved early-terminated Session to append one system-generated Focus Node, so that completed focus units are visible in chain history.
34. As a user, I want actual active time from a failed Session retained in history and included in Task Focus Progress, so that progress reflects time actually invested.
35. As a user, I want completed and failed Focus Sessions to add actual active time, excluding pauses, to Task Focus Progress without completing the Task, so that Task completion remains an explicit user action.
36. As a user, I want a failed Session to reset only the selected Focus Chain's current consecutive record, so that other chains and historical records remain intact.
37. As a user, I want abandonment recorded as an action leading to a failed outcome, and exception-approved completion distinguished from normal countdown completion with its original rule basis retained.

### National Focus Tree and Card Library

38. As a user, I want National Focus Tree to be a dedicated tree canvas, so that parent, branch, and child relationships remain visible.
39. As a user, I want the tree's Simple view to show node icons and structure only, so that I can scan the whole tree.
40. As a user, I want the tree's Detailed view to show card text, dates, records, internalization, and visible state, so that I can inspect a node without losing its position in the tree.
41. As a user, I want the tree's relevant header actions to open daily confirmation, Card Library, and attach-from-library flow, so that actions remain local to the tree context.
42. As a user, I want choosing to place or re-place a Card Library card to return me to the National Focus Tree main page in parent-selection mode, where I select a top-level position or click an existing tree node to make it the card's parent, so that I choose its position directly in the tree even when the tree is empty. A separate branch-list picker is not used. Card creation remains separate from placement.
43. As a user, I want to create a new National Focus Card from the Card Library's secondary page, so that card creation and tree placement remain separate operations.
44. As a user, I want a Card Library card to contain a primary Trigger Condition and Action with optional Scope and Exception Notes, so that I can define a small concrete rule.
45. As a user, I want the App to store and display card fields without evaluating whether I performed the real-world action, so that manual lighting remains authoritative.
46. As a user, I want to move a card between tree branches without losing its current or historical records, so that restructuring reflects real progress.
47. As a user, I want a card moved to the Card Library to retain its records and be individually placed and lit again before the checkpoint, so that timely recovery preserves its current consecutive record; removed parent-child relationships are dissolved.
48. As a user, I want a snapshot-referenced card to be soft-deletable and restorable to the Card Library but not permanently deletable, so that historical failure snapshots remain complete.
49. As a user, I want a card with no failure-snapshot reference to be permanently deletable, so that the Card Library remains manageable.
50. As a user, I want a newly placed card to start extinguished and require manual lighting, so that placement does not count as successful maintenance.
51. As a user, I want active extinguishing to offer an optional brief Failure Reason and leave the node Extinguished, so that a subsequent batch cannot undo my action. Current records are preserved until checkpoint settlement; relighting before it prevents that failure.
52. As a user, I want a parent extinguish to mark its children extinguished without deleting them, so that the tree still explains the route and its consequences.
53. As a user, I want each National Focus Checkpoint to move Lit nodes to Pending Today Confirmation without failure or a reason, so that visual darkness does not misrepresent a violation.
54. As a user, I want the failed node to remain visible with historical maximum and Internalization Progress preserved, so that failure does not erase the route.
55. As a user, I want descendants affected solely by a parent failure represented in that parent event, without separate failure logs or reasons, while independent child violations remain distinguishable.
56. As a user, I want a National Focus failure record to contain the complete tree snapshot and the applicable system reason or optional user explanation, so that later restructuring cannot rewrite history.
57. As a user, I want daily confirmation to acknowledge continued validity today, with pending nodes visibly distinguishable from Extinguished nodes.
58. As a user, I want One-click Confirm Today to light only Pending Today Confirmation nodes and leave Lit and Extinguished nodes unchanged.
59. As a user, I want to light pending nodes individually, and separately manually light Extinguished nodes, without repeated batch processing of nodes already Lit.
60. As a user, I want nodes still Pending Today Confirmation at the next National Focus Checkpoint to become Extinguished and formally failed, with current records cleared and historical maxima and Internalization Progress preserved.
61. As a user, I want historical maximum records and Internalization Progress retained after National Focus failure, so that failure remains useful for reflection.
62. As a user, I want Internalization Progress derived from cumulative successful National Focus Days, so that it is separate from current streak-like records and cannot be manually edited.

### User-defined strengthening requirements

Card details must display and allow the user to edit the concrete requirements of a strengthening level. A strengthening level consists of user-defined Trigger Condition and/or Action content, not merely a numeric +1/+2 setting.

- The user can strengthen the Trigger Condition independently, for example from "before 02:00" to "before 01:00".
- The user can strengthen the Action independently, for example from "read 5 pages" to "read 10 pages", or strengthen both fields together.
- The editor shows the base requirements alongside editable strengthened requirements so the change is explicit. Fields not strengthened retain their base requirements.
- Card details and Card Library summaries display the current applicable Trigger Condition and Action; a numeric badge alone is insufficient.
- Internalization Progress is separate from these user-defined requirements. The App does not automatically evaluate real-world compliance or upgrade requirements.
- Each card supports up to five user-created strengthening levels in addition to its base rules; the base is not one of the five levels. Users may create levels over time rather than replacing a single strengthened rule.
- Each level stores its own concrete Trigger Condition and Action requirements. The level list displays those requirements and allows editing each level.
- Show the existing count out of five and a New Strengthening Level action. Once five levels exist, prevent creation of a sixth and explain the limit while keeping existing levels editable.
- Users select strengthening levels manually; there is no automatic upgrade or failure-driven downgrade. Saving requirement edits or switching levels takes effect immediately without extinguishing the card, resetting records, or requiring reconfirmation. The user judges compliance. Preserve the requirements in effect for history, including both versions and their effective times when requirements change within a National Focus Day. Never interpret earlier activity that day as having followed a later requirement version.
- Acceptance: at 12:00 change “read 5 pages” to “read 10 pages”. The new version applies from 12:00, preserving the earlier version and effective interval; the card remains in its existing state and earlier activity is not relabeled as following the 10-page requirement.

### My and settings

63. As a user, I want My to contain personal records and settings, so that global configuration has one predictable home.
64. As a user, I want notification and background-timing settings under My, so that other pages do not expose unrelated settings menus.
65. As a user, I want shared Precedent Rule history and management reachable only from My, so that all chains use one centrally maintained collection. Chain menus have no rule-management entry; focus interruption flows still allow direct rule selection.

### Goals, effective time, and recovery

66. As a user, I want to create and edit Goals and their executable Tasks with estimated durations and deadlines, so that I can organize work and choose a next action.
67. As a user, I want to mark a Task complete or undo its completion myself, so that time invested is not mistaken for work finished.
68. As a user, I want an empty Goal to remain incomplete and a nonempty Goal to derive completion from all its Tasks, so that its status reflects actual work.
69. As a user, I want Focus Progress to exceed an estimate without being capped, so that estimates remain planning references.
70. As a user, I want deleted work excluded from new starts while existing flows and historical names remain available, so that deletion does not corrupt my records.
71. As a user, I want completed and failed Sessions to share one effective-time basis across Task Focus Progress and Recent Focus Activity, so that both views agree about invested time.
72. As a user, I want cross-midnight activity split in my device's display time zone, so that daily activity reflects my chosen display while total duration remains stable.
73. As a user, I want preparation and unpaused focus recovered on their original timeline after process termination, so that reopening does not extend the commitment or settle it twice.
74. As a user, I want an approved paused Session to remain paused across restarts, so that time away does not become focus time.

### Synchronization and reconciliation

75. As a user, I want the same core capabilities and offline workflows on Android and Windows, so that I can use either device independently.
76. As a user, I want to view and continue the same synchronized flow on another device, so that switching devices does not create another attempt.
77. As a user, I want known unfinished-flow conflicts to offer continuation or the applicable ending flow, so that I can resolve the conflict and proceed.
78. As a user, I want offline starts without remote-state confirmation, so that unavailable connectivity does not prevent work.
79. As a user, I want to choose one source configuration, confirm conflicting outcomes separately, and deduplicate valid intervals, so that reconciliation preserves both meaning and actual time.
80. As a user, I want duplicate records retained without extra time, nodes, or failures, so that redundant device records do not distort progress.
81. As a user, I want disputed contributions marked pending review while undisputed work remains usable, so that uncertainty does not stop new work.
82. As a user, I want valid offline National Focus confirmations recognized despite delayed upload, so that a missing upload is not treated as a missed confirmation.
83. As a user, I want genuinely conflicting tree operations reconciled with valid complete branches and original evidence, so that synchronization does not invent an invalid tree.
84. As a user, I want uncertain clock evidence left pending review without forced failure, so that I can defer a decision while continuing to use the App.

### Calendar and notifications

85. As a user, I want selected Android device calendars shown as read-only Calendar Blocks and synchronized to Windows, so that fixed commitments inform planning.
86. As a user, I want source changes, revoked access, recurring occurrences, and overlapping busy intervals handled accurately, so that the calendar view remains useful without altering Tasks.
87. As a user, I want stale calendar data labeled when reading fails, so that temporary failures do not look like event deletion.
88. As a user, I want calendar occupancy to leave focus startup available, so that planning context does not overrule my choice.
89. As a user, I want preparation-to-focus and focus-end notifications plus configurable National Focus reminders, so that I can follow transitions and confirm pending nodes.
90. As a user, I want National Focus reminders deferred until an unfinished flow ends, so that a reminder does not interrupt preparation, focus, or an approved pause.
91. As a user, I want deadlines displayed in-App and notification preferences kept per device, so that reminder behavior matches the agreed scope.

### Registration, isolation, and user lifecycle

92. As an eligible user, I want to register with an approved email address and a password, so that I can access my private data without an App-operated invitation or verification-message flow.
93. As an administrator, I want to issue and revoke unused registration eligibility and reject unauthorized or duplicate registration, so that shared-instance access stays controlled.
94. As a user, I want other users unable to read or change my business data, so that my tasks and history remain private.
95. As an administrator, I want to reset a password after manual verification through a trusted administrative operation, so that forgotten passwords have a recovery path.
96. As an administrator, I want to suspend and restore users, so that access can be managed without premature data deletion.
97. As a suspended user, I want retained local data and existing flows handled on the agreed timeline, so that suspension itself does not record failure.
98. As a restored user, I want retained offline records synchronized with original times and reconciliation, so that delayed uploads preserve valid work.
99. As an administrator, I want a user eligible for explicit cloud purge after 30 days of the current suspension, so that expiry alone never irreversibly deletes data.
100. As a user, I want local cleanup only after trustworthy confirmation that my old identity was purged, so that ordinary login or network errors cannot erase local records.
101. As a newly registered user reusing a purged identifier, I want a fresh identity requiring fresh eligibility, so that old identity data is not silently inherited.

## Implementation Decisions

The accepted stack and product boundaries come from the four accepted ADRs. Module responsibilities below organize those requirements for implementation; they do not claim existing application interfaces or prescribe final database tables, endpoint names, or component layouts.

- **Client and application shell:** use Flutter/Dart, Riverpod, Drift/SQLite, and Material 3 with custom design tokens. Deliver equivalent core and offline capabilities on Android 15 and Windows 11. Preserve the four primary destinations and their responsibilities; production visual design remains implementation work.
- **Goal and Task operations:** own creation, editing, explicit Task completion, derived Goal completion, classification, estimates, deadlines, and deletion. Retain historical task context and prevent ordinary synchronized edits from resurrecting deleted work. Do not support Task movement between Goals or Goal/Task restoration.
- **Focus execution:** own preparation, immediate start, approved pause/continue, approved early termination, abandonment, scheduled recovery, and three independent chain records. Preparation and focus transitions must settle once even after retries, restart, or synchronized handoff. The adopted mode determines focus attribution; Task classification only organizes work.
- **Shared Precedent Rules:** keep user-authored free text centrally managed in My and directly selectable or creatable during interruptions. Preserve the original rule revision for confirmed operations. Rule edits and deletion do not invalidate an existing approved pause.
- **Effective-time projections:** derive Task Focus Progress and Recent Focus Activity from the same accepted active intervals of completed and failed Sessions. Exclude pauses, unresolved disputed contributions, and duplicate records. Partition daily activity by device display zone without changing total time or chain order. Completion alone creates a Focus Node; failure retains its chain-reset effect.
- **National Focus maintenance:** own cards, tree placement, library moves, soft-deleted card restoration, requirement versions, daily confirmation, fixed checkpoints, failure events, and immutable full-tree snapshots. Keep internalization, consecutive records, and up to five strengthening levels distinct. Settle the ending day before creating the new pending-confirmation state.
- **Durable local state and synchronization:** retain flow configuration, active/paused timing evidence, original occurrence times, rule and card requirement revisions, deletion state, source records, pending uploads, and reconciliation results. Persist state changes sufficiently to recover each logical transition once. Synchronize on startup, resume, and restored connectivity. Final schema and migration design must preserve these behavioral contracts.
- **Reconciliation:** separate source-configuration selection, outcome confirmation, and effective-time union. Preserve original evidence and valid tree branches. Never use upload-order overwrite to determine conflicting focus outcomes or active National Focus operations. Ordinary editable Task metadata may use field-level last-write-wins subject to deletion precedence. Recompute affected projections in actual occurrence order after review.
- **Calendar adapter:** read selected Android calendars and synchronize only normalized minimum-field Calendar Blocks. Retain source identity and occurrence identity for updates and deduplication. Windows consumes synchronized blocks. Distinguish confirmed source removal from temporary read failure; occupancy never gates focus startup.
- **Notification adapter:** implement local flow-transition notifications, persistent countdown status, and the configurable deferred National Focus reminder. Device notification settings and display-zone preferences remain device-specific. Notification delivery does not determine business settlement.
- **Cloud access and administration:** use one Supabase project with Auth, PostgreSQL, and authoritative per-user RLS on exposed business tables. Business ownership is identified by user identity. Client credentials are publishable/anonymous only; privileged credentials stay in trusted server code. Registration eligibility, password reset, suspension, restoration, and purge require server-enforced authorization.
- **Identity lifecycle contract:** atomically enforce registration eligibility consumption and reject duplicates; retain suspended data and existing flows as specified. After 30 days mark purge eligibility without deleting automatically. A trustworthy explicit purge result must identify the old identity before local cleanup; failed authentication or ordinary permission errors cannot serve as that signal. Exact service interfaces and administrative initialization remain implementation design, not new user business decisions.

## Testing Decisions

**Testing seams — confirmed by the user on 2026-09-21:** use one shared application-use-case boundary as the primary seam for business behavior. Exercise commands and observable queries with durable local storage and controlled time, then replay the same behavior with restart and synchronization. Add focused real-service authorization tests and Android/Windows platform integration tests where a shared application boundary cannot prove RLS enforcement or OS behavior. The repository now contains the Flutter application, durable local storage, and executable automated and platform integration test suites.

- Good tests assert externally visible outcomes: available actions, flow state, retained history, effective minutes, nodes, chain records, pending-review markers, and allowed/denied access. Avoid assertions about private helpers, internal call order, widget trees, or an exact schema. Control time rather than sleeping through countdowns.
- Exercise Goal/Task lifecycle, focus execution, shared rules, National Focus maintenance, reconciliation, and statistics through the primary application boundary. Prefer complete workflows to separate mocks for every internal module. Use actual local persistence for restart and idempotency checks; simulate independent device stores and duplicated or reordered synchronization deliveries.
- Existing specification examples and the acceptance matrix A01–A32, including both 2026-09-21 supplements, remain the acceptance prior art. The repository includes unit/widget tests and platform integration tests; report actual platform, initial state, outcome, and evidence for each executed scenario.
- Focus cases must include normal completion, failure after a pause, exception-approved early termination, cancellation before confirmation, deleted Tasks with unfinished flows, preparation configuration edits, and 10:00 preparation recovered at 11:00 with exactly one 10:15 handoff and 10:45 completion.
- Verify the latest effective-time decision explicitly: 20 completed minutes followed by 10 active failed minutes and 5 paused minutes yields 30 minutes in both projections; failure resets only the adopted chain and creates no node. Same-Session intervals 10:00–10:20 and 10:10–10:30 yield a 30-minute union even when the reconciled outcome is failed. Duplicate synchronization adds nothing.
- National Focus cases must include 03:59 first lighting, checkpoint ordering, empty pending sets, child confirmation with an unconfirmed parent, independent versus cascading failure sources, one shared batch explanation, immutable snapshots, library removal and individual replacement, restored cards, strengthening-version changes, and repeated checkpoints without repeated failure.
- Reconciliation cases must distinguish missing offline confirmation from genuine conflicting actions, retain all sources, preserve valid branches, and exclude only disputed contributions. Verify deferred clock review and timezone redistribution without altered total duration or checkpoint time.
- Test registration eligibility, per-user isolation, administrative authorization, suspension/restoration, and purge against an isolated Supabase test instance through real public and privileged service boundaries. Use at least two users plus an administrator and exercise direct unauthorized access; UI-only tests cannot establish RLS enforcement. Verify that ordinary errors preserve local caches and a fresh identity cannot inherit old data.
- On Android 15 and Windows 11, verify the shell and critical user journeys, process termination/recovery, offline continuation, cross-device handoff, notification denial and deferral. Verify native calendar permission and source changes on Android and synchronized display on Windows. OS notifications and background behavior require actual platform evidence beyond controlled-time application tests.
- On 2026-09-26, `flutter test` passed 171 tests and `flutter analyze` reported no issues. Platform integration tests were not run during this audit; existing platform evidence remains tracked by T01–T27.

## Confirmed behavior and acceptance examples

### First acceptance platforms and shared focus records

- The currently committed platforms are Android and Windows only. Initial acceptance is on Android 15 and Windows 11 with equal core features and offline capabilities. Minimum support for earlier OS versions will be determined by compatibility validation, without advance promises. iOS, macOS, Linux, and Web are outside the committed scope and require a separate future decision.
- Both clients provide Task management, National Focus maintenance, focus execution, and record viewing. Mobile may emphasize quick actions and reminders, and desktop may emphasize work-time execution; neither emphasis removes these capabilities from the other client.
- Both support offline operation and synchronize the same business records. A user can view and continue handling the same Focus Session on either client; receiving or opening a synchronized record is not a new start.
- Acceptance example: preparation for Task A is started on Android with a preselected 30-minute focus duration. After Windows synchronizes, it shows that same preparation countdown and can show and handle the subsequent Focus Session. The preparation end starts one logical Session, not one per device; synchronization must not produce duplicate focus time or nodes from that handoff.
- Genuine divergent offline operations still follow reconciliation. Automatic handoff while devices are disconnected or unavailable follows Appointment preparation and automatic handoff and Focus Session process recovery below; this example does not silently choose an outcome for conflicting attempts.

### Precedent permissions: 下必为例

- Precedent Rules are shared across the user's Focus Chains and managed centrally in My, not separately per chain. Remove rule-management entries from chain menus. Focus interruption flows still allow selecting existing rules directly.
- “下必为例” is a principle the user voluntarily follows: otherwise disallowed behavior is permitted by an applicable precedent, and the user decides whether a new behavior calls for a lasting permission or admitting failure. The App does not detect or judge real-world violations or enforce this principle through anti-evasion restrictions.
- Users may create rules at any time in My or create and immediately use one during focus. Both paths add to the same shared collection.
- Each 下必为例 permission is a passage of user-written text. Users determine its meaning and applicability, including any conditions they choose to write. The App requires no separate name, structured conditions, or prescribed wording, and does not parse or judge the text for eligibility.
- Users may edit or delete their 下必为例 text to correct it. Edits apply to subsequent operations; deleted permissions are removed from management and selection for new operations. Already confirmed operations and history retain the original rule text, and an approved paused Session remains resumable.
- An ordinary permitted behavior leaves the countdown running and counts toward focus time; no per-occurrence App selection or log is required. Only an explicitly confirmed pause freezes the countdown and excludes paused time.
- To pause or end early, the user selects or creates the Precedent Rule serving as the basis and confirms the corresponding operation. No fixed permission wording is required. A pause remains the same unfinished Session; an approved early termination settles a completed Session using actual active focus time.
- Only the user's choice of Pause, Early Termination, or Abandon enters the handling flow. Switching to any other App triggers no flow; returning to Pacta shows the normally running countdown, subject to its ordinary scheduled completion.
- Before confirming an operation, the user may return at any time; the countdown continues normally. The App does not gate return on whether a real-world violation occurred. The user decides whether to establish an exception or acknowledge failure.
- Acceptance example: a shared rule permits drinking water. The user drinks water without operating the App; those minutes count normally on any selected chain. A pause or early termination still requires explicit rule selection and confirmation.
- Acceptance example: the user opens Pause, then returns without confirming. No pause or failure is recorded and the countdown continues, regardless of what the user did in another App.
- Acceptance example: editing or deleting a rule does not rewrite the rule basis retained by an earlier Session. The same shared collection is managed in My and offered in interruption flows across chains.
- Establishing a permission alone does not complete a Session or create a Focus Node. A user-confirmed failure clears only the selected chain's current consecutive record, preserves history and previously earned Task Focus Progress, and adds the failed attempt's actual active time under the reconciliation and deduplication rules.

### Attempt mode, classification, and record scope

- Task classifications organize and filter work; they neither assign a unique permanent consecutive-record owner nor determine success. The same Task may be used for Elite or Regular focus.
- Entering from an Elite or Regular list carries that mode. Entering from all Tasks shows the current mode in the existing duration-settings area, defaults to the last selected mode, and permits direct switching. No separate chain-selection page or appointment/focus binding step is introduced.
- A Focus Session contributes only once to the focus record corresponding to its adopted mode. If preparation is used, its result contributes once to the single Appointment Chain, regardless of the subsequent focus mode. Appointment and focus settle independently.
- Goals may contain differently classified Tasks. Goal classification is a suggested default for new Tasks; Tasks may be classified independently. Changing Goal classification does not automatically change existing Tasks.
- Changing Goal or Task classification affects organization and filtering only. It does not migrate history or recalculate existing consecutive records. An already started appointment or Session retains its adopted mode and record attribution; history identifies the Task executed, mode, and outcome at the time.
- Failure affects only the applicable focus record, preserving other records and previously earned Task Focus Progress. Shared exception rules do not themselves combine record scopes.
- Exactly three independent records exist per user: Appointment Chain, Elite Focus Chain, and Regular Focus Chain. No user-created independent chains are supported. Appointment outcomes affect only the Appointment Chain; focus outcomes affect only the adopted mode's Focus Chain. This supersedes the earlier custom-chain model and the unapproved four-set proposal.
- Acceptance example: successful preparation for Elite focus followed by successful preparation for Regular focus contributes two successes to the same Appointment Chain. A failed Elite Focus Session resets only Elite focus, leaving appointment and Regular focus records unchanged.

### Goal and Task lifecycle

- An empty Goal displays “暂无任务” and is not complete. A nonempty Goal displays completed only when every Task has been manually marked complete. Adding an incomplete Task or undoing a Task's completion makes the Goal incomplete again.
- This is a derived Goal status, not automatic Task completion: neither a Focus Session ending nor accumulated Focus Progress marks a Task complete.
- Moving a Task between Goals is not supported. No move-related progress transfer or history reassignment feature is required.
- Deleted Goals and Tasks cannot be restored. There is no Goal/Task recycle-bin or restore feature. This does not change National Focus Card restoration or user suspension/restoration rules.
- Deleting a Goal also deletes its Tasks, with no restore feature. Existing focus history and all three chain records are retained; history shows the original Task name marked “已删除”. An already running appointment, active Session, or paused Session continues and settles normally, including the existing appointment's automatic focus handoff. Deleted Tasks cannot be used to start a new flow. Deletion itself causes no failure, and ordinary edits from another device cannot resurrect the Task.

### No voluntary history correction

- The App provides no voluntary correction of settled focus or appointment outcomes in either direction. The earlier Q21 completed-to-failed correction and its historical-maximum recalculation question are withdrawn.
- Acceptance: history provides no action to change a completed Session to failed, a failed Session to completed, or a settled appointment outcome.
- Multi-device reconciliation remains a separate supported process for conflicting source records, as specified below; it is not a general history-editing feature.

### Appointment preparation and automatic handoff

- An Appointment Chain is a delayed-start chain with its own independent consecutive record and history. These records belong to the Appointment Chain, not to a Focus Chain. Do not infer a one-to-one association between the two chain types.
- Before starting preparation, the user selects the Task and Focus Session duration. The preparation countdown is fixed at 15 minutes. During preparation, both preselected values may be changed without resetting the preparation countdown.
- Preparation imposes no restrictions on what the user does in the real world and needs no exception permission for that behavior. There is no appointment pause operation.
- At zero, automatically start the configured Focus Session without another Start action or Immediate-start Signal. The user may also end preparation early and enter the configured Session immediately without an exception rule. Either transition records exactly one appointment success and increments that Appointment Chain's consecutive record once.
- Later failure of the resulting Focus Session does not revoke the appointment success. Cancelling an appointment does not clear a Focus Chain's record.
- Cancelling preparation requires a brief Failure Reason and settles appointment failure, clearing only the corresponding Appointment Chain's current consecutive record. There is no exception-based cancellation path. Appointment history remains; Focus Chain records are unaffected. This supersedes Q10's mistaken exception-cancellation proposal.
- Appointment and focus run and recover on the configured timeline even when all Apps are closed. The App does not detect, judge, or request proof of real-world execution. App closure is not failure. Settle each transition and Session only once; genuine multi-device conflicts still follow reconciliation.
- Acceptance example: at 10:00 preparation starts with a 30-minute focus duration. At 10:15 it enters focus and records one appointment success; at 10:45 focus completes. Reopening at 11:00 restores those outcomes once, with 30 focus minutes and one Focus Node, without proof of activity.
- Acceptance example: at 10:05 the user changes the Task and focus duration. Automatic entry remains due at 10:15 and uses the updated configuration. Alternatively, choosing early entry at 10:05 starts focus immediately and records appointment success once.
- Users select a Task and focus duration, then directly start preparation or focus. No separate Appointment Chain selection, chain-selection page, binding, or pairing step is required; the attempt mode is set in the existing duration area. Elite/Regular classifications organize Goals and Tasks; appointment and focus records remain independent. The attempt mode determines focus attribution independently of Task classification; all preparation uses the single Appointment Chain.

### Abandon action and failed outcome

- The operation is labeled “放弃本次专注”. Confirmation requires a brief Failure Reason and settles the Session as failed; abandoned is not a separate outcome, now or in later versions.
- Failure clears only the applicable Focus Chain's current consecutive record. This attempt's actual active time remains in history and adds to Task Focus Progress, excluding pauses and applying reconciliation and deduplication; previously accumulated progress, history, and other chains remain intact.
- Before confirmation the user may return, with the countdown continuing normally. The App does not judge whether real-world behavior constitutes failure.
- Pause is unfinished and does not settle. Rule-approved early termination settles completed, retains the original rule basis, and is distinguished from normal countdown completion.

### Resumable Focus Session pause

- An approved pause freezes the remaining countdown in the same Session. It creates no completed outcome, Focus Node, or Task Focus Progress contribution.
- Continuing resumes that Session. Only active focus time counts; final settlement happens once. Completion appends one Focus Node; failure retains its existing chain-reset effect and creates no Focus Node. Both outcomes contribute actual active time to Task Focus Progress once, subject to reconciliation and deduplication.
- Example: a 30-minute Session runs for 10 minutes, pauses by rule for 5 minutes, then continues for 20 minutes. It completes after 35 wall-clock minutes, contributes 30 focus minutes, and appends exactly one Focus Node.
- An approved early termination completes and settles immediately, using actual active focus time and retaining its rule revision.
- Continue requires no new rule selection or confirmation and uses the revision retained when the pause was approved. Later rule edits do not replace that revision.
- The first version has no automatic pause timeout. An approved pause remains resumable. Known conflicts with a new start use the actionable conflict flow below, including paused Sessions; offline starts do not require remote-state confirmation. Returning to a paused Session offers Continue, rule-approved Early Termination, and “放弃本次专注” with failure confirmation.
- Example: returning the following day leaves an approved pause resumable with the same remaining focus time; time spent paused overnight does not become focus time.

### Parent-caused National Focus failure

- Active extinguishing of parent A offers an optional Failure Reason and extinguishes its descendants without removing cards. Descendants affected solely by A do not receive independent failure logs or reasons; an independent child violation remains distinguishable with its own optional reason.
- Example: the user actively extinguishes B with a reason, then its parent A with a reason, which also extinguishes C. Preserve the distinction between B's independent action and C's parent-caused state. If these violations persist to the checkpoint, settle their failure events and current-record resets then, saving the checkpoint snapshot first. Relighting before that checkpoint prevents the corresponding failure.
- A parent failure is represented by one event with a complete tree snapshot covering affected descendants. Historical maxima and Internalization Progress are preserved. Relighting a parent does not automatically relight Extinguished children; a child cannot be lit while its parent is Extinguished.
- Pending Today Confirmation is not an active parent extinguish. When parent and child are both Pending Today Confirmation, the child may be confirmed alone without confirming the parent. If the parent remains unconfirmed and formally fails at the checkpoint, its child is affected and receives no success increment that day. One-click Confirm Today processes all Pending Today Confirmation nodes and never restores Extinguished nodes.
- Record unrelated nodes by independent failure source. A parent failure event includes descendants affected solely by that parent, without separate descendant events. Preserve an independent child event only when its independent failure condition still holds at the checkpoint. Each node settles failure at most once per checkpoint even if multiple sources affect it. Every event retains the complete immutable tree snapshot.
- A batch of failures arising from the daily-confirmation flow has exactly one optional failure-reason entry shared by all records in that batch, not one entry per event. Missed confirmation uses the system reason “未完成今日确认”; users may add one shared explanation linked to the batch records. Do not require completion, show mandatory dialogs, or block use. Separate failure events do not imply separate reason-entry chores.
- Acceptance: confirm child B while parent A stays pending. At the checkpoint A fails and B receives no successful day. If B has no independent failure source, only A's event records the cascade. If unrelated C also misses confirmation, C has a separate event, but the daily-confirmation failure batch still has one shared explanation entry.
- Acceptance: B has an independent active-extinguishing failure condition that still holds when A also fails. Retain B's independent event and A's parent event, but settle B's failure only once at that checkpoint.

### First card and top-level placement

- An empty tree exposes Add First National Focus Card and allows a Card Library card to be placed at the top level without selecting an existing parent. New card creation remains in the Card Library.
- Placing or re-placing a Card Library card supports top-level placement as well as selecting an existing parent on the canvas. Restoring a soft-deleted card first returns it to the library; placement is a separate operation.
- The top-level position is a structural location, not a rule card: it has no lighting, confirmation, progress, or failure state. A card placed there is a normal National Focus Node, initially extinguished and requiring manual lighting.

### National Focus Checkpoint and time-zone display

- The National Focus Checkpoint is fixed at 04:00 Beijing time (UTC+08:00) every day, equivalent to 20:00 UTC on the preceding date. A National Focus Day spans two consecutive checkpoints.
- Every user and device shares this same checkpoint instant. A user or device time-zone change only changes the displayed local time and date; it does not move settlement, shorten or extend the confirmation window, create another day, replay confirmation, or restore an expired window.
- Show the next checkpoint in the applicable display time zone with its date and zone identified. Do not label it universally as local 04:00. Beijing time remains the rule's reference.
- Acceptance example: the checkpoint at 2026-09-13 04:00 Beijing time is 2026-09-12 20:00 UTC and 2026-09-13 05:00 at UTC+09:00. Changing the display from Beijing to UTC+09:00 shows 05:00 for the same checkpoint; the remaining confirmation time is unchanged.
- This replaces the earlier user-controlled National Focus Time Zone and deadline-moving switch rules. Connectivity checks, acknowledgments, and switch blocking introduced solely to move that boundary no longer apply. Display time-zone preferences follow the per-device daily-statistics rules below.
- Focus Sessions and daily confirmation remain available offline. A valid offline confirmation takes effect locally; delayed upload or server non-receipt alone cannot establish failure. Changing a display time zone does not change which checkpoint interval contains that confirmation.
- Unless explicitly labeled otherwise, clock times in the National Focus acceptance examples below are Beijing time.

### Daily confirmation and node states

National Focus Daily Confirmation means “确认今日继续有效”: acknowledgment that a node remains valid today. It does not record yesterday's success. The following rules supersede the previous-day acknowledgment model.

| Business state | Meaning | One-click Confirm Today (一键确认今日) |
| --- | --- | --- |
| Lit (点亮) | Currently acknowledged as valid | Leave unchanged; do not process again |
| Pending Today Confirmation (待今日确认) | Visually unlit after the daily boundary; not failed | Light the node |
| Extinguished (真正熄灭) | Outside the pending-confirmation set; requires separate manual lighting | Leave extinguished |

- At each National Focus Checkpoint, previously Lit nodes become Pending Today Confirmation. This transition is not failure and requires no Failure Reason. Visual darkness alone is never a failure criterion.
- Users may light pending nodes individually or use One-click Confirm Today. The batch acts only on nodes still Pending Today Confirmation, without a separate first-confirmation batch gate for newly activated cards.
- Actively extinguishing a node allows entering a brief Failure Reason or skipping it. It becomes Extinguished and is no longer pending. Active extinguishing does not immediately reset the current record or create a final failure event. If the node remains Extinguished at the next checkpoint in an already started, not-yet-failed maintenance cycle, save the checkpoint snapshot and settle failure there, clearing its current record. Relighting before that checkpoint preserves the record and prevents that failure.
- Extinguished nodes require separate manual lighting. A batch confirmation cannot relight them. A newly placed, never-lit card likewise starts Extinguished and is not a failure merely because of that state.
- Acceptance example: independent nodes A, B, and C are Lit before 04:00. At 04:00 all become Pending Today Confirmation, visually unlit with no failure or reason. At 08:00 the user manually lights A and C. At 09:00 the user actively extinguishes A and supplies a reason. At 10:00 One-click Confirm Today lights only B: A stays Extinguished and C stays Lit without repeated processing. Repeating the batch changes none of them.
- Acceptance example: the user actively extinguishes a pending node with a reason before lighting it today. It leaves the pending set and is not relit by One-click Confirm Today.
- Daily confirmation remains available offline and takes effect locally immediately. The device later uploads the record and result. A valid offline confirmation is not invalidated by delayed upload, and server non-receipt alone cannot establish failure.
- Acceptance example: a valid offline confirmation is uploaded two days later. Delayed receipt alone creates no failure and does not replay the confirmation.

### National Focus settlement and retained records

- The National Focus Day runs from one fixed National Focus Checkpoint to the next. An empty daily eligible set creates no required confirmation chore or missed-confirmation failure. An empty pending set means there is nothing left to confirm now; it neither settles the day early nor adds success counts.
- At the next National Focus Checkpoint, all nodes still Pending Today Confirmation from the ending day become Extinguished and formally failed. Save the complete failure snapshot before clearing their current records; preserve historical maxima and Internalization Progress. They leave the pending set and require separate manual relighting to start again. This is final failure, not another temporary pending state.
- This clarifies the earlier tree-wide missed-window wording: unconfirmed nodes fail; an independently confirmed node does not fail merely because another node was unconfirmed. Existing parent-failure consequences still apply to descendants. The system reason is “未完成今日确认”; use the independent-source event grouping and single shared daily-confirmation batch explanation specified above.
- Boundary ordering: first settle the ending day's unconfirmed nodes, then move surviving Lit nodes into Pending Today Confirmation for the new day. Never fail nodes merely because this new-day transition makes them visually unlit.
- Acceptance example: independent A and B become pending Monday at 04:00. A is confirmed Monday; B is never confirmed. Tuesday at 04:00, B formally fails, its current record is cleared, and its history and Internalization Progress remain. A enters Tuesday's pending state without failure. Tuesday's batch cannot relight B. If both remained unconfirmed, both would formally fail.
- Failure ends an already started maintenance cycle. Never-lit cards do not fail merely through inactivity, and an already failed card left extinguished does not generate repeated daily failures. Historical maxima and Internalization Progress remain preserved.
- Internalization Progress retains the agreed formula: cumulative successful National Focus Day count `S`, with `I = 100 * (1 - exp(-S / 60))`. New cards start with `S = 0`; the value is not manually editable and survives failure, extinguishing, library moves, and restoration. Qualitative UI labels are presentation only.
- At each 04:00 Beijing-time checkpoint, settle the ending National Focus Day first. Each card still Lit and unaffected by parent failure gains one cumulative successful day and one current consecutive count, updating its historical maximum when exceeded; then surviving Lit cards enter the new day's Pending Today Confirmation state. Count at most once per card per National Focus Day. First lighting at 03:59 qualifies at 04:00; repeated extinguishing and relighting within the day never adds extra counts. A successful day means passing one checkpoint settlement, not maintaining validity for 24 hours.
- Active National Focus extinguishing permits a brief reason or “暂不填写”. If the node remains extinguished and formally fails at the checkpoint, its failure record offers a non-blocking reminder and an entry to add the missing reason, without mandatory dialogs or blocked functionality. Recovery before the checkpoint removes any need to supply a reason. Missed-confirmation failure uses the system reason “未完成今日确认”, with optional user commentary.
- Acceptance: skip a reason when extinguishing. If restored before 04:00, no missing-reason prompt remains; otherwise settle failure at 04:00 and offer optional completion of the reason in its record without interrupting use.
- Moving a card directly between branches preserves its records. The separate library-removal flow follows the rules below.

### Card Library removal and individual placement

- Moving a parent to the Card Library moves it and all descendants together, but removes their parent-child relationships: they become independent cards. Place cards back individually, choose a new tree position for each, and light each manually; there is no whole-subtree restore. Preserve each card's existing records and leave historical snapshots unchanged. Cards in the library do not participate in One-click Confirm Today. A card placed back and lit before the checkpoint retains its consecutive record; a card not restored to a valid state settles failure under the existing rules. Never-lit cards and cards whose maintenance cycle has already failed do not generate repeated failures merely by remaining in the library.
- Acceptance: move parent A and child B to the library. Both become independent cards, with no A-to-B relationship to restore. Place and light B alone before 04:00: B preserves its consecutive record and may pass the checkpoint; A remaining in the library settles failure only if its already-started maintenance cycle has not already failed. Repeated checkpoints do not repeatedly fail A.


### Daily focus allocation and display preferences

- Task Focus Progress and Recent Focus Activity use the same effective-time basis: actual active time from completed and failed Sessions, excluding pauses, unresolved conflicting contributions, and duplicate records. Task Focus Progress accumulates by Task; Recent Focus Activity groups by calendar date. Reconciliation and deduplication apply equally to both; outcome selection does not discard valid active time merely because the accepted outcome is failed. Task completion remains an explicit user action, and failure retains its existing Focus Chain consequences.

- Daily focus duration is allocated across calendar days using effective focus intervals, excluding pauses, in the device's display time zone. Default to the device time zone and allow a manual zone preference stored per device. Changing the display zone redistributes daily totals but never changes total duration, actual occurrence order, or the three consecutive records. Different devices using different zones may show different daily totals. National Focus settlement remains fixed at 04:00 Beijing time.
- Acceptance: a continuous effective interval from 23:50 to 00:20 contributes 10 minutes to the earlier date and 20 minutes to the later date in that display zone. Changing zones may move these minutes to other dates but preserves the 30-minute total and all chain records.

### Offline National Focus reconciliation

- When conflicting active offline National Focus operations cannot be reliably ordered, show the operations and their effects for user reconciliation rather than overwriting by upload order. Preserve valid, complete branch relationships when parent-child structure is involved; do not compose invalid structures field by field. Until review, mark affected states and statistics “待核对” without determining success or failure from the disputed part; other features and undisputed operations continue. After the user chooses which operations to adopt, recompute affected settlements and retain both original operations and reconciliation results. A failure inferred solely because an offline confirmation was not received is not a genuine conflict requiring user arbitration: accept the valid confirmation and reconcile that inference automatically.
- Acceptance: one device has a valid offline daily confirmation while another inferred missed confirmation solely from non-receipt. Apply the valid confirmation without asking the user to choose between it and the inference.
- Acceptance: unorderable active lighting/extinguishing or conflicting branch changes retain both sources and mark affected state and settlement as pending review. Reconciliation chooses valid operations and branch relationships, then recalculates affected settlement without erasing original evidence.

### Focus Session process recovery

- An application process being terminated does not itself create a failed outcome.
- An unpaused Session continues toward its scheduled countdown end. If that end has passed when the app recovers, settle completion at the scheduled end and count only effective focus time within the countdown, excluding paused intervals and the later delay before reopening.
- An approved paused Session remains paused after recovery. Restoring the app does not resume it automatically.
- Recovery settles each accepted Session only once; conflicting multi-device outcomes still require reconciliation.
- Example: a 30-minute unpaused Session loses its app process after 10 minutes and the app is reopened an hour later. It completes at the original 30-minute end and contributes 30 focus minutes and one node, not the elapsed time until reopening.

### Offline focus and multi-device reconciliation

- Starting preparation or focus requires neither a network connection nor cross-device state confirmation. The App does not inspect external behavior. If a known appointment or unfinished Session conflicts with a new start, explain it and offer to continue the original flow or handle its end/cancellation before starting the new flow. Do not provide only a disabled start with no resolution action. Appointment cancellation uses its failure-reason path; focus offers its applicable end/abandon flows without silently bypassing their rules.
- When synchronization reveals conflicts, retain original records and ask the user to review them. Do not choose an outcome automatically by upload order or last-write-wins.
- If records represent the same actual Session, merge their effective focus intervals with overlapping time counted once and generate only one Focus Node for an accepted completed Session.
- If distinct Sessions overlap, the user chooses the actual Session to adopt. Mark the other records as Duplicate Focus Records; these records are not failed outcomes and do not reset any Focus Chain.
- If records for the same actual Session contradict each other, such as completed versus failed, the user confirms the outcome. Neither outcome silently overwrites the other.
- While multi-device conflicts remain unresolved, affected consecutive records are marked “待核对” rather than presented as definitive current values. An optional “上次已确认：X” value must remain clearly labeled. Exclude disputed contributions from official statistics and label the affected totals as containing an unresolved portion. Preserve undisputed records and allow new flows to continue. After reconciliation, recompute affected consecutive records and statistics in actual occurrence order. This is multi-device reconciliation, not voluntary history correction.
- For conflicting Tasks, modes, or configuration of the same flow, show source differences and let the user choose one source record as the configuration basis; do not offer field-by-field composition. Retain every original source. Configuration selection, outcome reconciliation, and time deduplication are separate: choosing a configuration neither discards valid intervals from other sources nor settles a completed-versus-failed conflict. Merge valid focus intervals for the same Session with overlaps counted once, and have the user confirm conflicting outcomes separately. Appointment outcomes always belong to the single Appointment Chain.
- Acceptance: the same Session has 10:00–10:20 under Task A/Elite on one device and 10:10–10:30 under Task B/Regular on another. Choosing A/Elite as configuration does not discard the other source interval: if both intervals are valid and the accepted outcome is completed, count their 30-minute union once under A/Elite. Any outcome disagreement still needs separate confirmation; both sources remain available.
- Acceptance: a disputed completed/failed outcome leaves the affected consecutive record marked “待核对”, optionally showing “上次已确认：X”. Later undisputed attempts remain recorded; after reconciliation recompute in actual occurrence order rather than treating the disputed position as an automatic success or failure.
- Example: two devices hold records for one completed 30-minute focus attempt with identical focus intervals. After the user confirms they are one Session, the result is 30 focus minutes and one node, with both source records retained.
- Example: two different offline Sessions overlap. Once the user adopts one, the other is retained as a duplicate rather than causing a failure or chain reset.
- Example: one source reports completed and another failed for the same Session. Keep both source outcomes visible for review and withhold the disputed contribution pending the user's decision, without stopping current work.

### Device-clock anomaly review

- When device time is abnormal, automatically recover whatever reliable timing evidence establishes. Preserve original records and mark only uncertain times or ordering “待核对”, without directly declaring failure. After review, recompute affected statistics and settlements. Users may defer review when they cannot decide, leaving it pending; other features remain available and starting never requires online clock validation. This review is limited to affected records, not arbitrary timestamp editing of ordinary history.
- Acceptance: a clock jump leaves an uncertain interval marked “待核对” while reliably timed intervals remain valid. Deferring review does not force failure or prevent a new flow.

### Read-only calendar lifecycle and occupancy

- Source event changes or deletions update or remove the corresponding Calendar Blocks. Deselecting a calendar or confirmed permission revocation removes that import source and propagates the removal across devices. If the same event still has another valid import source, remove only the withdrawn source and preserve the valid block. Temporary offline status, read failures, or uncertain permission status retain the last data marked not updated; they do not establish event deletion. These changes affect calendar display and occupancy only, never Tasks or focus history.
- Timed events marked busy count toward occupancy; free events are displayed without occupancy; missing busy/free information defaults to busy. All-day events are date reminders and do not occupy a full day by default. Preserve their original calendar dates across display-time-zone changes. Show recurring events by actual occurrence; rescheduling or cancelling one occurrence changes only that occurrence. Repeated import of the same source event does not duplicate display, and overlapping occupancy is calculated as the union of intervals. Calendar occupancy assists planning and never restricts starting focus.
- Cloud calendar data is limited to title, start/end, all-day and busy/free flags, plus time-zone and source identifiers necessary for correct time interpretation, updates, and deduplication. Do not store descriptions, attendees, or locations.
- Acceptance: sources A and B support the same event. Revoking A removes only A; B keeps the event visible. A transient read failure instead leaves the cached data marked not updated.
- Acceptance: change one recurring occurrence without altering the others. Importing that occurrence repeatedly does not duplicate it. An all-day event on September 14 remains a September 14 date reminder after a display-zone change and never blocks focus startup.

### Notification behavior

- Task deadlines are displayed only inside the App; there are no deadline notifications or advance deadline reminders. Notify when preparation enters focus and when focus ends. National Focus pending-confirmation reminders default to once at 22:00 Beijing time, with a configurable time and an off option. Skip when no nodes are pending. If preparation, focus, or an approved pause is unfinished at reminder time, defer this reminder until the flow ends, then notify once only if nodes are still pending. Each device independently enables notifications and notifies locally, without network coordination to select one device. Other missed notifications are not replayed in a batch. Denied notification permission does not block core features.
- Acceptance: at 22:00 a paused Session defers the National Focus reminder. Resuming alone does not release it; when the flow ends, remind once if nodes remain pending, otherwise skip. A Task approaching its deadline produces no notification.

### Registration eligibility and password access

- Administrators add a specified email address to a registration allowlist in the administration interface. The operator informs users externally; the App sends no invitation or verification messages. Users register with an approved email and password, then log in with that email and password. The server checks registration eligibility, rejects unapproved identifiers and duplicate registration, and marks successfully consumed eligibility as used. Unused eligibility does not expire by default and may be revoked by an administrator. Revoking unused eligibility is distinct from suspending a registered user. The App does not verify email ownership; forgotten passwords are reset by an administrator after manual verification, and the App provides no self-service password recovery.
- Acceptance: an unapproved identifier cannot register; an approved unused identifier can register with a password without receiving a message or verification code. A second registration is rejected. Revoking unused eligibility does not suspend an existing user.

### Suspension retention and cloud purge

- The retention period is 30 days from the current suspension. On expiry mark the user eligible for purge, without automatic deletion. Restoration remains possible until actual purge, cancels the current purge eligibility, and a later suspension starts a new 30-day period. An administrator must explicitly execute purge after a clear confirmation identifying the user and irreversible consequences. Completed purge removes that user's cloud business data and authentication identity. It must not claim that offline devices or local caches have also been erased; their handling follows the offline lifecycle rules below.
- Acceptance: reaching day 30 makes the user eligible without deleting data. Restoring before purge removes eligibility; a later suspension begins a fresh retention period.

### Offline lifecycle during suspension and purge

- A device unaware of suspension may continue offline and retain records; remote suspension is not promised to immediately affect offline devices.
- Once a device reliably knows the account is suspended, stop new business operations and business-data uploads. Retain its local cache, pending uploads, and existing flow state. Existing preparation and unpaused focus settle locally on their original timeline, including automatic handoff; approved paused focus stays paused. Suspension itself causes no failure, cancellation, or abandonment.
- After restoration, synchronize retained records, including records created offline before the device learned of suspension, using original occurrence times, deduplication, and reconciliation. Neither suspension nor delayed upload directly establishes failure. National Focus continues to follow its checkpoint rules; valid offline confirmations do not become invalid because of late upload.
- After cloud purge, reject uploads by the old identity and do not recreate it from local records. Delete that identity's local business cache and pending uploads only after receiving a trustworthy, explicit server result that this old identity has been purged. Network errors, failed login, expired credentials, and ordinary permission denials are never sufficient evidence for local deletion.
- Offline-device data cannot be guaranteed remotely erased; clean it locally when the device later receives trustworthy confirmation of purge.
- Reusing the same email address requires fresh registration eligibility and creates a new user identity. Never automatically inherit, associate, or upload the old identity's data.

- Acceptance: known suspension during preparation does not cancel it: it hands off and settles unpaused focus locally on schedule. A previously paused Session remains paused. No business upload occurs until restoration.
- Acceptance: login failure, token expiry, permission denial, and network failure each preserve the local cache. Only a trustworthy purge result for the old identity authorizes local cleanup; later registration with the same identifier does not reconnect old data.

### Requirements review closure

D01–D25 are closed: 24 confirmed decisions and D03 cancelled. See [the acceptance matrix](acceptance-matrix-20260914.md); local automated verification is recorded above and platform evidence is tracked by T01–T27.

## Out of Scope

- A manual “complete Session” action.
- Separate primary pages for Elite and Regular chains.
- Automatic switching between Elite and Regular chains.
- App detection of user-performed Trigger Signals, such as snaps, gestures, or putting on specific headphones.
- Automatic failure caused only by backgrounding the App.
- Automatic Task or Goal completion from a Session countdown or Focus Progress.
- A separate standalone To-do navigation destination or a general project-management suite.
- Microsoft To Do, Outlook, Microsoft Graph, or bidirectional calendar synchronization.
- Shared organizations, teams, workspaces, or public unrestricted registration.
- Automatic post-failure tree redesign or splitting, replacement-card generation, post-failure redesign suggestions, or automatic card evaluation. User-requested library removal does dissolve the removed subtree as specified above.
- National Focus Groups, tolerance quotas, Water-tight Compartment exceptions, and complex inheritance mechanics.
- Structured Failure Reason categories or cross-domain failure analytics beyond retaining the original short text; these remain future work.
- iOS, macOS, Linux, and Web delivery, and unverified promises about earlier Android or Windows versions.
- Task moves between Goals, Goal/Task restoration, and voluntary changes to settled focus or appointment outcomes.
- Task deadline notifications, App-operated invitation/verification messages, self-service password recovery, and automatic purge on retention expiry.
- Treating removed historical UI images as production design requirements.

## Further Notes

- This specification synthesizes the local [requirements conversation review](requirements-review-20260912.md), [confirmed decisions D01–D25](requirements-decisions-20260913.md), [product design](product-design.md), and the existing core specification. D01/D02/D04–D25 are confirmed; D03 is cancelled. Superseded proposals in the conversation record are historical evidence, not active requirements.
- The 2026-09-21 effective-time revision supersedes the former exclusion of failed Sessions from Task Focus Progress. Both completed and failed Sessions now contribute accepted actual active time. Other outcome, chain, pause, and reconciliation rules remain as specified.
- Use the [domain glossary](../CONTEXT.md) and accepted ADRs for [cloud isolation](adr/0001-supabase-single-project-invite-only-users.md), [read-only calendars](adr/0002-app-owned-tasks-read-only-system-calendar.md), [client stack and platforms](adr/0003-flutter-dart-client-stack.md), and [information architecture](adr/0004-core-screen-information-architecture.md). No ADR change is proposed.
- The [acceptance matrix](acceptance-matrix-20260914.md) provides A01–A32 and supplementary boundary cases. The [document audit](document-audit-20260921.md) records the prior consistency review and removal of old UI references.
- Implementation status (2026-09-26): tickets T01–T27 are closed. Local Flutter tests passed 171 tests and flutter analyze reported no issues. Android 15, Windows 11, and isolated Supabase acceptance evidence is recorded in the tickets; platform integration tests were not rerun during this audit.
- Publication status: the user confirmed the testing seams on 2026-09-21. Implementation tickets T01–T27 are now complete, and [GitHub Issue #20](https://github.com/Kaniruka/Pacta/issues/20) is closed as delivered. To fit GitHub's body-length limit, the complete normative behavior and acceptance examples remain in the [specification supplement comment](https://github.com/Kaniruka/Pacta/issues/20#issuecomment-5761444364), which is part of the same specification.
