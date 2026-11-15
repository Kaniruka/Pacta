-- Rollback-only RLS and compare-and-swap checks. Run against an isolated
-- Supabase project after applying the snapshot and device metadata migrations.
begin;

do $setup$
declare
  owner_id uuid;
  other_id uuid;
begin
  select user_id into owner_id
  from public.app_admins
  order by user_id
  limit 1;
  if owner_id is null then
    raise exception 'an isolated active administrator is required';
  end if;
  -- Make this test repeatable, with rollback restoring any prior test state.
  delete from public.cloud_business_snapshots where user_id = owner_id;
  select id into other_id
  from auth.users
  where id <> owner_id
  order by created_at desc
  limit 1;
  if other_id is null then
    other_id := gen_random_uuid();
  end if;
  perform set_config('snapshot_test.owner_id', owner_id::text, true);
  perform set_config('snapshot_test.other_id', other_id::text, true);
  perform set_config('snapshot_test.goal_id', gen_random_uuid()::text, true);
end
$setup$;

set local role authenticated;
do $owner_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('snapshot_test.owner_id'),
    true
  );
end
$owner_claim$;

-- A nonzero revision must not create an absent snapshot.
do $first_revision$
begin
  begin
    perform public.save_cloud_business_snapshot(
      2,
      jsonb_build_object(
        'schemaVersion', '3',
        'userId', current_setting('snapshot_test.owner_id'),
        'tables', jsonb_build_object('local_schedules', '[]'::jsonb, 'local_schedule_recurrences', '[]'::jsonb, 'focus_appointments', '[]'::jsonb)
      ),
      'device-a', 'Device A', now(), 0
    );
    raise exception 'nonzero_initial_revision_was_accepted';
  exception
    when sqlstate 'PT409' then null;
  end;
end
$first_revision$;

insert into public.goals (
  id, user_id, title, classification, created_at, updated_at
) values (
  current_setting('snapshot_test.goal_id')::uuid,
  current_setting('snapshot_test.owner_id')::uuid,
  'legacy row', 'regular', now(), now()
);

do $legacy_inspect$
declare
  legacy_result jsonb;
begin
  legacy_result := public.read_legacy_business_records();
  if legacy_result is null or legacy_result ->> 'token' is null then
    raise exception 'legacy_cloud_data_was_not_read';
  end if;
  perform set_config(
    'snapshot_test.legacy_token', legacy_result ->> 'token', true
  );
end
$legacy_inspect$;

update public.goals
set title = 'legacy row changed after inspect'
where id = current_setting('snapshot_test.goal_id')::uuid;

do $stale_legacy_token$
begin
  begin
    perform public.save_cloud_business_snapshot(
      0,
      jsonb_build_object(
        'schemaVersion', '3',
        'userId', current_setting('snapshot_test.owner_id'),
        'tables', jsonb_build_object('local_schedules', '[]'::jsonb, 'local_schedule_recurrences', '[]'::jsonb, 'focus_appointments', '[]'::jsonb)
      ),
      'device-a', 'Device A', now(), 0,
      current_setting('snapshot_test.legacy_token')
    );
    raise exception 'stale_legacy_token_was_accepted';
  exception
    when sqlstate 'PT409' then null;
  end;
end
$stale_legacy_token$;

do $save_current_legacy$
declare
  current_legacy_result jsonb;
begin
  current_legacy_result := public.read_legacy_business_records();
  perform public.save_cloud_business_snapshot(
    0,
    jsonb_build_object(
      'schemaVersion', '3',
      'userId', current_setting('snapshot_test.owner_id'),
      'tables', jsonb_build_object('local_schedules', '[]'::jsonb, 'local_schedule_recurrences', '[]'::jsonb, 'focus_appointments', '[]'::jsonb)
    ),
    'device-a', 'Device A', now(), 0,
    current_legacy_result ->> 'token'
  );
  if public.read_legacy_business_records() is not null then
    raise exception 'legacy_projection_not_hidden_after_snapshot';
  end if;
end
$save_current_legacy$;

do $owner_visibility_and_cas$
begin
  if not exists (
    select 1 from public.cloud_business_snapshots
    where user_id = current_setting('snapshot_test.owner_id')::uuid
      and revision = 1
  ) then
    raise exception 'owner_cannot_read_own_snapshot';
  end if;
  begin
    insert into public.cloud_business_snapshots (
      user_id, revision, payload, device_id, device_name,
      data_updated_at, row_count
    ) values (
      current_setting('snapshot_test.owner_id')::uuid,
      1,
      jsonb_build_object(
        'schemaVersion', 1,
        'userId', current_setting('snapshot_test.owner_id'),
        'tables', jsonb_build_object('local_schedules', '[]'::jsonb)
      ),
      'direct-write', 'Direct write', now(), 0
    );
    raise exception 'authenticated_direct_write_was_accepted';
  exception
    when insufficient_privilege then null;
  end;
  begin
    update public.goals
    set title = 'old client write'
    where id = current_setting('snapshot_test.goal_id')::uuid;
    raise exception 'legacy_write_after_snapshot_was_accepted';
  exception
    when sqlstate 'PT410' then null;
  end;
  begin
    perform public.save_cloud_business_snapshot(
      0,
      jsonb_build_object(
        'schemaVersion', '3',
        'userId', current_setting('snapshot_test.owner_id'),
        'tables', jsonb_build_object('local_schedules', '[]'::jsonb, 'local_schedule_recurrences', '[]'::jsonb, 'focus_appointments', '[]'::jsonb)
      ),
      'device-a', 'Device A', now(), 0
    );
    raise exception 'stale_revision_was_accepted';
  exception
    when sqlstate 'PT409' then null;
  end;
end
$owner_visibility_and_cas$;

do $device_metadata_and_old_client_compatibility$
declare
  saved public.cloud_business_snapshots;
begin
  saved := public.save_cloud_business_snapshot(
    1,
    jsonb_build_object(
      'schemaVersion', '3',
      'userId', current_setting('snapshot_test.owner_id'),
      'tables', jsonb_build_object('local_schedules', '[]'::jsonb, 'local_schedule_recurrences', '[]'::jsonb, 'focus_appointments', '[]'::jsonb)
    ),
    'device-b', 'Device B', now(), 0, null, 'Example Corp', 'Example Model'
  );
  if saved.device_manufacturer <> 'Example Corp'
    or saved.device_model <> 'Example Model' then
    raise exception 'hardware_metadata_was_not_saved';
  end if;

  -- The previous RPC contract omits the two trailing nullable parameters.
  saved := public.save_cloud_business_snapshot(
    2,
    jsonb_build_object(
      'schemaVersion', '3',
      'userId', current_setting('snapshot_test.owner_id'),
      'tables', jsonb_build_object('local_schedules', '[]'::jsonb, 'local_schedule_recurrences', '[]'::jsonb, 'focus_appointments', '[]'::jsonb)
    ),
    'old-client-device', 'Old client', now(), 0
  );
  if saved.device_manufacturer is not null or saved.device_model is not null then
    raise exception 'old_rpc_client_metadata_was_invented';
  end if;
end
$device_metadata_and_old_client_compatibility$;

-- 旧客户端（载荷版本 1）上传必须被独立错误码拒绝：版本 1 缺少后来新增的列，
-- 静默接受等于让整份快照丢字段。
do $outdated_schema_version$
begin
  begin
    perform public.save_cloud_business_snapshot(
      3,
      jsonb_build_object(
        'schemaVersion', 1,
        'userId', current_setting('snapshot_test.owner_id'),
        'tables', '{}'::jsonb
      ),
      'device-a', 'Device A', now(), 0
    );
    raise exception 'outdated_schema_version_was_accepted';
  exception
    when sqlstate 'PT426' then null;
  end;
  if (select revision from public.cloud_business_snapshots
      where user_id = current_setting('snapshot_test.owner_id')::uuid) <> 3 then
    raise exception 'rejected_upload_changed_revision';
  end if;
  -- 回滚证据：被拒绝的版本 1 上传没有改写已存载荷。历史是私有表，
  -- 归档断言放在受信任会话里（见 $outdated_upload_left_no_history$）。
  if (select payload ->> 'schemaVersion' from public.cloud_business_snapshots
      where user_id = current_setting('snapshot_test.owner_id')::uuid) <> '3' then
    raise exception 'rejected_outdated_upload_rewrote_the_payload';
  end if;
end
$outdated_schema_version$;

-- The upload ledger is a private table: the authenticated role has no
-- privilege on it at all, and history is read-only for it. These denials are
-- part of the contract, so they are asserted instead of granting anything.
do $private_snapshot_tables_are_forbidden$
declare
  owner_id uuid := current_setting('snapshot_test.owner_id')::uuid;
begin
  begin
    perform 1 from public.cloud_business_snapshot_upload_requests
    where user_id = owner_id;
    raise exception 'authenticated_could_read_the_upload_ledger';
  exception
    when insufficient_privilege then null;
  end;
  begin
    insert into public.cloud_business_snapshot_upload_requests (
      user_id, request_id, revision, payload_fingerprint
    ) values (owner_id, 'direct-ledger-write', 1, md5('{}'));
    raise exception 'authenticated_could_write_the_upload_ledger';
  exception
    when insufficient_privilege then null;
  end;
  begin
    insert into public.cloud_business_snapshot_history (
      user_id, revision, payload, device_id, device_name, data_updated_at,
      uploaded_at, row_count
    ) values (
      owner_id, 99,
      jsonb_build_object(
        'schemaVersion', '2',
        'userId', owner_id::text,
        'tables', '{}'::jsonb
      ),
      'direct-write', 'Direct write', now(), now(), 0
    );
    raise exception 'authenticated_could_write_snapshot_history';
  exception
    when insufficient_privilege then null;
  end;
end
$private_snapshot_tables_are_forbidden$;

-- Seeding and inspecting the private tables happens in the trusted session.
-- The authenticated role is only used for the user-facing RPC calls and RLS
-- assertions below.
reset role;
do $seed_committed_legacy_request$
declare
  legacy_payload jsonb := jsonb_build_object(
    'schemaVersion', 1,
    'userId', current_setting('snapshot_test.owner_id'),
    'tables', '{}'::jsonb
  );
begin
  insert into public.cloud_business_snapshot_history (
    user_id, revision, payload, device_id, device_name, data_updated_at,
    uploaded_at, row_count, request_id
  ) values (
    current_setting('snapshot_test.owner_id')::uuid, 4, legacy_payload,
    'legacy-device', 'Legacy device', now(), now(), 0,
    'committed-legacy-request'
  );
  insert into public.cloud_business_snapshot_upload_requests (
    user_id, request_id, revision, payload_fingerprint
  ) values (
    current_setting('snapshot_test.owner_id')::uuid,
    'committed-legacy-request', 4, md5(legacy_payload::text)
  );
end
$seed_committed_legacy_request$;

-- The rejected version 1 upload left no history row behind.
do $outdated_upload_left_no_history$
begin
  if exists (
    select 1 from public.cloud_business_snapshot_history
    where user_id = current_setting('snapshot_test.owner_id')::uuid
      and revision = 3
      and payload ->> 'schemaVersion' = '1'
  ) then
    raise exception 'rejected_outdated_upload_was_archived';
  end if;
end
$outdated_upload_left_no_history$;

-- 升级前已经写入的请求（载荷当时就是版本 1）重试时按原请求身份只读返回：
-- 不重复写入，也不改写它的载荷；请求台账的不变量保持不变。
set local role authenticated;
do $owner_claim_again$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('snapshot_test.owner_id'),
    true
  );
end
$owner_claim_again$;

do $committed_outdated_request_replay$
declare
  saved public.cloud_business_snapshots;
  legacy_payload jsonb := jsonb_build_object(
    'schemaVersion', 1,
    'userId', current_setting('snapshot_test.owner_id'),
    'tables', '{}'::jsonb
  );
begin
  saved := public.save_cloud_business_snapshot(
    3, legacy_payload, 'device-a', 'Device A', now(), 0,
    null, null, null, 'committed-legacy-request'
  );
  if saved.revision <> 4 then
    raise exception 'committed_legacy_replay_returned_other_revision';
  end if;
  if saved.payload ->> 'schemaVersion' <> '1' then
    raise exception 'committed_legacy_replay_rewrote_its_payload';
  end if;
  if (select revision from public.cloud_business_snapshots
      where user_id = current_setting('snapshot_test.owner_id')::uuid) <> 3 then
    raise exception 'committed_legacy_replay_wrote_snapshot';
  end if;
end
$committed_outdated_request_replay$;

do $invalid_payload$
begin
  begin
    perform public.save_cloud_business_snapshot(
      1,
      '{"schemaVersion":1,"tables":{}}'::jsonb,
      'device-a', 'Device A', now(), 0
    );
    raise exception 'payload_without_owner_was_accepted';
  exception
    when sqlstate '22023' then null;
  end;
end
$invalid_payload$;

do $other_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('snapshot_test.other_id'),
    true
  );
end
$other_claim$;

do $other_user_isolation$
begin
  if exists (
    select 1 from public.cloud_business_snapshots
    where user_id = current_setting('snapshot_test.owner_id')::uuid
  ) then
    raise exception 'cross_user_snapshot_read_leak';
  end if;
end
$other_user_isolation$;

rollback;
