-- Rollback-only probe for the whole-snapshot version 2 protocol.
-- Run against an isolated Supabase project after applying
-- 202611150001_cloud_snapshot_schema_v2.sql (and the migrations it builds on).
-- Requires one active administrator identity; every step is asserted and the
-- whole script rolls back.
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

-- A version 2 snapshot is accepted as the first upload, archived in history,
-- and recorded in the upload request ledger.
do $accept_version_two$
declare
  payload jsonb := jsonb_build_object(
    'schemaVersion', '2',
    'userId', current_setting('schema_v2_test.owner_id'),
    'tables', jsonb_build_object(
      'local_schedules', '[]'::jsonb,
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
    '2026-11-15T01:00:00Z'::timestamptz, 0, null, null, null,
    'schema-v2-accept'
  );
  if saved.revision <> 1 or saved.payload ->> 'schemaVersion' <> '2' then
    raise exception 'version 2 upload was not stored as revision 1';
  end if;
  select count(*) into archived
  from public.cloud_business_snapshot_history
  where user_id = auth.uid() and revision = 1 and request_id = 'schema-v2-accept';
  if archived <> 1 then
    raise exception 'version 2 upload was not archived with its request id';
  end if;
  select count(*) into ledger
  from public.cloud_business_snapshot_upload_requests
  where user_id = auth.uid() and request_id = 'schema-v2-accept' and revision = 1;
  if ledger <> 1 then
    raise exception 'version 2 upload did not record its request ledger entry';
  end if;

  -- Retrying the same request returns the version it produced.
  saved := public.save_cloud_business_snapshot(
    1, payload, 'probe-device', 'Probe device',
    '2026-11-15T01:00:00Z'::timestamptz, 0, null, null, null,
    'schema-v2-accept'
  );
  if saved.revision <> 1 then
    raise exception 'retried version 2 request produced a new revision';
  end if;
end
$accept_version_two$;

-- A version 1 payload must not replace a version 2 snapshot.
do $reject_old_client_write$
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
    raise exception 'version 1 payload replaced a version 2 snapshot';
  exception
    when sqlstate '22023' then null;
  end;
  if exists (
    select 1 from public.cloud_business_snapshots
    where user_id = auth.uid() and (payload ->> 'schemaVersion') <> '2'
  ) then
    raise exception 'rejected version 1 write still changed the stored snapshot';
  end if;
end
$reject_old_client_write$;

-- A version 1 payload remains a valid first upload for accounts that never
-- produced a version 2 snapshot; that path is covered by the existing
-- cloud_snapshot_history / user_purge_access suites and is unchanged here.

-- Compare-and-swap still guards version 2 writes.
do $keep_cas_guard$
declare
  payload jsonb := jsonb_build_object(
    'schemaVersion', '2',
    'userId', current_setting('schema_v2_test.owner_id'),
    'tables', jsonb_build_object('local_schedules', '[]'::jsonb)
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

-- The delegated read accepts the version 2 snapshot instead of reporting it as
-- unsupported.
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
    raise exception 'version 2 snapshot reported as % instead of available',
      metadata ->> 'status';
  end if;
end
$metadata_available$;

rollback;
