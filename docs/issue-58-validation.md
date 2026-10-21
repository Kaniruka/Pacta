# Issue #58 implementation and validation

## Scope and baseline

Issue: **[国策 AI T2] 让 Codex 读取完整当前国策树与规则**.
Baseline: `687d7af6491d5ef50f2b7a5f692b022a0b75f849` on `master`.
Preserved pre-existing changes in AGENTS.md, development-environment.md, ADR 0006,
UI agent guide and National Focus AI design/spec files.

Public seams confirmed by the user: MCP HTTP contract, isolated Supabase
identity/authorization/RLS boundaries, and Android App guide/manual-upload flow.
The user requested cleanup of test identities, grants and fixtures.

## Implementation

- Retains metadata tool and the independent `national_focus:read` delegate;
  adds tree, library and revision-pinned card detail tools.
- Flat tree uses stable card IDs and uploaded parent IDs. Each card includes
  base/effective rules, all strengthening levels and requirement versions,
  active version, three-state status, consecutive records and internalization.
- Soft-deleted cards are absent from current collections/details. Typed recursive
  field projection strips unknown properties and excludes unrelated modules and
  mixed source logs. Invalid formats fail closed with a recovery instruction.
- Reads select the last manual upload, never recompute settlement by server time,
  and attach revision/source/upload metadata. Content SQL reads share one stable
  MVCC snapshot. New uploads invalidate revision-pinned follow-ups.
- Supports actual SQLite-export booleans (`0/1`) and Unix-second timestamps;
  normalizes timestamps without inferring current device state.
- App and browser consent text list the actual capabilities and freshness. Later
  failure-history and installable analysis skill tickets remain outside T2.

## Verification

| Boundary / command | Result |
| --- | --- |
| Changed Dart files `dart format` | Passed |
| `flutter analyze` | No issues |
| `flutter test --reporter compact` | 262 passed |
| National Focus AI App widget tests | 6 passed; includes 320-wide dark/2x text and Windows-wide layout |
| Node 24 `--experimental-transform-types --test .../handler.test.ts` | 12 passed |
| `npx --yes deno check .../index.ts` | Passed |
| PGlite content SQL probe | Passed with simplified Supabase schema; does not replace real service evidence |
| Android 15/API35 `emulator-5554`, `PactaT24Peer` | 1 integration test passed using `--no-uninstall` |
| Windows native integration test | 1 passed |
| `flutter build apk --debug --dart-define-from-file=.scratch/issue58/public.json` | Passed; only URL/publishable key passed to Flutter |

Android/Windows integration covers entry, capability text, explicit consent,
configuration copy, revoke, no implicit business sync, canceled upload with no
write, and confirmed upload via the existing whole-snapshot overwrite warning.
Initial Android runs exposed offscreen test targets after expanded disclosure;
scoped scrolling was corrected and the final native runs passed. No product
navigation behavior was changed to accommodate the tests.

## Review

- Standards: no confirmed documented-standard violations; minor repeated tool
  descriptor schema/annotations judged acceptable for four explicit tools.
- Spec: corrected stale browser metadata-only disclosure and README T1/T2 wording.
- UI: preserves existing Material components and four destinations. Applied
  apple-design `privacy.md > Best practices` (specific data access disclosure)
  and `layout.md > Adaptability` (large text and narrow/wide layouts). Targeted
  ui-ux-pro-max searches did not yield relevant permission-disclosure guidance;
  existing product conventions and the privacy reference govern this copy update.
- Source guidance: [official Codex MCP documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)
  checked; actual client evidence below defines the supported tested version.

## Live service / Codex / cleanup

Migration `202610210002` was applied transactionally to the configured Supabase
project and recorded in `supabase_migrations.schema_migrations`; the function and
history row were verified. The current Edge Function was deployed with its
opaque-token verification and `verify_jwt=false`. The rollback-only content SQL
probe passed on the actual project. All probe users and business fixtures were
created inside its rolled-back transaction; no ordinary identity was selected.

The configured project is shared with development. Remote validation uses
isolated temporary identities, not a separately provisioned Supabase project;
this distinction is deliberate and follows the test boundary confirmed by the
user. Native UI tests use in-memory business stores and authorization fakes.
Public HTTP and real Codex checks are recorded separately below.

Before Android testing, a scoped `run-as` application-data archive was saved.
Tests used `--no-uninstall`. Afterwards the normal public-config debug APK was
installed with `adb install -r`, the scoped backup restored, and SHA-256 checks
confirmed all seven original files unchanged. One generated resource timestamp
file was removed. No cloud ordinary-user data was used for device testing.

Public HTTP acceptance passed 12 groups: real DCR/PKCE and signed-in App consent
RPC, two users and same-name cards, multiple strengthening/requirement versions,
recursive field/sentinel exclusion, stable rules and IDs, foreign card/revoke
refusal, extra identity/SQL argument rejection, ordinary JWT/forged delegate
rejection, unchanged snapshots after repeated reads, expiry/suspension/revoke,
distinct unsupported/no/empty snapshots, and manual-upload revision replacement.
The main agent independently reran the actual Supabase rollback SQL probe and
confirmed success after reviewing the migration and fixture scope.

Actual installed Codex CLI/app-server `0.163.0-alpha.10.2` (WSL Linux binary)
completed OAuth DCR/PKCE and read a parent/child tree, library, base/effective
rules and current/historical requirement versions. The OAuth request was
inspected and explicitly approved using the isolated user's authenticated App
RPCs; this was not a manual browser/App interaction demonstration. The native
App consent UI was tested separately on Android and Windows.

The actual Codex read used revision 2. A local-only fixture rename did not appear
in the next read. Explicit upload produced revision 3, the stale revision-2 card
request returned `snapshot_changed`, and a new tree read returned the rename.
Revocation immediately caused the actual Codex client to reject a subsequent
read with `Auth required`. No model prompt or model/API key was involved; the
actual Codex MCP client performed discovery, authorization and tool calls.
Fixture-only responses are preserved in
[the Codex tree evidence](evidence/issue58-codex-tree.json).

Cleanup passed: both temporary Auth users, their snapshots, grants, requests,
OAuth clients and registration eligibility rows were removed. Auth user count
returned to its baseline 2; fixture users/snapshots/grants/clients/requests were
all 0. No ordinary user was selected, modified or used for a fixture. Feature
migration and the deployed function intentionally remain.

Codex's logout command could not delete the Linux keyring entry. Inspection
showed the acceptance credential existed only in the fallback credential file;
removed exactly the entry matching the temporary server name and URL. A fresh
actual Codex listing confirmed `not_logged_in`. No unrelated credential entries
were removed. Protected fixture/session state was deleted.

The final error-copy check added actionable recovery to invalid MCP tool
arguments (`tools/list`, correct revision, no user selectors/SQL). The 12 Node
contract tests and Deno check pass with that change; no content or authorization
behavior changed after the live acceptance.
