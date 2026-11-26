-- Rollback-only authorization, RLS, scoped token, audit log, suspension,
-- and constrained write-invariant checks for MCP v2.
-- Run only in an isolated Supabase project after applying
-- 202611250002_national_focus_mcp_v2.sql. Creates transaction-local test
-- identities; no ordinary user is selected or modified.

begin;

do $setup$
declare
  test_user_id uuid := gen_random_uuid();
  other_user_id uuid := gen_random_uuid();
  other_token text := 'pacta_mcp_' || repeat('b', 64);
  other_token_hash text;
  other_grant_id uuid;
begin
  perform set_config('request.jwt.claim.role', 'service_role', true);
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
  values
    ('00000000-0000-0000-0000-000000000000',test_user_id,'authenticated','authenticated','nf-v2-'||test_user_id||'@probe.invalid','',now(),now(),now()),
    ('00000000-0000-0000-0000-000000000000',other_user_id,'authenticated','authenticated','nf-v2-'||other_user_id||'@probe.invalid','',now(),now(),now());

  other_token_hash := encode(sha256(convert_to(other_token, 'UTF8')), 'hex');

  insert into public.national_focus_mcp_grants(
    user_id, label, agent_preset, scope, token_hash, token_prefix, expires_at
  ) values (
    other_user_id, 'Other user token', 'codex', 'national_focus:read',
    other_token_hash, 'pacta_mcp_bbbb...', now() + interval '1 hour'
  ) returning id into other_grant_id;

  insert into public.cloud_business_snapshots(
    user_id, revision, payload, device_id, device_name, data_updated_at, row_count
  ) values (
    test_user_id,
    1,
    jsonb_build_object(
      'schemaVersion', 4,
      'userId', test_user_id::text,
      'tables', jsonb_build_object(
        'local_goals', '[]'::jsonb,
        'local_tasks', '[]'::jsonb,
        'local_national_focus_cards', jsonb_build_array(
          jsonb_build_object(
            'user_id', test_user_id::text,
            'id', 'card-1',
            'name', '早起断屏',
            'trigger_condition', '',
            'action', '起床 30 分钟内不用娱乐 App',
            'scope', null,
            'exception_notes', null,
            'is_in_tree', 1,
            'parent_id', null,
            'state', 'lit',
            'successful_days', 5,
            'current_consecutive_days', 3,
            'best_consecutive_days', 4,
            'maintenance_cycle_started', 1,
            'failure_reason', null,
            'cascade_source_card_id', null,
            'cascade_prior_state', null,
            'review_disposition', 'accepted',
            'active_strengthening_level', null,
            'icon_key', 'lucide:sunrise',
            'created_at', 1700000000,
            'updated_at', 1700000000,
            'deleted_at', null
          )
        ),
        'local_national_focus_strengthening_levels', '[]'::jsonb,
        'local_national_focus_maintenance', '[]'::jsonb,
        'local_national_focus_failures', '[]'::jsonb,
        'focus_precedent_rules', '[]'::jsonb,
        'focus_appointments', '[]'::jsonb,
        'focus_sessions', '[]'::jsonb,
        'focus_nodes', '[]'::jsonb,
        'focus_chain_records', '[]'::jsonb,
        'appointment_chain_records', '[]'::jsonb,
        'chain_signals', '[]'::jsonb,
        'focus_sync_sources', '[]'::jsonb,
        'local_calendar_sources', '[]'::jsonb,
        'local_calendar_blocks', '[]'::jsonb,
        'local_schedules', '[]'::jsonb,
        'local_schedule_recurrences', '[]'::jsonb
      )
    ),
    'probe-device-id', 'Probe device', now(), 1
  );

  insert into public.user_suspension_periods(user_id) values (other_user_id);

  perform set_config('nf_mcp_test.user_id', test_user_id::text, true);
  perform set_config('nf_mcp_test.other_user_id', other_user_id::text, true);
  perform set_config('nf_mcp_test.other_token_hash', other_token_hash, true);
  perform set_config('nf_mcp_test.other_grant_id', other_grant_id::text, true);
end
$setup$;

-- Default-deny RLS check for authenticated role.
grant select, insert, update, delete on
  public.national_focus_mcp_grants,
  public.national_focus_mcp_audit_logs
to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('nf_mcp_test.user_id'), true);

do $rls_and_create_probe$
declare
  visible_rows integer;
  created_ro jsonb;
  created_rw jsonb;
  ro_hash text;
  rw_hash text;
begin
  select count(*) into visible_rows from public.national_focus_mcp_grants;
  if visible_rows <> 0 then
    raise exception 'rls_leaked_grants';
  end if;
  select count(*) into visible_rows from public.national_focus_mcp_audit_logs;
  if visible_rows <> 0 then
    raise exception 'rls_leaked_audit_logs';
  end if;

  -- Foreign revoke must fail with 42501.
  begin
    perform public.revoke_national_focus_mcp_grant(current_setting('nf_mcp_test.other_grant_id')::uuid);
    raise exception 'foreign_grant_revoked';
  exception when sqlstate '42501' then null;
  end;

  created_ro := public.create_national_focus_mcp_grant('Codex Read', 'national_focus:read', 1800, 'codex');
  created_rw := public.create_national_focus_mcp_grant('Antigravity RW', 'national_focus:readwrite', null, 'antigravity');

  if (created_ro ->> 'token') not like 'pacta_mcp_%'
    or created_rw ->> 'expires_at' is not null then
    raise exception 'unexpected_created_grant_shape';
  end if;

  ro_hash := encode(sha256(convert_to(created_ro ->> 'token', 'UTF8')), 'hex');
  rw_hash := encode(sha256(convert_to(created_rw ->> 'token', 'UTF8')), 'hex');

  perform set_config('nf_mcp_test.ro_id', created_ro ->> 'id', true);
  perform set_config('nf_mcp_test.rw_id', created_rw ->> 'id', true);
  perform set_config('nf_mcp_test.ro_hash', ro_hash, true);
  perform set_config('nf_mcp_test.rw_hash', rw_hash, true);
end
$rls_and_create_probe$;

reset role;
set local role service_role;

do $service_scope_and_write_probe$
declare
  meta jsonb;
  updated_cards jsonb;
  bad_cards jsonb;
begin
  -- Suspended user token fails.
  begin
    perform public.read_national_focus_mcp_metadata(current_setting('nf_mcp_test.other_token_hash'), null, 'national_focus:read');
    raise exception 'suspended_token_accepted';
  exception when sqlstate '28000' then null;
  end;

  -- Readonly token fails when readwrite scope is required.
  begin
    perform public.verify_national_focus_mcp_grant(current_setting('nf_mcp_test.ro_hash'), 'national_focus:readwrite');
    raise exception 'readonly_token_escalated';
  exception when sqlstate '42501' then null;
  end;

  meta := public.read_national_focus_mcp_metadata(current_setting('nf_mcp_test.rw_hash'), 1, 'national_focus:readwrite');
  if meta ->> 'status' <> 'available' or (meta ->> 'revision')::integer <> 1 then
    raise exception 'unexpected_metadata_before_write';
  end if;

  -- Forbidden runtime mutation (altering successful_days) must fail.
  bad_cards := jsonb_build_array(
    jsonb_build_object(
      'user_id', current_setting('nf_mcp_test.user_id'),
      'id', 'card-1',
      'name', '早起断屏',
      'trigger_condition', '',
      'action', '起床 30 分钟内不用娱乐 App',
      'scope', null,
      'exception_notes', null,
      'is_in_tree', 1,
      'parent_id', null,
      'state', 'lit',
      'successful_days', 999,
      'current_consecutive_days', 3,
      'best_consecutive_days', 4,
      'maintenance_cycle_started', 1,
      'failure_reason', null,
      'cascade_source_card_id', null,
      'cascade_prior_state', null,
      'review_disposition', 'accepted',
      'active_strengthening_level', null,
      'icon_key', 'lucide:sunrise',
      'created_at', 1700000000,
      'updated_at', 1700000001,
      'deleted_at', null
    )
  );
  begin
    perform public.write_national_focus_mcp_snapshot(
      current_setting('nf_mcp_test.rw_hash'), 1, bad_cards, '[]'::jsonb,
      'update_national_focus_card', 'illegal progress edit'
    );
    raise exception 'illegal_progress_mutation_succeeded';
  exception when sqlstate '42501' then null;
  end;

  -- Valid constrained write advances revision and archives history.
  updated_cards := jsonb_build_array(
    jsonb_build_object(
      'user_id', current_setting('nf_mcp_test.user_id'),
      'id', 'card-1',
      'name', '先发制人',
      'trigger_condition', '',
      'action', '起床 30 分钟内不用娱乐 App',
      'scope', null,
      'exception_notes', null,
      'is_in_tree', 1,
      'parent_id', null,
      'state', 'lit',
      'successful_days', 5,
      'current_consecutive_days', 3,
      'best_consecutive_days', 4,
      'maintenance_cycle_started', 1,
      'failure_reason', null,
      'cascade_source_card_id', null,
      'cascade_prior_state', null,
      'review_disposition', 'accepted',
      'active_strengthening_level', null,
      'icon_key', 'lucide:sunrise',
      'created_at', 1700000000,
      'updated_at', 1700000010,
      'deleted_at', null
    )
  );
  meta := public.write_national_focus_mcp_snapshot(
    current_setting('nf_mcp_test.rw_hash'), 1, updated_cards, '[]'::jsonb,
    'update_national_focus_card', '更新国策卡「先发制人」'
  );
  if (meta ->> 'revision')::integer <> 2 then
    raise exception 'write_did_not_advance_revision';
  end if;
  if not exists (
    select 1 from public.cloud_business_snapshot_history
    where user_id = current_setting('nf_mcp_test.user_id')::uuid and revision = 2
  ) then
    raise exception 'write_did_not_archive_history';
  end if;
end
$service_scope_and_write_probe$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('nf_mcp_test.user_id'), true);

do $audit_and_revoke_probe$
declare
  log_count integer;
  revoked integer;
  remaining_grants integer;
  preserved_label text;
begin
  select count(*) into log_count from public.list_national_focus_mcp_audit_logs(20);
  if log_count <> 1 then
    raise exception 'expected_one_audit_log_got_%', log_count;
  end if;

  -- Active grant cannot be deleted before revocation.
  begin
    perform public.delete_national_focus_mcp_grant(current_setting('nf_mcp_test.rw_id')::uuid);
    raise exception 'active_grant_deleted';
  exception when sqlstate '22023' then null;
  end;

  -- Foreign grant cannot be deleted.
  begin
    perform public.delete_national_focus_mcp_grant(current_setting('nf_mcp_test.other_grant_id')::uuid);
    raise exception 'foreign_grant_deleted';
  exception when sqlstate '42501' then null;
  end;

  revoked := public.revoke_all_national_focus_mcp_grants();
  if revoked <> 2 then
    raise exception 'expected_two_revoked_grants_got_%', revoked;
  end if;

  -- Revoking deletes grants directly while keeping historical audit log intact.
  select count(*) into remaining_grants from public.list_national_focus_mcp_grants();
  if remaining_grants <> 0 then
    raise exception 'expected_zero_remaining_grants_got_%', remaining_grants;
  end if;

  select grant_label into preserved_label
  from public.list_national_focus_mcp_audit_logs(20)
  limit 1;
  if preserved_label <> 'Antigravity RW' then
    raise exception 'audit_log_not_preserved_after_grant_revoke';
  end if;
end
$audit_and_revoke_probe$;

reset role;
set local role service_role;

-- Insert two expired grants for the test user to verify single delete and bulk clear.
do $seed_expired_grants$
declare
  uid uuid := current_setting('nf_mcp_test.user_id')::uuid;
  exp1 uuid;
begin
  insert into public.national_focus_mcp_grants(
    user_id, label, agent_preset, scope, token_hash, token_prefix, expires_at
  ) values
    (uid, 'Expired One', 'codex', 'national_focus:read', encode(sha256('exp1'::bytea), 'hex'), 'pacta_mcp_exp1...', now() - interval '2 hours'),
    (uid, 'Expired Two', 'codex', 'national_focus:read', encode(sha256('exp2'::bytea), 'hex'), 'pacta_mcp_exp2...', now() - interval '1 hour');
  select id into exp1 from public.national_focus_mcp_grants where user_id = uid and label = 'Expired One';
  perform set_config('nf_mcp_test.exp1_id', exp1::text, true);
end
$seed_expired_grants$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('nf_mcp_test.user_id'), true);

do $clear_expired_probe$
declare
  cleared integer;
  remaining integer;
begin
  perform public.delete_national_focus_mcp_grant(current_setting('nf_mcp_test.exp1_id')::uuid);
  cleared := public.clear_expired_national_focus_mcp_grants();
  if cleared <> 1 then
    raise exception 'expected_one_cleared_expired_grant_got_%', cleared;
  end if;
  select count(*) into remaining from public.list_national_focus_mcp_grants();
  if remaining <> 0 then
    raise exception 'expected_zero_grants_after_clear_got_%', remaining;
  end if;
end
$clear_expired_probe$;

reset role;
set local role service_role;

do $revoked_rejected$
begin
  begin
    perform public.read_national_focus_mcp_metadata(current_setting('nf_mcp_test.rw_hash'), null, 'national_focus:read');
    raise exception 'revoked_token_accepted';
  exception when sqlstate '28000' then null;
  end;
end
$revoked_rejected$;

rollback;
