# Chain App Context

Chain is an open-source, cross-platform self-regulation app. It combines short, executable focus commitments with a longer-term progression model so that users can turn deadlines and unfinished work into a concrete next action.

## Core concepts

**User**:
An individual person whose tasks, focus history, chains, and focus-tree progress are private to that person.
_Avoid_: Account, tenant, organization

**Focus Session**:
A bounded period in which the user commits to carrying out one clearly defined focus task under an agreed focus rule. It runs as a countdown, and the normal completion path is to remain in the session until the countdown ends. Pausing or ending early is not allowed by default. When an interruption occurs, the user chooses either to abandon the current progress, which records failure or abandonment and requires a brief Failure Reason, or to preserve the progress by creating or selecting a Precedent Rule. A Precedent Rule-approved pause or early termination is recorded as completed, with the exception basis retained separately. Only completed sessions contribute their actual elapsed focus time to Focus Progress; elapsed time from failed or abandoned sessions remains history but contributes no Task progress. Completion does not complete the linked Task. Its outcome is completed, failed, or abandoned. Failure or abandonment resets only the selected Focus Chain's current maximum consecutive record to zero; the session and its recorded reason remain in history. Moving the App to the background does not itself abandon the session. Abandonment may be grouped with failure when filtering, but remains a distinct recorded outcome.
_Avoid_: Timer, pomodoro

**Focus Session Outcome**:
The recorded result of a Focus Session: completed, failed, or abandoned. Abandoned sessions remain distinct in history but belong to the same filter group as failed sessions.
_Avoid_: Success/failure boolean

**Focus Progress**:
The accumulated actual focus time contributed by completed Focus Sessions toward a Task's estimated duration. Focus Progress is separate from Task completion and from a Focus Chain's consecutive record.
_Avoid_: Task completion, time quota

**Recent Focus Activity**:
A read-only, per-day summary of actual focus minutes recorded in recent Focus Session history, including effort from completed, failed, and abandoned sessions. It is a history projection and does not change Focus Progress, Focus Chain records, Task completion, or National Focus records.
_Avoid_: Investment data, Focus Progress, time quota

**Focus Chain**:
An ordered accumulation of completed focus sessions for a specific area of work or life. In the first version, each area has at most one Elite Focus Chain and one Regular Focus Chain. A Focus Chain is selected in one of two modes, Elite or Regular, according to the user's current state; that mode also classifies which Tasks are appropriate for the chain. Each chain maintains an independent current maximum consecutive record. Any failed session, including an active abandonment, resets only the selected chain's current record to zero while preserving its history.
_Avoid_: Streak, habit counter

**Focus Chain Mode**:
The mode of a Focus Chain selected for the user's current state: Elite Focus Chain (精锐链) or Regular Focus Chain (普通链).
_Avoid_: Difficulty level, streak tier

**Focus Practice Type**:
A state- and time-appropriate way to begin a Focus Session. The Regular Short Chain (普通短链) is a short entry into the Regular Focus Chain and shares its progress. A Recon Practice (侦查练习) is a non-persisted method the user may apply to a concrete Task within a Goal to test whether they can enter a working state; it is not a Task, Focus Chain, Focus Session, or other App entity.
_Avoid_: Timer preset, difficulty tier

**Focus Marker**:
A distinctive physical or digital marker that defines the selected Focus Chain's active context. The App does not detect whether the user has activated it; the user performs the marker and manually starts or confirms the corresponding App flow.
_Avoid_: Trigger Signal, notification

**Trigger Signal**:
A simple user-performed action that belongs to one of two flows: an Appointment Signal starts an Appointment Chain, while an Immediate-start Signal directly signals readiness to begin a Focus Chain. Trigger Signals are part of the user's real-world protocol; the App records the manually selected flow rather than detecting the signal itself.
_Avoid_: Push notification, biometric signal

**Appointment Chain**:
A parallel delayed-start chain with a fixed 15-minute commitment window before entering a Focus Chain. After the Appointment Signal, the user must manually perform the Immediate-start Signal and open the Focus Chain within that window; the App does not detect either signal or start the Focus Chain automatically. If the user does not enter, the Appointment Chain is failed; if the user actively abandons it, it is abandoned. Either outcome resets only the Appointment Chain's own current record. Neither case creates a Focus Session or resets the selected Focus Chain. Its expiry, exception, and handoff rules are separate from the Focus Session countdown.
_Avoid_: Calendar event, reminder

**Precedent Rule**:
The exception rule for a Focus Chain or Appointment Chain. When an interruption would otherwise discard progress, the user may create a new Precedent Rule or select an existing one eligible for the same Focus Chain and Focus Rule to preserve the progress and complete the session by exception. Each later adjustment creates a new rule revision rather than changing an old revision; the new revision affects future sessions, while each session retains the revision used at completion. The rule becomes part of the relevant chain's future boundary. If the user does not create or select a rule, the current progress is discarded and the session is recorded as failed or abandoned.
_Avoid_: One-time exception, ad hoc override

**Focus Node**:
One system-generated position in a focus chain appended when a Focus Session completes normally or through a Precedent Rule-approved exception. It records the completed focus unit independently of whether the linked Task or Goal is complete; it is not created merely because Focus Progress has reached an estimated duration. Users may add notes to a node but cannot create one manually.
_Avoid_: Check-in, badge

**National Focus Tree**:
A progression model in which small, maintainable rules and actions unlock or support broader improvements in the user's daily state. The tree reflects the user's current state and can inform which Focus Chain is appropriate, but the user still explicitly selects the chain; the App does not automatically switch or block a choice. The tree is not attached to a Goal or Task. The first version uses manually created National Focus Cards, presented in a Card Library and placed into a tree as National Focus Nodes, with explicit user lighting, daily confirmation records, and failure reasons. After each 04:00 boundary, the user must complete one National Focus Daily Confirmation before the next 04:00; it confirms every node eligible from the previous National Focus Day in one action. Nodes newly activated today require individual manual confirmation before joining a later batch. The user may exclude a node from the batch when it is no longer valid compared with yesterday; exclusion clears that node's current maximum consecutive record and extinguishes its child cards without creating separate child failure logs. The App may recommend adding at most one new card per day, but this is advisory rather than a hard limit. Missing a single daily confirmation window invalidates the current National Focus state: the failure snapshot is saved first, all current maximum consecutive records and the batch eligibility set are cleared, historical maximum records are retained, and the next cycle starts from zero. The system records the invalidation reason as “missed daily confirmation”; the user may edit that reason later. A node is never individually failed automatically by a deadline or inactivity. When a node fails, the failed node remains in the tree with its current maximum consecutive record cleared, its historical maximum record retained, and its child cards remain in the tree marked as extinguished. Its parent is not affected. Only the failed node receives a Failure Reason; extinguished child cards do not create separate failure logs. The user may then edit the current tree in place, soft-delete cards, or create new cards and manually attach them to any branch; the App does not automatically split or generate replacement cards. New cards are new nodes and do not inherit the failed node's current record. Each National Focus Card also has a persistent Internalization Progress value in addition to its current and historical maximum consecutive records. Complex inheritance is deferred.
_Avoid_: Skill tree, goal hierarchy

The first version does not model a separate National Focus Group or tolerance quota: parent-child status remains strict. It also does not provide a Water-tight Compartment freeze exception, policy strengthening levels, or automatic post-failure redesign suggestions.

**National Focus Card**:
A user-authored rule card with lightweight structure: a primary Trigger Condition and Action, plus optional Scope and Exception Notes. The App stores and presents these fields but does not automatically evaluate whether the user performed the real-world action; the user still lights and confirms nodes manually.
_Avoid_: Executable rule, automatic evaluator

Internalization Progress is retained separately from current and historical maximum consecutive records. It is derived from the card's cumulative successful National Focus Day count rather than entered by the user.

Node lighting, extinguishing, and moving a card to the Card Library are user actions. The App does not reset a node's current maximum consecutive record immediately after an extinguish or removal; it evaluates the state at the 04:00 National Focus Day boundary and only then records failure and clears the current maximum when the node is not lit.

**National Focus Card Library**:
The user's collection of National Focus Cards that are not currently placed in the tree. Explicitly moving a card from the tree into the library starts a reversible removal state and does not immediately clear its current maximum consecutive record. If the card is restored and lit before the daily boundary, its current, historical, and Internalization Progress records are preserved; otherwise the boundary evaluation records failure and then clears the current maximum consecutive record while retaining the historical maximum and Internalization Progress. Moving a card directly between tree branches preserves its current and historical records. A failed or extinguished card remains in the tree and is not moved to the library automatically. A restored soft-deleted card returns to the library rather than to any current tree position; the user may later drag it into any branch and establish a new parent relationship.
_Avoid_: Archive-only storage, task list

**National Focus Node**:
A Card Library card placed into the National Focus Tree under a chosen parent branch. A card can occupy only one tree position at a time. It represents one concrete state rule or action, has its own current maximum consecutive record, historical maximum record, and Internalization Progress, and may have child cards. The user manually lights or extinguishes a node. Extinguishing changes the node's visible state but does not immediately clear its current maximum consecutive record; if the node is lit again before the daily boundary, the record is preserved. At the daily boundary, a node that is not lit is recorded as failed, its current maximum consecutive record is cleared, and its historical maximum record and Internalization Progress are retained. Extinguishing a parent also extinguishes its child cards without removing any of them from the tree; extinguishing alone does not create a Failure Reason or failure log. A manually created replacement or follow-up card is a new node rather than a continuation of the failed node. Moving a card directly between tree branches preserves its current and historical records. Explicitly moving a card from the tree into the Card Library starts the same reversible removal state; it has no immediate reset, but if it remains removed at the daily boundary it is recorded as failed and its current maximum consecutive record is then cleared. If the card is referenced by any National Focus Failure Record, it cannot be permanently deleted and can only be restored to the Card Library. A card not referenced by any failure snapshot may be permanently deleted.
_Avoid_: Focus Node, Task, badge

A newly placed card starts extinguished and must be manually lit. A failed node relit on a later day starts with a current maximum consecutive record of zero while retaining its historical maximum record and Internalization Progress. Relighting a parent does not relight its extinguished children; each child requires separate manual lighting.

**Internalization Progress**:
A persistent card-level indication of how familiar a National Focus rule has become through successful confirmations. Let `S` be the card's cumulative number of successful National Focus Days. At each successful National Focus Daily Confirmation for that card, `S` increases by one. The derived score is `I = 100 * (1 - exp(-S / 60))`, where `60` is the initial global calibration constant in successful days. The score approaches 100 asymptotically, so three successful days cannot reach the highest familiarity range. `S` is retained when the card is failed, extinguished, moved to the Card Library, or restored; `I` is derived from `S`. A newly created card starts with `S = 0`. They are separate from the current and historical maximum consecutive records, are not a completion state, and cannot be manually edited.
_Avoid_: Current streak, Task progress, completion percentage

The user interface may derive qualitative labels from the continuous Internalization Progress score, but those labels are presentation only and do not define the number of progress levels.

Internalization Progress increases only after the user completes a successful National Focus Daily Confirmation for the previous National Focus Day; failure or extinguishing preserves the accumulated value but does not increase it.

Internalization Progress is not a policy strengthening level. The first version has no `+1`/`+2` strengthening or rollback-to-base mechanic.

**National Focus Daily Confirmation**:
A user action performed once after the 04:00 boundary and before the next 04:00 boundary. It confirms, in one batch, the nodes that were eligible from the previous National Focus Day, increments their current maximum consecutive records and Internalization Progress, and allows the user to exclude nodes that are no longer valid. Newly activated nodes require individual confirmation before they can join a later batch. If the user does not complete this action within the window, the current National Focus state is invalidated at the next 04:00 boundary.
_Avoid_: Automatic daily confirmation, per-node daily confirmation

**National Focus Day**:
A daily evaluation period from 04:00 until the next day's 04:00. A node's light or extinguished state is judged at the boundary: a node that is still lit becomes eligible for the next National Focus Daily Confirmation, while a node that is not lit is recorded as failed. Extinguishing or moving a card to the Card Library before the boundary is reversible and does not immediately clear its current maximum consecutive record.
_Avoid_: Calendar day, deadline

When a node reaches the 04:00 boundary without being lit, the system pre-fills its Failure Reason as “04:00 时未保持点亮”; the user may edit it later. A parent may mark children extinguished immediately, but those children are not formally failed until the boundary.

An extinguished child cannot be lit independently while its parent remains extinguished; the parent must be lit first.

**National Focus Failure Record**:
An immutable historical record created when the system determines that a National Focus Tree node was not lit at the boundary or when one missed daily confirmation window invalidates the current tree. It contains the required brief Failure Reason when a specific node is failed, or the system-generated “missed daily confirmation” reason for tree-wide invalidation, plus a complete snapshot of the National Focus Tree's structure and state at that moment. Later in-place tree restructuring or card removal cannot change what the user sees in the failure log.
_Avoid_: Current tree state, task failure

**Focus Rule**:
The explicit condition that defines what a focus session requires and what counts as a valid completion or failure.
_Avoid_: Motivation, promise

**Failure Reason**:
The user's required short free-text explanation for a failed or abandoned Focus Session or a failed National Focus Tree node. The initial entry may be only a few words and can be edited later for reflection. Structured categories or tags may be added later for aggregate statistics and pattern analysis, without replacing the original text. A completed session preserved by a Precedent Rule uses the rule as its exception basis instead of a Failure Reason.
_Avoid_: Excuse, diagnostic

**Goal**:
A broader intended outcome that groups multiple executable Tasks. In the first version, the hierarchy is limited to Goal -> Task: a Task does not contain nested child Tasks, and every Task in a Goal is required. A Goal may contain Tasks classified for different Focus Chain modes, and its progress is composed from those Tasks; the Goal is complete only when all of its Tasks are explicitly complete.
_Avoid_: Project, Focus Chain

**Task Chain Classification**:
The assignment of a Task to the Elite Focus Chain, the Regular Focus Chain, or explicitly both, so it can be selected in a state-appropriate task list. This classification does not determine the duration of a Focus Session.
_Avoid_: Duration tier, priority

**Focus Chain Selection**:
The user's explicit choice of which Focus Chain to enter for the current state. The App presents Tasks eligible for that chain and may suggest the Regular Focus Chain when the selected Elite Focus Chain has no available Tasks, but it does not switch chains automatically.
_Avoid_: Automatic fallback policy, timer mode

**Task**:
An executable subtask within a Goal, with enough information to connect it to a deadline or a Focus Session. In the first version, a Task has no nested child Tasks. A Task has a Task Chain Classification and may have an estimated duration and accumulated Focus Progress; Focus Progress is only evidence of work performed, and completing a Focus Session does not by itself complete the Task or its Goal. Task completion is recorded separately by explicit user confirmation.
_Avoid_: To-do item, ticket

**Calendar Block**:
A time interval imported from a device calendar and treated as an external scheduling constraint.
_Avoid_: Appointment, event

**Deadline**:
The point in time by which a task or outcome becomes materially late or loses value.
_Avoid_: Due date, reminder

**Active User**:
A user currently allowed to access the app and their data.
_Avoid_: Enabled account

**Suspended User**:
A user whose access is disabled while their data is retained for a possible recovery period.
_Avoid_: Deleted user, banned user

**Purge**:
The deliberate, irreversible removal of a user's app data and authentication account after suspension or explicit deletion.
_Avoid_: Deactivation, archive

## Boundaries

- The app owns tasks, focus sessions, chains, and focus-tree progress.
- Device calendars are external constraints and are read-only in the initial design.
- The app does not model organizations, teams, or shared workspaces.
- Each user's app data remains private and isolated from other users.
