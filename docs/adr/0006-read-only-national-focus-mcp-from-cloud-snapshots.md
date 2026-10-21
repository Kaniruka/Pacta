---
status: accepted
---

# Serve read-only National Focus analysis through remote MCP from cloud snapshots

On 2026-10-20, the user chose remote MCP for Codex analysis of National Focus rules, structure, and failures. It reads the latest manually uploaded Cloud Data Snapshot: users maintain cards on a phone and analyze them on other devices. Under ADR 0005, reads never upload, merge, or change device business data; results identify the source device and upload time.

Each User grants revocable read access to their own tree, card library, requirements, strengthening levels, progress, and failures with historical snapshots and explanations. Goals, Tasks, Focus Sessions, and calendars are excluded despite being in the snapshot. Delegated authorization enforces this scope without exposing full-access app sessions. A companion skill guides evidence-based analysis; skills cannot replace authorization or business validation. Writes require a separate future design.

Cross-device access accepts stale data until the next manual upload. Local-device MCP is deferred because it requires device availability and connections. Hosting, delegated authorization, query contracts, and analysis consistency require implementation design and validation.
