# Supabase setup for Ticket T01

For Issue #57's independent read-only National Focus MCP authorization,
deployment and contracts, see [the MCP runbook](functions/national-focus-mcp/README.md).

The Flutter client only receives `SUPABASE_URL` and the publishable/anon key.
Never put a `service_role` or `sb_secret_` key in `.env` passed to Flutter.

Apply the migration with the Supabase CLI or the SQL editor. Bootstrap the
first administrator through a trusted service-role operation after creating
the user in the Supabase Auth dashboard:

```sql
insert into public.app_admins (user_id)
values ('AUTH_USER_UUID');
```

An authenticated administrator can then call the two protected RPCs:

```sql
select public.admin_grant_registration_eligibility('person@example.com', 'email');
select public.admin_revoke_registration_eligibility('person@example.com', 'email');
```

The `auth.users` trigger consumes an unused, unrevoked eligibility in the
same database transaction as registration. A race or duplicate registration
therefore cannot consume one qualification twice. The trigger bypasses only
trusted `service_role` creation, which is used for administrator bootstrap.

## Email-only registration

The application uses email and password for registration and login. The
`registration_eligibility` table accepts email identifiers only. Its
`auth.users` trigger requires an email and consumes an unused, unrevoked
eligibility in the same transaction. The email-only constraint is applied by
`20260926120000_email_only_registration_schema.sql`.

Email Auth and user signups are enabled in the cloud project; the database
eligibility trigger limits successful registration to approved addresses.
Email confirmation is disabled because the App does not send verification
messages. Password resets are handled by an administrator after manual
identity verification.

## Administrator password reset

Ticket T25 adds `admin-reset-user-password`, a JWT-verified Edge Function for
administrators who have manually verified a user's identity. Apply
`202609260002_admin_password_reset_target_lookup.sql`, then deploy the function:

```powershell
supabase functions deploy admin-reset-user-password
```

The function verifies the caller's current Auth JWT and checks `app_admins`
before looking up the exact target email. The lookup RPC is executable only by
`service_role`; the function changes the existing Auth user through the Auth
Admin API, preserving that user's `user_id` and business-data ownership. The
function's runtime uses Supabase's server-side service-role/secret environment
variable. Do not copy it into Flutter, `.env`, or source control.

The administrator confirms that identity was checked outside the App and must
tell the user the new password through a secure external channel. The App sends
no account messages and does not claim to validate email ownership. No user or
administrator password is returned by the function or written to Pacta business
tables; Supabase Auth applies its own credential storage for the new password.

## User suspension

Ticket T26 adds `202609260003_user_suspension.sql`. Apply it after the preceding
business-data migrations. It adds administrator management RPCs, a signed-in
user status RPC, and restrictive write policies for business tables; it never
deletes users or business data. A suspension becomes eligible for purge after
30 days, but this ticket does not perform a purge. Restoring a user ends that
suspension period, and a later suspension starts a new 30-day period.

The client stores the last server lifecycle status locally. Once it knows the
user is suspended, it blocks new business writes and keeps pending local data
for retry after restoration. A device with no known suspension status remains
available for offline work until it next checks with the server.

The rollback-only server access probe requires one administrator and one
non-administrator account in an isolated test project. It checks administrator
RPC authorization, business-write denial, retained data, day-30 eligibility,
and restoration/re-suspension behavior, then rolls back its test changes:

```powershell
supabase db query --linked -f supabase/tests/user_suspension_access.sql
```

## Explicit cloud purge

Ticket T27 adds `20260926075712_user_purge.sql` and the
`admin-purge-user` Edge Function. Apply the migration after T26, then deploy
the function:

```powershell
supabase db push
supabase functions deploy admin-purge-user
```

The function verifies the caller's Auth JWT and `app_admins` membership. Its
service-only RPCs recheck that the target is not an administrator and has been
continuously suspended for at least 30 days. The operation first deletes all
current cloud business tables in dependency order, then permanently deletes the
Auth identity through the Auth Admin API, and records a completed receipt bound
to the old UUID. A pending operation never counts as a receipt. Retries resume
the same pending purge so an Auth API or completion-recording failure cannot
tell a device to clean its cache early. Restoration is blocked while a purge
is pending.

The public `user_purge_receipt` RPC returns only a completed receipt's old UUID
and completion time; it does not return email or business data. Offline devices
use that response to clean only local rows whose owner UUID matches. Ordinary
authentication, authorization, and network errors do not authorize local
cleanup. The old UUID receipt remains after Auth deletion; fresh registration
with the same email requires an explicit new administrator grant and consumes
eligibility for a different Auth UUID.

Run the rollback-only purge probe only against an isolated Supabase project
containing an administrator and two non-administrator email users. It inserts
business rows, simulates hard Auth deletion inside a transaction, checks the
receipt, business-data cascade, old-UUID rejection, and fresh eligibility, then
rolls back:

```powershell
supabase db query --linked -f supabase/tests/user_purge_access.sql
```

## Manual whole-data cloud sync — 2026-10-04

Apply `202610040001_cloud_business_snapshots.sql` and
`202610040002_cloud_snapshot_conflict_http_status.sql` before running the new
client's manual cloud sync. The client uses `cloud_business_snapshots` to
inspect/download the current user's whole business snapshot and
`save_cloud_business_snapshot` to upload with an expected revision. A stale
revision fails without replacing the cloud copy. Startup, foreground recovery,
connectivity restoration, and ordinary edits no longer transfer business data.

The table is private to its owning authenticated User; upload authorization
checks the current server-controlled lifecycle state. Snapshots exclude local
device settings, authentication, and administrator-controlled lifecycle state.
The new migration also makes explicit purge remove the snapshot.

For source hardware metadata, apply
`202610240001_cloud_snapshot_device_metadata.sql`. It adds nullable
`device_manufacturer` / `device_model` columns and trailing optional RPC
parameters, preserving calls from older snapshot clients. Existing rows remain
unknown; the client keeps their original device name and upload timestamp.
Android supplies brand/model and Windows supplies BIOS manufacturer/product
name, without serial numbers. Before this migration is applied, the new client
can still inspect and download old snapshots using their original columns;
uploading hardware metadata requires the new RPC contract. When PostgREST returns
`PGRST202` and its hint explicitly names an older snapshot RPC signature, the
client retries once with exactly that signature — dropping `p_request_id` first
and the two optional hardware fields if that is still too new — preserving the
payload, expected revision, and legacy token. Other errors do not trigger this
fallback.
This is a deployment
instruction, not evidence that the shared project has been migrated.

Run `supabase/tests/cloud_business_snapshots.sql` in an isolated test
project after applying the migration. Client tests do not prove deployed RLS
or a successful Android/Windows transfer. Migration preparation is distinct
from applying it to a live project.

If an existing User has legacy cloud records but no whole-data snapshot, the
manual preview reads a single legacy-record RPC and converts those records in
an isolated temporary local store. The UI marks original source/upload
metadata as unknown. A content token prevents uploading over a legacy preview
that changed. After the first whole-data snapshot exists, legacy business-table
write guards reject older clients; upgrade all devices. Legacy rows are retained
for historical conversion evidence and removed by explicit purge.

The follow-up migration returns business-version conflicts as `PT409`
(HTTP 409), and retired legacy writes as `PT410` (HTTP 410). Do not raise
`40001` for an expected stale preview: PostgREST treats it as a transient
serialization failure and retries the transaction. See the
[Supabase troubleshooting note](https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b).

Both snapshot migrations were applied to the configured development project
on 2026-10-04. Live acceptance used isolated temporary identities, not normal
users' data. Full results are in
[the validation record](../docs/manual-cloud-sync-validation-20261004.md).
## Retained cloud snapshot history — 2026-11-13

Apply `202611130001_cloud_snapshot_history.sql` for the 15-version retained
backup history. It adds `cloud_business_snapshot_history` (read-only to
authenticated owners through RLS, newest row included), backfills the current
`cloud_business_snapshots` row so no existing snapshot is lost, and replaces
`save_cloud_business_snapshot` so every successful write also lands a history
row and then evicts the oldest beyond 15 — all inside one transaction, after
the new version was written.

The replacement keeps the previous optional parameters defaulted, so clients
that still call the 7- or 9-parameter contract keep working and are subject to
the same retention and compare-and-swap guards; there is no unprotected write
path. The new trailing `p_request_id` makes upload retries idempotent through a
separate ledger table, `cloud_business_snapshot_upload_requests`, which stores
only the request identity, the revision it produced and a payload fingerprint —
no business payload — and is not subject to the 15-version limit. A retry with
the same user and request id therefore returns that request's own retained
version, never the current one; returning the current version would let one
device record another device's newer data as handled. Reusing a request id for
different data fails with `PT422`; a retry whose original version retention has
already evicted fails with `PT425` instead of being written again as a new
request. The client refuses to fall back to a signature without `p_request_id`
when a request id is present — it reports that the service must be upgraded —
and only manual uploads without a request id use the older 9- or 7-parameter
fallback.

Explicit purge now deletes the request ledger and the history table before the
snapshot, so account clearing leaves no cloud business copy behind.

Run `supabase/tests/cloud_snapshot_history.sql` in an isolated test project
after applying this migration. It needs one administrator identity and one
non-administrator identity and skips nothing: identity selection, seeding and
result assertions run in the trusted session, while the authenticated role is
used only for the RLS and compare-and-swap checks, so the script never reads
`auth.users` as a client role. It asserts the retention limit, that a rejected
write leaves no history row, that a retried request returns its own version after
another device wrote a newer one, `PT422`/`PT425` handling, owner read access
without direct writes, ledger privacy, cross-user isolation, and that the purge
function covers history and the request ledger. The purge probe suspends and
clears a real non-admin test identity before asserting that no cloud backup or
ledger row survives. Client tests in `test/sync/` use in-memory remotes and a
temporary Drift database, so they do not prove deployed RLS or a real transfer.
Migration preparation is not evidence that any project has been migrated.