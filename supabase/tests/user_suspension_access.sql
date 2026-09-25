-- Rollback-only checks for Ticket T26.
-- Run against an isolated Supabase project after applying the migration with:
--   supabase db query --linked -f supabase/tests/user_suspension_access.sql
-- The test requires one isolated administrator and one existing non-admin user,
-- exercises Postgres RLS under authenticated, then rolls every change back.

begin;

do $setup$
declare
  test_admin_id uuid;
  test_non_admin_id uuid;
begin
  select user_id into test_admin_id
  from public.app_admins
  order by user_id
  limit 1;
  if test_admin_id is null then
    raise exception 'an isolated test administrator is required';
  end if;

  select account.id into test_non_admin_id
  from auth.users as account
  where not exists (
    select 1 from public.app_admins as administrator
    where administrator.user_id = account.id
  )
  order by account.created_at desc
  limit 1;
  if test_non_admin_id is null then
    raise exception 'an isolated non-administrator test user is required';
  end if;

  perform set_config('t26.admin_id', test_admin_id::text, true);
  perform set_config('t26.goal_id', gen_random_uuid()::text, true);
  perform set_config('t26.non_admin_id', test_non_admin_id::text, true);
  perform set_config('t26.non_admin_goal_id', gen_random_uuid()::text, true);
end
$setup$;

set local role authenticated;
do $set_admin_claim$
begin
  perform set_config('request.jwt.claim.sub', current_setting('t26.admin_id'), true);
end
$set_admin_claim$;

insert into public.goals (
  id, user_id, title, classification, created_at, updated_at
)
values (
  current_setting('t26.goal_id')::uuid,
  current_setting('t26.admin_id')::uuid,
  'retained while suspended',
  'regular',
  now(),
  now()
);

do $set_non_admin_claim$
begin
  perform set_config('request.jwt.claim.sub', current_setting('t26.non_admin_id'), true);
end
$set_non_admin_claim$;

insert into public.goals (
  id, user_id, title, classification, created_at, updated_at
)
values (
  current_setting('t26.non_admin_goal_id')::uuid,
  current_setting('t26.non_admin_id')::uuid,
  'non-admin data retained while suspended',
  'regular',
  now(),
  now()
);

do $restore_admin_claim$
begin
  perform set_config('request.jwt.claim.sub', current_setting('t26.admin_id'), true);
end
$restore_admin_claim$;

select public.admin_suspend_user(current_setting('t26.non_admin_id')::uuid);

do $non_admin_probe$
begin
  perform set_config('request.jwt.claim.sub', current_setting('t26.non_admin_id'), true);

  if (public.current_user_lifecycle_status()->>'is_suspended')::boolean is not true then
    raise exception 'non_admin_suspension_status_not_reported';
  end if;

  begin
    perform public.admin_suspend_user(current_setting('t26.admin_id')::uuid);
    raise exception 'non_administrator_suspension_allowed';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform public.admin_restore_user(current_setting('t26.admin_id')::uuid);
    raise exception 'non_administrator_restoration_allowed';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform public.admin_list_user_lifecycles();
    raise exception 'non_administrator_user_listing_allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.goals (
      id, user_id, title, classification, created_at, updated_at
    )
    values (
      gen_random_uuid(),
      current_setting('t26.non_admin_id')::uuid,
      'suspended non-admin write must be rejected',
      'regular',
      now(),
      now()
    );
    raise exception 'suspended_non_admin_business_insert_allowed';
  exception
    when insufficient_privilege then null;
  end;

  if not exists (
    select 1 from public.goals
    where id = current_setting('t26.non_admin_goal_id')::uuid
  ) then
    raise exception 'suspended_non_admin_data_was_removed';
  end if;
end
$non_admin_probe$;

do $restore_admin_claim_again$
begin
  perform set_config('request.jwt.claim.sub', current_setting('t26.admin_id'), true);
end
$restore_admin_claim_again$;

select public.admin_suspend_user(current_setting('t26.admin_id')::uuid);

do $suspended_write_probe$
begin
  if (public.current_user_lifecycle_status()->>'is_suspended')::boolean is not true then
    raise exception 'suspension_status_not_reported';
  end if;
  if (public.current_user_lifecycle_status()->>'is_eligible_for_purge')::boolean is not false then
    raise exception 'new_suspension_is_already_purge_eligible';
  end if;

  begin
    insert into public.goals (
      id, user_id, title, classification, created_at, updated_at
    )
    values (
      gen_random_uuid(),
      current_setting('t26.admin_id')::uuid,
      'must be rejected',
      'regular',
      now(),
      now()
    );
    raise exception 'suspended_business_insert_allowed';
  exception
    when insufficient_privilege then null;
  end;
end
$suspended_write_probe$;

reset role;
update public.user_suspension_periods
set suspended_at = now() - interval '30 days'
where user_id = current_setting('t26.admin_id')::uuid
  and restored_at is null;

set local role authenticated;
do $set_admin_claim_again$
begin
  perform set_config('request.jwt.claim.sub', current_setting('t26.admin_id'), true);
end
$set_admin_claim_again$;

do $purge_eligibility_probe$
declare
  eligible boolean;
begin
  select is_eligible_for_purge into eligible
  from public.admin_list_user_lifecycles()
  where user_id = current_setting('t26.admin_id')::uuid;
  if eligible is not true then
    raise exception 'day_30_did_not_mark_user_purge_eligible';
  end if;
  if not exists (
    select 1 from public.goals
    where id = current_setting('t26.goal_id')::uuid
  ) then
    raise exception 'day_30_automatically_removed_business_data';
  end if;
end
$purge_eligibility_probe$;

select public.admin_restore_user(current_setting('t26.admin_id')::uuid);
select public.admin_suspend_user(current_setting('t26.admin_id')::uuid);

do $restored_and_resuspended_probe$
declare
  lifecycle record;
begin
  select is_suspended, is_eligible_for_purge, suspended_at
  into lifecycle
  from public.admin_list_user_lifecycles()
  where user_id = current_setting('t26.admin_id')::uuid;
  if lifecycle.is_suspended is not true then
    raise exception 'resuspension_not_recorded';
  end if;
  if lifecycle.is_eligible_for_purge is not false then
    raise exception 'restoration_did_not_reset_purge_eligibility_window';
  end if;
  if lifecycle.suspended_at <= now() - interval '30 days' then
    raise exception 'resuspension_reused_previous_suspension_time';
  end if;
end
$restored_and_resuspended_probe$;

rollback;
