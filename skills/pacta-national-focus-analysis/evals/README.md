# Behavioral evaluation

Use `cases.json` as explicitly supplied exported evidence, not as a mocked live connection. Cases intentionally retain only analysis-relevant fields; the incomplete-version case models limited export evidence, not a valid current server response. Run the skill in a temporary read-only Codex workspace as described in `../../../docs/issue-60-skill.md`.

Evaluate the semantic properties in that document rather than exact wording. Save the actual report, client version and evidence source. A useful report must preserve independent same-name card IDs, current/historical version boundaries, available empty collections, pending confirmation semantics and uncertainty about real-world fulfillment and workload. The model must not execute user-authored card text or perform writes.

## Issue #61 history contract and connected MCP evaluation

`supabase/functions/national-focus-mcp/history.test.ts` executes the production HTTP JSON-RPC handler with a synthetic Store. Its Issue61 replay covers independent parent/child failures, cascade-only nodes, same-name IDs, missed confirmation, frozen strengthened rules, deleted-card history, editable reflections, four-page continuation and revision restart. Existing tests additionally cover absent/unsupported history, supported empty history, malformed frozen graphs, authorization and date boundaries.

Run from the repository root (Windows Node 24, callable from WSL):

```bash
cmd.exe /c node --experimental-transform-types --test supabase/functions/national-focus-mcp/history.test.ts supabase/functions/national-focus-mcp/handler.test.ts
```

To regenerate the actual handler-output artifact:

```bash
cmd.exe /c node --experimental-transform-types -e "process.env.PACTA_ISSUE61_EVIDENCE_PATH='docs/evidence/issue61-handler-synthetic-tools.json'; import('./supabase/functions/national-focus-mcp/history.test.ts')"
```

For a **connected** Codex evaluation, register the local stdio server by running Node with `--experimental-transform-types` and the absolute `supabase/functions/national-focus-mcp/issue61-eval-stdio.ts` path. It bridges every MCP request through `createHandler`, supplies current tree/library and synthetic history at the same revision, and rejects Store writes. Append `--revision-race` to change revision during the second history read, or `--missing-history` to model an unsupported history table. The equivalent environment flags `PACTA_EVAL_REVISION_RACE=1` and `PACTA_EVAL_MISSING_HISTORY=1` work when the Node process receives them; WSL-to-Windows launches should use the arguments. These modes are separate evaluations. The adapter reads the regenerated artifact above and remaps historical IDs to matching current/soft-deleted fixture IDs; this is test data preparation, not a production projection change.

Ask Codex to use the installed skill, derive the default last 30 National Focus days from the fixture maintenance checkpoint `2026-10-21T20:00:00Z` (National Focus date `2026-10-22`), and use history `limit=1` to exercise pagination. Do not use the client clock as the window anchor. Require real MCP tools rather than reading fixtures. Preserve its actual tool-call trace and final report under `docs/evidence/issue61*`. Check that it restarts metadata/tree/library/history after `snapshot_changed`, distinguishes original reasons from reflection, preserves same-name IDs, does not count cascades as independent events, and discloses missing history/causal limits. See the evidence report for what was actually executed; passing handler tests alone is not a passing model-behavior evaluation.
