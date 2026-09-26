# Supabase setup for Ticket T01

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

## Email-only migration

`202609220002_email_only_registration.sql` stops new phone registrations and
revokes unused phone eligibility while preserving historical phone eligibility
rows and existing `auth.users` identities. Apply it before disabling Phone Auth
in the Supabase dashboard.

`202609220003_fix_email_eligibility_validation.sql` tightens the email-only
grant validation and recreates the eligibility trigger as `AFTER INSERT` so
`used_user_id` satisfies its foreign key to the newly created Auth user while
remaining part of the same transaction.

Do not create replacement users for existing phone-only users. First produce a
server-side inventory of users whose `auth.users.email` is null, collect and
confirm one unique email for each user, then deploy and call the trusted
`admin-migrate-phone-identity` Edge Function for that exact `user_id`. The
function authenticates the administrator, rejects identities that are not
phone-only or have a purge receipt, and updates the existing Auth user by ID.
It marks the operator-verified email confirmed without creating another user
or consuming registration eligibility. Verify email login and business-data
ownership on the same `user_id` before disabling the phone login path. The
operation must never be run from Flutter and must never expose a `service_role`
key.

Deploy the function after the email-only registration migration. Invoke it with
an administrator access token and explicit confirmation that the unique email
was verified outside the App:

```powershell
supabase functions deploy admin-migrate-phone-identity
```

Request body:

```json
{
  "user_id": "AUTH_USER_UUID",
  "email": "person@example.com",
  "email_manually_verified": true
}
```

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
no email or SMS and does not claim to validate email ownership. No user or
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

Ticket T27 adds `202609260004_user_purge.sql` and the
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
