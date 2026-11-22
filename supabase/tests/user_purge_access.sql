-- Rollback-only checks for the project-owner purge path (Phase 6.3).
-- Run only against an isolated Supabase project after applying the migrations:
--   supabase db query --linked -f supabase/tests/user_purge_access.sql
--
-- 管理员对象已随 202611220001_remove_legacy_admin_schema 全部移除：注销流程不再
-- 经过 app_admins / admin_* RPC，而由项目主（service_role）驱动
--   user_purge_receipts(pending) -> public.purge_user_business_data(uuid)
--   -> Auth Admin 删除账号 -> public.complete_user_purge(uuid)。
-- 本探针需要两名隔离的活跃用户（target 与 other），会在事务内删除 target 的
-- Auth 行，最后整体回滚。

begin;

do $setup$
declare
  test_target_id uuid;
  test_other_id uuid;
  target_email text;
begin
  -- 管理员名单已移除：任意一名带邮箱的活跃用户即可。an isolated active test
  -- user with an email is required.
  select account.id, account.email::text
  into test_target_id, target_email
  from auth.users as account
  where account.email is not null
    and not exists (
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
  if test_target_id is null then
    raise exception 'an isolated active email test user is required';
  end if;

  -- 第二名隔离活跃用户用于证明清除不会波及他人数据。
  select account.id into test_other_id
  from auth.users as account
  where account.id <> test_target_id
    and not exists (
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
  if test_other_id is null then
    raise exception 'a second isolated active test user is required';
  end if;

  perform set_config('purge.target_id', test_target_id::text, true);
  perform set_config('purge.other_id', test_other_id::text, true);
  perform set_config('purge.target_email', lower(btrim(target_email)), true);
  perform set_config('purge.goal_id', gen_random_uuid()::text, true);
  perform set_config('purge.task_id', gen_random_uuid()::text, true);
  perform set_config('purge.appointment_id', gen_random_uuid()::text, true);
  perform set_config('purge.session_id', gen_random_uuid()::text, true);
  perform set_config('purge.node_id', gen_random_uuid()::text, true);
  perform set_config('purge.source_id', gen_random_uuid()::text, true);
  perform set_config('purge.device_id', gen_random_uuid()::text, true);
  perform set_config('purge.other_goal_id', gen_random_uuid()::text, true);
  perform set_config('purge.calendar_source_id', gen_random_uuid()::text, true);
  perform set_config('purge.calendar_event_id', gen_random_uuid()::text, true);
  perform set_config('purge.calendar_occurrence_id', gen_random_uuid()::text, true);
  perform set_config('purge.calendar_identity', gen_random_uuid()::text, true);
  perform set_config('purge.precedent_rule', gen_random_uuid()::text, true);
end
$setup$;

-- 归一化目标账号：清掉上一次运行可能留下的停用期、回执与注册资格，避免短路。
update public.user_suspension_periods
set restored_at = now()
where user_id = current_setting('purge.target_id')::uuid
  and restored_at is null;

delete from public.user_purge_receipts
where user_id = current_setting('purge.target_id')::uuid;

delete from public.registration_eligibility
where used_user_id = current_setting('purge.target_id')::uuid;

-- 同样清掉可能残留的快照副本，保证种入行的唯一键不会冲突。
delete from public.cloud_business_snapshot_upload_requests
where user_id = current_setting('purge.target_id')::uuid;
delete from public.cloud_business_snapshot_history
where user_id = current_setting('purge.target_id')::uuid;
delete from public.cloud_business_snapshots
where user_id = current_setting('purge.target_id')::uuid;

-- 给目标一条已消费的注册资格，用于验证注销收尾会回填 purge_completed_at。
insert into public.registration_eligibility (
  identifier, identifier_type, used_at, used_user_id
)
values (
  current_setting('purge.target_email'),
  'email',
  now() - interval '60 days',
  current_setting('purge.target_id')::uuid
)
on conflict (identifier_type, identifier) do update
set used_at = excluded.used_at,
    used_user_id = excluded.used_user_id,
    revoked_at = null,
    purge_completed_at = null;

-- 1) 静态权限：两个项目主函数只允许 service_role。
do $privilege_probe$
begin
  if has_function_privilege(
    'authenticated',
    'public.purge_user_business_data(uuid)',
    'execute'
  ) then
    raise exception 'authenticated_can_execute_purge_user_business_data';
  end if;
  if has_function_privilege(
    'anon',
    'public.purge_user_business_data(uuid)',
    'execute'
  ) then
    raise exception 'anon_can_execute_purge_user_business_data';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.complete_user_purge(uuid)',
    'execute'
  ) then
    raise exception 'authenticated_can_execute_complete_user_purge';
  end if;
  if has_function_privilege(
    'anon',
    'public.complete_user_purge(uuid)',
    'execute'
  ) then
    raise exception 'anon_can_execute_complete_user_purge';
  end if;
  if not has_function_privilege(
    'service_role',
    'public.purge_user_business_data(uuid)',
    'execute'
  ) then
    raise exception 'service_role_cannot_execute_purge_user_business_data';
  end if;
  if not has_function_privilege(
    'service_role',
    'public.complete_user_purge(uuid)',
    'execute'
  ) then
    raise exception 'service_role_cannot_execute_complete_user_purge';
  end if;
end
$privilege_probe$;

-- 2) authenticated 既读不到也写不进注销台账，也不能直接执行两个 RPC。
set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('purge.target_id'), true);

do $authenticated_denied$
begin
  begin
    perform count(*)
    from public.user_purge_receipts;
    raise exception 'authenticated_can_read_user_purge_receipts';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.user_purge_receipts (user_id, status)
    values (current_setting('purge.target_id')::uuid, 'pending');
    raise exception 'authenticated_can_write_user_purge_receipts';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.user_purge_receipts
    set status = 'completed'
    where user_id = current_setting('purge.target_id')::uuid;
    raise exception 'authenticated_can_complete_purge_receipt';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.purge_user_business_data(
      current_setting('purge.target_id')::uuid
    );
    raise exception 'authenticated_can_execute_purge_user_business_data';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.complete_user_purge(
      current_setting('purge.target_id')::uuid
    );
    raise exception 'authenticated_can_execute_complete_user_purge';
  exception
    when insufficient_privilege then null;
  end;
end
$authenticated_denied$;

reset role;

-- 3) anon 同样被挡在台账与 RPC 之外。
set local role anon;
do $anon_denied$
begin
  begin
    perform count(*)
    from public.user_purge_receipts;
    raise exception 'anon_can_read_user_purge_receipts';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.user_purge_receipts (user_id, status)
    values (current_setting('purge.target_id')::uuid, 'pending');
    raise exception 'anon_can_write_user_purge_receipts';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.purge_user_business_data(
      current_setting('purge.target_id')::uuid
    );
    raise exception 'anon_can_execute_purge_user_business_data';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.complete_user_purge(
      current_setting('purge.target_id')::uuid
    );
    raise exception 'anon_can_execute_complete_user_purge';
  exception
    when insufficient_privilege then null;
  end;
end
$anon_denied$;

reset role;

-- 4) 项目主在封禁阶段写入停用记录（生产上配合 Auth Admin API 的同一次操作）。
insert into public.user_suspension_periods (user_id, suspended_at)
values (
  current_setting('purge.target_id')::uuid,
  now() - interval '31 days'
)
on conflict (user_id) where restored_at is null do update
  set suspended_at = excluded.suspended_at;

-- 5) 每个当前数据类别各准备一行：十一张业务表 + 三张快照表，外加上另一名
--    用户的对照数据。可信会话内写入，绕开 RLS 限制，便于验证清除范围。
insert into public.goals (
  id, user_id, title, classification, created_at, updated_at
)
values (
  current_setting('purge.goal_id')::uuid,
  current_setting('purge.target_id')::uuid,
  'purge test goal',
  'regular',
  now(),
  now()
);

insert into public.tasks (
  id, user_id, goal_id, title, classification, created_at, updated_at
)
values (
  current_setting('purge.task_id')::uuid,
  current_setting('purge.target_id')::uuid,
  current_setting('purge.goal_id')::uuid,
  'purge test task',
  'regular',
  now(),
  now()
);

insert into public.focus_appointments (
  id, user_id, task_id, mode, duration_seconds, started_at, ends_at, status,
  settled_at, updated_at
)
values (
  current_setting('purge.appointment_id')::uuid,
  current_setting('purge.target_id')::uuid,
  current_setting('purge.task_id')::uuid,
  'regular',
  60,
  now() - interval '2 minutes',
  now() - interval '1 minute',
  'succeeded',
  now() - interval '1 minute',
  now()
);

insert into public.focus_sessions (
  id, user_id, appointment_id, task_id, mode, duration_seconds, started_at,
  ends_at, status, completed_at, effective_seconds
)
values (
  current_setting('purge.session_id')::uuid,
  current_setting('purge.target_id')::uuid,
  current_setting('purge.appointment_id')::uuid,
  current_setting('purge.task_id')::uuid,
  'regular',
  60,
  now() - interval '1 minute',
  now(),
  'completed',
  now(),
  60
);

update public.focus_appointments
set session_id = current_setting('purge.session_id')::uuid
where id = current_setting('purge.appointment_id')::uuid;

insert into public.focus_nodes (
  id, user_id, session_id, task_id, mode, created_at, effective_seconds
)
values (
  current_setting('purge.node_id')::uuid,
  current_setting('purge.target_id')::uuid,
  current_setting('purge.session_id')::uuid,
  current_setting('purge.task_id')::uuid,
  'regular',
  now(),
  60
);

insert into public.focus_chain_records (
  user_id, mode, current_consecutive, best_consecutive, updated_at
)
values (current_setting('purge.target_id')::uuid, 'regular', 1, 1, now())
on conflict (user_id, mode) do update
set current_consecutive = excluded.current_consecutive,
    best_consecutive = excluded.best_consecutive,
    updated_at = excluded.updated_at;

insert into public.appointment_chain_records (
  user_id, current_consecutive, best_consecutive, updated_at
)
values (current_setting('purge.target_id')::uuid, 1, 1, now())
on conflict (user_id) do update
set current_consecutive = excluded.current_consecutive,
    best_consecutive = excluded.best_consecutive,
    updated_at = excluded.updated_at;

insert into public.focus_precedent_rules (user_id, rule_text)
values (
  current_setting('purge.target_id')::uuid,
  'purge test rule ' || current_setting('purge.precedent_rule')
);

insert into public.focus_sync_sources (
  source_id, user_id, device_id, entity_type, entity_id, occurred_at, payload
)
values (
  current_setting('purge.source_id')::uuid,
  current_setting('purge.target_id')::uuid,
  current_setting('purge.device_id')::uuid,
  'national_focus_tree',
  gen_random_uuid(),
  now(),
  '{}'::jsonb
);

insert into public.calendar_sources (
  user_id, source_id, display_name, time_zone_id
)
values (
  current_setting('purge.target_id')::uuid,
  current_setting('purge.calendar_source_id'),
  'Purge test source',
  'UTC'
);

insert into public.calendar_blocks (
  user_id, source_id, source_event_id, occurrence_id, event_identity, title,
  starts_at, ends_at, availability, time_zone_id
)
values (
  current_setting('purge.target_id')::uuid,
  current_setting('purge.calendar_source_id'),
  current_setting('purge.calendar_event_id'),
  current_setting('purge.calendar_occurrence_id'),
  current_setting('purge.calendar_identity'),
  'Purge test block',
  now(),
  now() + interval '1 hour',
  'busy',
  'UTC'
);

insert into public.cloud_business_snapshots (
  user_id, revision, payload, device_id, device_name, data_updated_at, row_count
)
values (
  current_setting('purge.target_id')::uuid,
  1,
  jsonb_build_object(
    'schemaVersion', '3',
    'userId', current_setting('purge.target_id'),
    'tables', jsonb_build_object(
      'local_schedules', '[]'::jsonb,
      'local_schedule_recurrences', '[]'::jsonb,
      'focus_appointments', '[]'::jsonb,
      'local_goals', '[]'::jsonb,
      'local_national_focus_failures', '[]'::jsonb
    )
  ),
  'purge-device', 'Purge device', now(), 0
);

insert into public.cloud_business_snapshot_history (
  user_id, revision, payload, device_id, device_name, data_updated_at, row_count,
  request_id
)
values (
  current_setting('purge.target_id')::uuid,
  1,
  jsonb_build_object(
    'schemaVersion', '3',
    'userId', current_setting('purge.target_id'),
    'tables', jsonb_build_object(
      'local_schedules', '[]'::jsonb,
      'local_schedule_recurrences', '[]'::jsonb,
      'focus_appointments', '[]'::jsonb,
      'local_goals', '[]'::jsonb,
      'local_national_focus_failures', '[]'::jsonb
    )
  ),
  'purge-device', 'Purge device', now(), 0, 'purge-request'
);

insert into public.cloud_business_snapshot_upload_requests (
  user_id, request_id, revision, payload_fingerprint
)
values (
  current_setting('purge.target_id')::uuid,
  'purge-request',
  1,
  md5('{}'::jsonb::text)
);

insert into public.goals (
  id, user_id, title, classification, created_at, updated_at
)
values (
  current_setting('purge.other_goal_id')::uuid,
  current_setting('purge.other_id')::uuid,
  'other user''s retained goal',
  'regular',
  now(),
  now()
);

-- 6) 项目主流程：pending 回执 -> 清除业务与快照数据（第二次调用验证幂等）。
set local role service_role;
insert into public.user_purge_receipts (
  user_id, status, requested_at, business_data_deleted, completed_at
)
values (
  current_setting('purge.target_id')::uuid,
  'pending',
  now(),
  false,
  null
);
select public.purge_user_business_data(
  current_setting('purge.target_id')::uuid
);
select public.purge_user_business_data(
  current_setting('purge.target_id')::uuid
);
reset role;

do $pending_state_probe$
declare
  target_id uuid := current_setting('purge.target_id')::uuid;
begin
  if public.user_purge_receipt(target_id) is not null then
    raise exception 'pending_purge_was_exposed_as_completed_receipt';
  end if;
  if not exists (
    select 1
    from public.user_purge_receipts as purge
    where purge.user_id = target_id
      and purge.status = 'pending'
      and purge.business_data_deleted
      and purge.completed_at is null
  ) then
    raise exception 'purge_rpc_did_not_mark_business_data_deleted';
  end if;
  if exists (select 1 from public.goals where user_id = target_id)
     or exists (select 1 from public.tasks where user_id = target_id)
     or exists (select 1 from public.focus_sessions where user_id = target_id)
     or exists (select 1 from public.focus_nodes where user_id = target_id)
     or exists (select 1 from public.focus_chain_records where user_id = target_id)
     or exists (select 1 from public.focus_appointments where user_id = target_id)
     or exists (select 1 from public.appointment_chain_records where user_id = target_id)
     or exists (select 1 from public.focus_precedent_rules where user_id = target_id)
     or exists (select 1 from public.focus_sync_sources where user_id = target_id)
     or exists (select 1 from public.calendar_sources where user_id = target_id)
     or exists (select 1 from public.calendar_blocks where user_id = target_id) then
    raise exception 'cloud_business_data_remained_after_purge_user_business_data';
  end if;
  if exists (
    select 1 from public.cloud_business_snapshots where user_id = target_id
  ) or exists (
    select 1 from public.cloud_business_snapshot_history where user_id = target_id
  ) or exists (
    select 1
    from public.cloud_business_snapshot_upload_requests
    where user_id = target_id
  ) then
    raise exception 'cloud_snapshot_copies_remained_after_purge_user_business_data';
  end if;
  if not exists (select 1 from auth.users where id = target_id) then
    raise exception 'auth_identity_was_removed_before_explicit_auth_deletion';
  end if;
  if not exists (
    select 1
    from public.goals
    where id = current_setting('purge.other_goal_id')::uuid
      and user_id = current_setting('purge.other_id')::uuid
  ) then
    raise exception 'other_user_data_was_removed';
  end if;
end
$pending_state_probe$;

-- 7) 模拟 Auth Admin API 的硬删除。注销台账刻意没有 Auth 外键。
delete from auth.users
where id = current_setting('purge.target_id')::uuid;

set local role service_role;
select public.complete_user_purge(
  current_setting('purge.target_id')::uuid
);
reset role;

do $completed_state_probe$
declare
  target_id uuid := current_setting('purge.target_id')::uuid;
begin
  if exists (select 1 from auth.users where id = target_id) then
    raise exception 'purged_auth_identity_still_exists';
  end if;
  if not exists (
    select 1
    from public.user_purge_receipts as purge
    where purge.user_id = target_id
      and purge.status = 'completed'
      and purge.completed_at is not null
      and purge.eligibility_id is null
  ) then
    raise exception 'completed_receipt_was_not_recorded';
  end if;
  if not exists (
    select 1
    from public.registration_eligibility
    where identifier = current_setting('purge.target_email')
      and identifier_type = 'email'
      and purge_completed_at is not null
  ) then
    raise exception 'purge_completed_at_was_not_backfilled';
  end if;
  if exists (
    select 1 from public.goals where user_id = target_id
  ) or exists (
    select 1 from public.cloud_business_snapshots where user_id = target_id
  ) then
    raise exception 'cloud_data_remained_after_completed_purge';
  end if;
end
$completed_state_probe$;

-- 8) 离线查询：anon 只凭旧 UUID 就能确认 completed，且拿不到邮箱或业务数据。
set local role anon;
do $offline_receipt_probe$
declare
  target_id uuid := current_setting('purge.target_id')::uuid;
  receipt jsonb;
begin
  receipt := public.user_purge_receipt(target_id);
  if receipt->>'user_id' <> target_id::text
     or receipt->>'status' <> 'completed'
     or nullif(receipt->>'purged_at', '') is null then
    raise exception 'offline_receipt_did_not_bind_to_deleted_identity';
  end if;
  if public.user_purge_receipt(gen_random_uuid()) is not null then
    raise exception 'offline_receipt_leaked_an_unknown_identity';
  end if;
end
$offline_receipt_probe$;

reset role;

-- 9) 已注销的 UUID 不能被重新用于建号：注册触发器必须拒绝。
do $recreate_denied$
declare
  target_id uuid := current_setting('purge.target_id')::uuid;
begin
  begin
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at
    )
    values (
      '00000000-0000-0000-0000-000000000000',
      target_id,
      'authenticated',
      'authenticated',
      current_setting('purge.target_email'),
      '',
      now(),
      now(),
      now()
    );
    raise exception 'purged_identity_recreation_was_allowed';
  exception
    when others then
      if sqlerrm <> 'purged identity cannot be recreated' then
        raise;
      end if;
  end;
  if exists (select 1 from auth.users where id = target_id) then
    raise exception 'rejected_recreation_left_an_auth_row';
  end if;
end
$recreate_denied$;

-- 10) 遗留管理员架构必须彻底消失。
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
