-- Rollback-only probe for the merged whole-snapshot version 2 protocol.
-- Run against an isolated Supabase project after applying
-- 202611150001_cloud_snapshot_schema_v2.sql (and the migrations it builds on).
-- Requires one active administrator identity; every step is asserted and the
-- whole script rolls back. No production project is contacted.
--
-- After the merge, version 2 is a single complete shape: the owned schedule
-- table (ticket 03) plus per-appointment preparation seconds (ticket 08).
-- Both pre-merge halves are refused as a whole, the request ledger still wins
-- over the version check on replay, and compare-and-swap is unchanged.
begin;

do $setup$
declare
  owner_id uuid;
begin
  select user_id into owner_id
  from public.app_admins
  order by user_id
  limit 1;
  if owner_id is null then
    raise exception 'an isolated active administrator is required';
  end if;
  delete from public.cloud_business_snapshot_upload_requests where user_id = owner_id;
  delete from public.cloud_business_snapshot_history where user_id = owner_id;
  delete from public.cloud_business_snapshots where user_id = owner_id;
  delete from public.national_focus_mcp_grants where user_id = owner_id;
  perform set_config('schema_v2_test.owner_id', owner_id::text, true);
end
$setup$;

set local role authenticated;
do $owner_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('schema_v2_test.owner_id'),
    true
  );
end
$owner_claim$;

-- A complete version 2 payload is accepted as the first upload, archived in
-- history, and recorded in the upload request ledger.
do $accept_complete_version_two$
declare
  owner_id text := current_setting('schema_v2_test.owner_id');
  payload jsonb := jsonb_build_object(
    'schemaVersion', '2',
    'userId', owner_id,
    'tables', jsonb_build_object(
      'local_schedules', jsonb_build_array(jsonb_build_object(
        'user_id', owner_id,
        'id', 'schedule-1',
        'title', '周会',
        'starts_at', 1763251200,
        'ends_at', 1763254800,
        'origin', 'owned',
        'created_at', 1763251200,
        'updated_at', 1763251200
      )),
      'focus_appointments', jsonb_build_array(jsonb_build_object(
        'user_id', owner_id,
        'id', 'appointment-1',
        'task_id', 'task-1',
        'preparation_seconds', 600
      )),
      'local_national_focus_cards', '[]'::jsonb,
      'local_national_focus_strengthening_levels', '[]'::jsonb,
      'local_national_focus_requirement_versions', '[]'::jsonb,
      'local_national_focus_maintenance', '[]'::jsonb,
      'local_national_focus_failures', '[]'::jsonb
    )
  );
  saved public.cloud_business_snapshots;
  archived integer;
  ledger integer;
begin
  saved := public.save_cloud_business_snapshot(
    0, payload, 'probe-device', 'Probe device',
    '2026-11-15T01:00:00Z'::timestamptz, 2, null, null, null,
    'schema-v2-accept'
  );
  if saved.revision <> 1 or saved.payload ->> 'schemaVersion' <> '2' then
    raise exception 'complete version 2 upload was not stored as revision 1';
  end if;
  if jsonb_array_length(saved.payload -> 'tables' -> 'local_schedules') <> 1 then
    raise exception 'stored version 2 payload lost its owned schedules';
  end if;
  if saved.payload -> 'tables' -> 'focus_appointments' -> 0
      ->> 'preparation_seconds' is distinct from '600' then
    raise exception 'stored version 2 payload lost its explicit preparation duration';
  end if;
  select count(*) into archived
  from public.cloud_business_snapshot_history
  where user_id = auth.uid() and revision = 1 and request_id = 'schema-v2-accept';
  if archived <> 1 then
    raise exception 'complete version 2 upload was not archived with its request id';
  end if;
  select count(*) into ledger
  from public.cloud_business_snapshot_upload_requests
  where user_id = auth.uid() and request_id = 'schema-v2-accept' and revision = 1;
  if ledger <> 1 then
    raise exception 'complete version 2 upload did not record its request ledger entry';
  end if;

  -- Retrying the same request returns the version it produced.
  saved := public.save_cloud_business_snapshot(
    1, payload, 'probe-device', 'Probe device',
    '2026-11-15T01:00:00Z'::timestamptz, 2, null, null, null,
    'schema-v2-accept'
  );
  if saved.revision <> 1 then
    raise exception 'retried version 2 request produced a new revision';
  end if;
end
$accept_complete_version_two$;

-- A brand-new version 1 upload is refused even as a first upload: it cannot
-- represent the owned schedules or the explicit preparation duration.
do $reject_new_version_one$
declare
  legacy_payload jsonb := jsonb_build_object(
    'schemaVersion', '1',
    'userId', current_setting('schema_v2_test.owner_id'),
    'tables', jsonb_build_object('local_goals', '[]'::jsonb)
  );
begin
  begin
    perform public.save_cloud_business_snapshot(
      1, legacy_payload, 'old-device', 'Old device',
      '2026-11-15T01:01:00Z'::timestamptz, 0
    );
    raise exception 'new version 1 upload was accepted';
  exception
    when sqlstate 'PT426' then null;
  end;
  if (select revision from public.cloud_business_snapshots
      where user_id = auth.uid()) <> 1 then
    raise exception 'rejected version 1 upload changed the stored snapshot';
  end if;
end
$reject_new_version_one$;

-- A version 2 payload without the owned schedule table is one of the two
-- pre-merge halves and must be refused as a whole.
do $reject_partial_version_two_schedules$
declare
  partial_payload jsonb := jsonb_build_object(
    'schemaVersion', '2',
    'userId', current_setting('schema_v2_test.owner_id'),
    'tables', jsonb_build_object('focus_appointments', '[]'::jsonb)
  );
begin
  begin
    perform public.save_cloud_business_snapshot(
      1, partial_payload, 'partial-device', 'Partial device',
      '2026-11-15T01:02:00Z'::timestamptz, 0
    );
    raise exception 'partial version 2 without schedules was accepted';
  exception
    when sqlstate 'PT426' then
      if sqlerrm not like '%owned schedules%' then
        raise exception 'partial version 2 rejection did not name the schedules: %', sqlerrm;
      end if;
  end;
  if (select revision from public.cloud_business_snapshots
      where user_id = auth.uid()) <> 1 then
    raise exception 'rejected partial version 2 changed the stored snapshot';
  end if;
  if (select payload -> 'tables' ->> 'local_schedules' is null
      from public.cloud_business_snapshots where user_id = auth.uid()) then
    raise exception 'rejected partial version 2 erased the stored schedules';
  end if;
end
$reject_partial_version_two_schedules$;

-- A version 2 payload whose appointments omit the explicit preparation
-- duration is the other pre-merge half and must be refused as a whole.
do $reject_partial_version_two_preparation$
declare
  partial_payload jsonb := jsonb_build_object(
    'schemaVersion', '2',
    'userId', current_setting('schema_v2_test.owner_id'),
    'tables', jsonb_build_object(
      'local_schedules', '[]'::jsonb,
      'focus_appointments', jsonb_build_array(jsonb_build_object(
        'user_id', current_setting('schema_v2_test.owner_id'),
        'id', 'appointment-1',
        'task_id', 'task-1'
      ))
    )
  );
begin
  begin
    perform public.save_cloud_business_snapshot(
      1, partial_payload, 'partial-device', 'Partial device',
      '2026-11-15T01:02:30Z'::timestamptz, 1
    );
    raise exception 'partial version 2 without preparation duration was accepted';
  exception
    when sqlstate 'PT426' then
      if sqlerrm not like '%preparation%' then
        raise exception 'partial version 2 rejection did not name the preparation duration: %', sqlerrm;
      end if;
  end;
  if (select revision from public.cloud_business_snapshots
      where user_id = auth.uid()) <> 1 then
    raise exception 'rejected partial version 2 preparation write changed the snapshot';
  end if;
end
$reject_partial_version_two_preparation$;

-- Compare-and-swap still guards complete version 2 writes.
do $keep_cas_guard$
declare
  payload jsonb := jsonb_build_object(
    'schemaVersion', '2',
    'userId', current_setting('schema_v2_test.owner_id'),
    'tables', jsonb_build_object(
      'local_schedules', '[]'::jsonb,
      'focus_appointments', '[]'::jsonb
    )
  );
begin
  begin
    perform public.save_cloud_business_snapshot(
      0, payload, 'probe-device', 'Probe device',
      '2026-11-15T01:03:00Z'::timestamptz, 0
    );
    raise exception 'stale revision was accepted';
  exception
    when sqlstate 'PT409' then null;
  end;
end
$keep_cas_guard$;

reset role;

-- Seed a revision that was committed before the upgrade: its payload is still
-- version 1 and its request ledger entry already exists.
do $seed_committed_version_one$
declare
  owner_id uuid := current_setting('schema_v2_test.owner_id')::uuid;
  legacy_payload jsonb := jsonb_build_object(
    'schemaVersion', '1',
    'userId', current_setting('schema_v2_test.owner_id'),
    'tables', jsonb_build_object('local_goals', '[]'::jsonb)
  );
begin
  insert into public.cloud_business_snapshot_history (
    user_id, revision, payload, device_id, device_name, data_updated_at,
    uploaded_at, row_count, request_id
  ) values (
    owner_id, 7, legacy_payload, 'legacy-device', 'Legacy device',
    '2026-11-15T00:30:00Z'::timestamptz, '2026-11-15T00:30:00Z'::timestamptz,
    0, 'committed-legacy-request'
  );
  insert into public.cloud_business_snapshot_upload_requests (
    user_id, request_id, revision, payload_fingerprint
  ) values (
    owner_id, 'committed-legacy-request', 7, md5(legacy_payload::text)
  );
end
$seed_committed_version_one$;

set local role authenticated;
do $owner_claim_again$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('schema_v2_test.owner_id'),
    true
  );
end
$owner_claim_again$;

-- The ledger is consulted before the version check: a request committed before
-- the upgrade is replayed read-only instead of being rejected as outdated.
do $replay_committed_version_one$
declare
  legacy_payload jsonb := jsonb_build_object(
    'schemaVersion', '1',
    'userId', current_setting('schema_v2_test.owner_id'),
    'tables', jsonb_build_object('local_goals', '[]'::jsonb)
  );
  changed_payload jsonb := jsonb_build_object(
    'schemaVersion', '1',
    'userId', current_setting('schema_v2_test.owner_id'),
    'tables', jsonb_build_object('local_goals', jsonb_build_array(jsonb_build_object(
      'user_id', current_setting('schema_v2_test.owner_id'),
      'id', 'goal-1'
    )))
  );
  saved public.cloud_business_snapshots;
begin
  saved := public.save_cloud_business_snapshot(
    1, legacy_payload, 'probe-device', 'Probe device',
    '2026-11-15T01:04:00Z'::timestamptz, 0, null, null, null,
    'committed-legacy-request'
  );
  if saved.revision <> 7 then
    raise exception 'committed version 1 replay returned revision %', saved.revision;
  end if;
  if saved.payload ->> 'schemaVersion' <> '1' then
    raise exception 'committed version 1 replay rewrote its payload';
  end if;
  if (select revision from public.cloud_business_snapshots
      where user_id = auth.uid()) <> 1 then
    raise exception 'committed version 1 replay wrote the current snapshot';
  end if;

  -- Same request id with different content still conflicts.
  begin
    perform public.save_cloud_business_snapshot(
      1, changed_payload, 'probe-device', 'Probe device',
      '2026-11-15T01:05:00Z'::timestamptz, 1, null, null, null,
      'committed-legacy-request'
    );
    raise exception 'reused request id with different content was accepted';
  exception
    when sqlstate 'PT422' then null;
  end;
end
$replay_committed_version_one$;

reset role;

-- The delegated read accepts a complete version 2 snapshot and refuses an
-- incomplete one instead of reporting it as available.
do $metadata_available$
declare
  owner_id uuid := current_setting('schema_v2_test.owner_id')::uuid;
  metadata jsonb;
begin
  insert into public.national_focus_mcp_clients (id, client_name, redirect_uris)
  values ('schema-v2-probe', 'Schema v2 probe', '[]'::jsonb)
  on conflict (id) do nothing;
  insert into public.national_focus_mcp_grants (user_id, client_id, token_hash, expires_at)
  values (owner_id, 'schema-v2-probe', 'schema-v2-probe-token',
    now() + interval '10 minutes');
  metadata := public.read_national_focus_mcp_metadata('schema-v2-probe-token');
  if metadata ->> 'status' <> 'available' then
    raise exception 'complete version 2 snapshot reported as % instead of available',
      metadata ->> 'status';
  end if;
end
$metadata_available$;

do $metadata_partial_version_two_unsupported$
declare
  owner_id uuid := current_setting('schema_v2_test.owner_id')::uuid;
  metadata jsonb;
begin
  update public.cloud_business_snapshots
  set payload = jsonb_build_object(
    'schemaVersion', '2',
    'userId', current_setting('schema_v2_test.owner_id'),
    'tables', jsonb_build_object(
      'focus_appointments', '[]'::jsonb,
      'local_national_focus_cards', '[]'::jsonb,
      'local_national_focus_strengthening_levels', '[]'::jsonb,
      'local_national_focus_requirement_versions', '[]'::jsonb,
      'local_national_focus_maintenance', '[]'::jsonb,
      'local_national_focus_failures', '[]'::jsonb
    )
  )
  where user_id = owner_id;
  metadata := public.read_national_focus_mcp_metadata('schema-v2-probe-token');
  if metadata ->> 'status' <> 'unsupported_snapshot' then
    raise exception 'partial version 2 snapshot reported as % instead of unsupported',
      metadata ->> 'status';
  end if;
end
$metadata_partial_version_two_unsupported$;

rollback;
