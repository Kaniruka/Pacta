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
  -- 这份载荷就是客户端实际导出的形状：19 张业务表全部出现，有数据的表带齐
  -- 该表在 Drift 里的全部列（含可空列显式 null），星期集合是 TEXT 里的 JSON
  -- 文本。test/sync/cloud_snapshot_sql_fixture_test.dart 会读这段 JSON 与真实
  -- 客户端导出逐表逐列比对，因此不要在这里手写不存在的字段。
  payload jsonb := replace(
    $snapshot_v3_fixture$
  {
    "schemaVersion": "3",
    "userId": "__OWNER_ID__",
    "tables": {
      "local_goals": [
        {
          "user_id": "__OWNER_ID__",
          "id": "goal-1",
          "title": "阅读计划",
          "description": "",
          "classification": "regular",
          "created_at": 1763251200,
          "updated_at": 1763251200,
          "deleted_at": null
        }
      ],
      "local_tasks": [
        {
          "user_id": "__OWNER_ID__",
          "id": "task-1",
          "goal_id": "goal-1",
          "title": "读完一章",
          "description": "",
          "classification": "regular",
          "estimated_minutes": 1500,
          "deadline": null,
          "is_complete": 0,
          "focus_progress_seconds": 0,
          "created_at": 1763251200,
          "updated_at": 1763251200,
          "deleted_at": null
        }
      ],
      "local_national_focus_cards": [],
      "local_national_focus_strengthening_levels": [],
      "local_national_focus_requirement_versions": [],
      "local_national_focus_maintenance": [],
      "local_national_focus_failures": [
        {
          "user_id": "__OWNER_ID__",
          "id": "failure-1",
          "batch_id": "batch-1",
          "card_id": "card-1",
          "checkpoint_at": 1763251200,
          "cause": "missed",
          "failure_reason": null,
          "shared_explanation": null,
          "tree_snapshot": "[]",
          "review_disposition": "accepted",
          "reviewed_at": 1763251200
        }
      ],
      "focus_precedent_rules": [],
      "focus_appointments": [
        {
          "user_id": "__OWNER_ID__",
          "id": "appointment-1",
          "task_id": "task-1",
          "mode": "focus",
          "duration_seconds": 1500,
          "started_at": 1763251200,
          "ends_at": 1763252100,
          "status": "scheduled",
          "settled_at": null,
          "session_id": null,
          "failure_reason": null,
          "updated_at": 1763251200,
          "review_disposition": "accepted",
          "review_disposition_updated_at": null,
          "configuration_basis_source_id": null,
          "preparation_seconds": 600
        }
      ],
      "focus_sessions": [],
      "focus_nodes": [],
      "focus_chain_records": [],
      "appointment_chain_records": [],
      "chain_signals": [],
      "focus_sync_sources": [],
      "local_calendar_sources": [],
      "local_calendar_blocks": [],
      "local_schedules": [
        {
          "user_id": "__OWNER_ID__",
          "id": "schedule-1",
          "title": "周会",
          "notes": "",
          "starts_at": 1763251200,
          "ends_at": 1763254800,
          "all_day": 0,
          "all_day_start_date": null,
          "all_day_end_date_exclusive": null,
          "is_completed": 0,
          "completed_at": null,
          "task_id": null,
          "reminder_minutes_before": null,
          "origin": "owned",
          "source_ids": "[]",
          "source_names": "[]",
          "source_event_id": null,
          "occurrence_id": null,
          "event_identity": null,
          "recurrence_id": "rule-1",
          "recurrence_series_id": "series-1",
          "recurrence_date": "2026-11-16",
          "recurrence_time_zone_id": "Asia/Shanghai",
          "recurrence_start_minutes": 540,
          "is_recurrence_exception": 0,
          "is_recurrence_cancelled": 0,
          "created_at": 1763251200,
          "updated_at": 1763251200
        }
      ],
      "local_schedule_recurrences": [
        {
          "user_id": "__OWNER_ID__",
          "id": "rule-1",
          "frequency": "weekly",
          "weekdays": "[1]",
          "first_date": "2026-11-16",
          "end_date": "2026-12-31",
          "time_zone_id": "Asia/Shanghai",
          "all_day": 0,
          "start_minutes_of_day": 540,
          "duration_minutes": 60,
          "day_span": 1,
          "shift_days": 0,
          "title": "周会",
          "notes": "",
          "task_id": null,
          "created_at": 1763251200,
          "updated_at": 1763251200
        }
      ]
    }
  }
$snapshot_v3_fixture$,
    '__OWNER_ID__',
    owner_id
  )::jsonb;
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

  -- 这份载荷还必须是客户端能整体还原的：预约和失败记录引用的任务、卡片都在
  -- 同一份快照里，而不是悬空的外键。
  if jsonb_array_length(saved.payload -> 'tables' -> 'local_tasks') <> 1 then
    raise exception 'complete version 3 upload lost the task its appointment references';
  end if;
  if saved.payload -> 'tables' -> 'focus_appointments' -> 0 ->> 'task_id'
      is distinct from 'task-1' then
    raise exception 'complete version 3 upload lost the appointment task reference';
  end if;
  if saved.payload -> 'tables' -> 'local_goals' -> 0 ->> 'id'
      is distinct from 'goal-1' then
    raise exception 'complete version 3 upload lost the goal its task references';
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

-- Version 3 whose recurrence rule rows lack the r3 template/shift metadata, or
-- carry a normalized calendar date, is malformed as a whole.
do $reject_malformed_three_rules$
declare
  owner_id text := current_setting('schema_v3_test.owner_id');
  missing_title jsonb := jsonb_build_object(
    'schemaVersion', '3',
    'userId', owner_id,
    'tables', jsonb_build_object(
      'local_schedules', '[]'::jsonb,
      'local_schedule_recurrences', jsonb_build_array(jsonb_build_object(
        'user_id', owner_id,
        'id', 'rule-1',
        'frequency', 'weekly',
        'weekdays', '[1]'::jsonb,
        'first_date', '2026-11-16',
        'time_zone_id', 'Asia/Shanghai',
        'shift_days', 0,
        'notes', '',
        'task_id', null
      )),
      'focus_appointments', '[]'::jsonb
    )
  );
  overflow_date jsonb := jsonb_set(
    missing_title,
    '{tables,local_schedule_recurrences,0,title}',
    to_jsonb('周会'::text)
  );
  overflow_date := jsonb_set(
    overflow_date,
    '{tables,local_schedule_recurrences,0,first_date}',
    to_jsonb('2026-02-30'::text)
  );
begin
  begin
    perform public.save_cloud_business_snapshot(
      1, missing_title, 'partial-device', 'Partial device',
      '2026-11-15T02:04:30Z'::timestamptz, 0
    );
    raise exception 'version 3 rule without its template title was accepted';
  exception
    when sqlstate 'PT426' then
      if sqlerrm not like '%malformed%' then
        raise exception 'malformed rule rejection did not name the rules: %', sqlerrm;
      end if;
  end;
  begin
    perform public.save_cloud_business_snapshot(
      1, overflow_date, 'partial-device', 'Partial device',
      '2026-11-15T02:04:45Z'::timestamptz, 0
    );
    raise exception 'version 3 rule with a normalized calendar date was accepted';
  exception
    when sqlstate 'PT426' then null;
  end;
  if (select revision from public.cloud_business_snapshots
      where user_id = auth.uid()) <> 1 then
    raise exception 'rejected malformed rule write changed the snapshot';
  end if;
end
$reject_malformed_three_rules$;

-- The strict union contract rejects rows a client could not restore: unknown IANA
-- zones, missing keys for nullable columns, and wrongly typed nullable values are
-- all refused before any write. Each case derives from the accepted payload.
do $reject_unrestorable_three$
declare
  owner_id text := current_setting('schema_v3_test.owner_id');
  base_payload jsonb;
  unknown_zone jsonb;
  missing_task_key jsonb;
  wrong_task_type jsonb;
  missing_nullable_key jsonb;
begin
  select payload into base_payload
  from public.cloud_business_snapshots
  where user_id = auth.uid();

  unknown_zone := jsonb_set(
    jsonb_set(
      base_payload,
      '{tables,local_schedule_recurrences,0,time_zone_id}',
      to_jsonb('Mars/Olympus'::text)
    ),
    '{tables,local_schedules,0,recurrence_time_zone_id}',
    to_jsonb('Mars/Olympus'::text)
  );
  missing_task_key := jsonb_set(
    base_payload,
    '{tables,local_schedule_recurrences,0}',
    (base_payload -> 'tables' -> 'local_schedule_recurrences' -> 0) - 'task_id'
  );
  wrong_task_type := jsonb_set(
    base_payload,
    '{tables,local_schedule_recurrences,0,task_id}',
    to_jsonb(42)
  );
  missing_nullable_key := jsonb_set(
    base_payload,
    '{tables,local_schedules,0}',
    (base_payload -> 'tables' -> 'local_schedules' -> 0) - 'completed_at'
  );

  begin
    perform public.save_cloud_business_snapshot(
      1, unknown_zone, 'partial-device', 'Partial device',
      '2026-11-15T02:04:10Z'::timestamptz, 1
    );
    raise exception 'version 3 with an unknown IANA zone was accepted';
  exception
    when sqlstate 'PT426' then null;
  end;
  begin
    perform public.save_cloud_business_snapshot(
      1, missing_task_key, 'partial-device', 'Partial device',
      '2026-11-15T02:04:20Z'::timestamptz, 1
    );
    raise exception 'version 3 rule missing a nullable key was accepted';
  exception
    when sqlstate 'PT426' then null;
  end;
  begin
    perform public.save_cloud_business_snapshot(
      1, wrong_task_type, 'partial-device', 'Partial device',
      '2026-11-15T02:04:30Z'::timestamptz, 1
    );
    raise exception 'version 3 rule with a wrongly typed nullable key was accepted';
  exception
    when sqlstate 'PT426' then null;
  end;
  begin
    perform public.save_cloud_business_snapshot(
      1, missing_nullable_key, 'partial-device', 'Partial device',
      '2026-11-15T02:04:40Z'::timestamptz, 1
    );
    raise exception 'version 3 instance missing a nullable key was accepted';
  exception
    when sqlstate 'PT426' then null;
  end;
  if (select revision from public.cloud_business_snapshots
      where user_id = auth.uid()) <> 1 then
    raise exception 'rejected unrestorable payload changed the snapshot';
  end if;
end
$reject_unrestorable_three$;
-- 星期集合的真实协议形状是 TEXT 里的 JSON 文本。任何客户端不会写出的形状
-- （原生 jsonb 数组、坏 JSON、非数组、小数、越界、重复、与频率不匹配）都必须
-- 整体拒绝；逐个破坏同一份已被接受的载荷，确认拒绝后没有半份写入。
do $reject_weekday_shapes$
declare
  owner_id text := current_setting('schema_v3_test.owner_id');
  base_payload jsonb;
  candidate jsonb;
  variant record;
  variants jsonb := jsonb_build_array(
    jsonb_build_object('label', 'native_json_array', 'weekdays', '[1]'::jsonb),
    jsonb_build_object('label', 'malformed_json_text', 'weekdays', to_jsonb('[1'::text)),
    jsonb_build_object('label', 'non_array_text', 'weekdays', to_jsonb('1'::text)),
    jsonb_build_object('label', 'fractional_weekday', 'weekdays', to_jsonb('[1.5]'::text)),
    jsonb_build_object('label', 'weekday_zero', 'weekdays', to_jsonb('[0]'::text)),
    jsonb_build_object('label', 'weekday_eight', 'weekdays', to_jsonb('[8]'::text)),
    jsonb_build_object('label', 'duplicate_weekday', 'weekdays', to_jsonb('[1,1]'::text)),
    jsonb_build_object('label', 'empty_weekly', 'weekdays', to_jsonb('[]'::text)),
    jsonb_build_object('label', 'null_weekdays', 'weekdays', 'null'::jsonb)
  );
begin
  select payload into base_payload
  from public.cloud_business_snapshots
  where user_id = auth.uid();
  if base_payload -> 'tables' -> 'local_schedule_recurrences' -> 0
      ->> 'weekdays' is distinct from '[1]' then
    raise exception 'accepted payload no longer carries the client weekday text';
  end if;
  for variant in select * from jsonb_to_recordset(variants) as item(label text, weekdays jsonb)
  loop
    candidate := jsonb_set(
      base_payload,
      '{tables,local_schedule_recurrences,0,weekdays}',
      coalesce(variant.weekdays, 'null'::jsonb)
    );
    begin
      perform public.save_cloud_business_snapshot(
        1, candidate, 'shape-device', 'Shape device',
        '2026-11-15T02:04:50Z'::timestamptz, 3
      );
      raise exception 'weekdays variant % was accepted', variant.label;
    exception
      when sqlstate 'PT426' then null;
    end;
  end loop;

  -- 频率与星期集合必须一致：daily 不能带星期。
  candidate := jsonb_set(
    base_payload,
    '{tables,local_schedule_recurrences,0,frequency}',
    to_jsonb('daily'::text)
  );
  begin
    perform public.save_cloud_business_snapshot(
      1, candidate, 'shape-device', 'Shape device',
      '2026-11-15T02:04:55Z'::timestamptz, 3
    );
    raise exception 'daily rule with weekday values was accepted';
  exception
    when sqlstate 'PT426' then null;
  end;

  if (select revision from public.cloud_business_snapshots
      where user_id = auth.uid()) <> 1 then
    raise exception 'rejected weekday shapes changed the stored snapshot';
  end if;
end
$reject_weekday_shapes$;


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
