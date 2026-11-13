-- Rollback-only checks for retained cloud snapshot history: retention limit,
-- atomic failure, upload request idempotency (including returning the request's
-- original version rather than the current one), request-ledger limits, cross-user
-- RLS and lifecycle clearing. Run against an isolated Supabase project after
-- applying 202611130001_cloud_snapshot_history.sql. Every step is asserted; the
-- last purge probe runs only when the project has a spare non-admin identity and
-- raises a notice instead of pretending to pass.
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
  ledger integer;
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
  select count(*) into ledger
  from public.cloud_business_snapshot_upload_requests
  where user_id = current_setting('history_test.owner_id')::uuid
    and request_id = 'request-92';
  if ledger <> 1 then
    raise exception 'upload_request_ledger_row_missing';
  end if;
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
  index integer;
  before_count integer;
  after_count integer;
  current_after public.cloud_business_snapshots;
begin
  for index in 1..16 loop
    perform public.save_cloud_business_snapshot(
      revision + index - 1,
      jsonb_build_object(
        'schemaVersion', 1,
        'userId', current_setting('history_test.owner_id'),
        'tables', '{}'::jsonb
      ),
      'device-c', 'Filler device', now(), 0
    );
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
      revision + 16,
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
  if current_after.revision <> revision + 16 then
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

-- Lifecycle clearing must cover retained history and the request ledger.
do $purge_covers_history$
declare
  definition text;
  target_id uuid;
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

  select id into target_id
  from auth.users
  where id <> current_setting('history_test.owner_id')::uuid
    and id not in (select user_id from public.app_admins)
  order by created_at desc
  limit 1;
  if target_id is null then
    raise notice 'no spare non-admin identity; dynamic purge probe skipped';
    return;
  end if;
  perform set_config('history_test.purge_target', target_id::text, true);
end
$purge_covers_history$;

do $seed_purge_target$
declare
  target_id uuid := nullif(
    current_setting('history_test.purge_target', true),
    ''
  );
begin
  if target_id is null then
    return;
  end if;
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
end
$seed_purge_target$;

do $purge_probe$
declare
  target_id uuid := nullif(
    current_setting('history_test.purge_target', true),
    ''
  );
  admin_id uuid := current_setting('history_test.owner_id')::uuid;
  before_count integer;
  after_count integer;
  ledger_after integer;
begin
  if target_id is null then
    return;
  end if;
  select count(*) into before_count
  from public.cloud_business_snapshot_history where user_id = target_id;
  perform public.admin_begin_user_purge(target_id, admin_id);
  perform public.admin_delete_user_business_data(target_id);
  select count(*) into after_count
  from public.cloud_business_snapshot_history where user_id = target_id;
  select count(*) into ledger_after
  from public.cloud_business_snapshot_upload_requests where user_id = target_id;
  if before_count = 0 or after_count <> 0 or ledger_after <> 0 then
    raise exception 'purge_left_cloud_backup_history_or_ledger_behind';
  end if;
end
$purge_probe$;

rollback;
