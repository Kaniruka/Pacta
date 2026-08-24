# Focus Loop and Core Application Shell

## Problem Statement

The App needs to turn the user's current state and available work into one clear next action while preserving the distinction between Tasks, Focus Chains, Focus Sessions, and the National Focus Tree. The first screen must show what should be done now, but the execution flow must not collapse into a generic task manager, an automatic habit tracker, or a timer with misleading completion controls.

The App also needs to preserve the user's deliberate protocols: Elite and Regular are task classifications and user-selected Focus Chain modes; Appointment Signals and Immediate-start Signals are human-performed signals; National Focus is manually maintained at a 04:00 boundary; and interruptions require an explicit Precedent Rule or a recorded failure/abandonment reason.

## Solution

Build a mobile-first four-destination application shell:

1. **Board** is the first landing surface. It shows the App-owned Task list first, then combines Focus Progress, current National Focus status, and Recent Focus Activity.
2. **National Focus Tree** is a structural tree canvas with daily confirmation, Card Library, and attach-card actions.
3. **Focus Chain** is the setup surface for selecting a Task, choosing the applicable chain classification through a secondary task-picker, selecting a user-chosen countdown, and starting an Appointment Chain or Focus Session.
4. **My** contains personal records and profile/global settings.

Starting a Focus Session moves the user to a dedicated countdown surface. A Session has no manual completion action: normal completion occurs only when the countdown reaches zero. Pause, continue, early termination, and abandonment enter the applicable Precedent Rule or Failure Reason flow and always offer a return-to-session path. Background execution continues through a persistent notification.

## User Stories

### Application shell and Board

1. As a user, I want the App to open on a Board, so that I immediately see what I should do next.
2. As a user, I want the primary navigation to contain Board, National Focus Tree, Focus Chain, and My, so that each major responsibility has one clear home.
3. As a user, I want today's executable Tasks shown before statistics, so that progress data does not hide the next action.
4. As a user, I want a Goal's Tasks shown with their estimated duration and Focus Chain classification, so that I can choose a feasible action.
5. As a user, I want to enter Focus Chain setup from a Task on the Board, so that I do not have to reconstruct the task context.
6. As a user, I want the Board to show accumulated Focus Progress, National Focus status, and Recent Focus Activity together, so that I can understand today's state without opening a separate data dashboard.
7. As a user, I want the Board to show a National Focus confirmation reminder, so that I remember the 04:00 confirmation window.
8. As a user, I want to open the National Focus Tree from its Board summary, so that I can inspect the underlying branches when the summary is insufficient.
9. As a user, I want the Board to remain a focused execution surface, so that it does not become a general project-management suite.

### Task selection and Focus Chain setup

10. As a user, I want to enter Focus Chain setup without seeing separate Elite and Regular primary pages, so that chain selection remains one focused flow.
11. As a user, I want a secondary task-picker to filter Tasks by Elite, Regular, Both, or all eligible classifications, so that I can choose a Task appropriate to my current state.
12. As a user, I want the selected Task's Goal, estimated duration, and accumulated Focus Progress shown before starting, so that I know what the Session contributes to.
13. As a user, I want to explicitly select the Focus Chain mode, so that the App never silently changes my selected chain.
14. As a user, I want the App to suggest Regular when the selected Elite chain has no eligible Tasks, so that I can recover a workable next action without losing control of the choice.
15. As a user, I want to choose the countdown duration myself, so that Elite or Regular classification does not secretly determine Session length.
16. As a user, I want to see the Appointment Signal and Immediate-start Signal as human-operated protocol instructions, so that I understand the App does not detect physical signals.
17. As a user, I want to start a fixed 15-minute Appointment Chain, so that I can delay the decision to enter focused work.
18. As a user, I want to start a Focus Session immediately when I am ready, so that confidence can bypass the Appointment Chain.
19. As a user, I want to open Precedent Rule management from a Focus Chain-specific expansion menu, so that interruption rules are available where they matter without becoming global settings.

### Focus Session

20. As a user, I want starting a Session to open a dedicated countdown page, so that execution is not mixed with task selection or the National Focus Tree.
21. As a user, I want the countdown to be the visible boundary for the current commitment, so that I can see elapsed and remaining time.
22. As a user, I want the Session page to provide only Pause, Early Termination, Abandon, and the current Continue action, so that there is no misleading manual completion button.
23. As a user, I want a Session to be recorded as normally completed only when its countdown reaches zero, so that ending early cannot be mistaken for normal completion.
24. As a user, I want backgrounding the App to leave the Session active, so that a phone operation does not cause an automatic failure.
25. As a user, I want a persistent notification to keep the countdown available while the App is in the background, so that I can return to the Session without losing state.
26. As a user, I want Pause to require selecting or creating an eligible Precedent Rule, or returning to the countdown, so that pausing does not become a default escape hatch.
27. As a user, I want Continue after an exception-controlled pause to require the same explicit rule flow or a return to the current countdown, so that the exception remains deliberate.
28. As a user, I want Early Termination to require selecting or creating an eligible Precedent Rule, or returning to the countdown, so that early exit is clearly exceptional.
29. As a user, I want Abandon to offer either a Precedent Rule path, a short Failure Reason path, or a return to the countdown, so that preserving progress and discarding progress are distinguishable choices.
30. As a user, I want a short Failure Reason to be required when I discard an interrupted Session, so that I can reflect on what happened.
31. As a user, I want to edit a Failure Reason later, so that a few words entered under pressure can become a useful reflection.
32. As a user, I want an exception-approved early termination or pause to retain the applicable rule revision, so that the history explains why the Session was completed by exception.
33. As a user, I want a normally completed or exception-approved Session to append one system-generated Focus Node, so that completed focus units are visible in chain history.
34. As a user, I want elapsed time from a failed or abandoned Session retained in history but excluded from Task Focus Progress, so that history and progress remain distinct.
35. As a user, I want a completed Focus Session to add actual elapsed time to Task Focus Progress without completing the Task, so that Task completion remains an explicit user action.
36. As a user, I want a failed or abandoned Session to reset only the selected Focus Chain's current maximum consecutive record, so that other chains and historical records remain intact.
37. As a user, I want abandoned Sessions to remain distinct in history while being groupable with failures in aggregate views, so that the record preserves what actually happened.

### National Focus Tree and Card Library

38. As a user, I want National Focus Tree to be a dedicated tree canvas, so that parent, branch, and child relationships remain visible.
39. As a user, I want the tree's Simple view to show node icons and structure only, so that I can scan the whole tree.
40. As a user, I want the tree's Detailed view to show card text, dates, records, internalization, and visible state, so that I can inspect a node without losing its position in the tree.
41. As a user, I want the tree's relevant header actions to open daily confirmation, Card Library, and attach-from-library flow, so that actions remain local to the tree context.
42. As a user, I want the tree's add action to place an existing Card Library card into a chosen branch, so that adding a node does not silently create a new card.
43. As a user, I want to create a new National Focus Card from the Card Library's secondary page, so that card creation and tree placement remain separate operations.
44. As a user, I want a Card Library card to contain a primary Trigger Condition and Action with optional Scope and Exception Notes, so that I can define a small concrete rule.
45. As a user, I want the App to store and display card fields without evaluating whether I performed the real-world action, so that manual lighting remains authoritative.
46. As a user, I want to move a card between tree branches without losing its current or historical records, so that restructuring reflects real progress.
47. As a user, I want a card moved to the Card Library to enter a reversible removal state, so that an accidental move can be restored before the boundary.
48. As a user, I want a snapshot-referenced card to be soft-deletable and restorable to the Card Library but not permanently deletable, so that historical failure snapshots remain complete.
49. As a user, I want a card with no failure-snapshot reference to be permanently deletable, so that the Card Library remains manageable.
50. As a user, I want a newly placed card to start extinguished and require manual lighting, so that placement does not count as successful maintenance.
51. As a user, I want extinguishing or removing a node not to clear its current maximum immediately, so that I can correct an accidental action before 04:00.
52. As a user, I want a parent extinguish to mark its children extinguished without deleting them, so that the tree still explains the route and its consequences.
53. As a user, I want a node that remains unlit at the 04:00 boundary to create a failure record and clear only its current maximum, so that failure evaluation follows the agreed time boundary.
54. As a user, I want the failed node to remain visible with historical maximum and Internalization Progress preserved, so that failure does not erase the route.
55. As a user, I want extinguished children to remain in the tree without separate failure reasons, so that the parent failure is not duplicated into misleading child failures.
56. As a user, I want a National Focus failure record to contain the complete tree snapshot and failure reason, so that later restructuring cannot rewrite history.
57. As a user, I want daily confirmation to occur once after 04:00 and before the next 04:00, so that maintaining the tree requires a deliberate daily habit.
58. As a user, I want yesterday's eligible nodes presented in one batch with the option to exclude individual nodes, so that I do not need to confirm every node separately while retaining control.
59. As a user, I want newly activated nodes to require individual confirmation before joining a later batch, so that new behavior is explicitly acknowledged.
60. As a user, I want missing a daily confirmation window to snapshot and invalidate the current National Focus state, so that the App does not silently auto-confirm days I did not maintain.
61. As a user, I want historical maximum records and Internalization Progress retained after National Focus failure, so that failure remains useful for reflection.
62. As a user, I want Internalization Progress derived from cumulative successful National Focus Days, so that it is separate from current streak-like records and cannot be manually edited.

### My and settings

63. As a user, I want My to contain personal records and settings, so that global configuration has one predictable home.
64. As a user, I want notification and background-timing settings under My, so that other pages do not expose unrelated settings menus.
65. As a user, I want Precedent Rule history and management reachable from My as well as the relevant Focus Chain expansion menu, so that rules are available both contextually and for review.

## Implementation Decisions

- Use one mobile-first Flutter/Dart client for mobile and desktop, with Material 3 as the foundation and custom design tokens for the product visual language.
- Use Riverpod for explicit UI and state transitions, Drift/SQLite for the local cache, local notifications for background Session timing, and the existing Supabase/PostgreSQL/Auth/RLS boundary for synchronized source-of-truth data.
- Keep the four primary destinations as Board, National Focus Tree, Focus Chain, and My.
- Define Recent Focus Activity as a read-only per-day projection of actual focus minutes from recent Focus Session history. It includes completed, failed, and abandoned effort for historical reflection, while remaining separate from Task Focus Progress and all chain or tree records.
- Keep App-owned Goals and Tasks as the source of executable work. Use only Goal → Task hierarchy in the first version; Tasks do not contain nested child Tasks.
- Keep Task Chain Classification as Elite, Regular, or Both. Use a secondary task-picker with classification filters instead of separate Elite and Regular primary pages.
- Keep Focus Chain Selection explicit. A Regular suggestion is allowed when no Elite Tasks are available, but automatic switching is not.
- Separate Focus Session execution from Focus Chain setup. The Session surface owns the countdown and interruption decisions; the Board, task-picker, and Focus Chain setup surface do not run the Session timer.
- Model normal Session completion as the countdown reaching zero. Do not expose a manual completion action.
- Route Pause, Continue, Early Termination, and Abandon through an interruption decision that can select or create an eligible Precedent Rule, record a Failure Reason when progress is discarded, or return to the Session.
- Append a system-generated Focus Node only for normal or Precedent Rule-approved Session completion. Do not use Focus Session completion to complete a Task or Goal.
- Keep Appointment Chain as a fixed 15-minute delayed-start flow and keep physical Trigger Signals and Focus Markers human-operated; the App records the selected flow but does not detect the signal.
- Keep the National Focus Tree independent from Goals and Tasks. It is a manually maintained state model, not a task classification tree.
- Make Card Library the source of user-authored National Focus Cards. Tree attachment places an existing card; card creation begins in the Card Library secondary page.
- Make National Focus Tree Simple and Detailed views differ by information density: icon-and-structure scan versus full card metadata and visible state.
- Keep the 04:00 National Focus Day boundary, batch confirmation, exclusion behavior, failure snapshots, soft-delete constraints, and Internalization formula already recorded in the domain context.
- Keep settings under My, while allowing Focus Chain-specific Precedent Rule access from an expansion menu and National Focus-specific actions in the tree header.
- Use the accepted throwaway UI prototype as a reference for the validated composition and interaction sequence, while rewriting the production UI as proper Flutter components.

## Testing Decisions

- Test externally observable behavior at the highest available seam: route/state-flow or widget/integration tests that drive user actions and inspect visible state and persisted outcomes.
- Test the primary navigation and Board landing behavior, including Task-first ordering and combined progress/status information.
- Test the secondary task-picker filters for Elite, Regular, Both, and all eligible Tasks; verify that selecting a Task preserves explicit chain choice and does not create a separate chain page.
- Test Focus Session state transitions: normal completion only at zero, no manual completion action, background continuity, interruption flows, Precedent Rule selection/creation, return-to-session, Failure Reason requirement, and correct progress/history effects.
- Test Appointment Chain's fixed 15-minute window and verify it does not create a Focus Session or reset a Focus Chain when it expires or is abandoned.
- Test National Focus Tree rendering at both information densities, structural parent/child relationships, Card Library attach flow, Card Library creation flow, and settings/action placement.
- Test National Focus daily confirmation around the 04:00 boundary, including exclusion, missed confirmation invalidation, failure snapshot creation, child extinguishing, current-record reset, historical-record retention, and Internalization retention.
- Test soft-delete and restore behavior for snapshot-referenced cards and permanent deletion eligibility for unreferenced cards.
- Test that completing a Focus Session does not complete its Task or Goal, and that only explicit Task completion can advance Goal completion.
- There is no existing application test suite to reuse because the repository is currently design- and prototype-led. New tests should establish behavior-level fixtures and avoid coupling to prototype markup or widget implementation details.

## Out of Scope

- A manual “complete Session” action.
- Separate primary pages for Elite and Regular chains.
- Automatic switching between Elite and Regular chains.
- App detection of snaps, gestures, Focus Markers, or other physical signals.
- Automatic failure caused only by backgrounding the App.
- Automatic Task or Goal completion from a Session countdown or Focus Progress.
- A separate standalone To-do navigation destination or a general project-management suite.
- Microsoft To Do, Outlook, Microsoft Graph, or bidirectional calendar synchronization.
- Shared organizations, teams, workspaces, or public unrestricted registration.
- Automatic tree splitting, replacement-card generation, post-failure redesign suggestions, or automatic card evaluation.
- National Focus Groups, tolerance quotas, Water-tight Compartment exceptions, policy-strengthening levels, and complex inheritance mechanics.
- Structured Failure Reason categories or cross-domain failure analytics beyond retaining the original short text; these remain future work.
- Pixel-perfect reproduction of any reference application or promotion of the throwaway prototype directly into production.

## Further Notes

The user explicitly accepted the current prototype direction after the Session controls, task-picker structure, Board task-first layout, Card Library relationship, and settings placement were corrected. The prototype is retained as a primary design reference; the production implementation should preserve the decisions, not copy the prototype's throwaway markup or styling literally.

The next implementation slice should establish the Flutter shell and navigation, then build the Board → task-picker → Focus Chain → Focus Session path before adding the National Focus Tree and Card Library flows.
