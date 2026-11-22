-- Rollback-only RLS checks for Ticket T20 calendar data.
-- Run against an isolated Supabase project with:
--   supabase db query --linked -f supabase/tests/calendar_blocks_rls.sql

begin;

do $setup$
declare
  owner_id uuid;
begin
  -- 管理员名单已随 202611220001_remove_legacy_admin_schema 移除：这里只要求
  -- 任意一名活跃用户，an isolated active test user is required.
  select account.id into owner_id
  from auth.users as account
  where not exists (
      select 1
      from public.user_suspension_periods as suspension
      where suspension.user_id = account.id
        and suspension.restored_at is null
    )
    and not exists (
      select 1
      from public.user_purge_receipts as purge
      where purge.user_id = account.id
        and purge.status in ('pending', 'completed')
    )
  order by account.created_at desc, account.id
  limit 1;
  if owner_id is null then
    raise exception 'an isolated active test user is required';
  end if;
  perform set_config('t20.calendar_owner_id', owner_id::text, true);
  perform set_config('t20.calendar_other_id', gen_random_uuid()::text, true);
  perform set_config('t20.calendar_source_id', 't20-source-rls-check', true);
end
$setup$;

set local role authenticated;
do $set_owner_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('t20.calendar_owner_id'),
    true
  );
end
$set_owner_claim$;

insert into public.calendar_sources (
  user_id, source_id, display_name, time_zone_id
)
values (
  current_setting('t20.calendar_owner_id')::uuid,
  current_setting('t20.calendar_source_id'),
  'T20 RLS test source',
  'Etc/UTC'
);

insert into public.calendar_blocks (
  user_id, source_id, source_event_id, occurrence_id, event_identity,
  title, starts_at, ends_at, is_all_day, availability, time_zone_id
)
values (
  current_setting('t20.calendar_owner_id')::uuid,
  current_setting('t20.calendar_source_id'),
  't20-event-rls-check', 't20-occurrence-rls-check',
  't20-identity-rls-check', 'T20 RLS test event',
  '2026-09-25 09:00:00+00', '2026-09-25 10:00:00+00',
  false, 'busy', 'Etc/UTC'
);

do $set_other_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('t20.calendar_other_id'),
    true
  );
end
$set_other_claim$;

do $probe$
begin
  if exists (
    select 1 from public.calendar_sources
    where source_id = current_setting('t20.calendar_source_id')
  ) then
    raise exception 'cross_user_calendar_source_leak';
  end if;
  if exists (
    select 1 from public.calendar_blocks
    where occurrence_id = 't20-occurrence-rls-check'
  ) then
    raise exception 'cross_user_calendar_block_leak';
  end if;

  begin
    insert into public.calendar_sources (
      user_id, source_id, display_name, time_zone_id
    )
    values (
      current_setting('t20.calendar_owner_id')::uuid,
      't20-cross-user-insert', 'T20 forbidden source', 'Etc/UTC'
    );
    raise exception 'cross_user_calendar_source_insert_allowed';
  exception
    when insufficient_privilege then null;
  end;
end
$probe$;

rollback;
