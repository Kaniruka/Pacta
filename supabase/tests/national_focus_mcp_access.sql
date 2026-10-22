-- Rollback-only authorization, RLS, OAuth, suspension, and metadata checks.
-- Run only in an isolated Supabase project after applying
-- 202610210001_national_focus_mcp.sql. Creates transaction-local test identities;
-- no ordinary user is selected or modified. All fixtures and temporary table
-- grants used to exercise default-deny RLS are rolled back.

begin;

do $setup$
declare
  test_user_id uuid;
  other_user_id uuid;
  client_id text := 'national-focus-mcp-probe-' || gen_random_uuid()::text;
  request_code text := 'nf-' || replace(gen_random_uuid()::text, '-', '');
  suspended_request_code text := 'nf-' || replace(gen_random_uuid()::text, '-', '');
  request_hash text;
  suspended_request_hash text;
  other_token_hash text := md5(gen_random_uuid()::text);
  other_grant_id uuid;
begin
  test_user_id := gen_random_uuid();
  other_user_id := gen_random_uuid();
  perform set_config('request.jwt.claim.role', 'service_role', true);
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
  values
    ('00000000-0000-0000-0000-000000000000',test_user_id,'authenticated','authenticated','nf-access-'||test_user_id||'@probe.invalid','',now(),now(),now()),
    ('00000000-0000-0000-0000-000000000000',other_user_id,'authenticated','authenticated','nf-access-'||other_user_id||'@probe.invalid','',now(),now(),now());

  request_hash := encode(
    sha256(convert_to(lower(btrim(request_code)), 'UTF8')), 'hex'
  );
  suspended_request_hash := encode(
    sha256(convert_to(lower(btrim(suspended_request_code)), 'UTF8')), 'hex'
  );

  perform set_config('nf_mcp_test.user_id', test_user_id::text, true);
  perform set_config('nf_mcp_test.other_user_id', other_user_id::text, true);
  perform set_config('nf_mcp_test.client_id', client_id, true);
  perform set_config('nf_mcp_test.request_code', request_code, true);
  perform set_config('nf_mcp_test.request_hash', request_hash, true);
  perform set_config('nf_mcp_test.suspended_request_code', suspended_request_code, true);
  perform set_config('nf_mcp_test.suspended_request_hash', suspended_request_hash, true);
  perform set_config('nf_mcp_test.other_token_hash', other_token_hash, true);

  insert into public.national_focus_mcp_clients(
    id, client_name, redirect_uris
  ) values (
    client_id,
    'National Focus MCP SQL probe',
    '["https://probe.invalid/callback"]'::jsonb
  );

  insert into public.national_focus_mcp_requests(
    request_hash, client_id, redirect_uri, resource, code_challenge, state
  ) values
    (
      request_hash, client_id, 'https://probe.invalid/callback',
      'https://probe.invalid/mcp', 'probe-challenge', 'probe-state'
    ),
    (
      suspended_request_hash, client_id, 'https://probe.invalid/callback',
      'https://probe.invalid/mcp', 'suspended-challenge', 'suspended-state'
    );

  insert into public.national_focus_mcp_grants(
    user_id, client_id, token_hash, expires_at
  ) values (
    other_user_id, client_id, other_token_hash, now() + interval '1 hour'
  ) returning id into other_grant_id;
  perform set_config('nf_mcp_test.other_grant_id', other_grant_id::text, true);

  insert into public.cloud_business_snapshots(
    user_id, revision, payload, device_id, device_name,
    data_updated_at, row_count
  ) values (
    test_user_id,
    7,
    jsonb_build_object(
      'schemaVersion', 1,
      'userId', test_user_id::text,
      'tables', jsonb_build_object(
        'local_national_focus_cards', jsonb_build_array(
          jsonb_build_object(
            'user_id', test_user_id::text,
            'name', 'SECRET-NF-MCP-PROBE private business payload'
          )
        ),
        'local_national_focus_strengthening_levels', '[]'::jsonb,
        'local_national_focus_requirement_versions', '[]'::jsonb,
        'local_national_focus_maintenance', '[]'::jsonb,
        'local_national_focus_failures', '[]'::jsonb
      )
    ),
    'probe-device-id', 'Probe device', now(), 1
  );

  insert into public.user_suspension_periods(user_id)
  values (other_user_id);
end
$setup$;

-- This grant is transaction-local in effect because the whole probe rolls back.
-- It allows authenticated queries to reach PostgreSQL RLS, whose default-deny
-- behavior is then exercised against rows that really exist.
grant select, insert, update, delete on
  public.national_focus_mcp_clients,
  public.national_focus_mcp_grants,
  public.national_focus_mcp_requests
to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub', current_setting('nf_mcp_test.user_id'), true
);

do $authenticated_probe$
declare
  visible_rows integer;
  changed_rows integer;
  own_grants integer;
  request_info jsonb;
  owner_grant_id uuid;
begin
  select count(*) into visible_rows from public.national_focus_mcp_clients;
  if visible_rows <> 0 then
    raise exception 'authenticated_role_bypassed_client_rls';
  end if;

  select count(*) into visible_rows from public.national_focus_mcp_grants;
  if visible_rows <> 0 then
    raise exception 'authenticated_role_bypassed_grant_rls';
  end if;

  select count(*) into visible_rows from public.national_focus_mcp_requests;
  if visible_rows <> 0 then
    raise exception 'authenticated_role_bypassed_request_rls';
  end if;

  begin
    insert into public.national_focus_mcp_clients(id, client_name, redirect_uris)
    values (
      'direct-write-' || gen_random_uuid()::text,
      'must be rejected',
      '[]'::jsonb
    );
    raise exception 'authenticated_direct_insert_bypassed_rls';
  exception
    when insufficient_privilege then null;
  end;

  update public.national_focus_mcp_grants
  set revoked_at = now()
  where id = current_setting('nf_mcp_test.other_grant_id')::uuid;
  get diagnostics changed_rows = row_count;
  if changed_rows <> 0 then
    raise exception 'authenticated_direct_update_bypassed_rls';
  end if;

  delete from public.national_focus_mcp_grants
  where id = current_setting('nf_mcp_test.other_grant_id')::uuid;
  get diagnostics changed_rows = row_count;
  if changed_rows <> 0 then
    raise exception 'authenticated_direct_delete_bypassed_rls';
  end if;

  request_info := public.inspect_national_focus_mcp_request(
    current_setting('nf_mcp_test.request_code')
  );
  if request_info ->> 'client_name' <> 'National Focus MCP SQL probe'
    or request_info ->> 'redirect_uri' <> 'https://probe.invalid/callback'
    or request_info ->> 'scope' <> 'national_focus:read'
    or request_info ->> 'expires_at' is null then
    raise exception 'app_request_inspection_returned_invalid_details';
  end if;
  if request_info ? 'state' or request_info ? 'code' then
    raise exception 'app_request_inspection_returned_sensitive_fields';
  end if;

  begin
    perform public.approve_national_focus_mcp_connection(
      current_setting('nf_mcp_test.request_code'), false
    );
    raise exception 'missing_explicit_consent_was_accepted';
  exception
    when insufficient_privilege then null;
  end;

  -- A declined attempt leaves the request available for a later explicit consent.
  perform public.inspect_national_focus_mcp_request(
    current_setting('nf_mcp_test.request_code')
  );
  perform public.approve_national_focus_mcp_connection(
    current_setting('nf_mcp_test.request_code'), true
  );

  begin
    perform public.inspect_national_focus_mcp_request(
      current_setting('nf_mcp_test.request_code')
    );
    raise exception 'approved_request_was_inspected_again';
  exception
    when sqlstate '22023' then null;
  end;

  select count(*) into own_grants
  from public.list_national_focus_mcp_grants();
  if own_grants <> 1 then
    raise exception 'user_grant_listing_did_not_scope_to_auth_uid';
  end if;
  select id into owner_grant_id
  from public.list_national_focus_mcp_grants();
  perform set_config('nf_mcp_test.owner_grant_id', owner_grant_id::text, true);

  begin
    perform public.exchange_national_focus_mcp_code(
      'not-authorized', current_setting('nf_mcp_test.client_id'),
      'https://probe.invalid/callback', 'https://probe.invalid/mcp',
      'probe-challenge', 'unauthorized-token-hash'
    );
    raise exception 'authenticated_role_called_service_only_exchange';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.read_national_focus_mcp_metadata('not-authorized', null);
    raise exception 'authenticated_role_called_service_only_metadata_read';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.revoke_national_focus_mcp_grant(
      current_setting('nf_mcp_test.other_grant_id')::uuid
    );
    raise exception 'user_revoked_another_users_grant';
  exception
    when insufficient_privilege then null;
  end;
end
$authenticated_probe$;

reset role;
set local role service_role;

do $service_role_probe$
declare
  request_row public.national_focus_mcp_requests;
  exchange_result jsonb;
  metadata_result jsonb;
  owner_user_id uuid := current_setting('nf_mcp_test.user_id')::uuid;
  expected_keys text[] := array[
    'contract_version', 'data_updated_at', 'freshness', 'revision',
    'source_device', 'status', 'uploaded_at'
  ];
  actual_keys text[];
  token_hash text := md5(gen_random_uuid()::text);
begin
  select * into request_row
  from public.national_focus_mcp_requests
  where request_hash = current_setting('nf_mcp_test.request_hash');

  if request_row.code_value is null or request_row.code_hash is null
    or request_row.code_value = current_setting('nf_mcp_test.request_code')
    or request_row.code_hash <> encode(
      sha256(convert_to(request_row.code_value, 'UTF8')), 'hex'
    ) then
    raise exception 'approved_request_did_not_store_a_separate_hashed_code';
  end if;
  perform set_config('nf_mcp_test.token_hash', token_hash, true);

  begin
    perform public.exchange_national_focus_mcp_code(
      request_row.code_hash,
      current_setting('nf_mcp_test.client_id'),
      request_row.redirect_uri,
      'https://wrong.invalid/mcp',
      request_row.code_challenge,
      token_hash
    );
    raise exception 'wrong_resource_was_accepted';
  exception
    when sqlstate '22023' then null;
  end;

  exchange_result := public.exchange_national_focus_mcp_code(
    request_row.code_hash,
    current_setting('nf_mcp_test.client_id'),
    request_row.redirect_uri,
    request_row.resource,
    request_row.code_challenge,
    token_hash
  );
  if exchange_result ->> 'scope' <> 'national_focus:read'
    or (exchange_result ->> 'expires_in')::integer <= 0 then
    raise exception 'authorization_code_exchange_returned_invalid_scope_or_expiry';
  end if;

  select * into request_row
  from public.national_focus_mcp_requests
  where request_hash = current_setting('nf_mcp_test.request_hash');
  if request_row.code_value is not null or request_row.consumed_at is null then
    raise exception 'authorization_code_was_not_cleared_after_exchange';
  end if;

  metadata_result := public.read_national_focus_mcp_metadata(token_hash, 7);
  if metadata_result ->> 'status' <> 'available'
    or (metadata_result ->> 'revision')::bigint <> 7 then
    raise exception 'delegated_metadata_status_or_revision_missing';
  end if;
  select array_agg(key order by key) into actual_keys
  from jsonb_object_keys(metadata_result) as keys(key);
  if actual_keys is distinct from expected_keys then
    raise exception 'delegated_metadata_returned_unexpected_keys: %', actual_keys;
  end if;
  if metadata_result::text like '%SECRET-NF-MCP-PROBE%'
    or metadata_result::text like '%private business payload%'
    or metadata_result::text like '%' || owner_user_id::text || '%' then
    raise exception 'delegated_metadata_leaked_user_or_business_payload';
  end if;

  begin
    perform public.read_national_focus_mcp_metadata(token_hash, 6);
    raise exception 'stale_snapshot_revision_was_accepted';
  exception
    when sqlstate 'PT409' then null;
  end;

  begin
    perform public.read_national_focus_mcp_metadata(
      current_setting('nf_mcp_test.other_token_hash'), null
    );
    raise exception 'suspended_user_delegate_was_accepted';
  exception
    when sqlstate '28000' then null;
  end;

  begin
    perform public.exchange_national_focus_mcp_code(
      request_row.code_hash,
      current_setting('nf_mcp_test.client_id'),
      request_row.redirect_uri,
      request_row.resource,
      request_row.code_challenge,
      md5(gen_random_uuid()::text)
    );
    raise exception 'authorization_code_replay_was_accepted';
  exception
    when sqlstate '22023' then null;
  end;
end
$service_role_probe$;

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', current_setting('nf_mcp_test.other_user_id'), true
);

do $suspended_user_probe$
begin
  begin
    perform public.inspect_national_focus_mcp_request(
      current_setting('nf_mcp_test.suspended_request_code')
    );
    raise exception 'suspended_user_inspected_new_request';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.approve_national_focus_mcp_connection(
      current_setting('nf_mcp_test.suspended_request_code'), true
    );
    raise exception 'suspended_user_approved_new_connection';
  exception
    when insufficient_privilege then null;
  end;
end
$suspended_user_probe$;

select set_config(
  'request.jwt.claim.sub', current_setting('nf_mcp_test.user_id'), true
);

do $revoke_probe$
begin
  begin
    perform public.revoke_national_focus_mcp_grant(
      current_setting('nf_mcp_test.other_grant_id')::uuid
    );
    raise exception 'user_revoked_another_users_grant';
  exception
    when insufficient_privilege then null;
  end;

  perform public.revoke_national_focus_mcp_grant(
    current_setting('nf_mcp_test.owner_grant_id')::uuid
  );
  perform public.revoke_national_focus_mcp_grant(
    current_setting('nf_mcp_test.owner_grant_id')::uuid
  );

  if not exists (
    select 1 from public.list_national_focus_mcp_grants()
    where id = current_setting('nf_mcp_test.owner_grant_id')::uuid
      and revoked_at is not null
  ) then
    raise exception 'owner_revocation_was_not_idempotently_recorded';
  end if;
end
$revoke_probe$;

reset role;
set local role service_role;

do $revoked_token_probe$
begin
  begin
    perform public.read_national_focus_mcp_metadata(
      current_setting('nf_mcp_test.token_hash'), null
    );
    raise exception 'revoked_delegate_was_accepted';
  exception
    when sqlstate '28000' then null;
  end;
end
$revoked_token_probe$;

-- Renewal is a fresh explicit approval, never a refresh of the old credential.
reset role;
do $renewal_setup$
begin
  insert into public.national_focus_mcp_requests(
    request_hash, client_id, redirect_uri, resource, code_challenge, state
  ) values (
    encode(sha256(convert_to('renewal-' || current_setting('nf_mcp_test.request_code'), 'UTF8')), 'hex'),
    current_setting('nf_mcp_test.client_id'), 'https://probe.invalid/callback',
    'https://probe.invalid/mcp', 'renewal-challenge', 'renewal-state'
  );
end
$renewal_setup$;
set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('nf_mcp_test.user_id'), true);
select public.approve_national_focus_mcp_connection(
  'renewal-' || current_setting('nf_mcp_test.request_code'), true
);
reset role;
set local role service_role;
do $renewal_probe$
declare
  renewed_request public.national_focus_mcp_requests;
  fresh_token text := md5(gen_random_uuid()::text);
  exchange_result jsonb;
begin
  select * into renewed_request from public.national_focus_mcp_requests
  where request_hash = encode(sha256(convert_to(
    'renewal-' || current_setting('nf_mcp_test.request_code'), 'UTF8')), 'hex');
  exchange_result := public.exchange_national_focus_mcp_code(
    renewed_request.code_hash, renewed_request.client_id, renewed_request.redirect_uri,
    renewed_request.resource, renewed_request.code_challenge, fresh_token
  );
  if (exchange_result ->> 'expires_in')::integer not between 1790 and 1800
    or exchange_result ? 'refresh_token' then
    raise exception 'renewed_grant_has_wrong_lifetime_or_refresh_token';
  end if;
  perform public.read_national_focus_mcp_metadata(fresh_token, 7);
  begin
    perform public.read_national_focus_mcp_metadata(current_setting('nf_mcp_test.token_hash'), 7);
    raise exception 'renewal_revived_revoked_token';
  exception when sqlstate '28000' then null;
  end;
end
$renewal_probe$;

rollback;
