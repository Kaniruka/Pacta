---
status: accepted
---

# Use manual whole-data cloud sync

On 2026-10-04, the user chose explicit whole-data upload or download instead of automatic synchronization and per-record reconciliation, because repeated review prompts (including single-device National Focus time review) made the app difficult to use. Every upload replaces that User's entire cloud business snapshot; every download replaces that User's entire local business snapshot, with source device and both data update times shown before the choice regardless of which is newer. This deliberately accepts loss of records unique to the overwritten snapshot in exchange for a predictable, user-controlled model; device settings, authentication, and administrator-controlled lifecycle status remain device/server-owned.

Startup, foreground recovery, connectivity restoration, and ordinary business edits do not transfer cloud business data. National Focus follows the device's current time without clock-review prompts or pending-clock-review settlement blocking. A check-in trigger for cloud synchronization is deferred. This decision supersedes the former automatic multi-device merging and National Focus clock-review requirements in the core specification and acceptance matrix; per-user isolation and lifecycle access restrictions remain in force.

Concurrent cloud changes after preview require a fresh preview instead of overwriting data that the user has not seen. Local replacement is transactional and cannot interrupt an active Focus Session or Appointment.

Existing cloud business records remain available as a read-only whole-data choice until the first new snapshot is uploaded. Conversion runs in an isolated local store and does not merge those records into the current device. Old records lacking device or upload metadata are labeled explicitly. Once a new snapshot exists, older clients cannot write through the retired per-record cloud interfaces; all devices must use the manual-snapshot client.
