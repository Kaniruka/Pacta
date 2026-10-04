-- Rollback-only RLS and compare-and-swap checks. Run against an isolated
-- Supabase project after applying the 202610040001 and 202610040002 snapshot migrations.
begin;

do $setup$
declare
  owner_id uuid;
  other_id uuid;
begin
  select user_id into owner_id
  from public.app_admins
  order by user_id
  limit 1;
  if owner_id is null then
    raise exception 'an isolated active administrator is required';
  end if;
  -- Make this test repeatable, with rollback restoring any prior test state.
  delete from public.cloud_business_snapshots where user_id = owner_id;
  select id into other_id
  from auth.users
  where id <> owner_id
  order by created_at desc
  limit 1;
  if other_id is null then
    other_id := gen_random_uuid();
  end if;
  perform set_config('snapshot_test.owner_id', owner_id::text, true);
  perform set_config('snapshot_test.other_id', other_id::text, true);
  perform set_config('snapshot_test.goal_id', gen_random_uuid()::text, true);
end
$setup$;

set local role authenticated;
do $owner_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('snapshot_test.owner_id'),
    true
  );
end
$owner_claim$;

-- A nonzero revision must not create an absent snapshot.
do $first_revision$
begin
  begin
    perform public.save_cloud_business_snapshot(
      2,
      jsonb_build_object(
        'schemaVersion', 1,
        'userId', current_setting('snapshot_test.owner_id'),
        'tables', '{}'::jsonb
      ),
      'device-a', 'Device A', now(), 0
    );
    raise exception 'nonzero_initial_revision_was_accepted';
  exception
    when sqlstate 'PT409' then null;
  end;
end
$first_revision$;

insert into public.goals (
  id, user_id, title, classification, created_at, updated_at
) values (
  current_setting('snapshot_test.goal_id')::uuid,
  current_setting('snapshot_test.owner_id')::uuid,
  'legacy row', 'regular', now(), now()
);

do $legacy_inspect$
declare
  legacy_result jsonb;
begin
  legacy_result := public.read_legacy_business_records();
  if legacy_result is null or legacy_result ->> 'token' is null then
    raise exception 'legacy_cloud_data_was_not_read';
  end if;
  perform set_config(
    'snapshot_test.legacy_token', legacy_result ->> 'token', true
  );
end
$legacy_inspect$;

update public.goals
set title = 'legacy row changed after inspect'
where id = current_setting('snapshot_test.goal_id')::uuid;

do $stale_legacy_token$
begin
  begin
    perform public.save_cloud_business_snapshot(
      0,
      jsonb_build_object(
        'schemaVersion', 1,
        'userId', current_setting('snapshot_test.owner_id'),
        'tables', '{}'::jsonb
      ),
      'device-a', 'Device A', now(), 0,
      current_setting('snapshot_test.legacy_token')
    );
    raise exception 'stale_legacy_token_was_accepted';
  exception
    when sqlstate 'PT409' then null;
  end;
end
$stale_legacy_token$;

do $save_current_legacy$
declare
  current_legacy_result jsonb;
begin
  current_legacy_result := public.read_legacy_business_records();
  perform public.save_cloud_business_snapshot(
    0,
    jsonb_build_object(
      'schemaVersion', 1,
      'userId', current_setting('snapshot_test.owner_id'),
      'tables', '{}'::jsonb
    ),
    'device-a', 'Device A', now(), 0,
    current_legacy_result ->> 'token'
  );
  if public.read_legacy_business_records() is not null then
    raise exception 'legacy_projection_not_hidden_after_snapshot';
  end if;
end
$save_current_legacy$;

do $owner_visibility_and_cas$
begin
  if not exists (
    select 1 from public.cloud_business_snapshots
    where user_id = current_setting('snapshot_test.owner_id')::uuid
      and revision = 1
  ) then
    raise exception 'owner_cannot_read_own_snapshot';
  end if;
  begin
    insert into public.cloud_business_snapshots (
      user_id, revision, payload, device_id, device_name,
      data_updated_at, row_count
    ) values (
      current_setting('snapshot_test.owner_id')::uuid,
      1,
      jsonb_build_object(
        'schemaVersion', 1,
        'userId', current_setting('snapshot_test.owner_id'),
        'tables', '{}'::jsonb
      ),
      'direct-write', 'Direct write', now(), 0
    );
    raise exception 'authenticated_direct_write_was_accepted';
  exception
    when insufficient_privilege then null;
  end;
  begin
    update public.goals
    set title = 'old client write'
    where id = current_setting('snapshot_test.goal_id')::uuid;
    raise exception 'legacy_write_after_snapshot_was_accepted';
  exception
    when sqlstate 'PT410' then null;
  end;
  begin
    perform public.save_cloud_business_snapshot(
      0,
      jsonb_build_object(
        'schemaVersion', 1,
        'userId', current_setting('snapshot_test.owner_id'),
        'tables', '{}'::jsonb
      ),
      'device-a', 'Device A', now(), 0
    );
    raise exception 'stale_revision_was_accepted';
  exception
    when sqlstate 'PT409' then null;
  end;
end
$owner_visibility_and_cas$;

do $invalid_payload$
begin
  begin
    perform public.save_cloud_business_snapshot(
      1,
      '{"schemaVersion":1,"tables":{}}'::jsonb,
      'device-a', 'Device A', now(), 0
    );
    raise exception 'payload_without_owner_was_accepted';
  exception
    when sqlstate '22023' then null;
  end;
end
$invalid_payload$;

do $other_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('snapshot_test.other_id'),
    true
  );
end
$other_claim$;

do $other_user_isolation$
begin
  if exists (
    select 1 from public.cloud_business_snapshots
    where user_id = current_setting('snapshot_test.owner_id')::uuid
  ) then
    raise exception 'cross_user_snapshot_read_leak';
  end if;
end
$other_user_isolation$;

rollback;
