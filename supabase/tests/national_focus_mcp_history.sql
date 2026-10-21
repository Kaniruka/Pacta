-- Rollback-only acceptance probe for read_national_focus_mcp_history_snapshot.
-- Run after migrations 202610210001 and 202610220001 in an isolated project.
-- All auth users and business fixtures are transaction-local; no ordinary user
-- is selected or modified.
begin;
select set_config('request.jwt.claim.role', 'service_role', true);

do $fixture$
declare
  owner_id uuid := gen_random_uuid(); other_id uuid := gen_random_uuid(); empty_id uuid := gen_random_uuid();
  client_id text := 'nf-content-probe-' || gen_random_uuid()::text;
  owner_token text := md5(gen_random_uuid()::text); other_token text := md5(gen_random_uuid()::text);
  empty_token text := md5(gen_random_uuid()::text); expired_token text := md5(gen_random_uuid()::text);
  revoked_token text := md5(gen_random_uuid()::text);
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
  values
    ('00000000-0000-0000-0000-000000000000',owner_id,'authenticated','authenticated','nf-owner-'||owner_id||'@probe.invalid','',now(),now(),now()),
    ('00000000-0000-0000-0000-000000000000',other_id,'authenticated','authenticated','nf-other-'||other_id||'@probe.invalid','',now(),now(),now()),
    ('00000000-0000-0000-0000-000000000000',empty_id,'authenticated','authenticated','nf-empty-'||empty_id||'@probe.invalid','',now(),now(),now());
  insert into public.national_focus_mcp_clients(id,client_name,redirect_uris)
  values(client_id,'Rollback history acceptance probe','["https://probe.invalid/callback"]'::jsonb);
  insert into public.national_focus_mcp_grants(user_id,client_id,token_hash,expires_at,revoked_at)
  values(owner_id,client_id,owner_token,now()+interval '1 hour',null),
    (other_id,client_id,other_token,now()+interval '1 hour',null),
    (empty_id,client_id,empty_token,now()+interval '1 hour',null),
    (owner_id,client_id,expired_token,now()-interval '1 minute',null),
    (owner_id,client_id,revoked_token,now()+interval '1 hour',now());
  insert into public.cloud_business_snapshots(user_id,revision,payload,device_id,device_name,data_updated_at,row_count)
  values
    (owner_id,1,jsonb_build_object('schemaVersion',1,'userId',owner_id::text,'tables',jsonb_build_object(
      'local_national_focus_cards',jsonb_build_array(jsonb_build_object('user_id',owner_id::text,'id','owner-card','name','Owner card','action','Owner action')),
      'local_national_focus_strengthening_levels',jsonb_build_array(jsonb_build_object('user_id',owner_id::text,'card_id','owner-card','level_number',1,'action_override','Strengthened action')),
      'local_national_focus_requirement_versions',jsonb_build_array(jsonb_build_object('user_id',owner_id::text,'id','owner-version','card_id','owner-card','version_number',1,'effective_action','Owner action')),
      'local_national_focus_maintenance',jsonb_build_array(jsonb_build_object('user_id',owner_id::text,'last_settled_checkpoint_at',now())),
      'local_national_focus_failures',jsonb_build_array(jsonb_build_object('user_id',owner_id::text,'id','owner-event')),
      'focus_sync_sources',jsonb_build_array(jsonb_build_object('payload','MIXED_SOURCE_LOG_OUT_OF_SCOPE')),
      'local_goals',jsonb_build_array(jsonb_build_object('title','OTHER_BUSINESS_DATA_OUT_OF_SCOPE'))
    )),'owner-device','Owner fixture device',now(),8),
    (other_id,1,jsonb_build_object('schemaVersion',1,'userId',other_id::text,'tables',jsonb_build_object(
      'local_national_focus_cards',jsonb_build_array(jsonb_build_object('user_id',other_id::text,'id','other-card','name','OTHER_USER_SECRET')),
      'local_national_focus_strengthening_levels','[]'::jsonb,'local_national_focus_requirement_versions','[]'::jsonb,
      'local_national_focus_maintenance','[]'::jsonb,'local_national_focus_failures','[]'::jsonb
    )),'other-device','Other fixture device',now(),1);
  insert into public.user_suspension_periods(user_id) values(other_id);
  perform set_config('nf_content.owner_id',owner_id::text,true);
  perform set_config('nf_content.other_id',other_id::text,true);
  perform set_config('nf_content.empty_id',empty_id::text,true);
  perform set_config('nf_content.owner_token',owner_token,true);
  perform set_config('nf_content.other_token',other_token,true);
  perform set_config('nf_content.empty_token',empty_token,true);
  perform set_config('nf_content.expired_token',expired_token,true);
  perform set_config('nf_content.revoked_token',revoked_token,true);
end
$fixture$;

do $client_privileges$
begin
  if has_function_privilege('anon','public.read_national_focus_mcp_history_snapshot(text,bigint)','EXECUTE')
    or has_function_privilege('authenticated','public.read_national_focus_mcp_history_snapshot(text,bigint)','EXECUTE') then
    raise exception 'history_rpc_granted_to_client_role';
  end if;
end
$client_privileges$;

set local role anon;
do $anon$
begin
  begin
    perform public.read_national_focus_mcp_history_snapshot(current_setting('nf_content.owner_token'),1);
    raise exception 'anon_called_history_rpc';
  exception when insufficient_privilege then null;
  end;
end
$anon$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('nf_content.other_id'),true);
do $authenticated$
declare visible_count integer;
begin
  begin
    perform public.read_national_focus_mcp_history_snapshot(current_setting('nf_content.owner_token'),1);
    raise exception 'authenticated_called_history_rpc';
  exception when insufficient_privilege then null;
  end;
  select count(*) into visible_count from public.cloud_business_snapshots;
  if visible_count <> 0 then raise exception 'rls_exposed_another_users_snapshot'; end if;
  perform set_config('request.jwt.claim.sub',current_setting('nf_content.owner_id'),true);
  select count(*) into visible_count from public.cloud_business_snapshots;
  if visible_count <> 1 then raise exception 'rls_did_not_expose_only_own_snapshot'; end if;
end
$authenticated$;
reset role;

set local role service_role;
do $scope_and_reads$
declare
  result jsonb;
  expected text[] := array['local_national_focus_failures'];
  actual text[]; before_row jsonb; after_row jsonb;
begin
  select jsonb_build_object('revision',revision,'payload',payload,'device_id',device_id,'device_name',device_name,
    'data_updated_at',data_updated_at,'uploaded_at',uploaded_at,'row_count',row_count)
  into before_row from public.cloud_business_snapshots where user_id=current_setting('nf_content.owner_id')::uuid;
  result := public.read_national_focus_mcp_history_snapshot(current_setting('nf_content.owner_token'),1);
  if result->>'status' <> 'available' or (result->>'revision')::bigint <> 1
    or result#>>'{source_device,id}' <> 'owner-device' then raise exception 'owner_metadata_missing'; end if;
  select array_agg(key order by key) into actual from jsonb_object_keys(result->'tables') keys(key);
  if actual is distinct from expected then raise exception 'unexpected_table_scope: %',actual; end if;
  if result::text like '%OTHER_USER_SECRET%'
    or result::text like '%MIXED_SOURCE_LOG_OUT_OF_SCOPE%' or result::text like '%OTHER_BUSINESS_DATA_OUT_OF_SCOPE%' then
    raise exception 'history_rpc_leaked_other_user_or_out_of_scope_data'; end if;
  if result#>>'{tables,local_national_focus_failures,0,id}' <> 'owner-event' then
    raise exception 'owner_failure_missing'; end if;
  perform public.read_national_focus_mcp_history_snapshot(current_setting('nf_content.owner_token'),1);
  select jsonb_build_object('revision',revision,'payload',payload,'device_id',device_id,'device_name',device_name,
    'data_updated_at',data_updated_at,'uploaded_at',uploaded_at,'row_count',row_count)
  into after_row from public.cloud_business_snapshots where user_id=current_setting('nf_content.owner_id')::uuid;
  if before_row is distinct from after_row then raise exception 'repeated_read_modified_business_snapshot'; end if;
  begin
    perform public.read_national_focus_mcp_history_snapshot(current_setting('nf_content.other_token'),1);
    raise exception 'suspended_delegate_accepted';
  exception when sqlstate '28000' then null;
  end;
  begin
    perform public.read_national_focus_mcp_history_snapshot(current_setting('nf_content.expired_token'),1);
    raise exception 'expired_delegate_accepted';
  exception when sqlstate '28000' then null;
  end;
  begin
    perform public.read_national_focus_mcp_history_snapshot(current_setting('nf_content.revoked_token'),1);
    raise exception 'revoked_delegate_accepted';
  exception when sqlstate '28000' then null;
  end;
end
$scope_and_reads$;

do $snapshot_states$
declare result jsonb;
begin
  result := public.read_national_focus_mcp_history_snapshot(current_setting('nf_content.empty_token'),null);
  if result->>'status' <> 'no_snapshot' or result ? 'tables' then raise exception 'no_snapshot_misrepresented'; end if;
  -- Once a client has seen revision 1, disappearance of its snapshot must be
  -- a revision conflict; otherwise stale analysis could silently restart on
  -- an absent state. This guards delete/recreate races.
  insert into public.cloud_business_snapshots(user_id,revision,payload,device_id,device_name,data_updated_at,row_count)
  values(current_setting('nf_content.empty_id')::uuid,1,
    jsonb_build_object('schemaVersion',1,'userId',current_setting('nf_content.empty_id'),'tables',jsonb_build_object(
      'local_national_focus_cards','[]'::jsonb,'local_national_focus_strengthening_levels','[]'::jsonb,
      'local_national_focus_requirement_versions','[]'::jsonb,'local_national_focus_maintenance','[]'::jsonb,
      'local_national_focus_failures','[]'::jsonb)), 'empty-device','Empty fixture device',now(),0);
  delete from public.cloud_business_snapshots where user_id=current_setting('nf_content.empty_id')::uuid;
  begin
    perform public.read_national_focus_mcp_history_snapshot(current_setting('nf_content.empty_token'),1);
    raise exception 'missing_snapshot_with_expected_revision_was_not_rejected';
  exception when sqlstate 'PT409' then null;
  end;
  update public.cloud_business_snapshots set payload=jsonb_set(payload,'{tables,local_national_focus_cards}','null'::jsonb)
  where user_id=current_setting('nf_content.owner_id')::uuid;
  result := public.read_national_focus_mcp_history_snapshot(current_setting('nf_content.owner_token'),null);
  if result->>'status' <> 'unsupported_snapshot' or result ? 'tables' then raise exception 'unsupported_snapshot_misrepresented'; end if;
end
$snapshot_states$;

-- Exercise a real explicit whole-snapshot replacement via Pacta's upload RPC.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('nf_content.owner_id'),true);
select public.save_cloud_business_snapshot(1,
  jsonb_build_object('schemaVersion',1,'userId',current_setting('nf_content.owner_id'),'tables',jsonb_build_object(
    'local_national_focus_cards',jsonb_build_array(jsonb_build_object('user_id',current_setting('nf_content.owner_id'),'id','replacement-card','name','Replacement card')),
    'local_national_focus_strengthening_levels','[]'::jsonb,'local_national_focus_requirement_versions','[]'::jsonb,
    'local_national_focus_maintenance','[]'::jsonb,'local_national_focus_failures','[]'::jsonb,'focus_sync_sources','[]'::jsonb
  )),'replacement-device','Replacement fixture device',now(),1);
reset role;
set local role service_role;
do $replacement$
declare result jsonb;
begin
  begin
    perform public.read_national_focus_mcp_history_snapshot(current_setting('nf_content.owner_token'),1);
    raise exception 'stale_revision_after_upload_accepted';
  exception when sqlstate 'PT409' then null;
  end;
  result := public.read_national_focus_mcp_history_snapshot(current_setting('nf_content.owner_token'),2);
  if result->>'status' <> 'available' or (result->>'revision')::bigint <> 2
    or result#>'{tables,local_national_focus_failures}' <> '[]'::jsonb
    or result#>>'{source_device,id}' <> 'replacement-device' then raise exception 'replacement_snapshot_missing'; end if;
end
$replacement$;
rollback;
