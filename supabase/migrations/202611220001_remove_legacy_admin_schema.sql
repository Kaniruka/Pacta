-- Phase 6.3: remove the legacy administrator schema.
--
-- 6.2 之后管理员身份改由项目主直接管理：Auth Admin API 负责封禁 / 恢复 / 删除
-- 账号，数据库内不再保留 app_admins 名单、is_app_admin() 判定或任何 admin_* RPC。
-- 本迁移删除全部遗留管理员对象，并用两个只对 service_role 开放的项目主函数取代
-- 原来的数据清除与注销收尾步骤：
--   * public.purge_user_business_data(uuid) 取代 admin_delete_user_business_data(uuid)
--   * public.complete_user_purge(uuid)      取代 admin_complete_user_purge(uuid)
--
-- 每一句都幂等（if exists / create or replace），因此既可作为最新迁移在干净库上
-- 重放，也可以直接在已上线的数据库上安全执行一次；重复执行不改变结果。
--
-- 本迁移刻意不再引用 requested_by / suspended_by / restored_by：这三列记录的是
-- 已删除的管理员操作人身份，随本迁移一并从用户生命周期表中移除。

-- 1) 依赖 is_app_admin() 的两条管理员读取策略。app_admins 会在本迁移中删除，
--    因此用 to_regclass 守卫：重复执行时表已消失，策略语句不会报错。
drop policy if exists "admins can view eligibility"
  on public.registration_eligibility;

do $drop_legacy_admin_policies$
begin
  if to_regclass('public.app_admins') is not null then
    execute $policy$drop policy if exists "admins can view admins" on public.app_admins$policy$;
  end if;
end;
$drop_legacy_admin_policies$;

-- 2) 遗留管理员 RPC 与判定函数。先按签名逐个 drop，避免残留重载在 PostgREST
--    中变成可解析的 RPC。
drop function if exists public.admin_grant_registration_eligibility(text, text);
drop function if exists public.admin_revoke_registration_eligibility(text, text);
drop function if exists public.admin_resolve_auth_user_id_by_email(text);
drop function if exists public.admin_list_user_lifecycles();
drop function if exists public.admin_suspend_user(uuid);
drop function if exists public.admin_restore_user(uuid);
drop function if exists public.admin_begin_user_purge(uuid, uuid);
drop function if exists public.admin_begin_user_purge(uuid, uuid, boolean);
drop function if exists public.admin_cancel_user_purge(uuid, uuid);
drop function if exists public.admin_delete_user_business_data(uuid);
drop function if exists public.admin_complete_user_purge(uuid);
drop function if exists public.is_app_admin();

-- 3) 管理员名单表。registration_eligibility 上的管理员读取策略已在第 1 步删除，
--    因此这里没有级联依赖。
drop table if exists public.app_admins;

-- 4) 遗留管理员操作人列。
alter table public.user_suspension_periods
  drop column if exists suspended_by;
alter table public.user_suspension_periods
  drop column if exists restored_by;
alter table public.user_purge_receipts
  drop column if exists requested_by;

-- 5) 项目主清除函数：删除目标账号的全部云端业务数据与快照副本。
--    前置条件由 user_purge_receipts 的 pending 回执表达；幂等体现在
--    business_data_deleted 已为 true 时直接返回。
create or replace function public.purge_user_business_data(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $purge_user_business_data$
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

  -- 先删历史与请求台账，再删当前快照与十一张业务表，符合既有外键依赖顺序，
  -- 保证随后的 Auth Admin API 删除不会被 RESTRICT 约束挡住。账号清除后云端
  -- 不保留任何业务数据副本。
  delete from public.cloud_business_snapshot_upload_requests where user_id = p_user_id;
  delete from public.cloud_business_snapshot_history where user_id = p_user_id;
  delete from public.cloud_business_snapshots where user_id = p_user_id;
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
$purge_user_business_data$;

-- 6) 项目主注销收尾函数：在 Auth Admin API 删除账号之后把回执置为 completed，
--    并把消费掉的注册资格标记为已完成注销，便于离线设备确认旧 UUID 已清除。
create or replace function public.complete_user_purge(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $complete_user_purge$
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

  -- requested_by 列已删除：注销收尾只记录状态与时间，不再写操作人。
  update public.user_purge_receipts
  set status = 'completed',
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
$complete_user_purge$;

-- 7) 只有 service_role（项目主服务端）可以执行清除与收尾。
revoke all on function public.purge_user_business_data(uuid)
  from public, anon, authenticated;
grant execute on function public.purge_user_business_data(uuid)
  to service_role;
revoke all on function public.complete_user_purge(uuid)
  from public, anon, authenticated;
grant execute on function public.complete_user_purge(uuid)
  to service_role;

comment on function public.purge_user_business_data(uuid) is
  'Project-owner purge step: deletes every cloud business row, snapshot and upload ledger entry for a user with a pending purge receipt. service_role only.';
comment on function public.complete_user_purge(uuid) is
  'Project-owner purge finalization: marks the pending receipt completed after the Auth identity is deleted. service_role only.';
