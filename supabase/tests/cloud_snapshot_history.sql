-- Rollback-only checks for retained cloud snapshot history: retention limit,
-- atomic failure, upload request idempotency (including returning the request's
-- original version rather than the current one), request-ledger limits, cross-user
-- RLS and lifecycle clearing. Run against an isolated Supabase project after
-- applying 202611130001_cloud_snapshot_history.sql. Every step is asserted and
-- nothing is skipped: the purge probe requires one administrator and one
-- non-administrator identity. Identity selection, seeding and result checks run
-- in the trusted session (reset role); the authenticated role is used only for
-- RLS checks, so the script never reads auth.users as a client role.
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
  -- Make this test repeatable; rollback restores any prior state.
  delete from public.cloud_business_snapshot_upload_requests where user_id = owner_id;
  delete from public.cloud_business_snapshot_history where user_id = owner_id;
  delete from public.cloud_business_snapshots where user_id = owner_id;
  select id into other_id
  from auth.users
  where id <> owner_id
  order by created_at desc
  limit 1;
  if other_id is null then
    other_id := gen_random_uuid();
  end if;
  perform set_config('history_test.owner_id', owner_id::text, true);
  perform set_config('history_test.other_id', other_id::text, true);
end
$setup$;

set local role authenticated;
do $owner_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('history_test.owner_id'),
    true
  );
end
$owner_claim$;

-- Seventeen successful writes keep the newest fifteen versions only.
do $retention_limit$
declare
  index integer;
  newest bigint;
  kept integer;
begin
  for index in 0..16 loop
    perform public.save_cloud_business_snapshot(
      index,
      jsonb_build_object(
        'schemaVersion', 1,
        'userId', current_setting('history_test.owner_id'),
        'tables', '{}'::jsonb
      ),
      'device-a', 'Pixel 7（Android）', now(), 0
    );
  end loop;

  select count(*) into kept
  from public.cloud_business_snapshot_history
  where user_id = current_setting('history_test.owner_id')::uuid;
  if kept <> 15 then
    raise exception 'history_retention_expected_15_kept_%', kept;
  end if;

  select max(revision) into newest
  from public.cloud_business_snapshot_history
  where user_id = current_setting('history_test.owner_id')::uuid;
  if newest <> 17 then
    raise exception 'latest_revision_missing_from_history_%', newest;
  end if;
  if exists (
    select 1 from public.cloud_business_snapshot_history
    where user_id = current_setting('history_test.owner_id')::uuid
      and revision < 3
  ) then
    raise exception 'oldest_versions_were_not_evicted';
  end if;
end
$retention_limit$;

-- A rejected compare-and-swap must not add a history row.
do $failed_write_is_atomic$
declare
  before_count integer;
  after_count integer;
begin
  select count(*) into before_count
  from public.cloud_business_snapshot_history
  where user_id = current_setting('history_test.owner_id')::uuid;
  begin
    perform public.save_cloud_business_snapshot(
      3,
      jsonb_build_object(
        'schemaVersion', 1,
        'userId', current_setting('history_test.owner_id'),
        'tables', '{}'::jsonb
      ),
      'device-a', 'Pixel 7（Android）', now(), 0
    );
    raise exception 'stale_revision_was_accepted';
  exception
    when sqlstate 'PT409' then null;
  end;
  select count(*) into after_count
  from public.cloud_business_snapshot_history
  where user_id = current_setting('history_test.owner_id')::uuid;
  if after_count <> before_count then
    raise exception 'failed_write_left_a_history_row';
  end if;
end
$failed_write_is_atomic$;

-- Retrying one upload request id returns the handled version without a new one.
do $request_idempotency$
declare
  saved public.cloud_business_snapshots;
  retried public.cloud_business_snapshots;
  kept integer;
begin
  saved := public.save_cloud_business_snapshot(
    17,
    jsonb_build_object(
      'schemaVersion', 1,
      'userId', current_setting('history_test.owner_id'),
      'tables', '{}'::jsonb
    ),
    'device-a', 'Pixel 7（Android）', now(), 0,
    null, null, null, 'request-92'
  );
  retried := public.save_cloud_business_snapshot(
    17,
    jsonb_build_object(
      'schemaVersion', 1,
      'userId', current_setting('history_test.owner_id'),
      'tables', '{}'::jsonb
    ),
    'device-a', 'Pixel 7（Android）', now(), 0,
    null, null, null, 'request-92'
  );
  if retried.revision <> saved.revision then
    raise exception 'upload_request_retry_created_a_new_revision';
  end if;
  select count(*) into kept
  from public.cloud_business_snapshot_history
  where user_id = current_setting('history_test.owner_id')::uuid
    and request_id = 'request-92';
  if kept <> 1 then
    raise exception 'upload_request_retry_duplicated_history';
  end if;
  -- 请求台账是内部表，authenticated 无读权限；它的断言放在后面的可信阶段。
  perform set_config('history_test.request_one_revision', saved.revision::text, true);
end
$request_idempotency$;

-- A retry must return the request's own version, never a newer device's version.
do $retry_returns_original_version$
declare
  owner_revision bigint;
  retried public.cloud_business_snapshots;
begin
  owner_revision := public.save_cloud_business_snapshot(
    18,
    jsonb_build_object(
      'schemaVersion', 1,
      'userId', current_setting('history_test.owner_id'),
      'tables', '{}'::jsonb
    ),
    'device-a', 'Pixel 7（Android）', now(), 0,
    null, null, null, 'request-92-second'
  ).revision;
  perform set_config(
    'history_test.request_two_revision', owner_revision::text, true
  );

  -- Another device writes a newer version after this request succeeded.
  perform public.save_cloud_business_snapshot(
    owner_revision,
    jsonb_build_object(
      'schemaVersion', 1,
      'userId', current_setting('history_test.owner_id'),
      'tables', '{}'::jsonb
    ),
    'device-b', 'DESKTOP-ABC（Windows）', now(), 0
  );

  retried := public.save_cloud_business_snapshot(
    18,
    jsonb_build_object(
      'schemaVersion', 1,
      'userId', current_setting('history_test.owner_id'),
      'tables', '{}'::jsonb
    ),
    'device-a', 'Pixel 7（Android）', now(), 0,
    null, null, null, 'request-92-second'
  );
  if retried.revision <> owner_revision then
    raise exception 'retry_returned_current_version_%_instead_of_%',
      retried.revision, owner_revision;
  end if;
  if retried.device_id <> 'device-a' then
    raise exception 'retry_returned_another_device_metadata';
  end if;
end
$retry_returns_original_version$;

-- Reusing a request id for different data must be rejected, not silently applied.
do $request_reuse_with_different_payload$
begin
  begin
    perform public.save_cloud_business_snapshot(
      current_setting('history_test.request_two_revision')::bigint,
      jsonb_build_object(
        'schemaVersion', 1,
        'userId', current_setting('history_test.owner_id'),
        'tables', jsonb_build_object('marker', 'different')
      ),
      'device-a', 'Pixel 7（Android）', now(), 0,
      null, null, null, 'request-92-second'
    );
    raise exception 'request_id_reuse_with_different_data_was_accepted';
  exception
    when sqlstate 'PT422' then null;
  end;
end
$request_reuse_with_different_payload$;

-- Once retention evicted the request's version, a retry must not write again.
do $evicted_request_is_not_rewritten$
declare
  revision bigint := current_setting(
    'history_test.request_two_revision'
  )::bigint;
  current bigint;
  index integer;
  before_count integer;
  after_count integer;
  current_after public.cloud_business_snapshots;
begin
  -- 从实际当前版本继续写，否则 compare-and-swap 会先报 PT409。
  select snapshot.revision into current
  from public.cloud_business_snapshots as snapshot
  where snapshot.user_id = current_setting('history_test.owner_id')::uuid;
  for index in 1..16 loop
    perform public.save_cloud_business_snapshot(
      current,
      jsonb_build_object(
        'schemaVersion', 1,
        'userId', current_setting('history_test.owner_id'),
        'tables', '{}'::jsonb
      ),
      'device-c', 'Filler device', now(), 0
    );
    current := current + 1;
  end loop;

  select count(*) into before_count
  from public.cloud_business_snapshot_history
  where user_id = current_setting('history_test.owner_id')::uuid;
  if exists (
    select 1 from public.cloud_business_snapshot_history
    where user_id = current_setting('history_test.owner_id')::uuid
      and revision = revision
  ) then
    raise exception 'test_setup_failed_to_evict_the_request_version';
  end if;

  begin
    perform public.save_cloud_business_snapshot(
      current,
      jsonb_build_object(
        'schemaVersion', 1,
        'userId', current_setting('history_test.owner_id'),
        'tables', '{}'::jsonb
      ),
      'device-a', 'Pixel 7（Android）', now(), 0,
      null, null, null, 'request-92-second'
    );
    raise exception 'evicted_request_was_rewritten_as_a_new_version';
  exception
    when sqlstate 'PT425' then null;
  end;

  select count(*) into after_count
  from public.cloud_business_snapshot_history
  where user_id = current_setting('history_test.owner_id')::uuid;
  if after_count <> before_count then
    raise exception 'evicted_request_retry_wrote_a_history_row';
  end if;
  select * into current_after
  from public.cloud_business_snapshots
  where user_id = current_setting('history_test.owner_id')::uuid;
  if current_after.revision <> current then
    raise exception 'evicted_request_retry_changed_the_current_version';
  end if;
end
$evicted_request_is_not_rewritten$;

-- History rows are readable but never directly writable by clients.
do $owner_read_and_no_direct_write$
declare
  newest bigint;
begin
  select max(revision) into newest
  from public.cloud_business_snapshots
  where user_id = current_setting('history_test.owner_id')::uuid;
  if not exists (
    select 1 from public.cloud_business_snapshot_history
    where user_id = current_setting('history_test.owner_id')::uuid
      and revision = newest
  ) then
    raise exception 'owner_cannot_read_own_history';
  end if;
  begin
    insert into public.cloud_business_snapshot_history (
      user_id, revision, payload, device_id, device_name,
      data_updated_at, row_count
    ) values (
      current_setting('history_test.owner_id')::uuid,
      9999,
      jsonb_build_object(
        'schemaVersion', 1,
        'userId', current_setting('history_test.owner_id'),
        'tables', '{}'::jsonb
      ),
      'direct-write', 'Direct write', now(), 0
    );
    raise exception 'authenticated_direct_history_write_was_accepted';
  exception
    when insufficient_privilege then null;
  end;
  -- 这是隐私反证：内部台账必须对 authenticated 不可读。正向的台账断言
  -- 一律在 reset role 之后的可信阶段执行，不要在这里补读。
  begin
    perform 1 from public.cloud_business_snapshot_upload_requests
    where user_id = current_setting('history_test.owner_id')::uuid;
    raise exception 'authenticated_can_read_upload_request_ledger';
  exception
    when insufficient_privilege then null;
  end;
end
$owner_read_and_no_direct_write$;

do $other_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('history_test.other_id'),
    true
  );
end
$other_claim$;

do $cross_user_isolation$
begin
  if exists (
    select 1 from public.cloud_business_snapshot_history
    where user_id = current_setting('history_test.owner_id')::uuid
  ) then
    raise exception 'cross_user_history_read_leak';
  end if;
end
$cross_user_isolation$;

reset role;

-- 内部表的断言必须在可信会话里做：台账没有、也不应该有 authenticated 读权限。
do $request_ledger_trusted_checks$
declare
  owner_id uuid := current_setting('history_test.owner_id')::uuid;
  ledger_rows integer;
  first_revision bigint;
  fingerprint text;
  expected_fingerprint text;
begin
  select count(*), min(revision) into ledger_rows, first_revision
  from public.cloud_business_snapshot_upload_requests
  where user_id = owner_id;
  if ledger_rows <> 2 then
    raise exception 'upload_request_ledger_expected_2_rows_kept_%', ledger_rows;
  end if;
  if first_revision <> current_setting('history_test.request_one_revision')::bigint then
    raise exception 'upload_request_ledger_recorded_wrong_first_revision';
  end if;
  select request.payload_fingerprint into fingerprint
  from public.cloud_business_snapshot_upload_requests as request
  where request.user_id = owner_id
    and request.request_id = 'request-92';
  expected_fingerprint := md5(
    jsonb_build_object(
      'schemaVersion', 1,
      'userId', owner_id,
      'tables', '{}'::jsonb
    )::text
  );
  if fingerprint is distinct from expected_fingerprint then
    raise exception 'upload_request_ledger_fingerprint_mismatch';
  end if;
end
$request_ledger_trusted_checks$;

-- 生命周期清除：身份选择与前置条件准备都在可信会话里完成，绝不在
-- authenticated 角色下读 auth.users；随后只以 service_role 执行清除 RPC。

do $purge_function_definition$
declare
  definition text;
begin
  definition := pg_get_functiondef(
    'public.admin_delete_user_business_data(uuid)'::regprocedure
  );
  if position('cloud_business_snapshot_history' in definition) = 0 then
    raise exception 'purge_does_not_delete_snapshot_history';
  end if;
  if position('cloud_business_snapshot_upload_requests' in definition) = 0 then
    raise exception 'purge_does_not_delete_upload_request_ledger';
  end if;
end
$purge_function_definition$;

do $pick_purge_target$
declare
  owner_id uuid := current_setting('history_test.owner_id')::uuid;
  target_id uuid;
begin
  select account.id into target_id
  from auth.users as account
  where account.id <> owner_id
    and account.id not in (select admin.user_id from public.app_admins as admin)
  order by account.created_at desc
  limit 1;
  if target_id is null then
    raise exception 'purge probe requires an isolated non-administrator identity';
  end if;
  perform set_config('history_test.purge_target', target_id::text, true);
end
$pick_purge_target$;

-- 种入待清除的历史与台账，并准备好已过保留期的停用记录；这些都在可信会话
-- 内完成，因此不依赖 service_role 的表权限，也不读取受保护的用户表给客户端。
do $seed_purge_target$
declare
  target_id uuid := current_setting('history_test.purge_target')::uuid;
  owner_id uuid := current_setting('history_test.owner_id')::uuid;
begin
  delete from public.cloud_business_snapshot_upload_requests where user_id = target_id;
  delete from public.cloud_business_snapshot_history where user_id = target_id;
  delete from public.user_purge_receipts where user_id = target_id;
  insert into public.cloud_business_snapshot_history (
    user_id, revision, payload, device_id, device_name,
    data_updated_at, row_count
  ) values (
    target_id,
    1,
    jsonb_build_object(
      'schemaVersion', 1,
      'userId', target_id,
      'tables', '{}'::jsonb
    ),
    'seed', 'Seed', now(), 0
  );
  insert into public.cloud_business_snapshot_upload_requests (
    user_id, request_id, revision, payload_fingerprint
  ) values (
    target_id, 'seed-request', 1, md5('{}'::jsonb::text)
  );
  insert into public.user_suspension_periods (user_id, suspended_at, suspended_by)
  values (target_id, now() - interval '31 days', owner_id)
  on conflict (user_id) where restored_at is null do update
    set suspended_at = excluded.suspended_at;
end
$seed_purge_target$;

set local role service_role;
select public.admin_begin_user_purge(
  current_setting('history_test.purge_target')::uuid,
  current_setting('history_test.owner_id')::uuid
);
select public.admin_delete_user_business_data(
  current_setting('history_test.purge_target')::uuid
);
reset role;

do $purge_probe$
declare
  target_id uuid := current_setting('history_test.purge_target')::uuid;
  history_left integer;
  ledger_left integer;
  snapshot_left integer;
begin
  select count(*) into history_left
  from public.cloud_business_snapshot_history where user_id = target_id;
  select count(*) into ledger_left
  from public.cloud_business_snapshot_upload_requests where user_id = target_id;
  select count(*) into snapshot_left
  from public.cloud_business_snapshots where user_id = target_id;
  if history_left <> 0 or ledger_left <> 0 or snapshot_left <> 0 then
    raise exception 'purge_left_cloud_backups_behind_history_%_ledger_%_snapshot_%',
      history_left, ledger_left, snapshot_left;
  end if;
end
$purge_probe$;

rollback;