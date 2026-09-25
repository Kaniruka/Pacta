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
confirm one unique email for each user, then update that same Auth user by ID
with a trusted server operation. Verify the email login and only then remove
the phone login path. The operation must never be run from Flutter and must
never expose a `service_role` key.

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
