-- Ticket T25: expose an Auth user ID lookup only to trusted server code.
-- Password mutation itself stays in the Auth Admin API inside an Edge Function.
create or replace function public.admin_resolve_auth_user_id_by_email(
  p_email text
)
returns uuid
language sql
security definer
set search_path = pg_catalog
as $$
  select users.id
  from auth.users as users
  where pg_catalog.lower(pg_catalog.btrim(users.email)) =
    pg_catalog.lower(pg_catalog.btrim(p_email))
  limit 1;
$$;

revoke all on function public.admin_resolve_auth_user_id_by_email(text)
  from public, anon, authenticated;
grant execute on function public.admin_resolve_auth_user_id_by_email(text)
  to service_role;
