# National Focus MCP v2 (Scoped Bearer Tokens + Constrained Writes + Skills-over-MCP)

This release exposes National Focus snapshot metadata, current tree/library/card details, read-only failure history with frozen trees, **Skills-over-MCP** (`initialize.instructions`, `list_skills` / `get_skill`, `resources/list` + `resources/read`, `prompts/list` + `prompts/get`), and constrained National Focus card/tree writes behind Scoped Bearer Tokens.

## Endpoints & Scopes

| Endpoint | Required Token Scope | Capabilities |
| --- | --- | --- |
| `POST .../national-focus-mcp/mcp/readonly` (and `/mcp` alias) | `national_focus:read` or `national_focus:readwrite` | Read metadata, tree, library, card, failure history, and built-in skills/resources/prompts |
| `POST .../national-focus-mcp/mcp/readwrite` | `national_focus:readwrite` | All read + skill tools, plus constrained card/tree write tools (`create`, `update`, `move`, `set_deleted`) |

Legacy OAuth DCR endpoints (`/register`, `/authorize`, `/token`, `/resource-metadata`, `/.well-known/openid-configuration`) are removed.

## Deploy

Apply `supabase/migrations/202611250002_national_focus_mcp_v2.sql` after existing snapshot migrations, regenerate the bundled skill module when `skills/` changes, and deploy:

```powershell
python scripts/sync_mcp_skills.py
supabase db push
supabase secrets set PACTA_MCP_PUBLIC_URL=https://PROJECT.supabase.co/functions/v1/national-focus-mcp
supabase functions deploy national-focus-mcp --no-verify-jwt
```

`PACTA_MCP_PUBLIC_URL` is the canonical HTTPS issuer without trailing `/mcp`. The runtime reads `SUPABASE_URL` and server-only `SUPABASE_SERVICE_ROLE_KEY` (or `SUPABASE_SECRET_KEYS`). Gateway JWT verification is disabled for this function only because clients authenticate with opaque `pacta_mcp_...` Scoped Bearer Tokens validated via SHA-256 hash in PostgreSQL on every request.

## Connect & Manage Tokens

1. Sign in to Pacta App and open **My → National Focus AI Analysis** (or **National Focus Tree → More → National Focus AI Analysis**).
2. Tap **Create Connection**, select an Agent preset (**Antigravity**, **Claude Code**, **Codex**, **DSH**, **Cursor**, or **Generic HTTP MCP**), choose **Read-only** or **Read-write**, and pick an expiry (`30m`, `24h`, `7d`, `30d`, or **Never expires**).
3. Copy the one-time generated Bearer token or ready-to-paste client configuration. Tokens are stored only as SHA-256 hashes and are never shown again.
4. Review recent reads/writes in the audit log section, or revoke one / all active connections at any time. Revocation and user suspension take effect immediately on the next MCP call.

## Constrained Write Invariants

Write tools (`create_national_focus_card`, `update_national_focus_card`, `move_national_focus_card`, `set_national_focus_card_deleted`) require a v4 snapshot and a matching `expected_revision`:

- **CAS & Backup**: Every write runs under a per-user advisory lock, checks `expected_revision` (`PT409` -> `snapshot_changed` on mismatch), updates only `local_national_focus_cards` and `local_national_focus_strengthening_levels`, advances the cloud snapshot revision, and archives a version in `cloud_business_snapshot_history` (retaining the latest 15 snapshots).
- **Hard Forbidden Mutations**: Enforced in both TypeScript (`mutations.ts`) and PostgreSQL (`write_national_focus_mcp_snapshot`):
  - Never hard-deletes existing cards.
  - Never alters `state` to `'lit'` or mutates `successful_days`, `current_consecutive_days`, `best_consecutive_days`, `maintenance_cycle_started`, `failure_reason`, or `created_at`.
  - Never alters `local_national_focus_maintenance`, `local_national_focus_failures`, or any non-National-Focus table.
- **Sync Boundary**: Cloud writes update the cloud snapshot; users still perform an explicit manual download in Pacta App to pull changes onto a device.

## Skills-over-MCP

Bundled skills under [`skills/`](../../../skills/) (currently [`skills/better-national-focus/`](../../../skills/better-national-focus/)) are synced into `skills_bundle.ts` via `python scripts/sync_mcp_skills.py` (`--check` verifies synchronization in CI/pre-commit).

- `initialize.instructions` summarizes snapshot freshness, revision coherence, write safety, and all bundled skills (`name`, `description`, `uri`, `references`).
- `list_skills` / `get_skill` (with `include_references: true` for one-call full skill loading) and `resources/list` / `resources/read` (`pacta://skills/<slug>/...`) serve `SKILL.md` and `references/*.md` directly from the MCP server.
- `get_national_focus_tree` / `get_national_focus_library` include `skill_guidance` pointing clients to `better-national-focus`.
- `prompts/list` / `prompts/get` expose `analyze_national_focus_tree`, `review_national_focus_failures`, and `design_or_optimize_national_focus` with embedded `SKILL.md` and relevant reference resources directly in prompt messages.
- The standalone skill ZIP remains reproducible via `python scripts/package_national_focus_skill.py` (`SKILL.md`, `references/card-design.md`, `references/tree-and-recovery.md`).

## Verify

```sh
python scripts/sync_mcp_skills.py --check
node --test supabase/functions/national-focus-mcp/handler.test.ts supabase/functions/national-focus-mcp/history.test.ts
```

Run `supabase/tests/national_focus_mcp_access.sql`, `national_focus_mcp_content.sql`, and `national_focus_mcp_history.sql` in an isolated test Supabase project (all are rollback-only).
