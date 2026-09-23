-- Reproducible, rollback-only RLS checks for Ticket T10.
-- Run against an isolated Supabase project with:
--   supabase db query --linked -f supabase/tests/focus_sync_sources_rls.sql
-- The test uses an existing isolated test administrator as the source owner and
-- a synthetic second identity. It creates only source rows in one transaction,
-- then rolls everything back. It exercises policies as `authenticated`.

begin;

do $setup$
declare
  test_owner_id uuid;
begin
  select user_id into test_owner_id
  from public.app_admins
  order by user_id
  limit 1;

  if test_owner_id is null then
    raise exception 'an isolated test administrator is required';
  end if;

  perform set_config('t10.focus_rls_owner_id', test_owner_id::text, true);
  perform set_config('t10.focus_rls_other_id', gen_random_uuid()::text, true);
  perform set_config(
    't10.focus_rls_source_id',
    'e4654ec9-cac3-4411-9a40-bd8310100001',
    true
  );
end
$setup$;

set local role authenticated;
do $set_owner_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('t10.focus_rls_owner_id'),
    true
  );
end
$set_owner_claim$;

insert into public.focus_sync_sources (
  source_id,
  user_id,
  device_id,
  entity_type,
  entity_id,
  parent_source_id,
  occurred_at,
  payload
)
values (
  current_setting('t10.focus_rls_source_id')::uuid,
  current_setting('t10.focus_rls_owner_id')::uuid,
  gen_random_uuid(),
  'focus_appointment',
  gen_random_uuid(),
  null,
  now(),
  '{}'::jsonb
);

do $set_other_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('t10.focus_rls_other_id'),
    true
  );
end
$set_other_claim$;

do $probe$
begin
  if exists (
    select 1
    from public.focus_sync_sources
    where source_id = current_setting('t10.focus_rls_source_id')::uuid
  ) then
    raise exception 'cross_user_select_leak';
  end if;

  begin
    insert into public.focus_sync_sources (
      source_id,
      user_id,
      device_id,
      entity_type,
      entity_id,
      parent_source_id,
      occurred_at,
      payload
    )
    values (
      gen_random_uuid(),
      current_setting('t10.focus_rls_owner_id')::uuid,
      gen_random_uuid(),
      'focus_appointment',
      gen_random_uuid(),
      null,
      now(),
      '{}'::jsonb
    );

    raise exception 'cross_user_insert_allowed';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config(
    'request.jwt.claim.sub',
    current_setting('t10.focus_rls_owner_id'),
    true
  );

  if not exists (
    select 1
    from public.focus_sync_sources
    where source_id = current_setting('t10.focus_rls_source_id')::uuid
  ) then
    raise exception 'owner_select_missing';
  end if;
end
$probe$;

rollback;

do $rollback_check$
begin
  if exists (
    select 1
    from public.focus_sync_sources
    where source_id = 'e4654ec9-cac3-4411-9a40-bd8310100001'::uuid
  ) then
    raise exception 'rls_probe_source_was_not_rolled_back';
  end if;
end
$rollback_check$;
