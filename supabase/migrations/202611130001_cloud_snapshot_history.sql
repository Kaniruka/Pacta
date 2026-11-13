-- 含最新份在内的最近 15 份成功写入的云端备份。
-- 写入、版本条件校验、历史落档与淘汰都在 save_cloud_business_snapshot 的
-- 同一事务内完成：只有新版本成功写入后才淘汰最旧版本。
-- 该表不授予任何写入权限，旧客户端只能通过同一个受保护 RPC 上传。
create table if not exists public.cloud_business_snapshot_history (
  user_id uuid not null references auth.users(id) on delete cascade,
  revision bigint not null check (revision > 0),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  device_id text not null check (btrim(device_id) <> ''),
  device_name text not null check (btrim(device_name) <> ''),
  device_manufacturer text
    check (device_manufacturer is null or btrim(device_manufacturer) <> ''),
  device_model text
    check (device_model is null or btrim(device_model) <> ''),
  data_updated_at timestamptz not null,
  uploaded_at timestamptz not null default now(),
  row_count integer not null check (row_count >= 0),
  request_id text check (request_id is null or btrim(request_id) <> ''),
  primary key (user_id, revision),
  constraint cloud_business_snapshot_history_payload_owner check (
    coalesce(payload ->> 'userId' = user_id::text, false)
  ),
  constraint cloud_business_snapshot_history_schema check (
    coalesce(
      payload ->> 'schemaVersion' = '1'
      and jsonb_typeof(payload -> 'tables') = 'object',
      false
    )
  )
);

-- 同一用户同一 upload request id 只落一份历史版本，使上传重试幂等。
create unique index if not exists cloud_business_snapshot_history_request_key
  on public.cloud_business_snapshot_history (user_id, request_id)
  where request_id is not null;

alter table public.cloud_business_snapshot_history enable row level security;
revoke all on table public.cloud_business_snapshot_history
  from public, anon, authenticated;
grant select on table public.cloud_business_snapshot_history to authenticated;

drop policy if exists "active users can read own snapshot history"
  on public.cloud_business_snapshot_history;
create policy "active users can read own snapshot history"
  on public.cloud_business_snapshot_history
  for select to authenticated
  using (user_id = auth.uid() and public.current_user_is_active());

-- 迁移保留现存快照：当前整份快照成为历史中的最新一份。
insert into public.cloud_business_snapshot_history (
  user_id, revision, payload, device_id, device_name,
  device_manufacturer, device_model, data_updated_at, uploaded_at, row_count
)
select
  snapshot.user_id, snapshot.revision, snapshot.payload, snapshot.device_id,
  snapshot.device_name, snapshot.device_manufacturer, snapshot.device_model,
  snapshot.data_updated_at, snapshot.uploaded_at, snapshot.row_count
from public.cloud_business_snapshots as snapshot
on conflict (user_id, revision) do nothing;

-- 旧客户端仍以 7 个或 9 个命名参数调用同一函数；新增参数使用默认值，
-- 因此历史落档与淘汰对所有旧调用同样生效，不存在绕过路径。
drop function if exists public.save_cloud_business_snapshot(
  bigint, jsonb, text, text, timestamptz, integer, text, text, text
);

create function public.save_cloud_business_snapshot(
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
  handled_revision bigint;
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
    or p_payload ->> 'schemaVersion' is distinct from '1'
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

  -- 同一 request id 的重试直接返回已写入结果，既不新增历史版本，也不因
  -- 期望版本已过期而失败。
  if p_request_id is not null then
    select history.revision into handled_revision
    from public.cloud_business_snapshot_history as history
    where history.user_id = owner_id
      and history.request_id = p_request_id;
    if handled_revision is not null then
      select * into saved
      from public.cloud_business_snapshots as snapshot
      where snapshot.user_id = owner_id;
      if found then
        return saved;
      end if;
    end if;
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

comment on table public.cloud_business_snapshot_history is
  'Retained cloud snapshot versions per user: the latest 15 successful writes, newest revision included.';

-- 生命周期清除必须同时删除历史备份：账号清除后不留云端业务数据副本。
create or replace function public.admin_delete_user_business_data(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
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
$$;

revoke all on function public.admin_delete_user_business_data(uuid)
  from public, anon, authenticated;
grant execute on function public.admin_delete_user_business_data(uuid)
  to service_role;
