# Pacta - Project Design

> UI 实施、评审与验收范围按 [ADR 0007](adr/0007-accessibility-out-of-product-scope.md) 和后续 [ADR 0008](adr/0008-large-text-and-keyboard-out-of-product-scope.md) 执行；被替代条款不再构成交付条件，有日期的验收记录保留当时事实。

## 1. Product intent

### Shared typography — 2026-11-13

Android 与 Windows 统一内置 MiSans，中文、英文和数字继承共用 `ThemeData`。保留 Material 3 的语义字号、亮暗颜色与层级；使用官方原版 Regular / Medium / Semibold / Bold 对应 400 / 500 / 600 / 700，避免系统回退造成同段文字字形和粗细割裂。未覆盖字符仍由系统回退，不承诺所有语言及 emoji 的跨平台字形一致。应用「我的」页注明使用 MiSans；许可随资源打包。字体获取、固定校验值和许可来源见 [字体说明](../assets/fonts/README.md)，本次验证见 [字体验收](typography-20261113.md)。

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

Focus Chains support deliberate commitment independently of Task completion. Elite/Regular mode, Task classification, and the shared Appointment Chain are distinct concepts; definitions are maintained in [GLOSSARY](../GLOSSARY.md), with executable rules in the [core specification](spec-focus-loop-and-core-shell.md#attempt-mode-classification-and-record-scope).

The product should preserve the useful CTDP ideas of lowering start resistance and making the session boundary explicit, without requiring users to understand the original mathematical terminology.

The current candidate selection table is:

| Situation | Focus practice | Typical duration |
| --- | --- | --- |
| High energy, enough time, quiet environment, high confidence of success | Elite Focus Chain (精锐链) | 45–60 minutes |
| Ordinary state but stable enough to work | Regular Focus Chain (普通链) | 20–30 minutes |
| Almost unable to start; only testing the current state | Recon Practice (侦查练习) applied to a concrete Goal Task | 5 minutes |

This table offers practice suggestions. Recon Practice is an execution method applied to an existing Goal Task; it has no independent App entity, chain, node, or history record. The listed durations are suggestions only: the user chooses the actual Focus Session countdown, and Elite or Regular classification never determines the timer length. If the user proceeds from the probe into focused work, they explicitly start a normal Focus Session for that Task.

Failure reasons begin as required short free-text summaries when the user fails or abandons a session. A few words are sufficient initially, and the user can edit the reason later. No empty “暂时无法总结” path is provided. Later, optional structured categories or tags may be added for aggregate statistics, trend analysis, and comparison with National Focus Tree failure reasons, while preserving the original text. Fine-grained filtering by reason is not a core interaction because early users will not have enough records for it to be useful.

The current focus loop is maintained in these core-specification sections; page presentation is described under the primary destinations below:

| Behavior | Current contract |
| --- | --- |
| Shared user-written permissions and interruption choices | [Precedent permissions](spec-focus-loop-and-core-shell.md#precedent-permissions-下必为例), [resumable pause](spec-focus-loop-and-core-shell.md#resumable-focus-session-pause) |
| Failed outcome, retained active time, and selected-chain reset | [Abandon action](spec-focus-loop-and-core-shell.md#abandon-action-and-failed-outcome), [Focus Session stories](spec-focus-loop-and-core-shell.md#focus-session) |
| Background/process recovery and one-time settlement | [Process recovery](spec-focus-loop-and-core-shell.md#focus-session-process-recovery) |
| Fixed preparation, configuration changes, early handoff and cancellation | [Appointment preparation](spec-focus-loop-and-core-shell.md#appointment-preparation-and-automatic-handoff) |
| Human-operated signals and cumulative/average duration | [Chain signals and duration](spec-focus-loop-and-core-shell.md#chain-signals-and-duration--2026-10-07) |

### 2.2 National Focus Tree

The National Focus Tree models gradual changes in the user's daily system. Nodes should be small enough to survive a poor day, and the tree should support branching, reinforcement, backtracking, and controlled recovery.

The tree reflects the user's current state and may inform the user's explicit Focus Chain selection; it never switches or blocks the chain automatically and is not attached to a Goal or Task. Users create cards in the Card Library and place each card at one tree position. Cards have no countdown. Adding at most one card per day may be recommended but is not a hard limit; complex inheritance remains deferred.

Detailed state and settlement rules are maintained in the core specification rather than repeated here:

| Behavior | Current contract |
| --- | --- |
| Daily confirmation, active extinguishing and batch membership | [Daily confirmation and node states](spec-focus-loop-and-core-shell.md#daily-confirmation-and-node-states) |
| Fixed checkpoint, time-zone display and parent-caused failure | [Checkpoint](spec-focus-loop-and-core-shell.md#national-focus-checkpoint-and-time-zone-display), [parent-caused failure](spec-focus-loop-and-core-shell.md#parent-caused-national-focus-failure) |
| Successful days, failure snapshots, optional reasons and Internalization Progress | [Settlement and retained records](spec-focus-loop-and-core-shell.md#national-focus-settlement-and-retained-records) |
| Branch/library moves and individual placement | [Library removal and placement](spec-focus-loop-and-core-shell.md#card-library-removal-and-individual-placement); snapshot-referenced deletion rules remain in [Card Library stories](spec-focus-loop-and-core-shell.md#national-focus-tree-and-card-library) |
| Offline operation and display-day focus totals | [Offline National Focus](spec-focus-loop-and-core-shell.md#offline-national-focus-and-manual-cloud-sync), [daily allocation](spec-focus-loop-and-core-shell.md#daily-focus-allocation-and-display-preferences) |

National Focus Cards have a required independent Name and 国策规则 (one rule text), plus optional 例外与判例. Names may repeat and can be changed independently of requirements, Strengthening Levels, and maintenance records; changing a name does not start a Requirement Version. Current names travel with explicit whole-data cloud snapshots, while new failure snapshots preserve the name at the event time. Current card information no longer shows the former Trigger Condition or Scope; stored requirement versions and failure snapshots may retain them as history. These fields describe the user's rule but are not automatically evaluated by the App. A card with non-empty 例外与判例 is excluded from the batch confirmation: after the batch, pending cards with notes are confirmed one by one with the current rule and the complete notes shown, and closing that panel leaves them pending. The App never parses the notes and never appends waivers or precedents automatically. The first version keeps parent-child behavior strict and does not model a separate National Focus Group or tolerance quota. It also excludes Water-tight Compartment freeze exceptions and automatic post-failure redesign suggestions. Failure reasons and tree snapshots remain available for later reflection and future recommendation features.

Strengthening levels are user-authored requirements, not numeric-only bonuses. Each level is a single stricter 国策规则 override; for example, "read 5 pages" can be strengthened to "read 10 pages". A legacy trigger-condition override already stored for an older level remains as history and is not offered as a new input. Card details display the concrete current rule with optional 例外与判例 kept in a collapsed section the user opens on demand, plus the records and a single edit entry; strengthening management is entered from the card editor only (2026-11-13 lightweight layering, confirmed prototype `data-design=a`). The management page sets the requirement in force apart, lists the other levels compactly with an explicit select action, and offers the base rule for comparison on demand while editing a level. Unsaved editor input survives the round trip into strengthening management. The node sheet keeps only the title, the rule in force and its actions: no dividers, no 例外与判例 and no strengthening entry. Library summaries show the current applicable rule rather than relying on a +1/+2 badge. Internalization Progress remains separate and does not automatically set or unlock these requirements. Each card retains its base rules and supports up to five user-created strengthening levels in addition to the base. Users can create levels over time and edit each level’s 国策规则 override. Existing legacy trigger-only levels may keep their rule override empty to inherit the base rule; new levels require a rule override. The interface lists the existing levels and their concrete requirements, shows the count out of five, and offers a new-level action until five levels exist. At the limit, it explains that at most five strengthening levels can be created; existing levels remain editable. Users select strengthening levels manually; there is no automatic upgrade or failure-driven downgrade. Saving requirement edits or switching levels takes effect immediately without extinguishing the card, resetting records, or requiring reconfirmation. The user judges compliance. Preserve the requirements in effect for history, including both versions and their effective times when requirements change within a National Focus Day. Never interpret earlier activity that day as having followed a later requirement version.

Choosing Attach or Restore from the Card Library returns to the National Focus Tree main page in parent-selection mode. The user selects a top-level position or clicks an existing node on the tree canvas to make it the card's parent; a separate branch-list dialog is not used. An empty tree offers Add First National Focus Card, leading to selection of an existing Card Library card for top-level placement; new card creation remains in the Card Library. The top-level position is only a structural location and does not participate in lighting, confirmation, or failure evaluation; the card placed there follows normal node rules. Placement still requires subsequent manual lighting. When Add Child is invoked from an existing node, choosing or creating a card in the library instead places it directly under that initiating node, without another parent-selection step.

### 2.3 Tasks and deadlines

The App owns the To-do experience. A first version should keep the model deliberately small:

- a Goal grouping multiple executable Tasks; the first version uses only a two-level Goal -> Task hierarchy, without nested child Tasks, and every Task in a Goal is required;
- title;
- deadline;
- estimated duration, entered as a number with an `h` / `min` unit selector (2026-11-13); switching units preserves the duration, and leaving it empty keeps the estimate optional;
- accumulated Focus Progress from completed and failed Focus Sessions, excluding paused time;
- Task Chain Classification as Elite, Regular, or explicitly both;
- priority;
- status;
- optional short descriptions, governed by [Board and description requirements](spec-pacta-refinements-20261022.md#看板与描述).

The task list exists to feed the focus loop, not to become a general-purpose project-management suite. A Goal may contain both Elite and Regular Tasks, and all of its Tasks are required in the first version. Chain classifications organize work; the user selects a Task and duration and starts preparation or focus without an additional chain-picking step. The attempt adopts Elite or Regular mode: a single-classification Task defaults to its corresponding mode, while a both-classification Task uses the last successfully started mode (Regular on first use); direct switching remains available in the duration-settings area, as confirmed on 2026-11-13. No separate mode-selection page is needed. Goal classification may suggest defaults for new Tasks; editing it does not reclassify existing Tasks. Classification edits never migrate past records, and active attempts retain their mode and attribution. The selected Focus Session then records progress against the Task while the chain records the session node. Recon Practice is only a user-selected way to approach one of those existing Tasks; it does not create a separate task or record.

Task completion remains separate from Focus Session completion. A normal countdown ending or an exception-approved early termination records a completed Focus Session and appends one Focus Node. An exception-approved pause preserves the same Session in a resumable state without settling progress or creating a node. Continue uses the retained pause-rule revision without asking for another rule selection or confirmation. The first version has no automatic pause timeout; a known conflicting appointment or Session opens an actionable choice to continue the original flow or end/cancel it through its applicable flow before starting the new one. A bare prohibition is insufficient, and remote-state confirmation is not a start prerequisite. An offline device that cannot know another device's state may still start a Session. Different device copies are selected whole through Manual Cloud Sync below. On return, the user can continue, request rule-approved early termination, or abandon through the existing outcome flow. Paused time is excluded from focus time; the Session settles only once when it reaches a final outcome. Completed and failed Sessions both contribute their actual active focus time to Task Focus Progress. Task Focus Progress accumulates by Task, while Recent Focus Activity groups the same effective time by calendar date; both exclude pauses and unresolved conflicting contributions and apply the same reconciliation and deduplication rules. Failure still resets the applicable Focus Chain's current consecutive record and creates no Focus Node. Neither session completion nor Focus Progress automatically completes the Task. A Task becomes complete only through explicit user confirmation, and a nonempty Goal becomes complete when all of its Tasks are explicitly complete; an empty Goal is not complete.

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

#### Board content hierarchy — 2026-10-07

The Board supports choosing the next Task. Tasks and their Focus Progress remain the primary content; National Focus status, Recent Focus Activity, and today's imported Calendar Blocks form compact supporting summaries. National Focus status shows confirmed state counts and an entry to the tree, without checkpoint timestamps or display-zone explanations. Recent Focus Activity shows seven days of activity and accepted cumulative focus duration, without display-zone controls or zone names. Display Time Zone preferences and Calendar Source management are accessed from My. Checkpoint details remain on the National Focus Tree's secondary page; removing their Board display does not change settlement or daily confirmation behavior.

Use the existing Material 3 semantic theme and platform fonts. Keep the page heading at `headlineSmall` (24 logical pixels), summary titles at `titleMedium` (16, medium weight), body text at `bodyMedium` (14), and supporting details at `bodySmall` (12). Ensure normal-size text remains legible; large-text adaptation follows the scope decision in ADR 0008. Summary cards use a consistent 16-pixel inset and 12-pixel spacing. Regular widths show the task column alongside a supporting summary column; compact widths use a single scrolling column. Activity rows wrap dates and durations above the activity bar when space is insufficient. No new animation or decorative visual system is needed: task progress remains the characteristic visual emphasis.

#### Other primary destinations

The National Focus Tree is a dedicated structural canvas. Its scrolling content heading follows the Board, Focus Chain, and My styles rather than introducing a separate elevated or fixed title bar. Daily confirmation with the pending count sits near the heading; a lightweight view selector, Card Library, and More provide secondary actions. Checkpoint information and failure records open secondary pages from More.

The `Simple` view shows circular state icons and independent card names with parent-child connections. The `Detailed` view adds a short current effective Action summary in compact rounded cards, normally one line, with layout adapted to the available viewport. A labelled view menu selects the density. The canvas displays only an icon-only Fit to Screen button, with a tooltip and accessible label; there are no zoom-in/zoom-out commands, reset-to-100% command, zoom menu, percentage readout, or persistent button text. Touch uses two-finger pan/pinch while one finger scrolls the page; desktop retains mouse dragging, ordinary wheel page scrolling, and Ctrl-wheel zoom.

Tapping a node opens a content-sized action sheet with its name and short Action summary, without a prominent state badge or node numbering. The first action consistently offers Light, Confirm Today, or Extinguish according to state; blocked actions stay in that position with an explanation. Pending nodes also retain their separate active-extinguish choice. Details, strengthening management, adding a child, relocation, and moving the branch to the library follow. Details open a separate reading page with a standard back action, showing rules, the current strengthening requirement, and records without changing the canvas position. Rare name editing is available through the detail-page or library-card More menu, not in the node action sheet; renaming a tree card never requires moving it out of the tree.

Creating a card from the ordinary Card Library leaves it in the library until the user explicitly selects a tree position. Adding a child opens the same library in the initiating-node context: selecting or creating a card returns and places it directly under that node, without another parent-selection step or automatic lighting. New cards remain Extinguished; existing library cards retain their established Pending Today Confirmation or Extinguished state under the normal placement rules. See [the current canvas design](national-focus-canvas-design.md) for geometry and [the acceptance matrix](acceptance-matrix-20260914.md#国策树界面与名称补充2026-10-05) for checks.

The Focus Chain destination is the setup surface for one Focus Session. Selecting a task opens a secondary task-picker page with All, Elite, and Regular filters; Both-classified Tasks appear in both mode filters; they are not separate primary pages. Appointment Chain and immediate-start flows remain available here. Shared Precedent Rule management is available only under My. Chain menus have no management entry; focus interruption flows retain direct selection of existing shared rules.

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

The executable retention, restoration and explicit purge requirements are maintained in [Suspension retention and cloud purge](spec-focus-loop-and-core-shell.md#suspension-retention-and-cloud-purge).

### Offline lifecycle during suspension and purge

Offline knowledge, retained flows, restoration through explicit whole-snapshot choice, trustworthy purge confirmation, and fresh identity on re-registration follow the [core offline lifecycle contract](spec-focus-loop-and-core-shell.md#offline-lifecycle-during-suspension-and-purge). This supersedes the former restoration-by-reconciliation description; the accepted trade-off is recorded in [ADR 0005](adr/0005-manual-whole-data-cloud-sync.md).

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

Cloud operations are accessed from My. Android and Windows support the same offline core capabilities. Whole-snapshot replacement, preview information, exclusions, stale-preview rejection, and unfinished-flow download blocking are defined in [the core synchronization contract](spec-focus-loop-and-core-shell.md#offline-focus-and-manual-cloud-sync); read-only inspection and its presentation are defined in [the refinement specification](spec-pacta-refinements-20261022.md#云检查与元数据).

Display-day allocation and National Focus device-clock behavior are maintained in [daily allocation](spec-focus-loop-and-core-shell.md#daily-focus-allocation-and-display-preferences) and [device-clock handling](spec-focus-loop-and-core-shell.md#device-clock-handling). These are distinct: display preferences do not change the fixed National Focus checkpoint.

Recommended data groups (conceptual illustration, not a schema or migration contract; inspect actual migrations, constraints, and RLS for implementation):

- `profiles`: user identity, lifecycle status, and activity timestamps;
- `goals`: broader outcomes grouping related Tasks;
- `tasks`: App-owned tasks;
- `calendar_blocks`: normalized read-only calendar planning context;
- `focus_chains` and `focus_nodes`: chain definitions and progression;
- `national_focus_nodes`: current focus-tree definitions and state, including soft-deletion state for snapshot-referenced cards;
- `national_focus_failure_records`: append-oriented failure logs with brief reasons and complete tree snapshots;
- `focus_sessions`: append-oriented history of focus attempts, outcomes, and failure reasons;
- `sync_metadata`: device cursors, versions, or synchronization timestamps.

[ADR 0005](adr/0005-manual-whole-data-cloud-sync.md) retains the whole-snapshot decision, its rationale, accepted record-loss trade-off, and amendment history; the linked core contract carries executable synchronization requirements.

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

The App does not offer corrections to settled focus or appointment outcomes. This withdraws the earlier completed-to-failed correction feature and related historical-maximum questions. Historical reconciliation records remain readable; current cloud synchronization uses the whole-snapshot choice in ADR 0005 and does not create new cross-device reconciliation cases.

### Chain commitment actions and duration (2026-10-07)

Focus Chain puts unfinished-flow recovery and task startup before records. As confirmed on 2026-11-13, Elite and Regular share one “专注标志” and one editing entry, while retaining their own current and historical-best consecutive records and cumulative/average effective focus duration. Their record cards can sit side by side at sufficient width and stack when needed. The shared Appointment Chain retains its separate “触发信号”. A labeled edit icon opens a field with cancel/save; unset actions do not block focus. Session setup shows the shared focus marker and appointment signal, with human-operated action guidance and unchanged automatic handoff. History is available from the page heading.

Elite and Regular summaries show cumulative and average actual effective duration, including failed Sessions and excluding pauses. Flexible vertical groups and wrapping text preserve hierarchy on compact screens with normal-size text. Use existing Material 3 semantic colors and typography; do not add decorative metrics, a new navigation destination, or an independent Sacred Seat counter.

### Card editing, Board disclosure, and concise copy (2026-10-08)

Card editing, requirement versioning, and preservation rules are maintained in the [core specification](spec-focus-loop-and-core-shell.md#card-and-board-refinement-2026-10-08). The current Board disclosure and description behavior is maintained in [Board and descriptions](spec-pacta-refinements-20261022.md#看板与描述), including title-area controls and hiding all internal add actions when collapsed.

Long Goal and Task titles use at most two lines; full text remains available through editing. Use concise action labels: 熄灭, 确认, 全部确认, 上传, 下载. Confirmation and error text retain necessary consequences and recovery steps; downloading still warns that cloud data replaces local data.

### Board, focus navigation, preferences, and cloud inspection — 2026-10-22

本轮已确认行为统一维护在[改进专题规格](spec-pacta-refinements-20261022.md)：

- 描述、折叠与分类：[看板与描述](spec-pacta-refinements-20261022.md#看板与描述)及 User Stories 1–20。
- 选择、返回、恢复及模式记忆：[专注导航与模式](spec-pacta-refinements-20261022.md#专注导航与模式)及 User Stories 21–34。
- 本机用户视图保存：[设备视图偏好](spec-pacta-refinements-20261022.md#设备视图偏好)及 User Stories 35–37。
- 同步卡片、只读检查与来源型号：[云检查与元数据](spec-pacta-refinements-20261022.md#云检查与元数据)及 User Stories 38–61；整份替换决策理由仍见 ADR 0005。

这些要求仅在明确声明的范围内替代旧界面描述；[验收矩阵 R22 场景](acceptance-matrix-20260914.md#2026-10-22-已确认改进验收)保留验收依据。[需求访谈](requirements-refinement-20261022.md)保留确认来源及原型依据。实施状态读取对应 Issue；有日期的记录提供历史证据，不作为本轮重新验收结果。

### Blue-white Material theme — 2026-11-13

The shared Material 3 theme follows the requested Google-inspired blue-white direction: blue primary actions and selected navigation, white and pale blue surfaces, rounded cards and sheets, and restrained elevation. Lit National Focus nodes use the shared green success palette; pending nodes use warm yellow, with existing status icons retained. Light and dark foreground/container roles are paired for readability. Keep the bundled MiSans typography and existing navigation and behavior. ThemeData and its status-color extension own these tokens, rather than per-page color constants.
