---
status: accepted
---

# Keep tasks in the App and treat device calendars as read-only constraints

Chain will own its To-do data and focus planning, while mobile clients may read selected device calendars and normalize them into Calendar Blocks. The first version will not integrate Microsoft services or perform bidirectional calendar editing. This keeps the core interaction centered on Focus Chains and the National Focus Tree, avoids building a full task/calendar replacement, and lets desktop clients consume synchronized calendar constraints without duplicating every platform-specific calendar API.

## Considered options

- App-owned tasks plus read-only device-calendar import: selected.
- Microsoft To Do/Outlook integration: rejected for the current scope because it adds authentication, permission, rendering, and synchronization complexity without being central to the self-regulation loop.
- Full bidirectional synchronization with all platform calendars: rejected for the first version because conflict resolution and platform differences would dominate the product work.
- No calendar integration: rejected because deadlines and fixed calendar blocks are useful context for deciding what focus action is feasible now.
