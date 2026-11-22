-- Rollback-only checks for the project-owner lifecycle model (Phase 6.3).
-- Run against an isolated Supabase project after applying the migrations with:
--   supabase db query --linked -f supabase/tests/user_suspension_access.sql
--
-- 管理员对象已随 202611220001_remove_legacy_admin_schema 全部移除：停用与恢复
-- 不再经过任何 RPC，而由项目主（service_role，配合 Auth Admin API 的封禁状态）
-- 直接写 public.user_suspension_periods。本探针需要一名隔离的活跃用户，在
-- authenticated 下验证 RLS 与生命周期函数，最后整体回滚。

begin;

do $setup$
declare
  test_user_id uuid;
begin
  -- 管理员名单已移除：任意一名活跃用户即可，an isolated active test user is required.
  select account.id into test_user_id
  from auth.users as account
  where not exists (
      select 1
      from public.user_suspension_periods as suspension
      where suspension.user_id = account.id
        and suspension.restored_at is null
    )
    and not exists (
      select 1
      from public.user_purge_receipts as purge
      where purge.user_id = account.id
        and purge.status in ('pending', 'completed')
    )
  order by account.created_at desc, account.id
  limit 1;
  if test_user_id is null then
    raise exception 'an isolated active test user is required';
  end if;

  perform set_config('lifecycle.user_id', test_user_id::text, true);
  perform set_config('lifecycle.goal_id', gen_random_uuid()::text, true);
  perform set_config('lifecycle.rejected_goal_id', gen_random_uuid()::text, true);
end
$setup$;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('lifecycle.user_id'), true);

-- 活跃用户先写入一条业务数据，作为停用后必须保留的既有数据。
insert into public.goals (
  id, user_id, title, classification, created_at, updated_at
)
values (
  current_setting('lifecycle.goal_id')::uuid,
  current_setting('lifecycle.user_id')::uuid,
  'retained while suspended',
  'regular',
  now(),
  now()
);

do $lifecycle_precheck$
begin
  if public.current_user_is_active() is not true then
    raise exception 'selected_user_is_not_active';
  end if;
  if (public.current_user_lifecycle_status()->>'is_suspended')::boolean then
    raise exception 'selected_user_is_already_suspended';
  end if;
end
$lifecycle_precheck$;

-- 停用台账只对项目主开放：authenticated 既读不到也写不进。
do $suspension_table_denied$
begin
  begin
    perform count(*)
    from public.user_suspension_periods;
    raise exception 'authenticated_can_read_user_suspension_periods';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.user_suspension_periods (user_id, suspended_at)
    values (current_setting('lifecycle.user_id')::uuid, now());
    raise exception 'authenticated_can_write_user_suspension_periods';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.user_suspension_periods
    set restored_at = now()
    where user_id = current_setting('lifecycle.user_id')::uuid
      and restored_at is null;
    raise exception 'authenticated_can_restore_user_suspension_periods';
  exception
    when insufficient_privilege then null;
  end;
end
$suspension_table_denied$;

reset role;

-- 项目主写入停用记录（生产上由 Auth Admin API 的封禁配合完成）。
set local role service_role;
insert into public.user_suspension_periods (user_id, suspended_at)
values (current_setting('lifecycle.user_id')::uuid, now());
reset role;

set local role authenticated;
do $suspension_probe$
declare
  status jsonb;
begin
  status := public.current_user_lifecycle_status();
  if (status->>'is_suspended')::boolean is not true then
    raise exception 'suspension_status_not_reported';
  end if;
  if (status->>'is_eligible_for_purge')::boolean is not false then
    raise exception 'new_suspension_is_already_purge_eligible';
  end if;
  if public.current_user_is_active() then
    raise exception 'suspended_user_was_reported_active';
  end if;

  -- 业务表的限制性策略必须在停用期间挡住写入。
  begin
    insert into public.goals (
      id, user_id, title, classification, created_at, updated_at
    )
    values (
      current_setting('lifecycle.rejected_goal_id')::uuid,
      current_setting('lifecycle.user_id')::uuid,
      'must be rejected while suspended',
      'regular',
      now(),
      now()
    );
    raise exception 'suspended_business_insert_allowed';
  exception
    when insufficient_privilege then null;
  end;

  -- 停用只限制写入，既有数据必须原样保留。
  if not exists (
    select 1
    from public.goals
    where id = current_setting('lifecycle.goal_id')::uuid
  ) then
    raise exception 'suspended_user_business_data_was_removed';
  end if;
end
$suspension_probe$;

reset role;

-- 解除停用只写时间戳：restored_by 列已随遗留管理员架构移除。
update public.user_suspension_periods
set restored_at = now()
where user_id = current_setting('lifecycle.user_id')::uuid
  and restored_at is null;

set local role authenticated;
do $restored_probe$
begin
  if public.current_user_is_active() is not true then
    raise exception 'restored_user_was_not_reported_active';
  end if;
  if (public.current_user_lifecycle_status()->>'is_suspended')::boolean then
    raise exception 'restored_user_still_reported_suspended';
  end if;

  insert into public.goals (
    id, user_id, title, classification, created_at, updated_at
  )
  values (
    current_setting('lifecycle.rejected_goal_id')::uuid,
    current_setting('lifecycle.user_id')::uuid,
    'accepted after restoration',
    'regular',
    now(),
    now()
  );
  if not exists (
    select 1
    from public.goals
    where id = current_setting('lifecycle.rejected_goal_id')::uuid
  ) then
    raise exception 'restored_user_write_was_not_persisted';
  end if;
  if not exists (
    select 1
    from public.goals
    where id = current_setting('lifecycle.goal_id')::uuid
  ) then
    raise exception 'restoration_removed_existing_business_data';
  end if;
end
$restored_probe$;

reset role;

-- 遗留管理员架构必须彻底消失：名单表、判定函数、全部 admin_* RPC、管理员读取
-- 策略，以及三列管理员操作人记录。
do $legacy_admin_removed$
declare
  legacy_function text;
begin
  if to_regclass('public.app_admins') is not null then
    raise exception 'legacy_app_admins_table_still_exists';
  end if;
  if to_regprocedure('public.is_app_admin()') is not null then
    raise exception 'legacy_is_app_admin_function_still_exists';
  end if;

  foreach legacy_function in array array[
    'public.admin_grant_registration_eligibility(text, text)',
    'public.admin_revoke_registration_eligibility(text, text)',
    'public.admin_resolve_auth_user_id_by_email(text)',
    'public.admin_list_user_lifecycles()',
    'public.admin_suspend_user(uuid)',
    'public.admin_restore_user(uuid)',
    'public.admin_begin_user_purge(uuid, uuid)',
    'public.admin_begin_user_purge(uuid, uuid, boolean)',
    'public.admin_cancel_user_purge(uuid, uuid)',
    'public.admin_delete_user_business_data(uuid)',
    'public.admin_complete_user_purge(uuid)'
  ] loop
    if to_regprocedure(legacy_function) is not null then
      raise exception 'legacy_admin_function_still_exists: %', legacy_function;
    end if;
  end loop;

  if exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and policyname in ('admins can view eligibility', 'admins can view admins')
  ) then
    raise exception 'legacy_admin_read_policies_still_exist';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_suspension_periods'
      and column_name in ('suspended_by', 'restored_by')
  ) then
    raise exception 'legacy_suspension_operator_columns_still_exist';
  end if;
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_purge_receipts'
      and column_name = 'requested_by'
  ) then
    raise exception 'legacy_purge_operator_column_still_exists';
  end if;
end
$legacy_admin_removed$;

rollback;
