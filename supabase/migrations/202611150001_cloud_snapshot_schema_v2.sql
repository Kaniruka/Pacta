-- 业务整份快照载荷版本 2：预约准备时长改为每条预约显式存储。
--
-- 客户端从版本 2 起只写当前版本；服务端写入口同样只接受当前版本。旧客户端
-- （版本 1）上传会丢掉后来新增的列，必须被明确拒绝，而不是靠“未知字段容错”
-- 静默合并。读取侧保留版本 1：现存快照与历史备份继续可读、可恢复，客户端按
-- 已存时间戳补齐缺失列，不重算也不延后正在进行的预约。
--
-- 表约束与历史表都接受 1 和 2：现存行仍是版本 1，放宽约束只是让读写两侧各自
-- 承担自己的校验（写入口拒绝旧版本，读取入口兼容旧版本）。

alter table public.cloud_business_snapshots
  drop constraint if exists cloud_business_snapshots_schema;
alter table public.cloud_business_snapshots
  add constraint cloud_business_snapshots_schema check (
    coalesce(
      payload ->> 'schemaVersion' in ('1', '2')
      and jsonb_typeof(payload -> 'tables') = 'object',
      false
    )
  );

alter table public.cloud_business_snapshot_history
  drop constraint if exists cloud_business_snapshot_history_schema;
alter table public.cloud_business_snapshot_history
  add constraint cloud_business_snapshot_history_schema check (
    coalesce(
      payload ->> 'schemaVersion' in ('1', '2')
      and jsonb_typeof(payload -> 'tables') = 'object',
      false
    )
  );

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
  if p_payload ->> 'schemaVersion' is distinct from '2' then
    if p_payload ->> 'schemaVersion' = '1' then
      raise exception 'snapshot schema version 1 is outdated; upgrade before uploading'
        using errcode = 'PT426';
    end if;
    raise exception 'invalid cloud business snapshot' using errcode = '22023';
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
    or s.payload ->> 'schemaVersion' not in ('1', '2')
    or jsonb_typeof(s.payload -> 'tables') is distinct from 'object'
    or s.payload ->> 'userId' is distinct from g.user_id::text then
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
  'One revisioned whole-account business-data snapshot per user; upload is compare-and-swap and only accepts the current payload schema version.';