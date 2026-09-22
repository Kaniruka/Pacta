-- Ticket T01: keep email eligibility validation stable across SQL publishing
-- paths. Avoid a backslash-dependent regex because dashboard/API publishing
-- can double-escape it before PostgreSQL evaluates the function body.

create or replace function public.admin_grant_registration_eligibility(
  p_identifier text,
  p_identifier_type text
)
returns public.registration_eligibility
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  result public.registration_eligibility;
  normalized text := public.normalize_registration_identifier(p_identifier);
  local_part text := split_part(normalized, '@', 1);
  domain_part text := split_part(normalized, '@', 2);
begin
  if not public.is_app_admin() then
    raise exception 'administrator privileges required' using errcode = '42501';
  end if;
  if coalesce(p_identifier_type, '') <> 'email'
     or normalized = ''
     or length(normalized) - length(replace(normalized, '@', '')) <> 1
     or local_part = ''
     or domain_part = ''
     or strpos(domain_part, '.') <= 1
     or right(domain_part, 1) = '.'
     or normalized ~ '[[:space:]]' then
    raise exception 'email registration eligibility required';
  end if;

  insert into public.registration_eligibility(identifier, identifier_type)
  values (normalized, 'email')
  on conflict (identifier_type, identifier) do update
    set revoked_at = case
      when registration_eligibility.used_at is null then null
      else registration_eligibility.revoked_at
    end
  returning * into result;
  return result;
end;
$$;

revoke all on function public.admin_grant_registration_eligibility(text, text)
from public;
grant execute on function public.admin_grant_registration_eligibility(text, text)
to authenticated;

-- The auth.users row must exist before used_user_id can satisfy its foreign key.
-- The AFTER trigger remains transactional: raising here rolls back the auth row.
create or replace function public.consume_registration_eligibility()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  identifier_value text;
  consumed_id uuid;
begin
  -- Trusted service-role creation is used for administrator bootstrap and
  -- controlled identity migration; it does not represent public registration.
  if current_setting('request.jwt.claim.role', true) = 'service_role' then
    return new;
  end if;

  if new.email is null or public.normalize_registration_identifier(new.email) = '' then
    raise exception 'email registration required' using errcode = 'P0001';
  end if;

  identifier_value := public.normalize_registration_identifier(new.email);

  update public.registration_eligibility
  set used_at = now(), used_user_id = new.id
  where identifier = identifier_value
    and identifier_type = 'email'
    and used_at is null
    and revoked_at is null
  returning id into consumed_id;

  if consumed_id is null then
    raise exception 'registration eligibility required' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists require_registration_eligibility on auth.users;
create trigger require_registration_eligibility
  after insert on auth.users
  for each row execute function public.consume_registration_eligibility();

revoke all on function public.consume_registration_eligibility() from public;
grant execute on function public.consume_registration_eligibility() to postgres;
