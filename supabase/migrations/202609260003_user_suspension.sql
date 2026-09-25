-- Ticket T26: suspend and restore registered users without purging data.

create table if not exists public.user_suspension_periods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  suspended_at timestamptz not null default now(),
  suspended_by uuid references auth.users(id) on delete set null,
  restored_at timestamptz,
  restored_by uuid references auth.users(id) on delete set null,
  constraint user_suspension_periods_restore_after_suspend
    check (restored_at is null or restored_at >= suspended_at)
);

create unique index if not exists user_suspension_periods_one_current_idx
  on public.user_suspension_periods(user_id)
  where restored_at is null;

create index if not exists user_suspension_periods_user_suspended_at_idx
  on public.user_suspension_periods(user_id, suspended_at desc);

alter table public.user_suspension_periods enable row level security;
revoke all on table public.user_suspension_periods from public, anon, authenticated;

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
    );
$$;

create or replace function public.current_user_lifecycle_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  current_period public.user_suspension_periods;
  checked_time timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;

  select * into current_period
  from public.user_suspension_periods as suspension
  where suspension.user_id = auth.uid()
    and suspension.restored_at is null
  order by suspension.suspended_at desc
  limit 1;

  return jsonb_build_object(
    'is_suspended', current_period.id is not null,
    'suspended_at', current_period.suspended_at,
    'purge_eligible_at', current_period.suspended_at + interval '30 days',
    'is_eligible_for_purge',
      current_period.id is not null
      and checked_time >= current_period.suspended_at + interval '30 days',
    'checked_at', checked_time
  );
end;
$$;

create or replace function public.admin_list_user_lifecycles()
returns table (
  user_id uuid,
  email text,
  created_at timestamptz,
  is_suspended boolean,
  suspended_at timestamptz,
  restored_at timestamptz,
  purge_eligible_at timestamptz,
  is_eligible_for_purge boolean
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
begin
  if not public.is_app_admin() then
    raise exception 'administrator privileges required' using errcode = '42501';
  end if;

  return query
  select
    account.id,
    account.email::text,
    account.created_at,
    coalesce(latest.restored_at is null and latest.suspended_at is not null, false),
    latest.suspended_at,
    latest.restored_at,
    latest.suspended_at + interval '30 days',
    latest.restored_at is null
      and latest.suspended_at is not null
      and now() >= latest.suspended_at + interval '30 days'
  from auth.users as account
  left join lateral (
    select period.suspended_at, period.restored_at
    from public.user_suspension_periods as period
    where period.user_id = account.id
    order by period.suspended_at desc
    limit 1
  ) as latest on true
  order by account.created_at desc, account.id;
end;
$$;

create or replace function public.admin_suspend_user(p_user_id uuid)
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
    select 1 from public.user_suspension_periods as suspension
    where suspension.user_id = p_user_id and suspension.restored_at is null
  ) then
    return;
  end if;

  insert into public.user_suspension_periods(user_id, suspended_by)
  values (p_user_id, auth.uid());
end;
$$;

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

  update public.user_suspension_periods
  set restored_at = now(), restored_by = auth.uid()
  where user_id = p_user_id and restored_at is null;
end;
$$;

revoke all on function public.current_user_is_active() from public;
revoke all on function public.current_user_lifecycle_status() from public;
revoke all on function public.admin_list_user_lifecycles() from public;
revoke all on function public.admin_suspend_user(uuid) from public;
revoke all on function public.admin_restore_user(uuid) from public;
grant execute on function public.current_user_is_active() to authenticated;
grant execute on function public.current_user_lifecycle_status() to authenticated;
grant execute on function public.admin_list_user_lifecycles() to authenticated;
grant execute on function public.admin_suspend_user(uuid) to authenticated;
grant execute on function public.admin_restore_user(uuid) to authenticated;

-- RLS remains the authority when a client is stale or attempts a direct write.
do $suspension_write_policies$
declare
  business_table text;
begin
  foreach business_table in array array[
    'goals',
    'tasks',
    'focus_sessions',
    'focus_nodes',
    'focus_chain_records',
    'focus_appointments',
    'appointment_chain_records',
    'focus_precedent_rules',
    'focus_sync_sources',
    'calendar_sources',
    'calendar_blocks'
  ] loop
    execute format(
      'drop policy if exists %I on public.%I',
      'active users may insert business data', business_table
    );
    execute format(
      'create policy %I on public.%I as restrictive for insert to authenticated with check (public.current_user_is_active())',
      'active users may insert business data', business_table
    );

    execute format(
      'drop policy if exists %I on public.%I',
      'active users may update business data', business_table
    );
    execute format(
      'create policy %I on public.%I as restrictive for update to authenticated using (public.current_user_is_active()) with check (public.current_user_is_active())',
      'active users may update business data', business_table
    );

    execute format(
      'drop policy if exists %I on public.%I',
      'active users may delete business data', business_table
    );
    execute format(
      'create policy %I on public.%I as restrictive for delete to authenticated using (public.current_user_is_active())',
      'active users may delete business data', business_table
    );
  end loop;
end;
$suspension_write_policies$;

comment on table public.user_suspension_periods is
  'Suspension history only. Day 30 marks purge eligibility; this migration does not purge users or business data.';
