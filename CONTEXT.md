# Chain App Context

Chain is an open-source, cross-platform self-regulation app. It combines short, executable focus commitments with a longer-term progression model so that users can turn deadlines and unfinished work into a concrete next action.

## Core concepts

**User**:
An individual person whose tasks, focus history, chains, and focus-tree progress are private to that person.
_Avoid_: Account, tenant, organization

**Focus Session**:
A bounded period in which the user commits to carrying out one clearly defined focus task under an agreed focus rule.
_Avoid_: Timer, pomodoro

**Focus Chain**:
An ordered series of successful focus sessions for a specific area of work or life.
_Avoid_: Streak, habit counter

**Focus Node**:
One position in a focus chain representing a completed or planned focus unit.
_Avoid_: Check-in, badge

**National Focus Tree**:
A branching progression model in which small, maintainable rules and actions unlock or support broader improvements in the user's daily state.
_Avoid_: Skill tree, goal hierarchy

**Focus Rule**:
The explicit condition that defines what a focus session requires and what counts as a valid completion or failure.
_Avoid_: Motivation, promise

**Task**:
An item the user intends to complete, with enough information to connect it to a deadline, a focus session, or a focus-tree node.
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
