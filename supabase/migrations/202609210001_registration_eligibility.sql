-- Ticket T01: administrator-issued registration eligibility.
-- The client only receives the publishable key. All writes below are
-- protected by auth.uid() and the service role is required for bootstrap.

create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.registration_eligibility (
  id uuid primary key default gen_random_uuid(),
  identifier text not null,
  identifier_type text not null check (identifier_type = 'email'),
  used_at timestamptz,
  used_user_id uuid unique references auth.users(id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint registration_eligibility_identifier_key unique (identifier_type, identifier)
);

create or replace function public.normalize_registration_identifier(value text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$ select lower(btrim(value)); $$;

create or replace function public.is_app_admin()
returns boolean
language sql
security definer
set search_path = public, pg_catalog
as $$
  select exists (
    select 1 from public.app_admins where user_id = auth.uid()
  );
$$;

alter table public.app_admins enable row level security;
alter table public.registration_eligibility enable row level security;

drop policy if exists "admins can view admins" on public.app_admins;
create policy "admins can view admins" on public.app_admins
  for select to authenticated using (public.is_app_admin());

drop policy if exists "admins can view eligibility" on public.registration_eligibility;
create policy "admins can view eligibility" on public.registration_eligibility
  for select to authenticated using (public.is_app_admin());

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
begin
  if not public.is_app_admin() then
    raise exception 'administrator privileges required' using errcode = '42501';
  end if;
  if coalesce(p_identifier_type, '') <> 'email'
     or normalized = ''
     or normalized !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'email registration eligibility required';
  end if;

  insert into public.registration_eligibility(identifier, identifier_type)
  values (normalized, p_identifier_type)
  on conflict (identifier_type, identifier) do update
    set revoked_at = case
      when registration_eligibility.used_at is null then null
      else registration_eligibility.revoked_at
    end
  returning * into result;
  return result;
end;
$$;

create or replace function public.admin_revoke_registration_eligibility(
  p_identifier text,
  p_identifier_type text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  changed_count integer;
begin
  if not public.is_app_admin() then
    raise exception 'administrator privileges required' using errcode = '42501';
  end if;
  if coalesce(p_identifier_type, '') <> 'email' then
    raise exception 'email registration eligibility required';
  end if;
  update public.registration_eligibility
  set revoked_at = now()
  where identifier = public.normalize_registration_identifier(p_identifier)
    and identifier_type = p_identifier_type
    and used_at is null;
  get diagnostics changed_count = row_count;
  return changed_count > 0;
end;
$$;

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
  -- does not represent public registration.
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
  before insert on auth.users
  for each row execute function public.consume_registration_eligibility();

revoke all on function public.admin_grant_registration_eligibility(text, text) from public;
revoke all on function public.admin_revoke_registration_eligibility(text, text) from public;
grant execute on function public.admin_grant_registration_eligibility(text, text) to authenticated;
grant execute on function public.admin_revoke_registration_eligibility(text, text) to authenticated;
