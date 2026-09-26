# Pacta - Project Design

## 1. Product intent

Pacta is a cross-platform, open-source app for improving self-regulation. It is intended for personal use with invite-only access rather than as a commercial public SaaS product or shared workspace.

### User agency and convenient support

The product relies on the user's voluntary adherence to their commitments. The App helps users express rules, carry out their chosen flows, and review records; it cannot establish real-world compliance or prevent a determined user from bypassing a rule. Prioritize convenient, understandable operations and trust the user's declarations. Do not introduce rigid restrictions solely to prevent users from finding loopholes in the underlying theory.

“下必为例” records the user's commitment to permit a behavior in future, with interpretation and applicability left to the user. Users may edit or delete permissions to correct their text. Edits apply to subsequent operations; deletion removes the permission from management and selection for new operations. Confirmed operations and history retain the original rule text, so an existing approved pause remains resumable. Rules may be created in My or created and immediately used during focus, in the same shared collection.

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

A Focus Chain records consecutive focus outcomes independently of Task identity. Each attempt adopts Elite or Regular mode, which determines only its focus record attribution; all preparation uses one shared, separately settled Appointment Chain. Task classifications organize and filter work and do not fix the attempt mode. The product has exactly three independent records per user: Appointment Chain, Elite Focus Chain, and Regular Focus Chain. It does not support user-created independent chains. The chain should support:

- selecting an appropriate focus practice according to the user's current state, available uninterrupted time, and task fit;
- user selection of the Focus Chain according to their current state;
- selecting Tasks from the current chain mode's eligible task pool;
- using a user-performed Trigger Signal, such as putting on specific headphones or snapping one's fingers three times, as the practical form of the Sacred Seat;
- supporting a manually invoked Trigger Signal without requiring the App to detect the real-world action;
- supporting an Appointment Chain as a delayed-start path into a Focus Chain;
- using a fixed 15-minute preparation countdown that automatically starts the preconfigured Focus Session when it ends;
- an explicit focus trigger or start protocol;
- a clearly defined session unit with a countdown boundary;
- the countdown boundary and available Precedent Rule operations shown before starting;
- requiring the session to run to the countdown boundary by default;
- allowing pause or early termination only through a Precedent Rule exception;
- supporting “下必为例” through shared, user-maintained permissions; users judge applicability and whether to establish a rule or acknowledge failure;
- requiring an interruption decision: acknowledge failure with a brief Failure Reason, or create or select a Precedent Rule for the applicable operation; actual active time counts toward Task Focus Progress for either settled outcome;
- failure when the user does not sustain a session successfully;
- failure when the user actively abandons a session;
- resetting only the selected chain's current consecutive record to zero after a confirmed failure;
- retaining the session history and a short user-entered reason for failure;
- treating “放弃本次专注” as an action that confirms a failed outcome with a brief reason, not a separate abandoned outcome;
- a visible history of system-generated completed nodes, with one Focus Node appended whenever a Focus Session completes normally or through Precedent Rule-approved early termination; users may add notes but cannot create nodes manually;

The product should preserve the useful CTDP ideas of lowering start resistance and making the session boundary explicit, without requiring users to understand the original mathematical terminology.

The current candidate selection table is:

| Situation | Focus practice | Typical duration |
| --- | --- | --- |
| High energy, enough time, quiet environment, high confidence of success | Elite Focus Chain (精锐链) | 45–60 minutes |
| Ordinary state but stable enough to work | Regular Focus Chain (普通链) | 20–30 minutes |
| Almost unable to start; only testing the current state | Recon Practice (侦查练习) applied to a concrete Goal Task | 5 minutes |

This table offers practice suggestions. Recon Practice is an execution method applied to an existing Goal Task; it has no independent App entity, chain, node, or history record. The listed durations are suggestions only: the user chooses the actual Focus Session countdown, and Elite or Regular classification never determines the timer length. If the user proceeds from the probe into focused work, they explicitly start a normal Focus Session for that Task.

Failure reasons begin as required short free-text summaries when the user fails or abandons a session. A few words are sufficient initially, and the user can edit the reason later. No empty “暂时无法总结” path is provided. Later, optional structured categories or tags may be added for aggregate statistics, trend analysis, and comparison with National Focus Tree failure reasons, while preserving the original text. Fine-grained filtering by reason is not a core interaction because early users will not have enough records for it to be useful.

Once started, a Focus Session continues while the App is in the background. Process termination alone does not fail the Session. On recovery, an unpaused Session whose scheduled countdown has elapsed completes at its scheduled end, counting only effective focus time within the countdown rather than the later reopening delay. An approved paused Session remains paused, and recovery settles an outcome only once. A persistent notification keeps the countdown visible and active for tasks that require the user to operate the mobile device. The countdown is a boundary and progress cue, not the sole measure of completion.

The CTDP-derived signal model is intentionally human-operated: a user may perform an Appointment Chain signal and open the corresponding flow, or perform an immediate-start signal and open the Focus Chain directly. The App does not listen for or verify snaps, gestures, or other physical markers. Once preparation has started, its transition into focus requires neither another signal nor another start click.

The Appointment Chain provides a fixed 15-minute delayed start and owns its own consecutive record and history independently of Focus Chains. Preparation does not restrict real-world behavior and cannot be paused. Users may change the preselected Task and focus duration without resetting preparation, or enter focus early without an exception. Normal and early entry each record one appointment success, which later focus failure does not revoke. Appointment and focus recover on their configured timeline even if all Apps were closed; no proof of real-world activity is required. Cancellation never resets a Focus Chain. Cancellation requires a brief Failure Reason and clears the corresponding Appointment Chain current consecutive record; there is no exception cancellation path. Users select a Task and duration, with the attempt mode shown in the existing settings area, and directly start preparation or focus without an extra chain-selection page, binding, or pairing. Classification organizes Goals and Tasks; the attempt mode determines focus attribution independently, while appointment attribution never varies by mode.

The focus boundary follows “下必为例” as a voluntary user commitment. 下必为例 permissions are shared across Focus Chains and each is recorded as a passage of user-written text; the user determines its meaning and applicability. The App requires no separate name, structured conditions, or prescribed wording and does not evaluate the text. Ordinary permitted behavior continues to count as focus time without per-use logging. Pause and early termination require selecting a rule and confirming the operation, with no mandated wording in the rule. The App does not detect violations or react to switching Apps. Before confirming an operation the user may always return to the running countdown. Rule editing and deletion remain available for user corrections with clear effects and preservation of historical rule bases. See the core specification for acceptance examples.

### 2.2 National Focus Tree

The National Focus Tree models gradual changes in the user's daily system. Nodes should be small enough to survive a poor day, and the tree should support branching, reinforcement, backtracking, and controlled recovery.

The tree reflects the user's current state and may inform the user's explicit Focus Chain selection; it never switches or blocks the chain automatically and is not attached to a Goal or Task. Users create cards in the Card Library and place each card at one tree position. Cards have no countdown. Adding at most one card per day may be recommended but is not a hard limit; complex inheritance remains deferred.

Daily confirmation means “确认今日继续有效”. At the National Focus Checkpoint, Lit nodes become Pending Today Confirmation: visually unlit, without failure or a Failure Reason. Users light them individually or click One-click Confirm Today, which lights only pending nodes. Already Lit nodes are unchanged. Active extinguishing offers an optional brief Failure Reason and puts the node in the distinct Extinguished state, outside the batch. It requires separate manual lighting to return. For example (all times Beijing time), a node made pending at 04:00, manually lit at 08:00, and actively extinguished at 09:00 stays Extinguished after the 10:00 batch. Active extinguishing preserves current records until the next checkpoint: if still extinguished then, settle failure and save its snapshot; relighting beforehand preserves the record and prevents that failure. Active National Focus extinguishing permits a brief reason or “暂不填写”. If the node remains extinguished and formally fails at the checkpoint, its failure record offers a non-blocking reminder and an entry to add the missing reason, without mandatory dialogs or blocked functionality. Recovery before the checkpoint removes any need to supply a reason. Missed-confirmation failure uses the system reason “未完成今日确认”, with optional user commentary. At each 04:00 Beijing-time checkpoint, settle the ending National Focus Day first. Each card still Lit and unaffected by parent failure gains one cumulative successful day and one current consecutive count, updating its historical maximum when exceeded; then surviving Lit cards enter the new day's Pending Today Confirmation state. Count at most once per card per National Focus Day. First lighting at 03:59 qualifies at 04:00; repeated extinguishing and relighting within the day never adds extra counts. A successful day means passing one checkpoint settlement, not maintaining validity for 24 hours. In this model, the prior yesterday-success and first-confirmation batch-gate rules no longer apply. See [the core specification](spec-focus-loop-and-core-shell.md#daily-confirmation-and-node-states) for state transitions, retained rules, and acceptance examples.

The National Focus Checkpoint is fixed at daily 04:00 Beijing time (UTC+08:00), equivalent to 20:00 UTC on the preceding date. A National Focus Day spans two consecutive checkpoints. Changing user or device time zones only changes the local date/time display; settlement and the confirmation deadline remain the same instant. Display the next checkpoint with its local date and time zone, rather than always calling it local 04:00. This replaces the former user-controlled boundary and the associated deadline-change acknowledgment, online validation, and switch-blocking rules. Daily focus duration is allocated across calendar days using effective focus intervals, excluding pauses, in the device's display time zone. Default to the device time zone and allow a manual zone preference stored per device. Changing the display zone redistributes daily totals but never changes total duration, actual occurrence order, or the three consecutive records. Different devices using different zones may show different daily totals. National Focus settlement remains fixed at 04:00 Beijing time. Focus Sessions and daily confirmation remain available offline, and valid confirmations cannot fail merely because their uploads are delayed or absent at the server.

Active parent extinguishing also extinguishes descendants, without deleting cards or creating separate descendant reasons solely for the cascade. Independent child violations remain distinguishable when their failure conditions still hold at settlement. When parent and child are both Pending Today Confirmation, the child may be confirmed alone without confirming the parent. If the parent remains unconfirmed and formally fails at the checkpoint, its child is affected and receives no success increment that day. One-click Confirm Today processes all Pending Today Confirmation nodes and never restores Extinguished nodes. Record unrelated nodes by independent failure source. A parent failure event includes descendants affected solely by that parent, without separate descendant events. Preserve an independent child event only when its independent failure condition still holds at the checkpoint. Each node settles failure at most once per checkpoint even if multiple sources affect it. Every event retains the complete immutable tree snapshot. A batch of failures arising from the daily-confirmation flow has exactly one optional failure-reason entry shared by all records in that batch, not one entry per event. Missed confirmation uses the system reason “未完成今日确认”; users may add one shared explanation linked to the batch records. Do not require completion, show mandatory dialogs, or block use. Separate failure events do not imply separate reason-entry chores. An Extinguished parent must be lit before its child; relighting the parent does not automatically relight Extinguished children. Failure records retain complete immutable tree snapshots and editable reasons; active-extinguish failure settles at the next checkpoint only if the node remains extinguished, with its snapshot saved at that checkpoint. Failure preserves historical maxima and Internalization Progress, leaves cards in place, and does not affect the parent of the failed node. Users may restructure in place or create new cards, which do not inherit failed records; no replacement cards are automatically generated. Never-lit cards are not failures and already failed cards left extinguished do not repeatedly fail.

Moving cards directly between branches preserves records. Moving a parent to the Card Library moves it and all descendants together, but removes their parent-child relationships: they become independent cards. Place cards back individually, choose a new tree position for each, and light each manually; there is no whole-subtree restore. Preserve each card's existing records and leave historical snapshots unchanged. Cards in the library do not participate in One-click Confirm Today. A card placed back and lit before the checkpoint retains its consecutive record; a card not restored to a valid state settles failure under the existing rules. Never-lit cards and cards whose maintenance cycle has already failed do not generate repeated failures merely by remaining in the library. Snapshot-referenced cards can only be soft-deleted and restored to the library; unreferenced cards may be permanently deleted. Later edits never rewrite failure snapshots.

Internalization Progress retains cumulative successful-day count `S` and the formula `I = 100 * (1 - exp(-S / 60))`, starting at zero and approaching 100 asymptotically. Failure, extinguishing, library moves, and restoration preserve it; users cannot edit it. Qualitative labels are presentation only. At each 04:00 Beijing-time checkpoint, settle the ending National Focus Day first. Each card still Lit and unaffected by parent failure gains one cumulative successful day and one current consecutive count, updating its historical maximum when exceeded; then surviving Lit cards enter the new day's Pending Today Confirmation state. Count at most once per card per National Focus Day. First lighting at 03:59 qualifies at 04:00; repeated extinguishing and relighting within the day never adds extra counts. A successful day means passing one checkpoint settlement, not maintaining validity for 24 hours. At the next National Focus Checkpoint, all nodes still awaiting the ending day's confirmation become Extinguished and formally failed: save the complete failure snapshot first, clear their current records, preserve historical maxima and Internalization Progress, and require manual relighting. This clarifies the earlier tree-wide wording: independently confirmed nodes are not failed because others remain unconfirmed; existing parent-failure effects still apply. Settle the ending day before moving surviving Lit nodes to the new day's Pending Today Confirmation state. Independent-source failure events share one explanation entry per daily-confirmation failure batch as specified above; an empty pending set does not settle the day early or add counts; the timeout itself is final failure.

National Focus Cards use lightweight structured fields for a Trigger Condition and Action, with optional Scope and Exception Notes. These fields describe the user's rule but are not automatically evaluated by the App. The first version keeps parent-child behavior strict and does not model a separate National Focus Group or tolerance quota. It also excludes Water-tight Compartment freeze exceptions and automatic post-failure redesign suggestions. Failure reasons and tree snapshots remain available for later reflection and future recommendation features.

Strengthening levels are user-authored requirements, not numeric-only bonuses. The user can customize a stricter Trigger Condition, a stricter Action, or both. For example, the base trigger "before 02:00" can be strengthened to "before 01:00"; an action may similarly be changed from "read 5 pages" to "read 10 pages". Card details must display the concrete current requirements and provide editable strengthening fields with the base requirements visible for comparison. Library summaries show the current applicable requirements rather than relying on a +1/+2 badge. Internalization Progress remains separate and does not automatically set or unlock these requirements. Each card retains its base rules and supports up to five user-created strengthening levels in addition to the base. Users can create levels over time and edit the Trigger Condition and Action requirements of each level. The interface lists the existing levels and their concrete requirements, shows the count out of five, and offers a new-level action until five levels exist. At the limit, it explains that at most five strengthening levels can be created; existing levels remain editable. Users select strengthening levels manually; there is no automatic upgrade or failure-driven downgrade. Saving requirement edits or switching levels takes effect immediately without extinguishing the card, resetting records, or requiring reconfirmation. The user judges compliance. Preserve the requirements in effect for history, including both versions and their effective times when requirements change within a National Focus Day. Never interpret earlier activity that day as having followed a later requirement version.

Choosing Attach or Restore from the Card Library returns to the National Focus Tree main page in parent-selection mode. The user selects a top-level position or clicks an existing node on the tree canvas to make it the card's parent; a separate branch-list dialog is not used. An empty tree offers Add First National Focus Card, leading to selection of an existing Card Library card for top-level placement; new card creation remains in the Card Library. The top-level position is only a structural location and does not participate in lighting, confirmation, or failure evaluation; the card placed there follows normal node rules. Placement still requires subsequent manual lighting.

### 2.3 Tasks and deadlines

The App owns the To-do experience. A first version should keep the model deliberately small:

- a Goal grouping multiple executable Tasks; the first version uses only a two-level Goal -> Task hierarchy, without nested child Tasks, and every Task in a Goal is required;
- title;
- deadline;
- estimated duration;
- accumulated Focus Progress from completed and failed Focus Sessions, excluding paused time;
- Task Chain Classification as Elite, Regular, or explicitly both;
- priority;
- status;
- optional notes.

The task list exists to feed the focus loop, not to become a general-purpose project-management suite. A Goal may contain both Elite and Regular Tasks, and all of its Tasks are required in the first version. Chain classifications organize work; the user selects a Task and duration and starts preparation or focus without an additional chain-picking step. The attempt adopts Elite or Regular mode: inherit it from a mode-specific list, or show the last selected mode with direct switching in the duration-settings area when entering from all Tasks. No separate mode-selection page is needed. Goal classification may suggest defaults for new Tasks; editing it does not reclassify existing Tasks. Classification edits never migrate past records, and active attempts retain their mode and attribution. The selected Focus Session then records progress against the Task while the chain records the session node. Recon Practice is only a user-selected way to approach one of those existing Tasks; it does not create a separate task or record.

Task completion remains separate from Focus Session completion. A normal countdown ending or an exception-approved early termination records a completed Focus Session and appends one Focus Node. An exception-approved pause preserves the same Session in a resumable state without settling progress or creating a node. Continue uses the retained pause-rule revision without asking for another rule selection or confirmation. The first version has no automatic pause timeout; a known conflicting appointment or Session opens an actionable choice to continue the original flow or end/cancel it through its applicable flow before starting the new one. A bare prohibition is insufficient, and remote-state confirmation is not a start prerequisite. An offline device that cannot know another device's state may still start a Session. Later conflicts follow the user reconciliation rules below. On return, the user can continue, request rule-approved early termination, or abandon through the existing outcome flow. Paused time is excluded from focus time; the Session settles only once when it reaches a final outcome. Completed and failed Sessions both contribute their actual active focus time to Task Focus Progress. Task Focus Progress accumulates by Task, while Recent Focus Activity groups the same effective time by calendar date; both exclude pauses and unresolved conflicting contributions and apply the same reconciliation and deduplication rules. Failure still resets the applicable Focus Chain's current consecutive record and creates no Focus Node. Neither session completion nor Focus Progress automatically completes the Task. A Task becomes complete only through explicit user confirmation, and a nonempty Goal becomes complete when all of its Tasks are explicitly complete; an empty Goal is not complete.

### Goal and Task lifecycle

- An empty Goal displays “暂无任务” and is not complete. A nonempty Goal displays completed only when every Task has been manually marked complete. Adding an incomplete Task or undoing a Task's completion makes the Goal incomplete again.
- This is a derived Goal status, not automatic Task completion: neither a Focus Session ending nor accumulated Focus Progress marks a Task complete.
- Moving a Task between Goals is not supported. No move-related progress transfer or history reassignment feature is required.
- Deleted Goals and Tasks cannot be restored. There is no Goal/Task recycle-bin or restore feature. This does not change National Focus Card restoration or user suspension/restoration rules.
- Deleting a Goal also deletes its Tasks, with no restore feature. Existing focus history and all three chain records are retained; history shows the original Task name marked “已删除”. An already running appointment, active Session, or paused Session continues and settles normally, including the existing appointment's automatic focus handoff. Deleted Tasks cannot be used to start a new flow. Deletion itself causes no failure, and ordinary edits from another device cannot resurrect the Task.

### 2.4 Device calendars

Device calendars provide read-only planning context and never restrict starting focus.

- Android reads selected calendars through the platform Calendar Provider.
- The App normalizes the result into Calendar Blocks.
- The cloud stores only the minimum information needed for cross-device planning.
- The desktop client reads the normalized blocks from the cloud instead of requiring a second platform-specific calendar integration.

Source event changes or deletions update or remove the corresponding Calendar Blocks. Deselecting a calendar or confirmed permission revocation removes that import source and propagates the removal across devices. If the same event still has another valid import source, remove only the withdrawn source and preserve the valid block. Temporary offline status, read failures, or uncertain permission status retain the last data marked not updated; they do not establish event deletion. These changes affect calendar display and occupancy only, never Tasks or focus history.

Timed events marked busy count toward occupancy; free events are displayed without occupancy; missing busy/free information defaults to busy. All-day events are date reminders and do not occupy a full day by default. Preserve their original calendar dates across display-time-zone changes. Show recurring events by actual occurrence; rescheduling or cancelling one occurrence changes only that occurrence. Repeated import of the same source event does not duplicate display, and overlapping occupancy is calculated as the union of intervals. Calendar occupancy assists planning and never restricts starting focus.

Cloud calendar data is limited to title, start/end, all-day and busy/free flags, plus time-zone and source identifiers necessary for correct time interpretation, updates, and deduplication. Do not store descriptions, attendees, or locations.

The initial UI needs an agenda or time-axis view, not a complete Outlook/Apple Calendar replacement. It should show fixed blocks, available focus windows, and approaching deadlines.

The first version does not integrate Microsoft To Do, Outlook, Microsoft Graph, or bidirectional calendar editing.

### Notifications

Task deadlines are displayed only inside the App; there are no deadline notifications or advance deadline reminders. Notify when preparation enters focus and when focus ends. National Focus pending-confirmation reminders default to once at 22:00 Beijing time, with a configurable time and an off option. Skip when no nodes are pending. If preparation, focus, or an approved pause is unfinished at reminder time, defer this reminder until the flow ends, then notify once only if nodes are still pending. Each device independently enables notifications and notifies locally, without network coordination to select one device. Other missed notifications are not replayed in a batch. Denied notification permission does not block core features.

### 2.5 Core screen information architecture

The accepted mobile-first shell uses four primary destinations: **Board**, **National Focus Tree**, **Focus Chain**, and **My**. The Board is the user's first landing surface: it shows the App-owned Task list first, then combines Task Focus Progress, Focus Chain consecutive records, National Focus status, and Recent Focus Activity. It is not a separate general-purpose project-management suite, and there is no standalone To-do navigation destination.

The National Focus Tree is a dedicated structural canvas. Its relevant actions are daily confirmation, opening the Card Library, and attaching an existing Card Library card to the tree. The tree's `Simple` view shows node icons and structure; its `Detailed` view adds card text, dates, records, and state. Creating a new National Focus Card begins in the Card Library's secondary page, not from the tree's attach action.

The Focus Chain destination is the setup surface for one Focus Session. Selecting a task opens a secondary task-picker page where Elite, Regular, and Both classifications are filters; they are not separate primary pages. Appointment Chain and immediate-start flows remain available here. Shared Precedent Rule management is available only under My. Chain menus have no management entry; focus interruption flows retain direct selection of existing shared rules.

After a Focus Session begins, the App enters a dedicated Session surface. A Session normally completes only when its countdown reaches zero; there is no manual completion action. Pause, early termination, and abandonment enter the applicable Precedent Rule or Failure Reason flow with an option to return to the Session. Continue resumes the existing approved pause without another rule selection or confirmation. Background execution remains supported by persistent notification.

## 3. Users and access

The App uses one Supabase project to serve multiple users. It does not create an App-level organization or workspace model.

- Supabase Auth identifies the user.
- Every business row is associated with `user_id`.
- Row Level Security ensures that a user can only read or modify their own rows.
- A separate `app_admins` table identifies the administrator identities.
- Registration eligibility records control which email addresses may register; email is the sole registration and password-login identifier.

The administrator should have an in-App user-management screen for:

- granting and revoking unused registration eligibility for an email address;
- reviewing unused and used registration eligibility;
- resetting forgotten passwords after manual verification;
- viewing active users and last activity;
- suspending or restoring users;
- purging users after the retention period.

Administrators add a specified email address to a registration allowlist in the administration interface. The operator informs users externally; the App sends no invitation or verification messages. Users register with an approved email and password, then log in using that email and password. The server checks registration eligibility, rejects unapproved identifiers and duplicate registration, and marks successfully consumed eligibility as used. Unused eligibility does not expire by default and may be revoked by an administrator. Revoking unused eligibility is distinct from suspending a registered user. The App does not verify email ownership. Forgotten passwords are reset by an administrator after manual verification; the App provides no self-service password recovery. Server-side eligibility enforcement is required; hiding client controls is insufficient.

## 4. User lifecycle

Registration Eligibility is a one-use registration permission. Successful registration consumes that permission and creates an Active User.

The registered user's lifecycle is active -> suspended -> purge_eligible -> deleted. Restoration from suspended or purge_eligible returns the user to active before actual purge; a later suspension starts a fresh retention period.

- `active`: normal access and participation;
- `suspended`: new business operations and uploads stop once the device knows of suspension; local data and existing flow state are retained under the offline lifecycle rules;
- `purge_eligible`: the current suspension has lasted 30 days; an administrator may purge, but deletion is not queued automatically;
- `deleted`: cloud business data and the authentication identity have been purged; local cleanup follows trustworthy confirmation on each device.

The retention period is 30 days from the current suspension. On expiry mark the user eligible for purge, without automatic deletion. Restoration remains possible until actual purge, cancels the current purge eligibility, and a later suspension starts a new 30-day period. An administrator must explicitly execute purge after a clear confirmation identifying the user and irreversible consequences. Completed purge removes that user's cloud business data and authentication identity. It must not claim that offline devices or local caches have also been erased; their handling follows the offline lifecycle rules below.

### Offline lifecycle during suspension and purge

- A device unaware of suspension may continue offline and retain records; remote suspension is not promised to immediately affect offline devices.
- Once a device reliably knows the account is suspended, stop new business operations and business-data uploads. Retain its local cache, pending uploads, and existing flow state. Existing preparation and unpaused focus settle locally on their original timeline, including automatic handoff; approved paused focus stays paused. Suspension itself causes no failure, cancellation, or abandonment.
- After restoration, synchronize retained records, including records created offline before the device learned of suspension, using original occurrence times, deduplication, and reconciliation. Neither suspension nor delayed upload directly establishes failure. National Focus continues to follow its checkpoint rules; valid offline confirmations do not become invalid because of late upload.
- After cloud purge, reject uploads by the old identity and do not recreate it from local records. Delete that identity's local business cache and pending uploads only after receiving a trustworthy, explicit server result that this old identity has been purged. Network errors, failed login, expired credentials, and ordinary permission denials are never sufficient evidence for local deletion.
- Offline-device data cannot be guaranteed remotely erased; clean it locally when the device later receives trustworthy confirmation of purge.
- Reusing the same email address requires fresh registration eligibility and creates a new user identity. Never automatically inherit, associate, or upload the old identity's data.

## 5. Persistence and synchronization

The cloud backend is required for mobile/desktop synchronization. The accepted client baseline is:

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

The cloud stores shared synchronized records; devices retain durable local records and synchronize when the App starts, resumes, or regains connectivity. Offline daily confirmations take effect locally immediately and later upload both the record and result. The server must not infer missed-confirmation failure from non-receipt or upload time. Offline Focus Session starts are allowed subject to the device's known unfinished Sessions; conflicting records require user reconciliation rather than cloud last-write-wins outcome selection. Android 15 and Windows 11 are both included in the first implementation and acceptance round, using the same Flutter/Dart codebase. Both support Task management, National Focus maintenance, focus execution, and history viewing; usage emphasis does not restrict features by device. Both support offline operation and synchronize the same business records. A synchronized preparation countdown and its subsequent Focus Session remain the same attempt across devices; viewing or continuing it on another device does not create a second Session. Conflicts follow the reconciliation rules. Material 3 supplies the cross-platform component foundation, while the product's final visual language and screen composition remain subject to UI prototyping.

When conflicting active offline National Focus operations cannot be reliably ordered, show the operations and their effects for user reconciliation rather than overwriting by upload order. Preserve valid, complete branch relationships when parent-child structure is involved; do not compose invalid structures field by field. Until review, mark affected states and statistics “待核对” without determining success or failure from the disputed part; other features and undisputed operations continue. After the user chooses which operations to adopt, recompute affected settlements and retain both original operations and reconciliation results. A failure inferred solely because an offline confirmation was not received is not a genuine conflict requiring user arbitration: accept the valid confirmation and reconcile that inference automatically.

Daily focus duration is allocated across calendar days using effective focus intervals, excluding pauses, in the device's display time zone. Default to the device time zone and allow a manual zone preference stored per device. Changing the display zone redistributes daily totals but never changes total duration, actual occurrence order, or the three consecutive records. Different devices using different zones may show different daily totals. National Focus settlement remains fixed at 04:00 Beijing time.

When device time is abnormal, automatically recover whatever reliable timing evidence establishes. Preserve original records and mark only uncertain times or ordering “待核对”, without directly declaring failure. After review, recompute affected statistics and settlements. Users may defer review when they cannot decide, leaving it pending; other features remain available and starting never requires online clock validation. This review is limited to affected records, not arbitrary timestamp editing of ordinary history.

Recommended data groups:

- `profiles`: user identity, lifecycle status, and activity timestamps;
- `goals`: broader outcomes grouping related Tasks;
- `tasks`: App-owned tasks;
- `calendar_blocks`: normalized read-only calendar planning context;
- `focus_chains` and `focus_nodes`: chain definitions and progression;
- `national_focus_nodes`: current focus-tree definitions and state, including soft-deletion state for snapshot-referenced cards;
- `national_focus_failure_records`: append-oriented failure logs with brief reasons and complete tree snapshots;
- `focus_sessions`: append-oriented history of focus attempts, outcomes, and failure reasons;
- `sync_metadata`: device cursors, versions, or synchronization timestamps.

For the first version, simple field-level last-write-wins behavior is acceptable for editable task metadata. Focus-session history retains original records. After synchronization reveals conflicting focus records, the user reviews them: records for the same actual Session merge with overlapping focus time counted once, and an accepted completed outcome creates one Focus Node; overlapping different Sessions require selection of the actual Session to retain, while the others become Duplicate Focus Records without failure or chain reset; contradictory outcomes such as completed and failed require user confirmation and must not overwrite one another automatically. While multi-device conflicts remain unresolved, affected consecutive records are marked “待核对” rather than presented as definitive current values. An optional “上次已确认：X” value must remain clearly labeled. Exclude disputed contributions from official statistics and label the affected totals as containing an unresolved portion. Preserve undisputed records and allow new flows to continue. After reconciliation, recompute affected consecutive records and statistics in actual occurrence order. This is multi-device reconciliation, not voluntary history correction. For conflicting Tasks, modes, or configuration of the same flow, show source differences and let the user choose one source record as the configuration basis; do not offer field-by-field composition. Retain every original source. Configuration selection, outcome reconciliation, and time deduplication are separate: choosing a configuration neither discards valid intervals from other sources nor settles a completed-versus-failed conflict. Merge valid focus intervals for the same Session with overlaps counted once, and have the user confirm conflicting outcomes separately. Appointment outcomes always belong to the single Appointment Chain. Other features remain usable and an ongoing Session is not interrupted. Deletions should be represented carefully so another device does not resurrect deleted data. Detailed behavior and acceptance scenarios are in [the core specification](spec-focus-loop-and-core-shell.md#offline-focus-and-multi-device-reconciliation).

## 6. Security and privacy

- All exposed tables require RLS.
- The client uses only the publishable/anonymous key.
- Secret/service-role keys are restricted to Edge Functions or other trusted server environments.
- Registration eligibility, suspension, purge, and other administrative operations run through trusted server code.
- Calendar synchronization should default to selected calendars and minimum necessary fields.
- The App should not store calendar descriptions, attendees, or locations unless a later feature explicitly requires them.

## 7. MVP boundary

### Product platform scope and delivery stages

The currently committed platforms are Android and Windows only. Initial acceptance is on Android 15 and Windows 11 with equal core features and offline capabilities. Minimum support for earlier OS versions will be determined by compatibility validation, without advance promises. iOS, macOS, Linux, and Web are outside the committed scope and require a separate future decision.

The first useful version should contain:

1. password registration and login with server-enforced administrator-issued eligibility for email addresses;
2. per-user task list;
3. the three fixed chain records and focus-session execution;
4. a minimal National Focus Tree;
5. read-only mobile system-calendar import;
6. focus-transition and deferred National Focus notifications, with deadlines displayed only in-App;
7. mobile/desktop synchronization;
8. administrator user lifecycle controls.

The first version should not contain:

- Microsoft ecosystem integration;
- full bidirectional calendar synchronization;
- shared organization data;
- a general project-management suite;
- public unrestricted registration;
- a full calendar replacement.

## 8. Implementation work and future scope

The reviewed business decisions D01–D24 are closed; see [the acceptance matrix](acceptance-matrix-20260914.md). This does not mean implementation or acceptance testing is complete.

- structured Failure Reason categories or tags remain future scope;
- National Focus states and transitions follow the core specification;
- responsive layout, production component inventory, and exact Material 3 token mapping;
- the final Supabase schema and migration strategy.

### No voluntary history correction

The App does not offer corrections to settled focus or appointment outcomes. This withdraws the earlier completed-to-failed correction feature and related historical-maximum questions. Multi-device reconciliation of conflicting source records remains supported as a separate flow.
