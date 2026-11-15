-- Rollback-only probe for whole-snapshot version 3 (complete core 2 + schedule
-- recurrence). Run against an isolated Supabase project after applying
-- 202611150003_cloud_snapshot_schema_v3.sql (and the migrations it builds on).
-- Requires one active administrator identity; every step is asserted and the
-- whole script rolls back. No production project is contacted.
--
-- Version 3 is the union shape: owned schedules, per-appointment preparation
-- seconds, the recurrence rule table and every instance's recurrence basis,
-- plus the ticket-11 reflection marker. Fresh uploads must be complete 3;
-- version 1 and a complete version 2 are both refused with PT426. The request
-- ledger still wins over the version check, so a request committed before the
-- upgrade replays read-only. Compare-and-swap is unchanged. Rows already stored
-- as version 1/2 stay readable and are never rewritten by this migration.
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
  perform set_config('schema_v3_test.owner_id', owner_id::text, true);
end
$setup$;

set local role authenticated;
do $owner_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('schema_v3_test.owner_id'),
    true
  );
end
$owner_claim$;

-- A complete version 3 payload is accepted as the first upload and stored with
-- every recurrence field, the reflection marker and the preparation duration.
do $accept_complete_version_three$
declare
  owner_id text := current_setting('schema_v3_test.owner_id');
  payload jsonb := jsonb_build_object(
    'schemaVersion', '3',
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
        'updated_at', 1763251200,
        'recurrence_id', 'rule-1',
        'recurrence_series_id', 'series-1',
        'recurrence_date', '2026-11-16',
        'recurrence_time_zone_id', 'Asia/Shanghai',
        'recurrence_start_minutes', 540,
        'is_recurrence_exception', 0,
        'is_recurrence_cancelled', 0
      )),
      'local_schedule_recurrences', jsonb_build_array(jsonb_build_object(
        'user_id', owner_id,
        'id', 'rule-1',
        'frequency', 'weekly',
        'weekdays', '[1]',
        'first_date', '2026-11-16',
        'end_date', '2026-12-31',
        'time_zone_id', 'Asia/Shanghai',
        'all_day', 0,
        'start_minutes_of_day', 540,
        'duration_minutes', 60,
        'day_span', 1,
        'created_at', 1763251200,
        'updated_at', 1763251200
      )),
      'focus_appointments', jsonb_build_array(jsonb_build_object(
        'user_id', owner_id,
        'id', 'appointment-1',
        'task_id', 'task-1',
        'preparation_seconds', 600
      )),
      'local_national_focus_failures', jsonb_build_array(jsonb_build_object(
        'user_id', owner_id,
        'id', 'failure-1',
        'reviewed_at', 1763251200
      )),
      'local_goals', '[]'::jsonb,
      'local_tasks', '[]'::jsonb
    )
  );
  saved public.cloud_business_snapshots;
begin
  saved := public.save_cloud_business_snapshot(
    0, payload, 'probe-device', 'Probe device',
    '2026-11-15T02:00:00Z'::timestamptz, 3, null, null, null,
    'schema-v3-accept'
  );
  if saved.revision <> 1 or saved.payload ->> 'schemaVersion' <> '3' then
    raise exception 'complete version 3 upload was not stored as revision 1';
  end if;
  if saved.payload -> 'tables' -> 'local_schedule_recurrences'
      -> 0 ->> 'frequency' <> 'weekly' then
    raise exception 'stored version 3 payload lost its recurrence rule';
  end if;
  if saved.payload -> 'tables' -> 'local_schedules'
      -> 0 ->> 'recurrence_date' <> '2026-11-16' then
    raise exception 'stored version 3 payload lost its occurrence basis';
  end if;
  if saved.payload -> 'tables' -> 'focus_appointments'
      -> 0 ->> 'preparation_seconds' <> '600' then
    raise exception 'stored version 3 payload lost its preparation duration';
  end if;
  if saved.payload -> 'tables' -> 'local_national_focus_failures'
      -> 0 ->> 'reviewed_at' <> '1763251200' then
    raise exception 'stored version 3 payload lost its reflection marker';
  end if;

  -- Retrying the same request returns the version it produced.
  saved := public.save_cloud_business_snapshot(
    1, payload, 'probe-device', 'Probe device',
    '2026-11-15T02:00:00Z'::timestamptz, 3, null, null, null,
    'schema-v3-accept'
  );
  if saved.revision <> 1 then
    raise exception 'retried version 3 request produced a new revision';
  end if;
end
$accept_complete_version_three$;

-- A brand-new version 1 upload cannot represent any of the version 3 domains.
do $reject_new_version_one$
declare
  legacy_payload jsonb := jsonb_build_object(
    'schemaVersion', '1',
    'userId', current_setting('schema_v3_test.owner_id'),
    'tables', jsonb_build_object('local_goals', '[]'::jsonb)
  );
begin
  begin
    perform public.save_cloud_business_snapshot(
      1, legacy_payload, 'old-device', 'Old device',
      '2026-11-15T02:01:00Z'::timestamptz, 0
    );
    raise exception 'new version 1 upload was accepted';
  exception
    when sqlstate 'PT426' then
      if sqlerrm not like '%outdated%' then
        raise exception 'version 1 rejection did not ask for an upgrade: %', sqlerrm;
      end if;
  end;
  if (select revision from public.cloud_business_snapshots
      where user_id = auth.uid()) <> 1 then
    raise exception 'rejected version 1 upload changed the stored snapshot';
  end if;
end
$reject_new_version_one$;

-- A complete version 2 payload is complete for the older shape but still lacks
-- the recurrence domain, so a fresh version 2 write is refused as a whole.
do $reject_complete_version_two$
declare
  core2_payload jsonb := jsonb_build_object(
    'schemaVersion', '2',
    'userId', current_setting('schema_v3_test.owner_id'),
    'tables', jsonb_build_object(
      'local_schedules', '[]'::jsonb,
      'focus_appointments', jsonb_build_array(jsonb_build_object(
        'user_id', current_setting('schema_v3_test.owner_id'),
        'id', 'appointment-1',
        'task_id', 'task-1',
        'preparation_seconds', 600
      ))
    )
  );
begin
  begin
    perform public.save_cloud_business_snapshot(
      1, core2_payload, 'core2-device', 'Core 2 device',
      '2026-11-15T02:02:00Z'::timestamptz, 1
    );
    raise exception 'complete version 2 upload was accepted as a new write';
  exception
    when sqlstate 'PT426' then
      if sqlerrm not like '%outdated%' then
        raise exception 'version 2 rejection did not ask for an upgrade: %', sqlerrm;
      end if;
  end;
  if (select revision from public.cloud_business_snapshots
      where user_id = auth.uid()) <> 1 then
    raise exception 'rejected version 2 upload changed the stored snapshot';
  end if;
  if (select payload -> 'tables' ->> 'local_schedules'
      from public.cloud_business_snapshots where user_id = auth.uid()) is null then
    raise exception 'rejected version 2 upload erased the stored schedules';
  end if;
end
$reject_complete_version_two$;

-- Version 3 without the owned schedule table is incomplete.
do $reject_partial_three_schedules$
declare
  partial_payload jsonb := jsonb_build_object(
    'schemaVersion', '3',
    'userId', current_setting('schema_v3_test.owner_id'),
    'tables', jsonb_build_object(
      'local_schedule_recurrences', '[]'::jsonb,
      'focus_appointments', '[]'::jsonb
    )
  );
begin
  begin
    perform public.save_cloud_business_snapshot(
      1, partial_payload, 'partial-device', 'Partial device',
      '2026-11-15T02:03:00Z'::timestamptz, 0
    );
    raise exception 'version 3 without schedules was accepted';
  exception
    when sqlstate 'PT426' then
      if sqlerrm not like '%owned schedules%' then
        raise exception 'partial 3 rejection did not name the schedules: %', sqlerrm;
      end if;
  end;
  if (select revision from public.cloud_business_snapshots
      where user_id = auth.uid()) <> 1 then
    raise exception 'rejected partial 3 schedules write changed the snapshot';
  end if;
end
$reject_partial_three_schedules$;

-- Version 3 without the recurrence rule table is incomplete.
do $reject_partial_three_recurrence$
declare
  partial_payload jsonb := jsonb_build_object(
    'schemaVersion', '3',
    'userId', current_setting('schema_v3_test.owner_id'),
    'tables', jsonb_build_object(
      'local_schedules', '[]'::jsonb,
      'focus_appointments', '[]'::jsonb
    )
  );
begin
  begin
    perform public.save_cloud_business_snapshot(
      1, partial_payload, 'partial-device', 'Partial device',
      '2026-11-15T02:04:00Z'::timestamptz, 0
    );
    raise exception 'version 3 without recurrence rules was accepted';
  exception
    when sqlstate 'PT426' then
      if sqlerrm not like '%recurrence rules%' then
        raise exception 'partial 3 rejection did not name the recurrence rules: %', sqlerrm;
      end if;
  end;
  if (select revision from public.cloud_business_snapshots
      where user_id = auth.uid()) <> 1 then
    raise exception 'rejected partial 3 recurrence write changed the snapshot';
  end if;
end
$reject_partial_three_recurrence$;

-- Version 3 whose appointment rows omit the preparation duration is incomplete.
do $reject_partial_three_preparation$
declare
  partial_payload jsonb := jsonb_build_object(
    'schemaVersion', '3',
    'userId', current_setting('schema_v3_test.owner_id'),
    'tables', jsonb_build_object(
      'local_schedules', '[]'::jsonb,
      'local_schedule_recurrences', '[]'::jsonb,
      'focus_appointments', jsonb_build_array(jsonb_build_object(
        'user_id', current_setting('schema_v3_test.owner_id'),
        'id', 'appointment-1',
        'task_id', 'task-1'
      ))
    )
  );
begin
  begin
    perform public.save_cloud_business_snapshot(
      1, partial_payload, 'partial-device', 'Partial device',
      '2026-11-15T02:05:00Z'::timestamptz, 1
    );
    raise exception 'version 3 without preparation duration was accepted';
  exception
    when sqlstate 'PT426' then
      if sqlerrm not like '%preparation%' then
        raise exception 'partial 3 rejection did not name the preparation duration: %', sqlerrm;
      end if;
  end;
  if (select revision from public.cloud_business_snapshots
      where user_id = auth.uid()) <> 1 then
    raise exception 'rejected partial 3 preparation write changed the snapshot';
  end if;
end
$reject_partial_three_preparation$;

-- Compare-and-swap still guards complete version 3 writes.
do $keep_cas_guard$
declare
  payload jsonb := jsonb_build_object(
    'schemaVersion', '3',
    'userId', current_setting('schema_v3_test.owner_id'),
    'tables', jsonb_build_object(
      'local_schedules', '[]'::jsonb,
      'local_schedule_recurrences', '[]'::jsonb,
      'focus_appointments', '[]'::jsonb
    )
  );
begin
  begin
    perform public.save_cloud_business_snapshot(
      0, payload, 'probe-device', 'Probe device',
      '2026-11-15T02:06:00Z'::timestamptz, 0
    );
    raise exception 'stale revision was accepted';
  exception
    when sqlstate 'PT409' then null;
  end;
end
$keep_cas_guard$;

reset role;

-- Trusted-session evidence: the RPC archived the accepted upload and recorded
-- its request ledger entry, which the authenticated role cannot see.
do $private_upload_evidence$
declare
  owner_id uuid := current_setting('schema_v3_test.owner_id')::uuid;
  archived integer;
  ledger integer;
begin
  select count(*) into archived
  from public.cloud_business_snapshot_history
  where user_id = owner_id
    and revision = 1
    and request_id = 'schema-v3-accept';
  if archived <> 1 then
    raise exception 'complete version 3 upload was not archived with its request id';
  end if;
  select count(*) into ledger
  from public.cloud_business_snapshot_upload_requests
  where user_id = owner_id
    and request_id = 'schema-v3-accept'
    and revision = 1;
  if ledger <> 1 then
    raise exception 'complete version 3 upload did not record its request ledger entry';
  end if;
end
$private_upload_evidence$;

-- Seed a request committed before this migration: a version 1 upload that
-- already has its ledger entry.
do $seed_committed_version_one$
declare
  owner_id uuid := current_setting('schema_v3_test.owner_id')::uuid;
  legacy_payload jsonb := jsonb_build_object(
    'schemaVersion', '1',
    'userId', current_setting('schema_v3_test.owner_id'),
    'tables', jsonb_build_object('local_goals', '[]'::jsonb)
  );
begin
  insert into public.cloud_business_snapshot_history (
    user_id, revision, payload, device_id, device_name, data_updated_at,
    uploaded_at, row_count, request_id
  ) values (
    owner_id, 7, legacy_payload, 'legacy-device', 'Legacy device',
    '2026-11-15T00:30:00Z'::timestamptz, '2026-11-15T00:30:00Z'::timestamptz,
    0, 'schema-v3-committed-legacy'
  );
  insert into public.cloud_business_snapshot_upload_requests (
    user_id, request_id, revision, payload_fingerprint
  ) values (
    owner_id, 'schema-v3-committed-legacy', 7, md5(legacy_payload::text)
  );
end
$seed_committed_version_one$;

set local role authenticated;
do $owner_claim_again$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('schema_v3_test.owner_id'),
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
    'userId', current_setting('schema_v3_test.owner_id'),
    'tables', jsonb_build_object('local_goals', '[]'::jsonb)
  );
  changed_payload jsonb := jsonb_build_object(
    'schemaVersion', '1',
    'userId', current_setting('schema_v3_test.owner_id'),
    'tables', jsonb_build_object('local_goals', jsonb_build_array(jsonb_build_object(
      'user_id', current_setting('schema_v3_test.owner_id'),
      'id', 'goal-1'
    )))
  );
  saved public.cloud_business_snapshots;
begin
  saved := public.save_cloud_business_snapshot(
    1, legacy_payload, 'probe-device', 'Probe device',
    '2026-11-15T02:07:00Z'::timestamptz, 0, null, null, null,
    'schema-v3-committed-legacy'
  );
  if saved.revision <> 7 or saved.payload ->> 'schemaVersion' <> '1' then
    raise exception 'committed version 1 replay did not return its own revision';
  end if;
  if (select revision from public.cloud_business_snapshots
      where user_id = auth.uid()) <> 1 then
    raise exception 'committed version 1 replay wrote the current snapshot';
  end if;

  -- Same request id with different content still conflicts.
  begin
    perform public.save_cloud_business_snapshot(
      1, changed_payload, 'probe-device', 'Probe device',
      '2026-11-15T02:07:30Z'::timestamptz, 0, null, null, null,
      'schema-v3-committed-legacy'
    );
    raise exception 'reused request id with different data was accepted';
  exception
    when sqlstate 'PT422' then null;
  end;
end
$replay_committed_version_one$;

reset role;

-- Rows already stored as version 2 stay readable and are not rewritten by the
-- migration. The analysis entrypoint's own contract (including
-- unsupported_snapshot for partial shapes) is covered by its dedicated probe.
do $seed_stored_version_two$
declare
  owner_id uuid := current_setting('schema_v3_test.owner_id')::uuid;
  core2_payload jsonb := jsonb_build_object(
    'schemaVersion', '2',
    'userId', owner_id::text,
    'tables', jsonb_build_object(
      'local_schedules', '[]'::jsonb,
      'focus_appointments', '[]'::jsonb
    )
  );
begin
  update public.cloud_business_snapshots
  set payload = core2_payload
  where user_id = owner_id;
end
$seed_stored_version_two$;

set local role authenticated;
do $owner_claim_final$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('schema_v3_test.owner_id'),
    true
  );
end
$owner_claim_final$;

do $stored_version_two_stays_readable$
declare
  stored jsonb;
begin
  select payload into stored
  from public.cloud_business_snapshots
  where user_id = auth.uid();
  if stored ->> 'schemaVersion' <> '2' then
    raise exception 'stored version 2 row was rewritten to %', stored ->> 'schemaVersion';
  end if;
  if jsonb_typeof(stored -> 'tables' -> 'focus_appointments') <> 'array' then
    raise exception 'stored version 2 row lost its appointment table';
  end if;
end
$stored_version_two_stays_readable$;

rollback;
