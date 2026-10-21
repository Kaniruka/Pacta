# National Focus MCP, contract v1 (Issue #57)

This release exposes **only `get_snapshot_metadata`**. National Focus content,
failure queries, write tools and arbitrary SQL/table access are not available.
Neither connecting nor reading performs a manual upload/download or settlement.

## Deploy

Apply `supabase/migrations/202610210001_national_focus_mcp.sql` after the existing
snapshot/lifecycle migrations. Review the selected project before applying it;
use isolated test identities for validation and never overwrite ordinary users'
snapshots.

```powershell
supabase db push
supabase secrets set PACTA_MCP_PUBLIC_URL=https://PROJECT.supabase.co/functions/v1/national-focus-mcp
supabase functions deploy national-focus-mcp --no-verify-jwt
```

`PACTA_MCP_PUBLIC_URL` is the canonical HTTPS issuer, without trailing `/mcp`.
The function uses the runtime's `SUPABASE_URL` and server-only
`SUPABASE_SERVICE_ROLE_KEY` (or `SUPABASE_SECRET_KEYS`). The secret never goes
into Flutter, Codex, a URL, or a conversation. Supabase's gateway JWT check must
be disabled **for this function only**: discovery is public and MCP uses a
different opaque credential. The handler and SQL recheck that delegate on every
MCP request, including initialization and tool discovery.

No static authorization hosting is needed. Supabase rewrites HTML responses to
plain text on its normal API domain. The browser authorization endpoint therefore
shows a plain text request code; the signed-in native App performs explicit
consent, and refreshing the browser completes the OAuth callback.

## Connect and renew

```sh
codex mcp add pacta-national-focus --url https://PROJECT.supabase.co/functions/v1/national-focus-mcp/mcp
codex mcp login pacta-national-focus --oauth-client-registration dcr
```

1. Codex opens a browser with a one-time request code.
2. Sign in normally in Pacta. Open **My → National Focus AI**, paste the code,
   inspect the requesting client's label and exact loopback callback, and
   explicitly approve only a request you just initiated yourself.
3. Refresh the browser page. It returns the authorization code to Codex's
   registered local callback. No Pacta password or full App session reaches Codex.
4. Ask Codex to call `get_snapshot_metadata`. To change the analyzed version,
   manually upload the whole-data snapshot through Pacta's existing overwrite
   confirmation; opening this guide or authorizing does not upload data.
5. Revoke the connection in the same App page. Subsequent calls fail immediately,
   including calls made with an otherwise unexpired credential. Revocation cannot
   remove information already copied into a conversation.

Requests and authorization codes expire after five minutes. A delegate lasts
30 minutes from App approval. There is no refresh token in T1; repeat `codex mcp
login` after expiry/revocation. App sign-out does not revoke an independently
approved delegate. A suspended/deleted User cannot use it; restoring a User does
not revive a revoked delegate. Desktop Codex uses the registered HTTP loopback
callback (127.0.0.1, localhost or ::1, explicit port). Other redirect schemes,
remote callbacks and tablet clients are not supported in T1. Actual tested
client/platform versions belong in the validation record, not inferred from
this protocol description.

## OAuth and security contract

The transport is stateless Streamable HTTP with JSON responses, POST-only MCP
and no persistent event stream. Discovery follows the `WWW-Authenticate`
`resource_metadata` URL at `/resource-metadata`. The path issuer publishes
`/.well-known/openid-configuration` **appended to its issuer path**, one of the
MCP discovery fallbacks, because Supabase does not route root-domain well-known
paths into an Edge Function.

- Public DCR `/register` creates public clients with `token_endpoint_auth_method`
  `none`. Only explicit loopback ports and registered exact callback URLs are
  accepted; URL credentials, fragments and callback queries are rejected.
- `/authorize` requires response type `code`, exact scope `national_focus:read`,
  exact canonical resource `<issuer>/mcp`, a bounded state and S256 PKCE. All
  checks run before redirecting. The callback returns state and issuer (`iss`).
- Initial GET allocates only a five-minute authorization request, never a grant.
  Its 256-bit random code is a capability to inspect/approve that request in an
  authenticated App. Browser refresh never authenticates the User or grants
  consent. Cookies and cross-origin browser API calls are not trusted.
- App approval resolves the owner from verified `auth.uid()`, checks current
  active status, requires explicit boolean consent and locks/consumes the request
  for approval. An OAuth client's user id cannot choose another User's data.
- `/token` requires the original client id, exact redirect/resource and S256
  verifier. SQL atomically consumes the code; null binding parameters fail.
  A short-lived raw authorization code is retained only until consumption or
  expiry in a service-only table. Access tokens and request capabilities are
  stored only as SHA-256 hashes. Access tokens have 256 bits of random entropy,
  are bound to this resource by their private grant store and have no validity at
  Supabase Auth/REST or any App business API.
- All three authorization tables have RLS and no anon/authenticated table
  privileges. Authenticated App users see redacted own grants via an RPC and can
  revoke only their own grants; only service-role code can exchange/read delegates.
  The sole delegated SQL read builds an explicit metadata projection without
  returning snapshot payloads, user ids, module counts, logs or Auth/admin data.
- SQL serializes public allocations: at most 200 client registrations/hour,
  5,000 retained clients, 1,000 pending requests globally and 10/client. Capacity
  returns HTTP 429. New allocations delete expired requests; registrations also
  remove grants expired for seven days and unreferenced clients older than a
  day. Operators may run that same cleanup periodically if the service is idle.
  Shared capacity is deliberately finite; add gateway per-IP throttling for a
  larger deployment. Retained App history can disappear after seven days.

Do not log bodies, authorization headers, callback queries or request-code URLs.
Supabase access logs may retain request URLs; configure their retention/access as
credential-bearing operational logs. The implementation itself logs none.

## App RPC contract

All App calls use the ordinary signed-in Supabase client; its session stays in
the App. RPCs never return delegated tokens, hashes, user ids or application
sessions. Errors use PostgreSQL codes `22023` for invalid/expired/already approved
requests, and `42501` for unauthenticated/suspended approval or foreign revoke.

| RPC | Parameters | Result |
| --- | --- | --- |
| `inspect_national_focus_mcp_request` | `p_request_code: text` | `{client_name, redirect_uri, scope, expires_at}` |
| `approve_national_focus_mcp_connection` | `p_request_code: text, p_consent: boolean` | void; creates own 30-minute grant |
| `list_national_focus_mcp_grants` | none | own `[{id,client_name,scope,created_at,expires_at,revoked_at}]`, newest first |
| `revoke_national_focus_mcp_grant` | `p_grant_id: uuid` | void; own-only and idempotent |

Request codes are 64 hex characters; surrounding spaces/case are normalized.
Canceling without approving makes no grant; the request expires automatically.
The client label is supplied by the registering client, not a verified vendor
identity. UI must show the destination and warn against approving codes sent by
someone else.

## Shared read/error/revision contract for T2/T3

`read_national_focus_mcp_metadata(p_token_hash, p_expected_revision default null)`
is service-only and is the current delegate-validation seam. It checks the token,
expiry, revocation, owner existence and current suspension every time. New tools
must preserve these checks and the explicit projection boundary, never forward
a whole Cloud Data Snapshot to the MCP client. Authorization does not imply
permission to read other business modules.

`get_snapshot_metadata` accepts an optional positive safe integer
`expected_revision`; all other input fields are rejected. An available result is:

```json
{
  "contract_version": 1,
  "status": "available",
  "revision": 2,
  "source_device": {"id": "device-id", "name": "Android"},
  "uploaded_at": "2026-10-21T01:00:00+00:00",
  "data_updated_at": "2026-10-20T23:00:00+00:00",
  "freshness": "latest_manual_upload"
}
```

`uploaded_at` comes from server snapshot persistence. `data_updated_at` describes
the **whole snapshot**, never the last National Focus edit. National Focus's
last edit time is not claimed. A valid current-format empty tree is available.
Format validation requires the five existing National Focus table arrays,
object rows owned by this User, and nonempty standalone card names.

| Status/error | Meaning and recovery |
| --- | --- |
| `no_snapshot` | No canonical or legacy data. Manually upload in Pacta; revision/device/times are null. |
| `legacy_snapshot` | Only legacy cloud records. Update the App and manually upload; metadata is unknown/null. |
| `unsupported_snapshot` | Canonical envelope contains an older/incomplete National Focus format. Update and manually upload; no inferred device/time is returned. |
| MCP tool `isError`, `code: snapshot_changed` | Expected revision differs. Re-read metadata and restart analysis; never combine pages/details from different uploads. |
| HTTP 401 `invalid_token` | Missing/forged/expired/revoked delegate, deleted or suspended owner. Check App status and repeat OAuth login as appropriate. |
| HTTP 503 `service_unavailable` | Service failure. Retry; it is not an empty tree. |
| JSON-RPC -32602 | Unknown tool/invalid arguments, including user selectors or SQL. |

T2/T3 details and pagination must require `expected_revision` and return the same
metadata/version context. No historical cloud snapshots are retained by MCP.
The skill and National Focus content tools remain later tickets; T1 must not
describe their availability as complete.

## Verify

Run the public HTTP contract tests without Supabase:

```sh
node --experimental-transform-types --test supabase/functions/national-focus-mcp/handler.test.ts
```

Use Node 24+; production is Supabase's Deno Edge runtime. Run
`supabase/tests/national_focus_mcp_access.sql` in an isolated test project after
the migration. It is rollback-only. Real public deployment/OAuth, App revoke,
Codex version and Android/Windows evidence are tracked separately in
`docs/issue-57-validation.md`; mock HTTP or local SQL evidence alone does not
prove those acceptance steps.

Primary protocol references reviewed 2026-10-21:
[MCP authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization),
[OpenAI Codex MCP/OAuth registration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli),
[Supabase routing/HTML restriction](https://supabase.com/docs/guides/functions/http-methods).
