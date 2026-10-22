# Issue #59 implementation and validation

> 历史适用范围：以下设计、评审及验收记录适用于各节所载日期（2026-10-23 范围调整之前）。原始事实、测试和证据保留；其中无障碍要求及未完成项不再构成未来交付条件，现行范围见 [ADR 0007](adr/0007-accessibility-out-of-product-scope.md)。

Issue: **[国策 AI T3] 让 Codex 查询失败事件和当时的国策树**.
Baseline: `d193cc4424203980e4f0e8f02edaae51d9e8ad8c` on `master`.
Preserved pre-existing AGENTS.md and environment-document changes, and untracked
ADR 0006, UI agent guide and National Focus AI design/spec documents.

## Implementation

- Adds read-only `list_national_focus_failures` and revision-pinned
  `get_national_focus_failure`. Existing T1/T2 tools and delegation remain.
- Lists independent stored failure sources, including missed confirmation and
  active extinguishing. Descendant cascade state remains in frozen trees rather
  than becoming extra failure events. Original reasons and later batch reflection
  remain separate; historical rules/names are never joined to current cards.
- Exact inclusive date range of at most 366 National Focus days, Beijing 04:00
  boundaries, ascending checkpoint and deterministic ID ordering, limit 1–100.
  Cursors bind query bounds, page size, last event and expected revision.
- New service-only STABLE RPC reads only the failure table from the latest
  manually uploaded snapshot after checking delegate and current owner state.
  Metadata/content use the same MVCC snapshot. No source logs or other modules.
- Typed field whitelists reconstruct event and frozen-tree objects. Optional
  older rule-version fields remain null. Missing required historical fields fail
  closed as unsupported data. Soft-deleted references remain frozen and readable.
- Public tools, browser consent, App disclosure and runbook explain the history
  scope and limits. No daily success log is inferred from cumulative progress;
  there are no failure creation/editing tools or implicit settlement/sync.

## Verification

| Command / boundary | Result |
| --- | --- |
| Windows Node 24.20.0, `node --experimental-transform-types --test supabase/functions/national-focus-mcp/handler.test.ts supabase/functions/national-focus-mcp/history.test.ts` | 23 passed |
| `npx --yes deno check supabase/functions/national-focus-mcp/index.ts` | Passed |
| `git diff --check` | Passed |

Public HTTP tests cover exact start/end boundaries, same-time ordering,
revision-pinned continuation/details, missing and empty history, distinct owner
tokens, revoked access including between metadata/content reads, service error
redaction, frozen strengthened rules, legacy missing optional rules, batch
reflection, cascade-only detail absence and recursive unknown-field exclusion.
Regression cases also verify malformed JSON date types and explicit null limits,
frozen dangling references and cycles, and Unicode code-point sorting with cursor
continuation.

## Standards review

Review compares task files against the baseline above; pre-existing user files
are excluded. Repository standards and UI disclosure requirements govern the
review. Independent review found 0 actionable documented-standard violations and 0
actionable Fowler smells. Required Dart verification is recorded below.

## Spec review

Independent review found invalid runtime date types could become service errors,
explicit null limits could default silently, and malformed frozen graph references
could pass validation. These are fixed with runtime input checks, explicit limit
validation and graph reference/cycle validation. Sorting now implements the
promised Unicode code-point order. The added regressions and Deno check pass.
No unresolved spec finding is accepted as completed validation.

## Native and remote evidence

- `dart format` completed on changed Dart files.
- `flutter analyze`: no issues.
- Targeted National Focus AI widget tests: 6 passed.
- `flutter test --reporter compact`: all 262 passed.
- Android `national_focus_ai_device_test.dart --no-uninstall` on `PactaT24Peer`, Android 15/API35, emulator-5554:
  1 passed. The test exercises history disclosure, explicit consent, revoke and
  manual upload confirmation using fake repositories; it does not replace the
  separate real MCP service checks.
- Existing Android app data was archived through `run-as`, restored and compared
  byte-for-byte after excluding/removing one generated Flutter resource timestamp
  file. The normal debug APK was rebuilt with only public URL/publishable-key
  defines and installed using `adb install -r`; the temporary define file was
  removed. No screenshot was captured; this copy-only change was exercised by
  the native flow and narrow/dark/large-text and desktop-wide widget tests.
  Windows native execution was not repeated for this ticket.
- Migration 202610220001 applied transactionally to the configured project and
  tracked in migration history. Real rollback-only history SQL probe passed and
  was independently rerun by the main agent. Probe identities remaining: 0.
  This is test-identity isolation in the shared development project, not a newly
  provisioned isolated Supabase project.

Final Edge Function deployment is ACTIVE version 9 (`verify_jwt=false`, opaque
delegate validation remains inside the function). The main agent independently
checked deployed status/version.

Actual installed Codex CLI/app-server `0.163.0-alpha.10.2` read the remote service
using an isolated test identity and opaque read delegate through
`bearer_token_env_var`. This run tests T3 history behavior; it does **not** retest
OAuth DCR/PKCE or manual consent. T1/T2 evidence remains separate. Configuration
follows [official Codex MCP guidance](https://learn.chatgpt.com/docs/extend/mcp),
reviewed on 2026-10-22. No model/API prompt or model API key was involved.

The actual client verified same-checkpoint stable ordering, cursor continuation,
frozen rules/names and separate reflection with recursive field exclusion. A
local-only fixture edit stayed invisible. Explicit authenticated whole-snapshot
upload advanced revision 1 to 2; the old cursor returned `snapshot_changed`, and
new revision detail reflected the upload. Revocation then refused subsequent
reads through the actual client. Sanitized fixture-only responses are in
[Codex history evidence](evidence/issue59-codex-history.json).

Cleanup verified ordinary Auth baseline restored to 2 and temporary test users,
clients, snapshots, grants and authorization requests all 0. The actual-client
session used a temporary separate configuration home with an environment bearer;
no application password, service secret or delegated token is committed in the
evidence. Existing ordinary user data was not selected as a fixture.

UI review applied apple-design Privacy › Best practices (specific disclosure),
Accessibility › Vision, Layout › Adaptability and Typography › Supporting Dynamic
Type, translated to the existing Flutter Material UI. ui-ux-pro-max readable-text,
error-announcement and Flutter Semantics guidance informed the copy checks.
Standards review: 0 actionable findings. Spec review: 3 issues corrected (runtime
input handling, frozen graph validation, Unicode ordering); 0 unresolved findings.
