-- Reproducible, rollback-only RLS checks for Ticket T18.
-- Run against an isolated Supabase project after applying the T18 migration.

begin;

-- Exercise the migration contract in this same rollback-only transaction.
alter table public.focus_sync_sources
  add column if not exists parent_source_ids uuid[] not null default '{}';
alter table public.focus_sync_sources
  drop constraint if exists focus_sync_sources_entity_type_check;
alter table public.focus_sync_sources
  add constraint focus_sync_sources_entity_type_check
  check (
    entity_type in (
      'focus_session',
      'focus_appointment',
      'national_focus_tree'
    )
  );

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

  perform set_config('t18.national_focus_owner_id', test_owner_id::text, true);
  perform set_config(
    't18.national_focus_other_id',
    gen_random_uuid()::text,
    true
  );
  perform set_config(
    't18.national_focus_source_id',
    'e4654ec9-cac3-4411-9a40-bd8310180001',
    true
  );
end
$setup$;

set local role authenticated;
do $set_owner_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('t18.national_focus_owner_id'),
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
  parent_source_ids,
  occurred_at,
  payload
)
values (
  current_setting('t18.national_focus_source_id')::uuid,
  current_setting('t18.national_focus_owner_id')::uuid,
  gen_random_uuid(),
  'national_focus_tree',
  '00000000-0000-4000-8000-000000000018'::uuid,
  null,
  '{}',
  now(),
  '{"schemaVersion":1,"operation":"rls_probe","cards":[]}'::jsonb
);

do $set_other_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('t18.national_focus_other_id'),
    true
  );
end
$set_other_claim$;

do $probe$
begin
  if exists (
    select 1
    from public.focus_sync_sources
    where source_id = current_setting('t18.national_focus_source_id')::uuid
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
      parent_source_ids,
      occurred_at,
      payload
    )
    values (
      gen_random_uuid(),
      current_setting('t18.national_focus_owner_id')::uuid,
      gen_random_uuid(),
      'national_focus_tree',
      '00000000-0000-4000-8000-000000000018'::uuid,
      null,
      '{}',
      now(),
      '{}'::jsonb
    );

    raise exception 'cross_user_insert_allowed';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config(
    'request.jwt.claim.sub',
    current_setting('t18.national_focus_owner_id'),
    true
  );

  if not exists (
    select 1
    from public.focus_sync_sources
    where source_id = current_setting('t18.national_focus_source_id')::uuid
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
    where source_id = 'e4654ec9-cac3-4411-9a40-bd8310180001'::uuid
  ) then
    raise exception 'rls_probe_source_was_not_rolled_back';
  end if;
end
$rollback_check$;
