-- Independent, revocable OAuth delegates. No MCP credential is an Auth JWT.
create table public.national_focus_mcp_clients (
  id text primary key,
  client_name text not null,
  redirect_uris jsonb not null,
  created_at timestamptz not null default now()
);
create table public.national_focus_mcp_grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id text not null references public.national_focus_mcp_clients(id),
  scope text not null default 'national_focus:read' check (scope = 'national_focus:read'),
  token_hash text unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 minutes',
  revoked_at timestamptz
);
create index national_focus_mcp_grants_owner on public.national_focus_mcp_grants(user_id);
create table public.national_focus_mcp_requests (
  request_hash text primary key,
  client_id text not null references public.national_focus_mcp_clients(id),
  redirect_uri text not null,
  resource text not null,
  code_challenge text not null,
  state text not null,
  expires_at timestamptz not null default now() + interval '5 minutes',
  grant_id uuid references public.national_focus_mcp_grants(id) on delete cascade,
  code_hash text unique,
  code_value text,
  consumed_at timestamptz
);
alter table public.national_focus_mcp_clients enable row level security;
alter table public.national_focus_mcp_grants enable row level security;
alter table public.national_focus_mcp_requests enable row level security;
revoke all on public.national_focus_mcp_clients, public.national_focus_mcp_grants,
  public.national_focus_mcp_requests from public, anon, authenticated;
grant all on public.national_focus_mcp_clients, public.national_focus_mcp_grants,
  public.national_focus_mcp_requests to service_role;

-- Public OAuth allocation is globally bounded, including under parallel load.
-- These deletes affect authorization storage only, never business snapshots.
create function public.guard_national_focus_mcp_allocation()
returns trigger language plpgsql security definer set search_path = public, pg_catalog as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('national-focus-mcp-allocation', 0));
  delete from public.national_focus_mcp_requests where expires_at < now();
  if tg_table_name = 'national_focus_mcp_clients' then
    delete from public.national_focus_mcp_grants where expires_at < now() - interval '7 days';
    delete from public.national_focus_mcp_clients c where created_at < now() - interval '1 day'
      and not exists(select 1 from public.national_focus_mcp_grants g where g.client_id = c.id)
      and not exists(select 1 from public.national_focus_mcp_requests r where r.client_id = c.id);
    if (select count(*) from public.national_focus_mcp_clients where created_at > now() - interval '1 hour') >= 200
      or (select count(*) from public.national_focus_mcp_clients) >= 5000 then
      raise exception 'authorization capacity reached' using errcode = 'PT429';
    end if;
  elsif (select count(*) from public.national_focus_mcp_requests) >= 1000
    or (select count(*) from public.national_focus_mcp_requests where client_id = new.client_id) >= 10 then
    raise exception 'authorization capacity reached' using errcode = 'PT429';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_national_focus_mcp_allocation() from public, anon, authenticated;
create trigger national_focus_mcp_client_capacity before insert on public.national_focus_mcp_clients
  for each row execute function public.guard_national_focus_mcp_allocation();
create trigger national_focus_mcp_request_capacity before insert on public.national_focus_mcp_requests
  for each row execute function public.guard_national_focus_mcp_allocation();

create function public.list_national_focus_mcp_grants()
returns table(id uuid, client_name text, scope text, created_at timestamptz,
  expires_at timestamptz, revoked_at timestamptz)
language sql stable security definer set search_path = public, pg_catalog as $$
  select g.id, c.client_name, g.scope, g.created_at, g.expires_at, g.revoked_at
  from public.national_focus_mcp_grants g
  join public.national_focus_mcp_clients c on c.id = g.client_id
  where g.user_id = auth.uid() order by g.created_at desc;
$$;
create function public.revoke_national_focus_mcp_grant(p_grant_id uuid)
returns void language plpgsql security definer set search_path = public, pg_catalog as $$
begin
  update public.national_focus_mcp_grants set revoked_at = coalesce(revoked_at, now())
  where id = p_grant_id and user_id = auth.uid();
  if not found then
    raise exception 'grant unavailable' using errcode = '42501';
  end if;
end;
$$;
revoke all on function public.list_national_focus_mcp_grants() from public, anon;
revoke all on function public.revoke_national_focus_mcp_grant(uuid) from public, anon;
grant execute on function public.list_national_focus_mcp_grants(),
  public.revoke_national_focus_mcp_grant(uuid) to authenticated;

-- An authenticated App user inspects and explicitly approves a browser request.
-- The request capability is never an access token; it expires in five minutes.
create function public.inspect_national_focus_mcp_request(p_request_code text)
returns jsonb language plpgsql stable security definer set search_path = public, pg_catalog as $$
declare r public.national_focus_mcp_requests; client_label text;
begin
  if not public.current_user_is_active() then
    raise exception 'active user required' using errcode = '42501';
  end if;
  select * into r from public.national_focus_mcp_requests
    where request_hash = encode(sha256(convert_to(lower(btrim(p_request_code)), 'UTF8')), 'hex');
  if not found or r.expires_at <= now() or r.grant_id is not null then
    raise exception 'invalid authorization request' using errcode = '22023';
  end if;
  select client_name into client_label from public.national_focus_mcp_clients where id = r.client_id;
  return jsonb_build_object('client_name', client_label, 'redirect_uri', r.redirect_uri,
    'scope', 'national_focus:read', 'expires_at', r.expires_at);
end;
$$;
create function public.approve_national_focus_mcp_connection(p_request_code text, p_consent boolean)
returns void language plpgsql security definer set search_path = public, pg_catalog as $$
declare r public.national_focus_mcp_requests; new_grant uuid; new_code text;
begin
  if not public.current_user_is_active() or p_consent is distinct from true then
    raise exception 'active user and explicit consent required' using errcode = '42501';
  end if;
  select * into r from public.national_focus_mcp_requests
    where request_hash = encode(sha256(convert_to(lower(btrim(p_request_code)), 'UTF8')), 'hex') for update;
  if not found or r.expires_at <= now() or r.grant_id is not null then
    raise exception 'invalid authorization request' using errcode = '22023';
  end if;
  insert into public.national_focus_mcp_grants(user_id, client_id)
    values(auth.uid(), r.client_id) returning id into new_grant;
  new_code := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  update public.national_focus_mcp_requests set grant_id = new_grant, code_value = new_code,
    code_hash = encode(sha256(convert_to(new_code, 'UTF8')), 'hex'),
    expires_at = now() + interval '5 minutes' where request_hash = r.request_hash;
end;
$$;
revoke all on function public.inspect_national_focus_mcp_request(text),
  public.approve_national_focus_mcp_connection(text, boolean) from public, anon;
grant execute on function public.inspect_national_focus_mcp_request(text),
  public.approve_national_focus_mcp_connection(text, boolean) to authenticated;

create function public.exchange_national_focus_mcp_code(
  p_code_hash text, p_client_id text, p_redirect_uri text, p_resource text,
  p_code_challenge text, p_token_hash text
) returns jsonb language plpgsql security definer set search_path = public, pg_catalog as $$
declare r public.national_focus_mcp_requests; g public.national_focus_mcp_grants;
begin
  select * into r from public.national_focus_mcp_requests
    where code_hash = p_code_hash for update;
  if not found or r.expires_at <= now() or r.consumed_at is not null
    or r.client_id is distinct from p_client_id or r.redirect_uri is distinct from p_redirect_uri
    or r.resource is distinct from p_resource or r.code_challenge is distinct from p_code_challenge then
    raise exception 'invalid authorization code' using errcode = '22023';
  end if;
  select * into g from public.national_focus_mcp_grants where id = r.grant_id for update;
  if not found or g.revoked_at is not null or g.expires_at <= now()
    or exists (select 1 from public.user_suspension_periods
      where user_id = g.user_id and restored_at is null) then
    raise exception 'invalid authorization code' using errcode = '22023';
  end if;
  update public.national_focus_mcp_requests set consumed_at = now(), code_value = null
    where request_hash = r.request_hash;
  update public.national_focus_mcp_grants set token_hash = p_token_hash where id = g.id;
  return jsonb_build_object('expires_in', greatest(0, floor(extract(epoch from (g.expires_at - now())))),
    'scope', g.scope);
end;
$$;

-- This is the only delegated business read. The payload is inspected only for
-- format validity; no payload, table counts, task ids or user ids leave SQL.
create function public.read_national_focus_mcp_metadata(
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
  if old_format or s.payload ->> 'schemaVersion' is distinct from '1'
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
revoke all on function public.exchange_national_focus_mcp_code(text, text, text, text, text, text),
  public.read_national_focus_mcp_metadata(text, bigint) from public, anon, authenticated;
grant execute on function public.exchange_national_focus_mcp_code(text, text, text, text, text, text),
  public.read_national_focus_mcp_metadata(text, bigint) to service_role;
