-- One explicit, revisioned whole-account business snapshot per user.
create table if not exists public.cloud_business_snapshots (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null check (revision > 0),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  device_id text not null check (btrim(device_id) <> ''),
  device_name text not null check (btrim(device_name) <> ''),
  data_updated_at timestamptz not null,
  uploaded_at timestamptz not null default now(),
  row_count integer not null check (row_count >= 0),
  constraint cloud_business_snapshots_payload_owner check (
    coalesce(payload ->> 'userId' = user_id::text, false)
  ),
  constraint cloud_business_snapshots_schema check (
    coalesce(
      payload ->> 'schemaVersion' = '1'
      and jsonb_typeof(payload -> 'tables') = 'object',
      false
    )
  )
);

alter table public.cloud_business_snapshots enable row level security;
revoke all on table public.cloud_business_snapshots from public, anon, authenticated;
grant select on table public.cloud_business_snapshots to authenticated;

drop policy if exists "active users can read own business snapshot"
  on public.cloud_business_snapshots;
create policy "active users can read own business snapshot"
  on public.cloud_business_snapshots
  for select to authenticated
  using (user_id = auth.uid() and public.current_user_is_active());


-- Produce a deterministic, user-scoped view of the eleven legacy business
-- tables. This helper is callable only by the SECURITY DEFINER read/save RPCs.
create or replace function public.legacy_business_records_for_user(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select jsonb_build_object(
    'goals', (select coalesce(jsonb_agg(item.row_json order by item.row_json::text), '[]'::jsonb) from (select to_jsonb(row_data) as row_json from public.goals as row_data where user_id = p_user_id) as item),
    'tasks', (select coalesce(jsonb_agg(item.row_json order by item.row_json::text), '[]'::jsonb) from (select to_jsonb(row_data) as row_json from public.tasks as row_data where user_id = p_user_id) as item),
    'focus_sessions', (select coalesce(jsonb_agg(item.row_json order by item.row_json::text), '[]'::jsonb) from (select to_jsonb(row_data) as row_json from public.focus_sessions as row_data where user_id = p_user_id) as item),
    'focus_nodes', (select coalesce(jsonb_agg(item.row_json order by item.row_json::text), '[]'::jsonb) from (select to_jsonb(row_data) as row_json from public.focus_nodes as row_data where user_id = p_user_id) as item),
    'focus_chain_records', (select coalesce(jsonb_agg(item.row_json order by item.row_json::text), '[]'::jsonb) from (select to_jsonb(row_data) as row_json from public.focus_chain_records as row_data where user_id = p_user_id) as item),
    'focus_appointments', (select coalesce(jsonb_agg(item.row_json order by item.row_json::text), '[]'::jsonb) from (select to_jsonb(row_data) as row_json from public.focus_appointments as row_data where user_id = p_user_id) as item),
    'appointment_chain_records', (select coalesce(jsonb_agg(item.row_json order by item.row_json::text), '[]'::jsonb) from (select to_jsonb(row_data) as row_json from public.appointment_chain_records as row_data where user_id = p_user_id) as item),
    'focus_precedent_rules', (select coalesce(jsonb_agg(item.row_json order by item.row_json::text), '[]'::jsonb) from (select to_jsonb(row_data) as row_json from public.focus_precedent_rules as row_data where user_id = p_user_id) as item),
    'focus_sync_sources', (select coalesce(jsonb_agg(item.row_json order by item.row_json::text), '[]'::jsonb) from (select to_jsonb(row_data) as row_json from public.focus_sync_sources as row_data where user_id = p_user_id) as item),
    'calendar_sources', (select coalesce(jsonb_agg(item.row_json order by item.row_json::text), '[]'::jsonb) from (select to_jsonb(row_data) as row_json from public.calendar_sources as row_data where user_id = p_user_id) as item),
    'calendar_blocks', (select coalesce(jsonb_agg(item.row_json order by item.row_json::text), '[]'::jsonb) from (select to_jsonb(row_data) as row_json from public.calendar_blocks as row_data where user_id = p_user_id) as item)
  );
$$;
revoke all on function public.legacy_business_records_for_user(uuid)
  from public, anon, authenticated;

create or replace function public.read_legacy_business_records()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  owner_id uuid := auth.uid();
  records jsonb;
  row_count bigint;
begin
  if owner_id is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;
  if not public.current_user_is_active() then
    raise exception 'suspended user cannot read business data'
      using errcode = '42501';
  end if;
  if exists (
    select 1 from public.cloud_business_snapshots
    where user_id = owner_id
  ) then
    return null;
  end if;
  records := public.legacy_business_records_for_user(owner_id);
  select coalesce(sum(jsonb_array_length(value)), 0)
  into row_count
  from jsonb_each(records);
  if row_count = 0 then
    return null;
  end if;
  return jsonb_build_object('records', records, 'token', md5(records::text));
end;
$$;
revoke all on function public.read_legacy_business_records() from public, anon;
grant execute on function public.read_legacy_business_records() to authenticated;

drop function if exists public.save_cloud_business_snapshot(bigint, jsonb, text, text, timestamptz, integer);

create or replace function public.save_cloud_business_snapshot(
  p_expected_revision bigint,
  p_payload jsonb,
  p_device_id text,
  p_device_name text,
  p_data_updated_at timestamptz,
  p_row_count integer,
  p_expected_legacy_token text default null
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
    or p_row_count is null or p_row_count < 0 then
    raise exception 'invalid cloud business snapshot' using errcode = '22023';
  end if;

  -- A per-user transaction lock also serializes the first insert, when there
  -- is no row available for SELECT FOR UPDATE to lock yet.
  perform pg_advisory_xact_lock(hashtextextended(owner_id::text, 0));
  select snapshot.revision into current_revision
  from public.cloud_business_snapshots as snapshot
  where snapshot.user_id = owner_id
  for update;
  current_revision := coalesce(current_revision, 0);
  if current_revision <> p_expected_revision then
    raise exception 'cloud snapshot revision changed; inspect before retrying'
      using errcode = '40001';
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
        using errcode = '40001';
    end if;
  elsif p_expected_legacy_token is not null then
    raise exception 'legacy token is only valid for the initial snapshot'
      using errcode = '22023';
  end if;

  insert into public.cloud_business_snapshots as current_snapshot (
    user_id, revision, payload, device_id, device_name,
    data_updated_at, uploaded_at, row_count
  ) values (
    owner_id, 1, p_payload, p_device_id, p_device_name,
    p_data_updated_at, now(), p_row_count
  )
  on conflict (user_id) do update set
    revision = current_snapshot.revision + 1,
    payload = excluded.payload,
    device_id = excluded.device_id,
    device_name = excluded.device_name,
    data_updated_at = excluded.data_updated_at,
    uploaded_at = now(),
    row_count = excluded.row_count
  returning * into saved;
  return saved;
end;
$$;

revoke all on function public.save_cloud_business_snapshot(
  bigint, jsonb, text, text, timestamptz, integer, text
) from public, anon;
grant execute on function public.save_cloud_business_snapshot(
  bigint, jsonb, text, text, timestamptz, integer, text
) to authenticated;


-- Serialize old-client mutations against both legacy inspection and snapshot
-- upload. After the first canonical snapshot exists, old clients must stop
-- writing business rows rather than diverging silently from the snapshot.
create or replace function public.reject_legacy_write_after_snapshot()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  affected_user uuid;
begin
  affected_user := case when tg_op = 'DELETE' then old.user_id else new.user_id end;
  if affected_user is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(affected_user::text, 0));
  if exists (
    select 1 from public.cloud_business_snapshots
    where user_id = affected_user
  ) then
    raise exception 'whole-account cloud snapshot is active; legacy writes are disabled'
      using errcode = '55000';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.reject_legacy_write_after_snapshot()
  from public, anon;
grant execute on function public.reject_legacy_write_after_snapshot()
  to authenticated;

do $legacy_write_guards$
declare
  legacy_table text;
begin
  foreach legacy_table in array array[
    'goals', 'tasks', 'focus_sessions', 'focus_nodes',
    'focus_chain_records', 'focus_appointments', 'appointment_chain_records',
    'focus_precedent_rules', 'focus_sync_sources', 'calendar_sources',
    'calendar_blocks'
  ] loop
    execute format(
      'drop trigger if exists reject_legacy_write_after_snapshot on public.%I',
      legacy_table
    );
    execute format(
      'create trigger reject_legacy_write_after_snapshot before insert or update or delete on public.%I for each row execute function public.reject_legacy_write_after_snapshot()',
      legacy_table
    );
  end loop;
end;
$legacy_write_guards$;

comment on table public.cloud_business_snapshots is
  'One revisioned whole-account business-data snapshot per user; upload is compare-and-swap.';

-- The existing purge function uses explicit deletes for business tables;
-- include this new table so cloud data is removed before Auth deletion.
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
