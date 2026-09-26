# Pacta Context

Pacta is an open-source, cross-platform self-regulation app. It combines short, executable focus commitments with a longer-term progression model so that users can turn deadlines and unfinished work into a concrete next action.

## Core concepts

**User**:
An individual person whose tasks, focus history, chains, and focus-tree progress are private to that person.
_Avoid_: Account, tenant, organization

**Focus Session (专注会话)**:
A bounded countdown devoted to one Task, whose completed or failed outcome contributes actual active focus time independently of Task completion. A rule-approved pause is an unfinished state of that same Session; normal countdown completion and rule-approved early completion remain distinguishable.
_Avoid_: Timer, pomodoro

**Focus Session Outcome (专注结果)**:
The settled result of a Focus Session: completed or failed, with completed records distinguishing normal countdown completion from exception-approved early termination. “Abandon this Focus Session” is a user action that settles failure after confirmation, not an independent outcome or a temporary first-version distinction.
_Avoid_: Abandoned outcome, success/failure boolean

**Focus Session Reconciliation (专注记录核对)**:
The user's review of conflicting multi-device focus records, separating configuration selection, outcome confirmation, and effective-time deduplication. Original sources remain available, disputed contributions and affected records are marked pending review, and ongoing work remains usable.
_Avoid_: Automatic outcome overwrite

**Duplicate Focus Record (重复专注记录)**:
A retained source record marked as a duplicate during Focus Session Reconciliation rather than a separate accepted focus attempt. It contributes no additional official progress or Focus Node and is not a failed Session that resets a chain.
_Avoid_: Failed Session, deleted history

**Task Estimated Duration (任务预计时长)**:
The user's estimate of the focus time needed to complete a Task, used only as a progress reference rather than a time limit or completion criterion. A Task may be explicitly completed before this estimate is reached, or remain incomplete after accumulated Focus Progress exceeds it.
_Avoid_: Time quota, deadline, required completion threshold

**Focus Progress (任务专注进度)**:
The accumulated actual active focus time contributed to a Task by accepted completed and failed Focus Sessions, excluding paused time and using the same effective-time basis as Recent Focus Activity. It excludes unresolved conflicting contributions and duplicate records, may exceed the Task Estimated Duration without being capped, and is separate from explicit Task completion and from a Focus Chain's consecutive record.
_Avoid_: Task completion, time quota

**Recent Focus Activity (近期专注活动)**:
A read-only summary using the same effective-time basis as Focus Progress: actual active time from completed and failed Sessions, excluding pauses, unresolved conflicting contributions, and duplicate records, grouped by calendar day in each device's display time zone rather than by Task. Redistributing daily totals when the display zone changes does not change total duration, occurrence order, Focus Progress, or chain records.
_Avoid_: Investment data, Focus Progress, time quota

**Focus Chain (专注链)**:
One of two fixed focus records, Elite or Regular, each with its own consecutive record and failure scope shared across Tasks. Together with the single Appointment Chain, these form the user's three independent records; there are no user-created independent chains.
_Avoid_: Streak, habit counter, task dependency chain, a single Focus Session

**Elite Focus Chain (精锐链)**:
One of the two fixed Focus Chains, with a consecutive record independent of the Regular Focus Chain and Appointment Chain. Its mode does not prescribe a fixed session duration or an automatically assessed difficulty level.
_Avoid_: 精英链, fixed-duration chain, automatic difficulty level

**Regular Focus Chain (普通链)**:
One of the two fixed Focus Chains, with a consecutive record independent of the Elite Focus Chain and Appointment Chain. The user chooses the duration of each Focus Session.
_Avoid_: Fixed-duration chain

**Recon Practice (侦查练习)**:
A method the user may apply to a concrete Task within a Goal to test whether they can enter a working state. It is an approach to existing work, with no independent App record.
_Avoid_: Task, Focus Chain, Focus Session

**Trigger Signal (启动信号)**:
A user-chosen action carrying an appointment or focus commitment, such as putting on specific headphones or snapping three times; it is the product adaptation of the theoretical Sacred Seat (神圣座位). The Appointment Signal initiates preparation and the Immediate-start Signal initiates focus; the App relies on the user to perform the action.
_Avoid_: Push notification, biometric signal

**Appointment Chain (预约链)**:
The single delayed-start record shared across Elite and Regular preparation, with its own consecutive record and history; each attempt prepares a selected Task and Focus Session duration through a fixed 15-minute countdown. Normal or early entry into focus records one appointment success, while cancellation records failure and clears only the current Appointment Chain record.
_Avoid_: Calendar event, reminder, Focus Chain record

**下必为例 (Precedent Rule)**:
A user-written permission for otherwise disallowed behavior during focus, shared by Elite and Regular Focus Chains: the user judges its meaning and applicability and chooses whether to permit that behavior in future or acknowledge failure. Users may edit or delete the text to correct it; confirmed operations retain their original rule basis, and this permission applies only to focus.
_Avoid_: One-time exception, automatic compliance evaluator

**Focus Node (专注节点)**:
One system-generated position in a focus chain appended when a Focus Session completes normally or through Precedent Rule-approved early termination. It records the completed focus unit independently of whether the linked Task or Goal is complete; it is not created merely because Focus Progress has reached an estimated duration. Users may add notes to a node but cannot create one manually.
_Avoid_: Check-in, badge

**National Focus Tree (国策树)**:
A user-maintained progression tree of National Focus Cards, independent of Goals and Tasks, reflecting the user's current state. Its nodes distinguish Lit, Pending Today Confirmation, and Extinguished; detailed behavior is defined in the core specification.
_Avoid_: Skill tree, goal hierarchy

**National Focus Card (国策卡)**:
A user-authored rule with a primary Trigger Condition and Action, optional Scope and Exception Notes, and persistent Internalization Progress. The user evaluates its real-world validity manually.
_Avoid_: Executable rule, automatic evaluator

**National Focus Card Library (国策卡片库)**:
The user's collection of independent cards not currently placed in the tree, including restored soft-deleted cards. Cards moved here from a subtree no longer retain their parent-child relationships and are placed back individually.
_Avoid_: Archive-only storage, task list

**National Focus Node (国策节点)**:
A National Focus Card occupying one tree position, optionally with child cards, and carrying current/historical consecutive records and Internalization Progress. Its state is Lit (点亮), Pending Today Confirmation (待今日确认; visually unlit without failure), or Extinguished (真正熄灭; requires separate manual lighting).
_Avoid_: Focus Node, Task, badge

**Internalization Progress (内化进度)**:
A persistent card-level indication of familiarity derived from cumulative successful National Focus Days, separate from current/historical consecutive records and Strengthening Levels. It survives failure and is not manually editable; successful days are counted at National Focus Checkpoints rather than per lighting action.
_Avoid_: Current streak, Task progress, completion percentage

**National Focus Strengthening Level (国策强化等级)**:
A user-defined stricter set of requirements for a National Focus Card, expressed through concrete Trigger Condition and/or Action content; for example, changing a trigger from before 02:00 to before 01:00. A card retains its base requirements and supports up to five user-created strengthening levels, each with its own concrete requirements; the base is not counted toward this limit. Levels are defined independently of Internalization Progress and are not automatically earned upgrades.
_Avoid_: Internalization Progress, automatic upgrade, numeric-only bonus

**National Focus Requirement Version (国策要求版本)**:
An immutable snapshot of a National Focus Card's effective Trigger Condition, Action, Scope, and Exception Notes, tied to the period when that combination governed the card. Selecting another Strengthening Level or editing the active level starts a new version without changing prior versions or National Focus records.
_Avoid_: Card revision, automatic evaluation

**National Focus Daily Confirmation (国策每日确认)**:
The user's acknowledgment that a node remains valid today (确认今日继续有效), performed by individually lighting pending nodes or by One-click Confirm Today. The batch lights only Pending Today Confirmation nodes and leaves Lit and Extinguished nodes unchanged.
_Avoid_: Yesterday-success acknowledgment, automatic daily confirmation

**National Focus Checkpoint (国策检查点)**:
The fixed daily settlement boundary at 04:00 Beijing time (UTC+08:00), the same instant for every user and device. Changing the user's time zone changes its local-time display, never the checkpoint itself.
_Avoid_: Local 04:00, user-configurable settlement time

**National Focus Day (国策日)**:
The period from one National Focus Checkpoint to the next. At the closing checkpoint, nodes still awaiting that day's confirmation formally fail and become Extinguished; surviving Lit nodes then become Pending Today Confirmation for the new day without failure.
_Avoid_: Local calendar day, deadline

**National Focus Failure Record (国策失败记录)**:
A historical National Focus failure event identified by an independent failure source, with a complete immutable tree snapshot and optional user explanation. Events in one daily-confirmation failure batch share one explanation entry without becoming a single failure event.
_Avoid_: Current tree state, task failure

**Failure Reason**:
A short explanation of a failed attempt or National Focus event: required for focus abandonment and appointment cancellation, optional for active National Focus extinguishing. Missed National Focus confirmation has a system reason, and users may later add or edit reflective explanations without changing settled outcomes.
_Avoid_: Excuse, diagnostic

**Goal (目标)**:
A broader intended outcome that groups executable Tasks in the first-version Goal -> Task hierarchy, with no nested Tasks; its progress includes differently classified Tasks, and a nonempty Goal completes only when every Task is explicitly complete (an empty Goal is incomplete). A deleted Goal and its Tasks cannot be restored; existing Focus Sessions and Appointments remain valid, with their original Task identities retained and marked as deleted in history.
_Avoid_: Project, Focus Chain

**Task Chain Classification (任务链分类)**:
An organizational and filtering classification of a Task as Elite, Regular, or both, independent of the mode used for a particular attempt. A Goal's classification may suggest a new Task's default without requiring its Tasks to share that classification.
_Avoid_: Fixed record ownership, success criterion

**Focus Chain Mode (本次专注模式)**:
The Elite or Regular mode adopted for the current attempt, determining its focus record attribution; preparation always belongs to the single independent Appointment Chain regardless of mode. It is carried from the originating mode list or shown and switchable alongside duration settings, without a separate chain-selection or pairing page.
_Avoid_: Task classification, start-time chain pairing

**Task (任务)**:
An executable subtask belonging to one Goal, without cross-Goal movement or nested child Tasks, with a Task Chain Classification and enough information to connect it to a deadline or Focus Session. It may have an estimated duration and Focus Progress; progress records work but does not complete the Task, which requires explicit confirmation. A deleted Task cannot be restored or chosen for a new Focus Session or Appointment, and its original name and existing history remain available marked as deleted.
_Avoid_: To-do item, ticket

**Calendar Block (日历块)**:
An imported calendar event used as read-only planning context: timed busy intervals indicate occupancy, while all-day events retain their original dates as reminders. Calendar occupancy never restricts starting focus.
_Avoid_: Appointment, event

**Deadline (截止时间)**:
The point in time by which a task or outcome becomes materially late or loses value.
_Avoid_: Due date, reminder

**Registration Eligibility (注册资格)**:
An administrator-issued permission for a specified email address to register once, without App-operated ownership verification. Unused eligibility remains valid until revoked; successful registration consumes it. Email is the sole registration and password-login identifier.
_Avoid_: Email invitation, verification code, proof of identity

**Active User (正常用户)**:
A user currently allowed to access the app and their data.
_Avoid_: Enabled account

**Suspended User (停用用户)**:
A user whose new business operations and uploads are disabled once suspension is known, while local data and existing flow state are retained for recovery. Suspension itself is not a failed focus or appointment outcome.
_Avoid_: Deleted user, banned user

**Purge (清除)**:
The administrator's deliberate, irreversible removal of an eligible user's cloud business data and authentication identity. Cloud purge does not itself establish deletion of data on offline devices.
_Avoid_: Deactivation, archive

## Boundaries

- The app owns tasks, focus sessions, chains, and focus-tree progress.
- Device calendars provide read-only planning context.
- The app does not model organizations, teams, or shared workspaces.
- Each user's app data remains private and isolated from other users.
