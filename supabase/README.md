# Supabase setup for Ticket T01

For Issue #57's independent read-only National Focus MCP authorization,
deployment and contracts, see [the MCP runbook](functions/national-focus-mcp/README.md).

The Flutter client only receives `SUPABASE_URL` and the publishable/anon key.
A local `.env` may also enable `SUPABASE_SECRET_KEY` for the project-owner CLI
and `SUPABASE_ACCESS_TOKEN` (Personal Access Token) for the Supabase CLI and
the acceptance scripts; never pass that file to `--dart-define-from-file` or
any client release build.

Apply the migration with the Supabase CLI or the SQL editor. Administration has
no separate role, table or RPC: the project owner manages every account with
the local CLI [`scripts/pacta_admin.py`](../scripts/pacta_admin.py), which reads
`SUPABASE_URL` and `SUPABASE_SECRET_KEY` from the process environment or the
repository `.env` and calls GoTrue Admin / PostgREST directly.

The previous administrative schema is gone from both the repository and the
cloud project: the administrator membership table, `is_app_admin()`, every
`admin_*` RPC, the operator audit columns on suspensions and purge receipts,
and the `admin-reset-user-password` / `admin-purge-user` Edge Functions were
all removed. No migration recreates them; a stale reference to any of those
names is a regression, not a compatibility path.

Registration eligibility is written directly through PostgREST, with no
administrator-gated RPC in the path:

```sql
insert into public.registration_eligibility (identifier, identifier_type)
values ('person@example.com', 'email');

update public.registration_eligibility
set revoked_at = now()
where identifier = 'person@example.com' and used_at is null;
```

The `auth.users` trigger consumes an unused, unrevoked eligibility in the
same database transaction as registration. A race or duplicate registration
therefore cannot consume one qualification twice. The trigger bypasses only
trusted `service_role` creation, which the project-owner CLI uses when it
creates a user.

## Email-only registration

The application uses email and password for registration and login. The
`registration_eligibility` table accepts email identifiers only. Its
`auth.users` trigger requires an email and consumes an unused, unrevoked
eligibility in the same transaction. The email-only constraint is applied by
`20260926120000_email_only_registration_schema.sql`.

Email Auth and user signups are enabled in the cloud project; the database
eligibility trigger limits successful registration to approved addresses.
Email confirmation is disabled because the App does not send verification
messages. Password resets are handled by the project owner after manual
identity verification.

## Project-owner password reset

The project owner resets any user's password from the local CLI through the
GoTrue Auth Admin API (`PUT /auth/v1/admin/users/{uid}` with `password`). No
administrator JWT or permission table is involved, and the existing `user_id`
plus all business-data ownership stay unchanged.

The operator confirms that identity was checked outside the App and must tell
the user the new password through a secure external channel. The App sends no
account messages and does not claim to validate email ownership. The CLI never
prints the new password, and Supabase Auth applies its own credential storage.

The legacy `admin-reset-user-password` Edge Function (Ticket T25) was removed
from the repository and the project together with the rest of the
administrative surface. The CLI is the only password-reset path, and no
`admin-*` function is deployed any more.

## User suspension

Ticket T26 adds `202609260003_user_suspension.sql`. Apply it after the preceding
business-data migrations. It adds a signed-in user status RPC and restrictive
write policies for business tables; it never deletes users or business data.
A suspension becomes eligible for purge after 30 days, but this ticket does
not perform a purge. Restoring a user ends that suspension period, and a later
suspension starts a new 30-day period.

The client stores the last server lifecycle status locally. Once it knows the
user is suspended, it blocks new business writes and keeps pending local data
for retry after restoration. A device with no known suspension status remains
available for offline work until it next checks with the server.

The rollback-only server access probe only needs one or two active registered
users in an isolated test project. It checks business-write denial, retained
data, day-30 eligibility, and restoration/re-suspension behavior, then rolls
back its test changes:

```powershell
supabase db query --linked -f supabase/tests/user_suspension_access.sql
```

## Explicit cloud purge

Ticket T27 adds `20260926075712_user_purge.sql`. The current contracts
`purge_user_business_data(p_user_id)` and `complete_user_purge(p_user_id)`
replace the old administrator-gated functions, which no longer exist. The
project-owner CLI performs the database contract directly, without any Edge
Function:

1. Confirm the target and type its email (or UUID) verbatim.
2. Insert or reuse a `user_purge_receipts` row as `pending`, binding the
   consumed `registration_eligibility` row when one exists. The receipt table
   records only its own user, eligibility, status and timestamps.
3. Call `purge_user_business_data(p_user_id)` to delete the legacy business
   tables in dependency order.
4. Call `DELETE /auth/v1/admin/users/{uid}` through the Auth Admin API.
5. Call `complete_user_purge(p_user_id)`; the receipt becomes `completed` and
   `registration_eligibility.purge_completed_at` is filled so the email can be
   granted again.

This path accepts active, never-suspended users, because no waiting-period or
role guard exists any more. A completed receipt is idempotent; a pending
receipt is reused so an Auth API or completion failure does not tell a device
to clean its cache early.

The public `user_purge_receipt` RPC returns only a completed receipt's old UUID
and completion time; it does not return email or business data. Offline devices
use that response to clean only local rows whose owner UUID matches. Ordinary
authentication, authorization, and network errors do not authorize local
cleanup. The old UUID receipt remains after Auth deletion; fresh registration
with the same email requires an explicit new project-owner grant and consumes
eligibility for a different Auth UUID.

Run the rollback-only purge probe only against an isolated Supabase project
containing two active registered email users. It inserts business rows,
simulates hard Auth deletion inside a transaction, checks the receipt,
business-data cascade, old-UUID rejection, and fresh eligibility, then rolls
back:

```powershell
supabase db query --linked -f supabase/tests/user_purge_access.sql
```

## Testing-phase immediate purge — Ticket 03

`202611220001_admin_immediate_purge.sql` and the `admin_begin_user_purge` RPC
it modified were removed with the rest of the administrative surface. Nothing
is left that could only purge after a continuous suspension or a 30-day wait,
so the project-owner CLI no longer needs a skip flag to purge an active target.
Pending and completed receipts stay idempotent.

`delete-user` prepares the pending receipt itself and therefore removes any
target immediately: active users, never-suspended users and previously
suspended ones behave the same way. No Edge Function and no boolean flag take
part in that decision.

Registration eligibility and the receipt ledger behave exactly as before, so an
immediate purge still records the pending receipt, removes the cloud business
data, deletes the Auth identity, and only then writes a completed receipt.

Deploy the database functions only:

```powershell
supabase db push
```

The rollback-only probe `supabase/tests/user_purge_access.sql` now also checks
that `authenticated` and `anon` cannot execute `purge_user_business_data` or
`complete_user_purge`, that an active target enters `pending`, that a five-day
suspension behaves the same way, and that the service-role grant accepts both
functions. The immediate block runs inside a savepoint and is rolled back
before the original T27 flow.

## Project-owner terminal tool

`scripts/pacta_admin.py` is a standard-library-only Python 3 tool for Windows
PowerShell. It is a **project-owner direct client**: it reads `SUPABASE_URL`
and `SUPABASE_SECRET_KEY` from the process environment or the repository
`.env`, then calls GoTrue Admin and PostgREST directly. It never asks for an
account email or password, never parses a user JWT, and never checks a
permission table.

Request headers follow the Supabase key rules:

- `sb_secret_...` (opaque secret key, not a three-part JWT) is sent only in
  `apikey`. Sending it in `Authorization: Bearer` makes the gateway / GoTrue
  reject the request as an invalid JWT.
- A legacy `service_role` JWT (three dot-separated parts) is sent in both
  `apikey` and `Authorization: Bearer <key>`.

Configuration:

- `--env-file` defaults to the repository root `.env`. Process environment
  variables win; the file only fills missing values. Only `SUPABASE_URL` and
  `SUPABASE_SECRET_KEY` (or the legacy `SUPABASE_SERVICE_ROLE_KEY`) are read.
  `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_ANON_KEY` and `SUPABASE_ACCESS_TOKEN`
  (Supabase CLI / acceptance-script only) are ignored.
- A missing or blank URL/key stops with exit code 2 and names the Supabase
  Dashboard -> Project Settings -> API Keys location; the value is never
  printed.
- A secret key is never written to source, output, JSON, logs or files.

Run without arguments to enter the numeric menu (0 exits, 1-11 are the
capabilities below). Every subcommand also accepts `--json` and `--yes`; in
JSON mode, commands that would otherwise prompt (suspend, restore,
reset-password, delete-user, clear-cloud-data) require an explicit `--yes`
so the output stays machine-readable:

```powershell
python scripts/pacta_admin.py
python scripts/pacta_admin.py users [--filter TEXT] [--json]
python scripts/pacta_admin.py create-user person@example.com [--password ...] [--nickname 小明] [--no-eligibility]
python scripts/pacta_admin.py eligibilities [--filter TEXT]
python scripts/pacta_admin.py grant person@example.com [--note ...]
python scripts/pacta_admin.py revoke person@example.com
python scripts/pacta_admin.py suspend person@example.com [--yes]
python scripts/pacta_admin.py restore person@example.com [--yes]
python scripts/pacta_admin.py reset-password person@example.com [--password ...] [--yes]
python scripts/pacta_admin.py delete-user person@example.com [--yes]
python scripts/pacta_admin.py cloud-data [person@example.com] [--json]
python scripts/pacta_admin.py clear-cloud-data person@example.com [--yes]
```

`users` pages through `GET /auth/v1/admin/users` and joins
`profile_accounts`, `registration_eligibility`, `user_suspension_periods`,
`cloud_business_snapshots` (latest revision / schema / row count),
`cloud_business_snapshot_history`, `cloud_business_snapshot_upload_requests`
and `national_focus_mcp_grants`. `create-user` ensures a
`registration_eligibility` row by default and writes the nickname to
`profile_accounts`.

`suspend` inserts an active `user_suspension_periods` row and sets a long
GoTrue `ban_duration`; `restore` ends the active period and clears the ban.
`reset-password` uses the Auth Admin `PUT` endpoint.

`delete-user` always asks the operator to type the target email (or UUID when
the account has none) in full, case-insensitively; `--yes` skips only that
prompt. It performs the four-step purge documented above and works for every
active account.

`clear-cloud-data` deletes only the snapshot, history and upload-ledger rows;
the Auth identity, `profile_accounts` row and registration eligibility remain.

Tests never touch a network, a real project-owner key or the workspace `.env`:
`python -m unittest discover -s scripts -p "test_*.py" -v` runs the
fake-transport suite in `scripts/test_pacta_admin.py`.

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
device settings, authentication, and server-controlled lifecycle state.
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
users' data.

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
after applying this migration. It needs two active registered users and skips
nothing: identity selection, seeding and result assertions run in the trusted
session, while the authenticated role is used only for the RLS and
compare-and-swap checks, so the script never reads
`auth.users` as a client role. It asserts the retention limit, that a rejected
write leaves no history row, that a retried request returns its own version after
another device wrote a newer one, `PT422`/`PT425` handling, owner read access
without direct writes, ledger privacy, cross-user isolation, and that the purge
function covers history and the request ledger. The purge probe suspends and
clears a real registered test identity before asserting that no cloud backup or
ledger row survives. Client tests in `test/sync/` use in-memory remotes and a
temporary Drift database, so they do not prove deployed RLS or a real transfer.
Migration preparation is not evidence that any project has been migrated.


## Account profile and avatar — 2026-11-13

Apply `202611130002_profile_account.sql` for Issue #94. The account display
name and one bounded avatar binary live in `public.profile_accounts`, never in
`cloud_business_snapshots`, so restoring a business snapshot cannot rewind the
profile. Clients reach it only through two owner-scoped RPCs:

- `read_profile_account()` returns the caller's profile, or null when none is
  stored.
- `save_profile_account(display_name, avatar_base64, clear_avatar)` trims the
  name, decodes at most 256 KB, verifies the PNG/JPEG signature, and upserts the
  caller's own row. Passing no avatar keeps the stored binary; `clear_avatar`
  removes it.

RLS is enabled with owner-only, active-user policies, and the table grants no
direct privileges to `anon` or `authenticated`. Avatar binaries are limited to
256 KB and must match their declared image signature; there is no public avatar
URL or shared bucket. The row references `auth.users(id) on delete cascade`, so
an explicit account purge removes the profile and its avatar with the identity.
This migration deliberately does not replace `purge_user_business_data()`;
the backup/history migration extends that function, and the FK keeps both
migrations composable.

Run the rollback-only probe against an isolated project after applying the
migration. It needs two signed-in users, rejects non-image and oversized
avatars, checks cross-user reads and direct table access, and verifies the
identity cascade:

```powershell
supabase db query --linked -f supabase/tests/profile_accounts.sql
```

Client tests cover local caching, retry after a failed account write,
cross-device adoption, and unchanged profile after a business restore. They do
not prove deployed RLS.

## Account display time zone — 2026-11-15

Apply `202611150002_account_time_zone.sql` for the account-time-zone ticket.
The display time zone is account-level: one value per account, shared by every
device, stored on the same `public.profile_accounts` row and still excluded
from `cloud_business_snapshots`. There is no device-level override and no
second business store.

- `read_profile_account()` now also returns `timeZoneId` (null until
  recorded) and the account's server-owned `timeZoneRevision`.
- `initialize_profile_time_zone(time_zone_id)` is the atomic first migration.
  Two devices may both read "no value"; the database decides one winner with
  `coalesce(existing, new)` and every caller reads the stored winner back. When
  the account has no profile row, this RPC inserts it with an empty
  `display_name` — an unset nickname, not a fabricated name — so the time zone
  can exist before the person picks a nickname. Only a still-null account value
  is ever filled, and the value must be an IANA identifier from the server's own
  catalog.
- `save_profile_account(display_name, avatar_base64, clear_avatar,
  time_zone_id, time_zone_revision)` keeps the stored time zone when the zone
  argument is omitted, so a nickname/avatar edit never re-asserts a cached
  device value. An explicit zone must name the revision the choice is based on:
  the write applies only while that revision is still current, so a late request
  cannot replace a newer accepted value and no ordering depends on a device
  clock. A superseded request returns the stored winner with
  `"timeZoneConflict": true`; the client adopts it and a later explicit edit
  uses the current revision. A blank display name is accepted only when the
  stored name is already unset and the call carries a time zone: it never clears
  an existing nickname and never creates a profile row.
- `time_zone_revision` is written only by these RPCs and only advances on an
  accepted change; `time_zone_updated_at` records when the current value was
  accepted, in server time, for audit and never for ordering.
- Both RPCs take an account-scoped `pg_advisory_xact_lock` before deciding
  anything. An existing row is already serialized by `SELECT ... FOR UPDATE`,
  but a missing row cannot be locked that way: two first writers could both read
  "absent" and the later upsert would apply a stale decision over the winner.
  The lock serializes first save/first save, first save/initialize and
  initialize/initialize for the same account.

The legacy three-argument call form remains valid through parameter defaults and
never touches the stored time zone or its revision. The old five-argument
signature with a client-supplied request time is dropped rather than kept next to
the new one, because PostgREST resolves RPCs by name and two overloads would make
the same call ambiguous. RLS, owner-scoped RPCs, the active-user checks and the
`auth.users` cascade are unchanged, so an explicit purge still removes the row
and its time zone with the identity.

The rollback-only probe now also covers: initialization creating an
empty-nickname row, a second device adopting the stored winner, a time-zone-only
save keeping an unset name, a stale revision being refused and reported as a
conflict, a nickname-only (including legacy three-argument) save keeping the zone,
a blank name failing to clear an existing nickname, a missing revision being
rejected, and invalid IANA identifiers being rejected by both RPCs. The
real-service probe exercises
true concurrent first save/first save, first save/initialize and
initialize/initialize requests, because one session cannot prove that race.

```powershell
supabase db query --linked -f supabase/tests/profile_accounts.sql
```

Local tests cover repository revision semantics, true simultaneous first
migration, future-clock independence and app-level display; the real-service
probe `integration_test/profile_time_zone_real_service_test.dart` covers
cross-client initialization, revision conflicts, isolation and offline recovery
against the isolated project, and is host-run.
