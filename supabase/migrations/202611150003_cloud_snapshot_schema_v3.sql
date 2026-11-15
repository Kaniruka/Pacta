-- 业务整份快照载荷版本 3（完整形状 + 重复日程）。
--
-- 版本 3 在完整 core 2（自有日程表 local_schedules + 每场预约的
-- preparation_seconds）之上加入重复日程：规则表 local_schedule_recurrences
-- 与每条实例的规则归属、稳定系列身份、原始本地日期、规则时区、开始分钟、
-- 例外与墓碑标记。
--
-- 写入口只接受完整的当前版本：
-- * 全新上传的版本 1 或版本 2 一律拒绝（PT426）：它们缺少重复领域，继续接受
--   会静默丢掉规则与例外；补救动作一致——先升级客户端再上传。
-- * 版本 3 但缺 local_schedules、缺 local_schedule_recurrences、或任一预约行缺
--   preparation_seconds 的残缺载荷同样拒绝（PT426）。判定都在任何写入之前，
--   不会留下半份快照。
-- * 请求台账重放仍是第一步：同一 request_id 且内容相同则返回它原本写入的
--   版本；不同内容 PT422；历史已被淘汰 PT425。升级前已写入的旧请求只读重放，
--   不被版本判定改写。
--
-- 读取侧保留 1、2、3：现存快照与历史备份继续可读、可恢复。客户端对 1/2 做
-- 逐字段显式转换（空规则表 + 非重复默认值），而不是依赖未知字段容错。服务端
-- 读路径把残缺的 pre-merge 2 与残缺 3 都判为 unsupported_snapshot。
--
-- 表约束与历史表接受 1、2、3：现存行仍是历史版本，放宽约束只是让读写两侧各自
-- 承担自己的校验。001（core v2）与 002（账号资料）保持不变。
--
-- 其余行为保持不变：每用户 advisory lock、revision CAS（PT409）、旧令牌守卫、
-- 历史落档与 15 个版本保留清扫、RLS 与函数授权。

alter table public.cloud_business_snapshots
  drop constraint if exists cloud_business_snapshots_schema;
alter table public.cloud_business_snapshots
  add constraint cloud_business_snapshots_schema check (
    coalesce(
      payload ->> 'schemaVersion' in ('1', '2', '3')
      and jsonb_typeof(payload -> 'tables') = 'object',
      false
    )
  );

alter table public.cloud_business_snapshot_history
  drop constraint if exists cloud_business_snapshot_history_schema;
alter table public.cloud_business_snapshot_history
  add constraint cloud_business_snapshot_history_schema check (
    coalesce(
      payload ->> 'schemaVersion' in ('1', '2', '3')
      and jsonb_typeof(payload -> 'tables') = 'object',
      false
    )
  );

comment on constraint cloud_business_snapshots_schema
  on public.cloud_business_snapshots is
  'Accepts snapshot schema versions 1, 2 and 3; version 3 adds the schedule recurrence rules and per-instance recurrence basis on top of complete core 2.';

-- 写入口：结构与归属校验沿用原错误码，版本单独判定。
-- 版本 1 使用独立错误码，便于旧客户端把它识别为“需要先升级”，而不是普通
-- 非法载荷。
create or replace function public.save_cloud_business_snapshot(
  p_expected_revision bigint,
  p_payload jsonb,
  p_device_id text,
  p_device_name text,
  p_data_updated_at timestamptz,
  p_row_count integer,
  p_expected_legacy_token text default null,
  p_device_manufacturer text default null,
  p_device_model text default null,
  p_request_id text default null
)
returns public.cloud_business_snapshots
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  saved public.cloud_business_snapshots;
  owner_id uuid := auth.uid();
  current_revision bigint;
  current_legacy_records jsonb;
  current_legacy_token text;
  legacy_row_count bigint;
  handled_request public.cloud_business_snapshot_upload_requests;
  payload_fingerprint text := md5(p_payload::text);
begin
  if owner_id is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;
  if not public.current_user_is_active() then
    raise exception 'suspended user cannot upload business data'
      using errcode = '42501';
  end if;
  if p_expected_revision is null or p_expected_revision < 0
    or p_payload is null
    or jsonb_typeof(p_payload) <> 'object'
    or p_payload ->> 'userId' is distinct from owner_id::text
    or jsonb_typeof(p_payload -> 'tables') is distinct from 'object'
    or p_device_id is null or btrim(p_device_id) = ''
    or p_device_name is null or btrim(p_device_name) = ''
    or p_data_updated_at is null
    or p_row_count is null or p_row_count < 0
    or (p_device_manufacturer is not null and btrim(p_device_manufacturer) = '')
    or (p_device_model is not null and btrim(p_device_model) = '')
    or (p_request_id is not null
      and (btrim(p_request_id) = '' or length(p_request_id) > 200)) then
    raise exception 'invalid cloud business snapshot' using errcode = '22023';
  end if;
  -- A per-user transaction lock also serializes the first insert, when there
  -- is no row available for SELECT FOR UPDATE to lock yet.
  perform pg_advisory_xact_lock(hashtextextended(owner_id::text, 0));

  -- 同一 request id 的重试返回该请求原本写入的版本，绝不返回当前版本：
  -- 否则调用方会把别的设备的数据标记成本机已处理。
  if p_request_id is not null then
    select * into handled_request
    from public.cloud_business_snapshot_upload_requests as request
    where request.user_id = owner_id
      and request.request_id = p_request_id;
    if found then
      if handled_request.payload_fingerprint <> payload_fingerprint then
        raise exception 'upload request id was reused with different data'
          using errcode = 'PT422';
      end if;
      select
        history.user_id, history.revision, history.payload, history.device_id,
        history.device_name, history.data_updated_at, history.uploaded_at,
        history.row_count, history.device_manufacturer, history.device_model
      into saved
      from public.cloud_business_snapshot_history as history
      where history.user_id = owner_id
        and history.revision = handled_request.revision;
      if found then
        return saved;
      end if;
      -- 原版本已被保留上限淘汰：台账仍证明该请求已处理，但不能当作新请求重写。
      raise exception 'upload request was already handled but its backup is no longer retained'
        using errcode = 'PT425';
    end if;
  end if;

  -- 版本判定放在请求台账之后：升级前已经写入的旧版本请求，重试时仍按原
  -- 请求身份读取它产生的版本（只读返回），不重复写入，也不改写它的载荷。
  -- 只有全新的上传才被要求使用当前载荷版本。
  if p_payload ->> 'schemaVersion' is distinct from '3' then
    if p_payload ->> 'schemaVersion' in ('1', '2') then
      raise exception 'snapshot schema version % is outdated; upgrade before uploading',
        p_payload ->> 'schemaVersion'
        using errcode = 'PT426';
    end if;
    raise exception 'invalid cloud business snapshot' using errcode = '22023';
  end if;

  -- 残缺版本 2：合并前两个客户端各自只写过一半，任一残缺载荷整体拒绝。
  -- 判定在任何写入之前，因此不会留下半份快照；错误码沿用 PT426（补救动作
  -- 同样是先升级再上传），消息区分缺日程表与缺准备时长两种情况。
  if jsonb_typeof(p_payload -> 'tables' -> 'local_schedules') is distinct from 'array' then
    raise exception 'snapshot payload version 3 is incomplete: owned schedules are missing; upgrade before uploading'
      using errcode = 'PT426';
  end if;
  if jsonb_typeof(p_payload -> 'tables' -> 'focus_appointments') = 'array'
    and exists (
      select 1
      from jsonb_array_elements(p_payload -> 'tables' -> 'focus_appointments') as appointment
      where jsonb_typeof(appointment) = 'object'
        and not jsonb_exists(appointment, 'preparation_seconds')
    ) then
    raise exception 'snapshot payload version 3 is incomplete: appointment preparation duration is missing; upgrade before uploading'
      using errcode = 'PT426';
  end if;

  if jsonb_typeof(p_payload -> 'tables' -> 'local_schedule_recurrences') is distinct from 'array' then
    raise exception 'snapshot payload version 3 is incomplete: schedule recurrence rules are missing; upgrade before uploading'
      using errcode = 'PT426';
  end if;

  -- r3：重复领域是严格并集。规则行必须带齐全部列（可空列也必须出现，值可为
  -- null），并逐字段校验类型与取值。任何子表达式为 NULL（例如缺键）都会让整行
  -- 谓词变成 NULL，因此统一用 "is not true" 判定：不合格或无法判定都拒绝，绝不
  -- 让 SQL 三值逻辑把坏行放过去。
  --
  -- 时区使用 PostgreSQL 自带的 IANA 目录（与 02 的资料时区校验同一来源），
  -- 不把导入/重复限制成界面上的 7 个城市；客户端 supported 集合是它的子集。
  if exists (
    select 1
    from jsonb_array_elements(p_payload -> 'tables' -> 'local_schedule_recurrences') as rule
    where (
      jsonb_typeof(rule) = 'object'
      and rule ?& array[
        'user_id', 'id', 'frequency', 'weekdays', 'first_date', 'end_date',
        'time_zone_id', 'all_day', 'start_minutes_of_day', 'duration_minutes',
        'day_span', 'shift_days', 'title', 'notes', 'task_id',
        'created_at', 'updated_at'
      ]
      and jsonb_typeof(rule -> 'user_id') = 'string'
      and rule ->> 'user_id' = owner_id::text
      and jsonb_typeof(rule -> 'id') = 'string'
      and btrim(rule ->> 'id') <> ''
      and rule ->> 'frequency' in ('daily', 'weekly')
      and jsonb_typeof(rule -> 'weekdays') = 'array'
      and (
        (rule ->> 'frequency' = 'weekly'
          and jsonb_array_length(rule -> 'weekdays') >= 1)
        or (rule ->> 'frequency' = 'daily'
          and jsonb_array_length(rule -> 'weekdays') = 0)
      )
      and not exists (
        select 1
        from jsonb_array_elements(rule -> 'weekdays') as day
        where jsonb_typeof(day) <> 'number'
          or (day #>> '{}')::numeric <> trunc((day #>> '{}')::numeric)
          or (day #>> '{}')::int not between 1 and 7
      )
      and jsonb_typeof(rule -> 'time_zone_id') = 'string'
      and (rule ->> 'time_zone_id') in (select name from pg_timezone_names)
      and jsonb_typeof(rule -> 'all_day') = 'number'
      and rule ->> 'all_day' in ('0', '1')
      and jsonb_typeof(rule -> 'start_minutes_of_day') = 'number'
      and (rule ->> 'start_minutes_of_day')::int between 0 and 1439
      and jsonb_typeof(rule -> 'duration_minutes') = 'number'
      and (rule ->> 'duration_minutes')::int >= 1
      and jsonb_typeof(rule -> 'day_span') = 'number'
      and (rule ->> 'day_span')::int >= 1
      and jsonb_typeof(rule -> 'shift_days') = 'number'
      and (rule ->> 'shift_days')::numeric = trunc((rule ->> 'shift_days')::numeric)
      and (rule ->> 'shift_days')::int between -3660 and 3660
      and jsonb_typeof(rule -> 'title') = 'string'
      and btrim(rule ->> 'title') <> ''
      and jsonb_typeof(rule -> 'notes') = 'string'
      and jsonb_typeof(rule -> 'task_id') in ('string', 'null')
      and (rule ->> 'task_id' is null or btrim(rule ->> 'task_id') <> '')
      and jsonb_typeof(rule -> 'first_date') = 'string'
      and (rule ->> 'first_date') ~ '^\d{4}-\d{2}-\d{2}$'
      and to_char(to_date(rule ->> 'first_date', 'YYYY-MM-DD'), 'YYYY-MM-DD')
        = (rule ->> 'first_date')
      and jsonb_typeof(rule -> 'end_date') in ('string', 'null')
      and (
        rule ->> 'end_date' is null
        or (
          (rule ->> 'end_date') ~ '^\d{4}-\d{2}-\d{2}$'
          and to_char(to_date(rule ->> 'end_date', 'YYYY-MM-DD'), 'YYYY-MM-DD')
            = (rule ->> 'end_date')
          and (rule ->> 'end_date') >= (rule ->> 'first_date')
        )
      )
      and jsonb_typeof(rule -> 'created_at') = 'number'
      and jsonb_typeof(rule -> 'updated_at') = 'number'
    ) is not true
  ) then
    raise exception 'snapshot payload version 3 is incomplete: schedule recurrence rules are malformed; upgrade before uploading'
      using errcode = 'PT426';
  end if;

  -- 实例行同样必须带齐列。非重复行的重复领域必须整体为空；重复行的原始身份必须
  -- 是真实日历日，时区必须可用且与所属规则一致，否则客户端恢复后无法展开。
  if exists (
    select 1
    from jsonb_array_elements(p_payload -> 'tables' -> 'local_schedules') as instance
    where (
      jsonb_typeof(instance) = 'object'
      and instance ?& array[
        'user_id', 'id', 'title', 'notes', 'starts_at', 'ends_at', 'all_day',
        'all_day_start_date', 'all_day_end_date_exclusive', 'is_completed',
        'completed_at', 'task_id', 'reminder_minutes_before', 'origin',
        'source_ids', 'source_names', 'source_event_id', 'occurrence_id',
        'event_identity', 'recurrence_id', 'recurrence_series_id',
        'recurrence_date', 'recurrence_time_zone_id',
        'recurrence_start_minutes', 'is_recurrence_exception',
        'is_recurrence_cancelled', 'created_at', 'updated_at'
      ]
      and (
        (
          jsonb_typeof(instance -> 'recurrence_id') = 'null'
          and jsonb_typeof(instance -> 'recurrence_series_id') = 'null'
          and jsonb_typeof(instance -> 'recurrence_date') = 'null'
          and jsonb_typeof(instance -> 'recurrence_time_zone_id') = 'null'
          and jsonb_typeof(instance -> 'recurrence_start_minutes') = 'null'
          and instance ->> 'is_recurrence_exception' = '0'
          and instance ->> 'is_recurrence_cancelled' = '0'
        )
        or (
          jsonb_typeof(instance -> 'recurrence_id') = 'string'
          and btrim(instance ->> 'recurrence_id') <> ''
          and jsonb_typeof(instance -> 'recurrence_series_id') = 'string'
          and btrim(instance ->> 'recurrence_series_id') <> ''
          and jsonb_typeof(instance -> 'recurrence_date') = 'string'
          and (instance ->> 'recurrence_date') ~ '^\d{4}-\d{2}-\d{2}$'
          and to_char(
            to_date(instance ->> 'recurrence_date', 'YYYY-MM-DD'),
            'YYYY-MM-DD'
          ) = (instance ->> 'recurrence_date')
          and jsonb_typeof(instance -> 'recurrence_time_zone_id') = 'string'
          and (instance ->> 'recurrence_time_zone_id')
            in (select name from pg_timezone_names)
          and jsonb_typeof(instance -> 'recurrence_start_minutes')
            in ('number', 'null')
          and (
            instance ->> 'recurrence_start_minutes' is null
            or (instance ->> 'recurrence_start_minutes')::int between 0 and 1439
          )
          and instance ->> 'is_recurrence_exception' in ('0', '1')
          and instance ->> 'is_recurrence_cancelled' in ('0', '1')
          and exists (
            select 1
            from jsonb_array_elements(
              p_payload -> 'tables' -> 'local_schedule_recurrences'
            ) as rule
            where rule ->> 'id' = instance ->> 'recurrence_id'
              and rule ->> 'user_id' = instance ->> 'user_id'
              and rule ->> 'time_zone_id'
                = instance ->> 'recurrence_time_zone_id'
          )
        )
      )
    ) is not true
  ) then
    raise exception 'snapshot payload version 3 is incomplete: schedule recurrence identity is malformed; upgrade before uploading'
      using errcode = 'PT426';
  end if;

  select snapshot.revision into current_revision
  from public.cloud_business_snapshots as snapshot
  where snapshot.user_id = owner_id
  for update;
  current_revision := coalesce(current_revision, 0);
  if current_revision <> p_expected_revision then
    raise exception 'cloud snapshot revision changed; inspect before retrying'
      using errcode = 'PT409';
  end if;
  if current_revision = 0 then
    current_legacy_records := public.legacy_business_records_for_user(owner_id);
    select coalesce(sum(jsonb_array_length(value)), 0)
    into legacy_row_count
    from jsonb_each(current_legacy_records);
    if legacy_row_count > 0 then
      current_legacy_token := md5(current_legacy_records::text);
    else
      current_legacy_token := null;
    end if;
    if p_expected_legacy_token is distinct from current_legacy_token then
      raise exception 'legacy cloud data changed; inspect before retrying'
        using errcode = 'PT409';
    end if;
  elsif p_expected_legacy_token is not null then
    raise exception 'legacy token is only valid for the initial snapshot'
      using errcode = '22023';
  end if;

  insert into public.cloud_business_snapshots as current_snapshot (
    user_id, revision, payload, device_id, device_name,
    data_updated_at, uploaded_at, row_count,
    device_manufacturer, device_model
  ) values (
    owner_id, 1, p_payload, p_device_id, p_device_name,
    p_data_updated_at, now(), p_row_count,
    p_device_manufacturer, p_device_model
  )
  on conflict (user_id) do update set
    revision = current_snapshot.revision + 1,
    payload = excluded.payload,
    device_id = excluded.device_id,
    device_name = excluded.device_name,
    data_updated_at = excluded.data_updated_at,
    uploaded_at = now(),
    row_count = excluded.row_count,
    device_manufacturer = excluded.device_manufacturer,
    device_model = excluded.device_model
  returning * into saved;

  -- 历史落档与快照写入同一事务：任一步失败都不会留下半份版本。
  insert into public.cloud_business_snapshot_history (
    user_id, revision, payload, device_id, device_name,
    device_manufacturer, device_model, data_updated_at, uploaded_at,
    row_count, request_id
  ) values (
    saved.user_id, saved.revision, saved.payload, saved.device_id,
    saved.device_name, saved.device_manufacturer, saved.device_model,
    saved.data_updated_at, saved.uploaded_at, saved.row_count, p_request_id
  );

  if p_request_id is not null then
    insert into public.cloud_business_snapshot_upload_requests (
      user_id, request_id, revision, payload_fingerprint
    ) values (
      owner_id, p_request_id, saved.revision, payload_fingerprint
    );
  end if;

  -- 新版本已写入后才淘汰超出的最旧版本。
  delete from public.cloud_business_snapshot_history as stale
  where stale.user_id = owner_id
    and stale.revision not in (
      select retained.revision
      from public.cloud_business_snapshot_history as retained
      where retained.user_id = owner_id
      order by retained.revision desc
      limit 15
    );

  return saved;
end;
$$;

revoke all on function public.save_cloud_business_snapshot(
  bigint, jsonb, text, text, timestamptz, integer, text, text, text, text
) from public, anon;
grant execute on function public.save_cloud_business_snapshot(
  bigint, jsonb, text, text, timestamptz, integer, text, text, text, text
) to authenticated;

-- 只读分析入口读取 1 与 2 两个版本：现存版本 1 快照继续可分析，
-- 新上传的版本 2 不被当成 unsupported_snapshot。
create or replace function public.read_national_focus_mcp_metadata(
  p_token_hash text, p_expected_revision bigint default null
) returns jsonb language plpgsql stable security definer set search_path = public, pg_catalog as $$
declare g public.national_focus_mcp_grants; s public.cloud_business_snapshots; table_name text; old_format boolean := false;
begin
  select * into g from public.national_focus_mcp_grants
    where token_hash = p_token_hash and revoked_at is null and expires_at > now();
  if not found or not exists(select 1 from auth.users where id = g.user_id)
    or exists(select 1 from public.user_suspension_periods
      where user_id = g.user_id and restored_at is null) then
    raise exception 'invalid delegate' using errcode = '28000';
  end if;
  select * into s from public.cloud_business_snapshots where user_id = g.user_id;
  if not found then
    return jsonb_build_object('contract_version', 1, 'status',
      case when exists(select 1 from jsonb_each(public.legacy_business_records_for_user(g.user_id))
        where jsonb_array_length(value) > 0) then 'legacy_snapshot' else 'no_snapshot' end,
      'revision', null, 'source_device', null, 'uploaded_at', null,
      'recovery', 'Manually upload a whole-data snapshot in Pacta.');
  end if;
  if p_expected_revision is not null and s.revision <> p_expected_revision then
    raise exception 'snapshot revision changed' using errcode = 'PT409';
  end if;
  foreach table_name in array array['local_national_focus_cards',
    'local_national_focus_strengthening_levels', 'local_national_focus_requirement_versions',
    'local_national_focus_maintenance', 'local_national_focus_failures'] loop
    if jsonb_typeof(s.payload -> 'tables' -> table_name) is distinct from 'array' then
      old_format := true;
    elsif exists(select 1 from jsonb_array_elements(s.payload -> 'tables' -> table_name) row_data
      where jsonb_typeof(row_data) is distinct from 'object'
        or row_data ->> 'user_id' is distinct from g.user_id::text) then
      old_format := true;
    end if;
  end loop;
  if not old_format and exists(select 1 from jsonb_array_elements(s.payload -> 'tables' -> 'local_national_focus_cards') row_data
    where jsonb_typeof(row_data -> 'name') is distinct from 'string' or btrim(coalesce(row_data ->> 'name', '')) = '') then
    old_format := true;
  end if;
  if old_format
    or s.payload ->> 'schemaVersion' is null
    or s.payload ->> 'schemaVersion' not in ('1', '2', '3')
    or jsonb_typeof(s.payload -> 'tables') is distinct from 'object'
    or s.payload ->> 'userId' is distinct from g.user_id::text
    -- 残缺版本 2 不是可分析的完整快照；版本 1 本来就没有日程表。
    or (s.payload ->> 'schemaVersion' = '2'
      and jsonb_typeof(s.payload -> 'tables' -> 'local_schedules') is distinct from 'array')
    or (s.payload ->> 'schemaVersion' = '3'
      and (jsonb_typeof(s.payload -> 'tables' -> 'local_schedules') is distinct from 'array'
        or jsonb_typeof(s.payload -> 'tables' -> 'local_schedule_recurrences') is distinct from 'array')) then
    return jsonb_build_object('contract_version', 1, 'status', 'unsupported_snapshot',
      'revision', s.revision, 'source_device', null, 'uploaded_at', null,
      'recovery', 'Update Pacta and manually upload a whole-data snapshot.');
  end if;
  return jsonb_build_object('contract_version', 1, 'status', 'available',
    'revision', s.revision, 'source_device', jsonb_build_object('id', s.device_id, 'name', s.device_name),
    'uploaded_at', s.uploaded_at, 'data_updated_at', s.data_updated_at,
    'freshness', 'latest_manual_upload');
end;
$$;
revoke all on function public.read_national_focus_mcp_metadata(text, bigint)
  from public, anon, authenticated;
grant execute on function public.read_national_focus_mcp_metadata(text, bigint)
  to service_role;

comment on table public.cloud_business_snapshots is
  'One revisioned whole-account business-data snapshot per user; upload is compare-and-swap and only accepts the complete current payload schema version (owned schedules, per-appointment preparation seconds and schedule recurrence rules with per-instance basis).';