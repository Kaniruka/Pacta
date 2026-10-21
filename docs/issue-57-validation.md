# Issue #57 implementation and validation

## Scope and baseline

- Issue: 从 App 授权 Codex 并读取云快照信息.
- Baseline: `2c45a90fbeb185bb31e4fe72b5d36445d65fcf02` (`master`).
- Preserve pre-existing changes in AGENTS.md, development-environment.md, ADR 0006, UI agent guide and National Focus AI design/spec documents.
- Public test seams already accepted in the Issue/spec: MCP HTTP entry, App shell, and real authorization/RLS/revocation.
- User explicitly authorized deployment of this ticket's authorization schema/Edge Function and independent test identities in the existing Supabase project; remove test identities, credentials and fixtures after validation. Existing users are excluded from fixtures.

## Progress

Android 15/API35 AVD `PactaT24Peer` runs as `emulator-5554`. Debug APK built and installed with `adb install -r`, preserving existing data. Public client configuration was extracted into an ignored temporary file containing only URL/publishable key; the root credential file was not passed to Flutter.

- Edge Function deployed through Supabase Management API with `verify_jwt=false`; its own delegated-token verification protects every MCP request.
- Deployed migration applies independent grants, App consent/revocation RPCs and service-only metadata projection.
- Real HTTP probe passed: OAuth PKCE/DCR, single-use code, no snapshot, actual upload metadata, expected-revision conflict, unexpected identity arguments, unchanged snapshot after repeated reads, cross-user revoke refusal, direct authorization-table denial, expiry, suspension and immediate revoke rejection for call/initialize/list/ping.
- Rollback SQL probe ran on actual Supabase with the two explicit isolated fixture UUIDs. Snapshot/grant fixture normalization was inside the rolled-back transaction; no ordinary user was selected.
- Actual Windows Codex CLI `0.163.0-alpha.10.2` completed discovery, DCR and PKCE. App login and explicit consent were performed on the Android emulator, then the browser callback returned to Codex. `mcpServer/tool/call` returned `get_snapshot_metadata` revision 1, device `Issue57 isolated probe`, actual upload `2026-10-21T15:26:19.735369Z`, distinct from business update `2026-01-01T00:00:00Z`.
- First live deployment exposed the Supabase forwarded-path difference; fixed and covered by a public HTTP regression. Actual Codex registration required compatible DCR grant-type metadata; the server still issues no refresh token and advertises only authorization_code.

## Final verification

| Command / boundary | Result |
| --- | --- |
| `dart format` for the 7 changed Dart files | No pending formatting changes |
| `flutter analyze` (Windows Flutter from WSL) | No issues found |
| `flutter test --reporter compact` | 262 passed |
| `flutter test integration_test/national_focus_ai_device_test.dart -d emulator-5554` | 1 passed; Android 15/API35 |
| `flutter test integration_test/national_focus_ai_device_test.dart -d windows` | 1 passed; actual Windows build/run |
| `flutter build apk --debug --dart-define-from-file=.scratch/issue57-public.json` | Debug APK built |
| Node 24 `--experimental-transform-types --test .../handler.test.ts` | 9 passed |
| `npx --yes deno check supabase/functions/national-focus-mcp/index.ts` | Passed |
| PostgreSQL 18.6 / PGlite 0.5.11 | Actual role-switching RLS/OAuth probe passed |
| Supabase Management API rollback SQL probe | Passed, bound explicitly to the two fixture identities |
| Real remote HTTP probes | All checks listed above passed; additionally rejected ordinary App JWT/forged delegate, distinguished legacy-only and unsupported old snapshots with unknown upload/source times |
| Actual Codex after App revocation | Stored delegated credential rejected during initialize with `Auth required`; no tool result |

The first full Flutter run found an existing administrator-navigation test tapping a cached offscreen card after the new My entry changed layout. Scope its Scrollable to MyPage and ensure the card is visible before tapping; the final full suite passes. No administrator behavior was removed.

Public metadata and actual App revocation evidence:
[Codex response](evidence/issue57-codex-metadata.json),
[Android revoked state](evidence/issue57-android-revoked.png).
The read and revoke checks used the actual Codex app-server MCP client rather than an AI model prompt; no model/API key was required. Only this recorded Codex version is claimed tested.

## Review

- Standards: 0 hard violations. Fixed two nonblocking suggestions: reuse the page configuration formatter and remove the no-op CORS wrapper.
- Spec: 0 confirmed deviations. The original Issue acceptance is the review source; later tree/history/skill tools remain unavailable.
- UI: use existing Material 3 theme, semantic labels and explicit consent; tested 320-wide dark layout with 2x text, 1200-wide layout, missing service, load failure/retry and both entry points. Android screenshot was inspected. Windows interaction ran through the native integration test; no separate Windows screenshot inspection is claimed.

## Cleanup

The existing Supabase project was used only after explicit user permission, with two newly created test identities rather than normal users. Removed their registration eligibility, snapshots, legacy fixture rows (Auth cascade), grants, requests, OAuth clients and Auth identities. Auth user count returned to its initial 2; all three MCP authorization tables contained 0 fixture rows. Logged out the temporary `pacta57_acceptance` Codex OAuth credential. Feature schema, migration history and deployed service remain intentionally.

The Android integration command unexpectedly uninstalled its test APK on completion: Flutter defaults `--uninstall` to true. This was an execution mistake; future runs must use `--no-uninstall` and take a scoped device-data backup before installation. The existing `default_boot` RAM snapshot could not load. After backing up the disk images, applied the existing disk snapshots (dated 2026-10-06 23:39:12 as reported by emulator tools), cold-booted with `-no-snapshot-load -no-snapshot-save`, and verified that the original Pacta package and app assets returned. Installed the final debug APK with `adb install -r`. This recovers the existing snapshot state, not a proven byte-for-byte pre-session state; there was no separate pre-test SQLite backup. The initial screen was signed out. Recovery disk backups are retained at `C:\Users\Stray\AppData\Local\Temp\pacta57-avd-recovery` for safety; no claim of exact pre-session local-cache restoration is made. Cloud normal-user data was not modified.

For future Android device runs use:

```sh
flutter test integration_test/national_focus_ai_device_test.dart -d emulator-5554 --no-uninstall
```

The native test uses in-memory business data and fake authorization state. The separate real consent/revoke demonstration used the isolated cloud identities described above. Protected temporary credential state and request-code files were removed after verification.

## Delivery gate

Record actual static analysis, full test-suite, emulator, database/RLS and real Codex results below. Close Issue #57 and unblock dependent tickets only after required evidence passes.
