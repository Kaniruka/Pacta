---
status: accepted
---

# Use manual whole-data cloud sync

On 2026-10-04, the user chose explicit whole-data upload or download instead of automatic synchronization and per-record reconciliation, because repeated review prompts (including single-device National Focus time review) made the app difficult to use. Every upload replaces that User's entire cloud business snapshot; every download replaces that User's entire local business snapshot, with source device and both data update times shown before the choice regardless of which is newer. This deliberately accepts loss of records unique to the overwritten snapshot in exchange for a predictable, user-controlled model; device settings, authentication, and administrator-controlled lifecycle status remain device/server-owned.

Startup, foreground recovery, connectivity restoration, and ordinary business edits do not transfer cloud business data. National Focus follows the device's current time without clock-review prompts or pending-clock-review settlement blocking. A check-in trigger for cloud synchronization is deferred. This decision supersedes the former automatic multi-device merging and National Focus clock-review requirements in the core specification and acceptance matrix; per-user isolation and lifecycle access restrictions remain in force.

Concurrent cloud changes after preview require a fresh preview instead of overwriting data that the user has not seen. Local replacement is transactional and cannot interrupt an active Focus Session or Appointment.

Existing cloud business records remain available as a read-only whole-data choice until the first new snapshot is uploaded. Conversion runs in an isolated local store and does not merge those records into the current device. Old records lacking device or upload metadata are labeled explicitly. Once a new snapshot exists, older clients cannot write through the retired per-record cloud interfaces; all devices must use the manual-snapshot client.

## Read-only update inspection — 2026-10-22

The user accepted cold-start inspection and foreground inspection throttled to five minutes, after authentication and accessible-user status are established. This permits read-only discovery of an unhandled cloud version while retaining explicit whole-snapshot upload/download: inspection must never apply cloud records to local business data. It supersedes the earlier prohibition on startup/foreground business reads, including the corresponding acceptance clause, without authorizing automatic snapshot replacement.

Track handled and ignored cloud versions per user on each device, independently of downloadable business data. A first-seen cloud snapshot prompts even if its data timestamp is older; timestamps do not determine novelty. Own uploads and successfully downloaded versions do not prompt. The action is labeled “忽略”: it suppresses automatic reminders for that version across restarts, retains manual access, and performs no upload or download. Dismissing a prompt does not ignore it. New cloud versions may prompt again. During an unfinished Appointment or active/paused Focus Session, show a nonblocking indicator and defer the automatic choice prompt until the flow ends; explicit upload remains available and download remains prohibited.

Keep source device names and add available hardware model information, explicitly marking missing legacy information as unknown. Offline inspection failures do not block use. Existing revision/fingerprint checks, transactional replacement, user isolation, and destination preservation on failure remain required. Full confirmed UI and acceptance details are recorded in the [2026-10-22 requirements](../requirements-refinement-20261022.md).
