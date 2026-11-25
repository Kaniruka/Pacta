-- National Focus MCP v2: Scoped Bearer Tokens, audit log, and constrained
-- read-write snapshot mutations with CAS + automatic 15-snapshot history.
-- Replaces legacy OAuth DCR endpoints, tables, and RPCs.

drop trigger if exists national_focus_mcp_client_capacity on public.national_focus_mcp_clients;
drop trigger if exists national_focus_mcp_request_capacity on public.national_focus_mcp_requests;

drop function if exists public.guard_national_focus_mcp_allocation();
drop function if exists public.inspect_national_focus_mcp_request(text);
drop function if exists public.approve_national_focus_mcp_connection(text, boolean);
drop function if exists public.exchange_national_focus_mcp_code(text, text, text, text, text, text);
drop function if exists public.list_national_focus_mcp_grants();
drop function if exists public.revoke_national_focus_mcp_grant(uuid);
drop function if exists public.read_national_focus_mcp_history_snapshot(text, bigint);
drop function if exists public.read_national_focus_mcp_snapshot(text, bigint);
drop function if exists public.read_national_focus_mcp_metadata(text, bigint);

drop table if exists public.national_focus_mcp_requests;
drop table if exists public.national_focus_mcp_grants;
drop table if exists public.national_focus_mcp_clients;

create table public.national_focus_mcp_grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null check (btrim(label) <> '' and length(label) <= 80),
  agent_preset text check (agent_preset is null or (btrim(agent_preset) <> '' and length(agent_preset) <= 40)),
  scope text not null check (scope in ('national_focus:read', 'national_focus:readwrite')),
  token_hash text not null unique,
  token_prefix text not null check (btrim(token_prefix) <> '' and length(token_prefix) <= 32),
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  last_used_at timestamptz,
  revoked_at timestamptz
);

create index national_focus_mcp_grants_owner_created_idx
  on public.national_focus_mcp_grants (user_id, created_at desc);

create table public.national_focus_mcp_audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  grant_id uuid references public.national_focus_mcp_grants(id) on delete set null,
  grant_label text not null check (btrim(grant_label) <> '' and length(grant_label) <= 80),
  tool_name text not null check (btrim(tool_name) <> '' and length(tool_name) <= 100),
  action_kind text not null check (action_kind in ('read', 'write')),
  summary text not null check (btrim(summary) <> '' and length(summary) <= 240),
  snapshot_revision bigint,
  created_at timestamptz not null default now()
);

create index national_focus_mcp_audit_logs_owner_created_idx
  on public.national_focus_mcp_audit_logs (user_id, created_at desc);

alter table public.national_focus_mcp_grants enable row level security;
alter table public.national_focus_mcp_audit_logs enable row level security;

revoke all on table public.national_focus_mcp_grants, public.national_focus_mcp_audit_logs
  from public, anon, authenticated;
grant all on table public.national_focus_mcp_grants, public.national_focus_mcp_audit_logs
  to service_role;

-- Authenticated App RPCs (never expose token_hash or other users' rows).
create function public.create_national_focus_mcp_grant(
  p_label text,
  p_scope text,
  p_ttl_seconds integer default null,
  p_agent_preset text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  owner_id uuid := auth.uid();
  clean_label text := btrim(coalesce(p_label, ''));
  clean_preset text := nullif(btrim(coalesce(p_agent_preset, '')), '');
  raw_token text;
  hashed_token text;
  prefix_label text;
  expiry timestamptz;
  created_row public.national_focus_mcp_grants;
begin
  if owner_id is null or not public.current_user_is_active() then
    raise exception 'active user required' using errcode = '42501';
  end if;
  if clean_label = '' or length(clean_label) > 80
    or p_scope not in ('national_focus:read', 'national_focus:readwrite')
    or (clean_preset is not null and length(clean_preset) > 40)
    or (p_ttl_seconds is not null and (p_ttl_seconds < 60 or p_ttl_seconds > 315360000)) then
    raise exception 'invalid grant parameters' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('mcp-grant:' || owner_id::text, 0));

  if (
    select count(*)
    from public.national_focus_mcp_grants
    where user_id = owner_id
      and revoked_at is null
      and (expires_at is null or expires_at > now())
  ) >= 20 then
    raise exception 'too many active mcp connections' using errcode = 'PT429';
  end if;

  raw_token := 'pacta_mcp_'
    || replace(gen_random_uuid()::text, '-', '')
    || replace(gen_random_uuid()::text, '-', '');
  hashed_token := encode(sha256(convert_to(raw_token, 'UTF8')), 'hex');
  prefix_label := left(raw_token, 14) || '...';
  expiry := case
    when p_ttl_seconds is null then null
    else now() + make_interval(secs => p_ttl_seconds)
  end;

  insert into public.national_focus_mcp_grants (
    user_id, label, agent_preset, scope, token_hash, token_prefix, expires_at
  ) values (
    owner_id, clean_label, clean_preset, p_scope, hashed_token, prefix_label, expiry
  )
  returning * into created_row;

  return jsonb_build_object(
    'id', created_row.id,
    'label', created_row.label,
    'agent_preset', created_row.agent_preset,
    'scope', created_row.scope,
    'token_prefix', created_row.token_prefix,
    'created_at', created_row.created_at,
    'expires_at', created_row.expires_at,
    'last_used_at', created_row.last_used_at,
    'revoked_at', created_row.revoked_at,
    'token', raw_token
  );
end;
$$;

create function public.list_national_focus_mcp_grants()
returns table(
  id uuid,
  label text,
  agent_preset text,
  scope text,
  token_prefix text,
  created_at timestamptz,
  expires_at timestamptz,
  last_used_at timestamptz,
  revoked_at timestamptz
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select
    g.id,
    g.label,
    g.agent_preset,
    g.scope,
    g.token_prefix,
    g.created_at,
    g.expires_at,
    g.last_used_at,
    g.revoked_at
  from public.national_focus_mcp_grants as g
  where g.user_id = auth.uid()
  order by g.created_at desc
  limit 50;
$$;

create function public.revoke_national_focus_mcp_grant(p_grant_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  update public.national_focus_mcp_grants
  set revoked_at = coalesce(revoked_at, now())
  where id = p_grant_id and user_id = auth.uid();
  if not found then
    raise exception 'grant unavailable' using errcode = '42501';
  end if;
end;
$$;

create function public.revoke_all_national_focus_mcp_grants()
returns integer
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  revoked_count integer;
begin
  if auth.uid() is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;
  update public.national_focus_mcp_grants
  set revoked_at = now()
  where user_id = auth.uid() and revoked_at is null;
  get diagnostics revoked_count = row_count;
  return revoked_count;
end;
$$;

create function public.list_national_focus_mcp_audit_logs(p_limit integer default 20)
returns table(
  id uuid,
  grant_id uuid,
  grant_label text,
  tool_name text,
  action_kind text,
  summary text,
  snapshot_revision bigint,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select
    l.id,
    l.grant_id,
    l.grant_label,
    l.tool_name,
    l.action_kind,
    l.summary,
    l.snapshot_revision,
    l.created_at
  from public.national_focus_mcp_audit_logs as l
  where l.user_id = auth.uid()
  order by l.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke all on function
  public.create_national_focus_mcp_grant(text, text, integer, text),
  public.list_national_focus_mcp_grants(),
  public.revoke_national_focus_mcp_grant(uuid),
  public.revoke_all_national_focus_mcp_grants(),
  public.list_national_focus_mcp_audit_logs(integer)
  from public, anon;

grant execute on function
  public.create_national_focus_mcp_grant(text, text, integer, text),
  public.list_national_focus_mcp_grants(),
  public.revoke_national_focus_mcp_grant(uuid),
  public.revoke_all_national_focus_mcp_grants(),
  public.list_national_focus_mcp_audit_logs(integer)
  to authenticated;

-- Service-only token verification & snapshot access.
create function public.verify_national_focus_mcp_grant(
  p_token_hash text,
  p_required_scope text default 'national_focus:read'
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  g public.national_focus_mcp_grants;
begin
  select * into g
  from public.national_focus_mcp_grants
  where token_hash = p_token_hash
    and revoked_at is null
    and (expires_at is null or expires_at > now());

  if not found
    or not exists (select 1 from auth.users where id = g.user_id)
    or exists (
      select 1 from public.user_suspension_periods
      where user_id = g.user_id and restored_at is null
    ) then
    raise exception 'invalid delegate' using errcode = '28000';
  end if;

  if p_required_scope = 'national_focus:readwrite'
    and g.scope <> 'national_focus:readwrite' then
    raise exception 'insufficient mcp scope' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'grant_id', g.id,
    'user_id', g.user_id,
    'label', g.label,
    'scope', g.scope
  );
end;
$$;

create function public.read_national_focus_mcp_metadata(
  p_token_hash text,
  p_expected_revision bigint default null,
  p_required_scope text default 'national_focus:read'
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  grant_info jsonb;
  owner_id uuid;
  s public.cloud_business_snapshots;
  table_name text;
  old_format boolean := false;
begin
  grant_info := public.verify_national_focus_mcp_grant(p_token_hash, p_required_scope);
  owner_id := (grant_info ->> 'user_id')::uuid;

  select * into s from public.cloud_business_snapshots where user_id = owner_id;
  if not found then
    return jsonb_build_object(
      'contract_version', 1,
      'status', case
        when exists(
          select 1 from jsonb_each(public.legacy_business_records_for_user(owner_id))
          where jsonb_array_length(value) > 0
        ) then 'legacy_snapshot'
        else 'no_snapshot'
      end,
      'revision', null,
      'source_device', null,
      'uploaded_at', null,
      'recovery', 'Manually upload a whole-data snapshot in Pacta.'
    );
  end if;

  if p_expected_revision is not null and s.revision <> p_expected_revision then
    raise exception 'snapshot revision changed' using errcode = 'PT409';
  end if;

  foreach table_name in array array[
    'local_national_focus_cards',
    'local_national_focus_strengthening_levels',
    'local_national_focus_maintenance',
    'local_national_focus_failures'
  ] loop
    if jsonb_typeof(s.payload -> 'tables' -> table_name) is distinct from 'array' then
      old_format := true;
    elsif exists(
      select 1 from jsonb_array_elements(s.payload -> 'tables' -> table_name) row_data
      where jsonb_typeof(row_data) is distinct from 'object'
        or row_data ->> 'user_id' is distinct from owner_id::text
    ) then
      old_format := true;
    end if;
  end loop;

  if not old_format and exists(
    select 1 from jsonb_array_elements(s.payload -> 'tables' -> 'local_national_focus_cards') row_data
    where jsonb_typeof(row_data -> 'name') is distinct from 'string'
      or btrim(coalesce(row_data ->> 'name', '')) = ''
  ) then
    old_format := true;
  end if;

  if not old_format and exists(
    select 1 from jsonb_array_elements(s.payload -> 'tables' -> 'local_national_focus_cards') row_data
    where jsonb_exists(row_data, 'icon_key')
      and jsonb_typeof(row_data -> 'icon_key') not in ('null', 'string')
  ) then
    old_format := true;
  end if;

  if not old_format and s.payload ->> 'schemaVersion' = '4' and exists(
    select 1 from jsonb_array_elements(s.payload -> 'tables' -> 'local_national_focus_cards') row_data
    where not jsonb_exists(row_data, 'icon_key')
      or (
        jsonb_typeof(row_data -> 'icon_key') = 'string'
        and (
          btrim(row_data ->> 'icon_key') = ''
          or btrim(row_data ->> 'icon_key') <> row_data ->> 'icon_key'
        )
      )
  ) then
    old_format := true;
  end if;

  if old_format
    or s.payload ->> 'schemaVersion' is null
    or s.payload ->> 'schemaVersion' not in ('1', '2', '3', '4')
    or jsonb_typeof(s.payload -> 'tables') is distinct from 'object'
    or s.payload ->> 'userId' is distinct from owner_id::text
    or (
      s.payload ->> 'schemaVersion' = '2'
      and jsonb_typeof(s.payload -> 'tables' -> 'local_schedules') is distinct from 'array'
    )
    or (
      s.payload ->> 'schemaVersion' in ('3', '4')
      and (
        jsonb_typeof(s.payload -> 'tables' -> 'local_schedules') is distinct from 'array'
        or jsonb_typeof(s.payload -> 'tables' -> 'local_schedule_recurrences') is distinct from 'array'
      )
    ) then
    return jsonb_build_object(
      'contract_version', 1,
      'status', 'unsupported_snapshot',
      'revision', s.revision,
      'source_device', null,
      'uploaded_at', null,
      'recovery', 'Update Pacta and manually upload a whole-data snapshot.'
    );
  end if;

  return jsonb_build_object(
    'contract_version', 1,
    'status', 'available',
    'revision', s.revision,
    'source_device', jsonb_build_object('id', s.device_id, 'name', s.device_name),
    'uploaded_at', s.uploaded_at,
    'data_updated_at', s.data_updated_at,
    'freshness', 'latest_manual_upload'
  );
end;
$$;

create function public.read_national_focus_mcp_snapshot(
  p_token_hash text,
  p_expected_revision bigint default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  metadata jsonb;
  snapshot public.cloud_business_snapshots;
begin
  metadata := public.read_national_focus_mcp_metadata(
    p_token_hash, p_expected_revision, 'national_focus:read'
  );
  if p_expected_revision is not null and metadata ->> 'revision' is null then
    raise exception 'snapshot revision changed' using errcode = 'PT409';
  end if;
  if metadata ->> 'status' <> 'available' then
    return metadata;
  end if;
  select s.* into snapshot
  from public.cloud_business_snapshots s
  join public.national_focus_mcp_grants g on g.user_id = s.user_id
  where g.token_hash = p_token_hash;
  return metadata || jsonb_build_object(
    'tables', jsonb_build_object(
      'local_national_focus_cards', snapshot.payload -> 'tables' -> 'local_national_focus_cards',
      'local_national_focus_strengthening_levels', snapshot.payload -> 'tables' -> 'local_national_focus_strengthening_levels',
      'local_national_focus_maintenance', snapshot.payload -> 'tables' -> 'local_national_focus_maintenance'
    )
  );
end;
$$;

create function public.read_national_focus_mcp_history_snapshot(
  p_token_hash text,
  p_expected_revision bigint default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  metadata jsonb;
  snapshot public.cloud_business_snapshots;
begin
  metadata := public.read_national_focus_mcp_metadata(
    p_token_hash, p_expected_revision, 'national_focus:read'
  );
  if p_expected_revision is not null and metadata ->> 'revision' is null then
    raise exception 'snapshot revision changed' using errcode = 'PT409';
  end if;
  if metadata ->> 'status' <> 'available' then
    return metadata;
  end if;
  select s.* into snapshot
  from public.cloud_business_snapshots s
  join public.national_focus_mcp_grants g on g.user_id = s.user_id
  where g.token_hash = p_token_hash;
  return metadata || jsonb_build_object(
    'tables', jsonb_build_object(
      'local_national_focus_failures', snapshot.payload -> 'tables' -> 'local_national_focus_failures'
    )
  );
end;
$$;

create function public.record_national_focus_mcp_audit(
  p_token_hash text,
  p_tool_name text,
  p_action_kind text,
  p_summary text,
  p_snapshot_revision bigint default null
) returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  g public.national_focus_mcp_grants;
begin
  if p_action_kind not in ('read', 'write')
    or btrim(coalesce(p_tool_name, '')) = ''
    or btrim(coalesce(p_summary, '')) = '' then
    return;
  end if;

  select * into g
  from public.national_focus_mcp_grants
  where token_hash = p_token_hash;
  if not found then
    return;
  end if;

  update public.national_focus_mcp_grants
  set last_used_at = now()
  where id = g.id;

  insert into public.national_focus_mcp_audit_logs (
    user_id, grant_id, grant_label, tool_name, action_kind, summary, snapshot_revision
  ) values (
    g.user_id, g.id, g.label, left(btrim(p_tool_name), 100), p_action_kind,
    left(btrim(p_summary), 240), p_snapshot_revision
  );

  delete from public.national_focus_mcp_audit_logs as stale
  where stale.user_id = g.user_id
    and stale.id not in (
      select retained.id
      from public.national_focus_mcp_audit_logs as retained
      where retained.user_id = g.user_id
      order by retained.created_at desc, retained.id desc
      limit 50
    );
end;
$$;

create function public.write_national_focus_mcp_snapshot(
  p_token_hash text,
  p_expected_revision bigint,
  p_cards jsonb,
  p_strengthening_levels jsonb,
  p_tool_name text,
  p_summary text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  grant_info jsonb;
  grant_id uuid;
  grant_label text;
  owner_id uuid;
  s public.cloud_business_snapshots;
  saved public.cloud_business_snapshots;
  next_payload jsonb;
  next_row_count integer;
  old_card jsonb;
  new_card jsonb;
  old_in_tree boolean;
  new_in_tree boolean;
begin
  grant_info := public.verify_national_focus_mcp_grant(p_token_hash, 'national_focus:readwrite');
  grant_id := (grant_info ->> 'grant_id')::uuid;
  grant_label := grant_info ->> 'label';
  owner_id := (grant_info ->> 'user_id')::uuid;

  if p_expected_revision is null or p_expected_revision < 1
    or p_cards is null or jsonb_typeof(p_cards) <> 'array'
    or p_strengthening_levels is null or jsonb_typeof(p_strengthening_levels) <> 'array'
    or btrim(coalesce(p_tool_name, '')) = ''
    or btrim(coalesce(p_summary, '')) = '' then
    raise exception 'invalid mcp write payload' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(owner_id::text, 0));

  select * into s
  from public.cloud_business_snapshots
  where user_id = owner_id
  for update;

  if not found then
    raise exception 'snapshot not found' using errcode = '22023';
  end if;

  if s.revision <> p_expected_revision then
    raise exception 'snapshot revision changed' using errcode = 'PT409';
  end if;

  if s.payload ->> 'schemaVersion' is distinct from '4'
    or jsonb_typeof(s.payload -> 'tables') is distinct from 'object'
    or s.payload ->> 'userId' is distinct from owner_id::text then
    raise exception 'snapshot version does not support mcp write' using errcode = 'PT426';
  end if;

  -- Ownership and basic row checks for cards and strengthening levels.
  if exists (
    select 1 from jsonb_array_elements(p_cards) row_data
    where jsonb_typeof(row_data) <> 'object'
      or row_data ->> 'user_id' is distinct from owner_id::text
      or btrim(coalesce(row_data ->> 'id', '')) = ''
      or btrim(coalesce(row_data ->> 'name', '')) = ''
      or btrim(coalesce(row_data ->> 'action', '')) = ''
      or (jsonb_exists(row_data, 'icon_key')
        and jsonb_typeof(row_data -> 'icon_key') not in ('null', 'string'))
      or (jsonb_typeof(row_data -> 'icon_key') = 'string'
        and (btrim(row_data ->> 'icon_key') = ''
          or btrim(row_data ->> 'icon_key') <> row_data ->> 'icon_key'))
      or coalesce(row_data ->> 'state', '') not in ('lit', 'pending_today_confirmation', 'extinguished')
  ) then
    raise exception 'invalid national focus card row' using errcode = '22023';
  end if;

  -- Unique card IDs.
  if (
    select count(*) from jsonb_array_elements(p_cards) row_data
  ) <> (
    select count(distinct row_data ->> 'id') from jsonb_array_elements(p_cards) row_data
  ) then
    raise exception 'duplicate card id' using errcode = '22023';
  end if;

  -- Strengthening levels belong to owner and reference existing cards.
  if exists (
    select 1 from jsonb_array_elements(p_strengthening_levels) lvl
    where jsonb_typeof(lvl) <> 'object'
      or lvl ->> 'user_id' is distinct from owner_id::text
      or btrim(coalesce(lvl ->> 'card_id', '')) = ''
      or not exists (
        select 1 from jsonb_array_elements(p_cards) c
        where c ->> 'id' = lvl ->> 'card_id'
      )
      or jsonb_typeof(lvl -> 'level_number') <> 'number'
      or (lvl ->> 'level_number')::integer < 1
      or (lvl ->> 'level_number')::integer > 5
      or (
        btrim(coalesce(lvl ->> 'action_override', '')) = ''
        and btrim(coalesce(lvl ->> 'trigger_condition_override', '')) = ''
      )
  ) then
    raise exception 'invalid strengthening level row' using errcode = '22023';
  end if;

  -- Hard invariant: existing cards cannot be hard-deleted or have runtime
  -- progress / streaks / lit status forged.
  for old_card in
    select value from jsonb_array_elements(s.payload -> 'tables' -> 'local_national_focus_cards')
  loop
    select value into new_card
    from jsonb_array_elements(p_cards)
    where value ->> 'id' = old_card ->> 'id'
    limit 1;

    if not found then
      raise exception 'mcp cannot hard delete existing card' using errcode = '42501';
    end if;

    if (new_card -> 'successful_days') is distinct from (old_card -> 'successful_days')
      or (new_card -> 'current_consecutive_days') is distinct from (old_card -> 'current_consecutive_days')
      or (new_card -> 'best_consecutive_days') is distinct from (old_card -> 'best_consecutive_days')
      or (new_card -> 'maintenance_cycle_started') is distinct from (old_card -> 'maintenance_cycle_started')
      or (new_card -> 'failure_reason') is distinct from (old_card -> 'failure_reason')
      or (new_card -> 'created_at') is distinct from (old_card -> 'created_at') then
      raise exception 'mcp cannot alter card runtime records' using errcode = '42501';
    end if;

    old_in_tree := coalesce(old_card ->> 'is_in_tree', '') in ('1', 'true');
    new_in_tree := coalesce(new_card ->> 'is_in_tree', '') in ('1', 'true');

    if (new_card ->> 'state') is distinct from (old_card ->> 'state') then
      if not (
        old_in_tree
        and not new_in_tree
        and (old_card ->> 'state') in ('lit', 'pending_today_confirmation')
        and (new_card ->> 'state') = 'pending_today_confirmation'
      ) then
        raise exception 'mcp cannot alter card lighting state' using errcode = '42501';
      end if;
    end if;
  end loop;

  -- Hard invariant: newly created cards must start in library, extinguished, zeroed.
  for new_card in
    select value from jsonb_array_elements(p_cards)
    where not exists (
      select 1 from jsonb_array_elements(s.payload -> 'tables' -> 'local_national_focus_cards') old_c
      where old_c.value ->> 'id' = value ->> 'id'
    )
  loop
    if coalesce(new_card ->> 'is_in_tree', '') not in ('0', 'false')
      or (new_card ->> 'parent_id') is not null
      or (new_card ->> 'state') <> 'extinguished'
      or coalesce((new_card ->> 'successful_days')::integer, -1) <> 0
      or coalesce((new_card ->> 'current_consecutive_days')::integer, -1) <> 0
      or coalesce((new_card ->> 'best_consecutive_days')::integer, -1) <> 0
      or coalesce(new_card ->> 'maintenance_cycle_started', '') not in ('0', 'false')
      or (new_card ->> 'deleted_at') is not null then
      raise exception 'new mcp card violates initial invariants' using errcode = '42501';
    end if;
  end loop;

  next_payload := jsonb_set(
    jsonb_set(
      s.payload,
      '{tables,local_national_focus_cards}',
      p_cards
    ),
    '{tables,local_national_focus_strengthening_levels}',
    p_strengthening_levels
  );

  select coalesce(sum(jsonb_array_length(t.value)), 0)::integer
  into next_row_count
  from jsonb_each(next_payload -> 'tables') as t;

  update public.cloud_business_snapshots
  set revision = s.revision + 1,
      payload = next_payload,
      device_id = 'mcp:' || grant_id::text,
      device_name = left('MCP · ' || grant_label, 120),
      device_manufacturer = null,
      device_model = null,
      data_updated_at = now(),
      uploaded_at = now(),
      row_count = next_row_count
  where user_id = owner_id
  returning * into saved;

  insert into public.cloud_business_snapshot_history (
    user_id, revision, payload, device_id, device_name,
    device_manufacturer, device_model, data_updated_at, uploaded_at,
    row_count, request_id
  ) values (
    saved.user_id, saved.revision, saved.payload, saved.device_id,
    saved.device_name, saved.device_manufacturer, saved.device_model,
    saved.data_updated_at, saved.uploaded_at, saved.row_count, null
  );

  delete from public.cloud_business_snapshot_history as stale
  where stale.user_id = owner_id
    and stale.revision not in (
      select retained.revision
      from public.cloud_business_snapshot_history as retained
      where retained.user_id = owner_id
      order by retained.revision desc
      limit 15
    );

  perform public.record_national_focus_mcp_audit(
    p_token_hash, p_tool_name, 'write', p_summary, saved.revision
  );

  return jsonb_build_object(
    'contract_version', 1,
    'status', 'available',
    'revision', saved.revision,
    'source_device', jsonb_build_object('id', saved.device_id, 'name', saved.device_name),
    'uploaded_at', saved.uploaded_at,
    'data_updated_at', saved.data_updated_at,
    'freshness', 'latest_manual_upload'
  );
end;
$$;

revoke all on function
  public.verify_national_focus_mcp_grant(text, text),
  public.read_national_focus_mcp_metadata(text, bigint, text),
  public.read_national_focus_mcp_snapshot(text, bigint),
  public.read_national_focus_mcp_history_snapshot(text, bigint),
  public.record_national_focus_mcp_audit(text, text, text, text, bigint),
  public.write_national_focus_mcp_snapshot(text, bigint, jsonb, jsonb, text, text)
  from public, anon, authenticated;

grant execute on function
  public.verify_national_focus_mcp_grant(text, text),
  public.read_national_focus_mcp_metadata(text, bigint, text),
  public.read_national_focus_mcp_snapshot(text, bigint),
  public.read_national_focus_mcp_history_snapshot(text, bigint),
  public.record_national_focus_mcp_audit(text, text, text, text, bigint),
  public.write_national_focus_mcp_snapshot(text, bigint, jsonb, jsonb, text, text)
  to service_role;
