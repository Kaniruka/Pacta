-- Ticket T27: explicitly purge an eligible cloud identity and retain the
-- smallest receipt needed by offline devices to clean that old local identity.

alter table public.registration_eligibility
  add column if not exists purge_completed_at timestamptz;

create table if not exists public.user_purge_receipts (
  user_id uuid primary key,
  status text not null check (status in ('pending', 'completed', 'cancelled')),
  requested_at timestamptz not null default now(),
  requested_by uuid references auth.users(id) on delete set null,
  eligibility_id uuid references public.registration_eligibility(id)
    on delete set null,
  business_data_deleted boolean not null default false,
  completed_at timestamptz,
  constraint user_purge_receipts_completed_at_state
    check ((status = 'completed') = (completed_at is not null))
);

alter table public.user_purge_receipts enable row level security;
revoke all on table public.user_purge_receipts from public, anon, authenticated;

comment on table public.user_purge_receipts is
  'Minimal old-UUID purge ledger. user_id intentionally has no auth.users foreign key so offline devices can confirm completed purge after Auth deletion.';

create or replace function public.current_user_is_active()
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select auth.uid() is not null
    and not exists (
      select 1
      from public.user_suspension_periods as suspension
      where suspension.user_id = auth.uid()
        and suspension.restored_at is null
    )
    and not exists (
      select 1
      from public.user_purge_receipts as purge
      where purge.user_id = auth.uid()
        and purge.status in ('pending', 'completed')
    );
$$;

-- A consumed email becomes eligible for a new grant only after its prior
-- identity has a completed purge receipt. Granting again still requires an
-- explicit administrator action.
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
    set used_at = case
          when registration_eligibility.purge_completed_at is not null then null
          else registration_eligibility.used_at
        end,
        used_user_id = case
          when registration_eligibility.purge_completed_at is not null then null
          else registration_eligibility.used_user_id
        end,
        revoked_at = case
          when registration_eligibility.purge_completed_at is not null
            or registration_eligibility.used_at is null then null
          else registration_eligibility.revoked_at
        end,
        purge_completed_at = null
  returning * into result;
  return result;
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
  if exists (
    select 1 from public.user_purge_receipts as purge
    where purge.user_id = new.id and purge.status in ('pending', 'completed')
  ) then
    raise exception 'purged identity cannot be recreated' using errcode = 'P0001';
  end if;

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

create or replace function public.admin_begin_user_purge(
  p_user_id uuid,
  p_admin_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  existing_receipt public.user_purge_receipts;
  current_period public.user_suspension_periods;
  eligibility_row_id uuid;
  result public.user_purge_receipts;
begin
  if not exists (
    select 1 from public.app_admins as administrator
    where administrator.user_id = p_admin_id
  ) then
    raise exception 'administrator privileges required' using errcode = '42501';
  end if;
  if p_admin_id = p_user_id then
    raise exception 'administrator cannot purge their own identity' using errcode = '42501';
  end if;

  select * into existing_receipt
  from public.user_purge_receipts as purge
  where purge.user_id = p_user_id
  for update;
  if found and existing_receipt.status in ('pending', 'completed') then
    return jsonb_build_object(
      'user_id', existing_receipt.user_id,
      'status', existing_receipt.status,
      'purged_at', existing_receipt.completed_at
    );
  end if;

  perform account.id
  from auth.users as account
  where account.id = p_user_id
  for update;
  if not found then
    raise exception 'user does not exist';
  end if;
  if exists (
    select 1 from public.app_admins as administrator
    where administrator.user_id = p_user_id
  ) then
    raise exception 'administrator identity cannot be purged' using errcode = '42501';
  end if;

  select * into current_period
  from public.user_suspension_periods as suspension
  where suspension.user_id = p_user_id
    and suspension.restored_at is null
  order by suspension.suspended_at desc
  limit 1
  for update;
  if not found or now() < current_period.suspended_at + interval '30 days' then
    raise exception 'user is not eligible for purge' using errcode = '55000';
  end if;

  select eligibility.id into eligibility_row_id
  from public.registration_eligibility as eligibility
  where eligibility.used_user_id = p_user_id
  limit 1;

  insert into public.user_purge_receipts (
    user_id, status, requested_at, requested_by, eligibility_id, completed_at
  )
  values (p_user_id, 'pending', now(), p_admin_id, eligibility_row_id, null)
  on conflict (user_id) do update
    set status = 'pending',
        requested_at = now(),
        requested_by = excluded.requested_by,
        eligibility_id = excluded.eligibility_id,
        completed_at = null
  where public.user_purge_receipts.status = 'cancelled'
  returning * into result;

  if not found then
    raise exception 'purge request could not be started';
  end if;

  return jsonb_build_object(
    'user_id', result.user_id,
    'status', result.status,
    'purged_at', result.completed_at
  );
end;
$$;

create or replace function public.admin_cancel_user_purge(
  p_user_id uuid,
  p_admin_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  current_receipt public.user_purge_receipts;
begin
  if not exists (
    select 1 from public.app_admins as administrator
    where administrator.user_id = p_admin_id
  ) then
    raise exception 'administrator privileges required' using errcode = '42501';
  end if;

  select * into current_receipt
  from public.user_purge_receipts as purge
  where purge.user_id = p_user_id
  for update;
  if not found or current_receipt.status <> 'pending' then
    return false;
  end if;
  if current_receipt.business_data_deleted then
    raise exception 'purge has already removed cloud business data'
      using errcode = '55000';
  end if;
  if not exists (select 1 from auth.users as account where account.id = p_user_id) then
    raise exception 'purged identity cannot be restored from a pending receipt'
      using errcode = '55000';
  end if;

  update public.user_purge_receipts
  set status = 'cancelled',
      requested_by = null,
      eligibility_id = null,
      completed_at = null
  where user_id = p_user_id;
  return true;
end;
$$;

create or replace function public.admin_delete_user_business_data(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  current_receipt public.user_purge_receipts;
begin
  select * into current_receipt
  from public.user_purge_receipts as purge
  where purge.user_id = p_user_id
  for update;
  if not found or current_receipt.status <> 'pending' then
    raise exception 'purge request is not pending' using errcode = '55000';
  end if;
  if current_receipt.business_data_deleted then
    return;
  end if;
  if not exists (select 1 from auth.users as account where account.id = p_user_id) then
    raise exception 'auth identity is missing before cloud data purge';
  end if;

  -- Remove dependent records first so existing RESTRICT foreign keys between
  -- business tables cannot prevent the Auth Admin API from deleting the user.
  delete from public.calendar_blocks where user_id = p_user_id;
  delete from public.focus_nodes where user_id = p_user_id;
  delete from public.focus_sessions where user_id = p_user_id;
  delete from public.focus_appointments where user_id = p_user_id;
  delete from public.tasks where user_id = p_user_id;
  delete from public.goals where user_id = p_user_id;
  delete from public.focus_chain_records where user_id = p_user_id;
  delete from public.appointment_chain_records where user_id = p_user_id;
  delete from public.focus_precedent_rules where user_id = p_user_id;
  delete from public.focus_sync_sources where user_id = p_user_id;
  delete from public.calendar_sources where user_id = p_user_id;

  update public.user_purge_receipts
  set business_data_deleted = true
  where user_id = p_user_id;
end;
$$;

create or replace function public.admin_complete_user_purge(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  current_receipt public.user_purge_receipts;
  completed_time timestamptz := now();
begin
  select * into current_receipt
  from public.user_purge_receipts as purge
  where purge.user_id = p_user_id
  for update;
  if not found then
    raise exception 'purge request does not exist';
  end if;
  if current_receipt.status = 'completed' then
    return jsonb_build_object(
      'user_id', current_receipt.user_id,
      'status', current_receipt.status,
      'purged_at', current_receipt.completed_at
    );
  end if;
  if current_receipt.status <> 'pending' then
    raise exception 'purge request is not pending' using errcode = '55000';
  end if;
  if not current_receipt.business_data_deleted then
    raise exception 'cloud business data has not been purged' using errcode = '55000';
  end if;
  if exists (select 1 from auth.users as account where account.id = p_user_id) then
    raise exception 'auth identity still exists' using errcode = '55000';
  end if;

  if current_receipt.eligibility_id is not null then
    update public.registration_eligibility
    set purge_completed_at = coalesce(purge_completed_at, completed_time)
    where id = current_receipt.eligibility_id;
  end if;

  update public.user_purge_receipts
  set status = 'completed',
      requested_by = null,
      eligibility_id = null,
      completed_at = completed_time
  where user_id = p_user_id
  returning * into current_receipt;

  return jsonb_build_object(
    'user_id', current_receipt.user_id,
    'status', current_receipt.status,
    'purged_at', current_receipt.completed_at
  );
end;
$$;

-- This lookup contains no email or business data. Offline devices use the
-- previously cached UUID to learn the explicit completed result after the old
-- Auth token is no longer valid.
create or replace function public.user_purge_receipt(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select jsonb_build_object(
    'user_id', purge.user_id,
    'status', purge.status,
    'purged_at', purge.completed_at
  )
  from public.user_purge_receipts as purge
  where purge.user_id = p_user_id
    and purge.status = 'completed';
$$;

-- Serialize restore with the external Auth Admin deletion window.
create or replace function public.admin_restore_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
begin
  if not public.is_app_admin() then
    raise exception 'administrator privileges required' using errcode = '42501';
  end if;

  perform account.id
  from auth.users as account
  where account.id = p_user_id
  for update;
  if not found then
    raise exception 'user does not exist';
  end if;

  if exists (
    select 1 from public.user_purge_receipts as purge
    where purge.user_id = p_user_id and purge.status = 'pending'
  ) then
    raise exception 'user purge is pending' using errcode = '55000';
  end if;

  update public.user_suspension_periods
  set restored_at = now(), restored_by = auth.uid()
  where user_id = p_user_id and restored_at is null;
end;
$$;

revoke all on function public.admin_grant_registration_eligibility(text, text)
  from public;
grant execute on function public.admin_grant_registration_eligibility(text, text)
  to authenticated;
revoke all on function public.consume_registration_eligibility() from public;
grant execute on function public.consume_registration_eligibility() to postgres;

revoke all on function public.admin_begin_user_purge(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.admin_cancel_user_purge(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.admin_delete_user_business_data(uuid)
  from public, anon, authenticated;
revoke all on function public.admin_complete_user_purge(uuid)
  from public, anon, authenticated;
grant execute on function public.admin_begin_user_purge(uuid, uuid)
  to service_role;
grant execute on function public.admin_cancel_user_purge(uuid, uuid)
  to service_role;
grant execute on function public.admin_delete_user_business_data(uuid)
  to service_role;
grant execute on function public.admin_complete_user_purge(uuid)
  to service_role;

revoke all on function public.user_purge_receipt(uuid) from public;
grant execute on function public.user_purge_receipt(uuid)
  to anon, authenticated, service_role;

revoke all on function public.current_user_is_active() from public;
grant execute on function public.current_user_is_active() to authenticated;

revoke all on function public.admin_restore_user(uuid) from public;
grant execute on function public.admin_restore_user(uuid) to authenticated;

comment on function public.user_purge_receipt(uuid) is
  'Returns only the completed purge receipt for the requested old UUID; intentionally omits identity and business data.';
