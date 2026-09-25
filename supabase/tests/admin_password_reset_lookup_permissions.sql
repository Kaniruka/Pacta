-- Verify that only trusted server code can resolve an Auth user by email.
-- Run after applying 202609260002_admin_password_reset_target_lookup.sql.
do $permissions$
declare
  lookup_function regprocedure :=
    'public.admin_resolve_auth_user_id_by_email(text)'::regprocedure;
begin
  if has_function_privilege('anon', lookup_function, 'EXECUTE') then
    raise exception 'anonymous_role_can_resolve_auth_user_email';
  end if;
  if has_function_privilege('authenticated', lookup_function, 'EXECUTE') then
    raise exception 'authenticated_role_can_resolve_auth_user_email';
  end if;
  if not has_function_privilege('service_role', lookup_function, 'EXECUTE') then
    raise exception 'service_role_cannot_resolve_auth_user_email';
  end if;
end
$permissions$;
