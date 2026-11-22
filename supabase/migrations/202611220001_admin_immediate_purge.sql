-- Ticket 03: testing-phase immediate explicit purge.
--
-- The 30-day suspension window stays the production rule. During the testing
-- phase an administrator may start the same explicit purge immediately by
-- setting p_skip_waiting_period = true; the Edge Function exposes that as an
-- optional "immediate" boolean and keeps the default strict.
--
-- The historical two-argument signature is dropped first on purpose.
-- PostgREST resolves RPCs by name: a surviving (uuid, uuid) overload next to
-- (uuid, uuid, boolean) would either make two-argument calls ambiguous or pick
-- an unexpected candidate. The third parameter is defaulted so an old
-- two-argument SQL call keeps its strict 30-day behavior.
--
-- All other boundaries of 20260926075712_user_purge.sql are preserved:
--   * p_admin_id must be in public.app_admins (42501);
--   * an administrator cannot purge their own identity (42501);
--   * the target must exist in auth.users and is locked FOR UPDATE;
--   * another administrator's identity cannot be purged (42501);
--   * a pending/completed receipt is returned idempotently;
--   * the receipt records the consumed registration eligibility and is
--     created or reused from a cancelled row.
-- Only service_role may execute the function.

drop function if exists public.admin_begin_user_purge(uuid, uuid);
drop function if exists public.admin_begin_user_purge(uuid, uuid, boolean);

create or replace function public.admin_begin_user_purge(
  p_user_id uuid,
  p_admin_id uuid,
  p_skip_waiting_period boolean default false
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
  skip_waiting boolean := coalesce(p_skip_waiting_period, false);
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

  -- Testing-phase bypass: only an explicit true skips the continuous
  -- suspension and 30-day wait. NULL and false keep the strict rule.
  if not skip_waiting then
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

revoke all on function public.admin_begin_user_purge(uuid, uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.admin_begin_user_purge(uuid, uuid, boolean)
  to service_role;

comment on function public.admin_begin_user_purge(uuid, uuid, boolean) is
  'Starts a pending purge receipt. p_skip_waiting_period = true is the testing-phase immediate purge and bypasses the continuous 30-day suspension wait; production callers leave it false.';
