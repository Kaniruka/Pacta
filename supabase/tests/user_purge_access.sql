-- Rollback-only checks for Ticket T27.
-- Run only against an isolated Supabase project after applying the migration:
--   supabase db query --linked -f supabase/tests/user_purge_access.sql
-- Requires one administrator and one non-administrator email user. This test
-- deletes the test identity inside a transaction and rolls it back at the end.

begin;

do $setup$
declare
  test_admin_id uuid;
  test_target_id uuid;
  test_other_id uuid;
  target_email text;
begin
  select user_id into test_admin_id
  from public.app_admins
  order by user_id
  limit 1;
  if test_admin_id is null then
    raise exception 'an isolated test administrator is required';
  end if;

  select account.id, account.email into test_target_id, target_email
  from auth.users as account
  where account.email is not null
    and not exists (
      select 1 from public.app_admins as administrator
      where administrator.user_id = account.id
    )
  order by account.created_at desc
  limit 1;
  if test_target_id is null then
    raise exception 'an isolated non-administrator email user is required';
  end if;

  select account.id into test_other_id
  from auth.users as account
  where account.id <> test_target_id
    and account.id <> test_admin_id
  order by account.created_at desc
  limit 1;
  if test_other_id is null then
    raise exception 'a second isolated user is required';
  end if;

  perform set_config('t27.admin_id', test_admin_id::text, true);
  perform set_config('t27.target_id', test_target_id::text, true);
  perform set_config('t27.other_id', test_other_id::text, true);
  perform set_config('t27.target_email', lower(btrim(target_email)), true);
  perform set_config('t27.goal_id', gen_random_uuid()::text, true);
  perform set_config('t27.task_id', gen_random_uuid()::text, true);
  perform set_config('t27.appointment_id', gen_random_uuid()::text, true);
  perform set_config('t27.session_id', gen_random_uuid()::text, true);
  perform set_config('t27.node_id', gen_random_uuid()::text, true);
  perform set_config('t27.source_id', gen_random_uuid()::text, true);
  perform set_config('t27.device_id', gen_random_uuid()::text, true);
  perform set_config('t27.other_goal_id', gen_random_uuid()::text, true);
  perform set_config('t27.calendar_source_id', gen_random_uuid()::text, true);
  perform set_config('t27.calendar_event_id', gen_random_uuid()::text, true);
  perform set_config('t27.calendar_occurrence_id', gen_random_uuid()::text, true);
  perform set_config('t27.calendar_identity', gen_random_uuid()::text, true);
  perform set_config('t27.precedent_rule', gen_random_uuid()::text, true);
end
$setup$;

-- Give the target a consumed eligibility row so the test covers fresh
-- eligibility issuance after a completed purge.
delete from public.registration_eligibility
where used_user_id = current_setting('t27.target_id')::uuid;

insert into public.registration_eligibility (
  identifier, identifier_type, used_at, used_user_id
)
values (
  current_setting('t27.target_email'),
  'email',
  now() - interval '60 days',
  current_setting('t27.target_id')::uuid
)
on conflict (identifier_type, identifier) do update
set used_at = excluded.used_at,
    used_user_id = excluded.used_user_id,
    revoked_at = null,
    purge_completed_at = null;

-- Move any earlier suspension out of the way, then create a fresh eligible
-- period through the same administrator RPC used by the App.
update public.user_suspension_periods
set restored_at = now(), restored_by = current_setting('t27.admin_id')::uuid
where user_id = current_setting('t27.target_id')::uuid
  and restored_at is null;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('t27.admin_id'), true);
select public.admin_suspend_user(current_setting('t27.target_id')::uuid);
reset role;

update public.user_suspension_periods
set suspended_at = now() - interval '31 days'
where user_id = current_setting('t27.target_id')::uuid
  and restored_at is null;

-- The service-only begin RPC verifies the administrator and current retention
-- state. The returned pending state is not a local cleanup receipt.
set local role service_role;
select public.admin_begin_user_purge(
  current_setting('t27.target_id')::uuid,
  current_setting('t27.admin_id')::uuid
);

select set_config('request.jwt.claim.sub', current_setting('t27.target_id'), true);
do $pending_receipt_probe$
declare
  receipt jsonb;
begin
  receipt := public.user_purge_receipt(
    current_setting('t27.target_id')::uuid
  );
  if receipt is not null then
    raise exception 'pending_purge_was_exposed_as_completed_receipt';
  end if;
  if public.current_user_is_active() then
    raise exception 'suspended_user_was_active_before_cloud_purge';
  end if;
end
$pending_receipt_probe$;
reset role;

-- A restore cannot race a pending Auth Admin deletion.
set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('t27.admin_id'), true);
do $restore_pending_probe$
begin
  begin
    perform public.admin_restore_user(current_setting('t27.target_id')::uuid);
    raise exception 'restore_allowed_during_pending_purge';
  exception
    when sqlstate '55000' then null;
  end;
end
$restore_pending_probe$;
reset role;

-- Prepare one row in every cloud business-data category represented by the
-- current migrations. National Focus is carried in focus_sync_sources.
insert into public.goals (
  id, user_id, title, classification, created_at, updated_at
)
values (
  current_setting('t27.goal_id')::uuid,
  current_setting('t27.target_id')::uuid,
  'purge test goal',
  'regular',
  now(),
  now()
);

insert into public.tasks (
  id, user_id, goal_id, title, classification, created_at, updated_at
)
values (
  current_setting('t27.task_id')::uuid,
  current_setting('t27.target_id')::uuid,
  current_setting('t27.goal_id')::uuid,
  'purge test task',
  'regular',
  now(),
  now()
);

insert into public.focus_appointments (
  id, user_id, task_id, mode, duration_seconds, started_at, ends_at, status,
  settled_at, updated_at
)
values (
  current_setting('t27.appointment_id')::uuid,
  current_setting('t27.target_id')::uuid,
  current_setting('t27.task_id')::uuid,
  'regular',
  60,
  now() - interval '2 minutes',
  now() - interval '1 minute',
  'succeeded',
  now() - interval '1 minute',
  now()
);

insert into public.focus_sessions (
  id, user_id, appointment_id, task_id, mode, duration_seconds, started_at,
  ends_at, status, completed_at, effective_seconds
)
values (
  current_setting('t27.session_id')::uuid,
  current_setting('t27.target_id')::uuid,
  current_setting('t27.appointment_id')::uuid,
  current_setting('t27.task_id')::uuid,
  'regular',
  60,
  now() - interval '1 minute',
  now(),
  'completed',
  now(),
  60
);

update public.focus_appointments
set session_id = current_setting('t27.session_id')::uuid
where id = current_setting('t27.appointment_id')::uuid;

insert into public.focus_nodes (
  id, user_id, session_id, task_id, mode, created_at, effective_seconds
)
values (
  current_setting('t27.node_id')::uuid,
  current_setting('t27.target_id')::uuid,
  current_setting('t27.session_id')::uuid,
  current_setting('t27.task_id')::uuid,
  'regular',
  now(),
  60
);

insert into public.focus_chain_records (
  user_id, mode, current_consecutive, best_consecutive, updated_at
)
values (current_setting('t27.target_id')::uuid, 'regular', 1, 1, now())
on conflict (user_id, mode) do update
set current_consecutive = excluded.current_consecutive,
    best_consecutive = excluded.best_consecutive,
    updated_at = excluded.updated_at;

insert into public.appointment_chain_records (
  user_id, current_consecutive, best_consecutive, updated_at
)
values (current_setting('t27.target_id')::uuid, 1, 1, now())
on conflict (user_id) do update
set current_consecutive = excluded.current_consecutive,
    best_consecutive = excluded.best_consecutive,
    updated_at = excluded.updated_at;

insert into public.focus_precedent_rules (user_id, rule_text)
values (
  current_setting('t27.target_id')::uuid,
  'purge test rule ' || current_setting('t27.precedent_rule')
);

insert into public.focus_sync_sources (
  source_id, user_id, device_id, entity_type, entity_id, occurred_at, payload
)
values (
  current_setting('t27.source_id')::uuid,
  current_setting('t27.target_id')::uuid,
  current_setting('t27.device_id')::uuid,
  'national_focus_tree',
  gen_random_uuid(),
  now(),
  '{}'::jsonb
);

insert into public.calendar_sources (
  user_id, source_id, display_name, time_zone_id
)
values (
  current_setting('t27.target_id')::uuid,
  current_setting('t27.calendar_source_id'),
  'Test',
  'UTC'
);

insert into public.calendar_blocks (
  user_id, source_id, source_event_id, occurrence_id, event_identity, title,
  starts_at, ends_at, availability, time_zone_id
)
values (
  current_setting('t27.target_id')::uuid,
  current_setting('t27.calendar_source_id'),
  current_setting('t27.calendar_event_id'),
  current_setting('t27.calendar_occurrence_id'),
  current_setting('t27.calendar_identity'),
  'Test block',
  now(),
  now() + interval '1 hour',
  'busy',
  'UTC'
);

insert into public.goals (
  id, user_id, title, classification, created_at, updated_at
)
values (
  current_setting('t27.other_goal_id')::uuid,
  current_setting('t27.other_id')::uuid,
  'other user''s retained goal',
  'regular',
  now(),
  now()
);

-- Delete business rows first, in dependency order, before the Auth Admin API
-- removes the identity. This also guards against RESTRICT foreign keys.
set local role service_role;
select public.admin_delete_user_business_data(
  current_setting('t27.target_id')::uuid
);

select set_config('request.jwt.claim.sub', current_setting('t27.target_id'), true);
reset role;
do $business_data_pending_probe$
declare
  target_id uuid := current_setting('t27.target_id')::uuid;
begin
  if public.user_purge_receipt(target_id) is not null then
    raise exception 'business_data_deletion_was_exposed_as_completed_receipt';
  end if;
  if exists (select 1 from public.goals where user_id = target_id)
     or exists (select 1 from public.tasks where user_id = target_id)
     or exists (select 1 from public.focus_sessions where user_id = target_id)
     or exists (select 1 from public.focus_nodes where user_id = target_id)
     or exists (select 1 from public.focus_chain_records where user_id = target_id)
     or exists (select 1 from public.focus_appointments where user_id = target_id)
     or exists (select 1 from public.appointment_chain_records where user_id = target_id)
     or exists (select 1 from public.focus_precedent_rules where user_id = target_id)
     or exists (select 1 from public.focus_sync_sources where user_id = target_id)
     or exists (select 1 from public.calendar_sources where user_id = target_id)
     or exists (select 1 from public.calendar_blocks where user_id = target_id) then
    raise exception 'cloud_business_data_remained_after_business_delete_rpc';
  end if;
  if not exists (select 1 from auth.users where id = target_id) then
    raise exception 'auth_identity_was_removed_before_explicit_auth_deletion';
  end if;
end
$business_data_pending_probe$;

-- Simulate the hard Auth Admin API deletion. Auth foreign keys cascade all
-- current business tables; the purge ledger intentionally has no Auth FK.
delete from auth.users
where id = current_setting('t27.target_id')::uuid;

set local role service_role;
select public.admin_complete_user_purge(
  current_setting('t27.target_id')::uuid
);

select set_config('request.jwt.claim.sub', current_setting('t27.target_id'), true);
reset role;
do $completed_purge_probe$
declare
  target_id uuid := current_setting('t27.target_id')::uuid;
  receipt jsonb;
begin
  receipt := public.user_purge_receipt(target_id);
  if receipt->>'user_id' <> target_id::text
     or receipt->>'status' <> 'completed'
     or nullif(receipt->>'purged_at', '') is null then
    raise exception 'completed_receipt_did_not_bind_to_deleted_identity';
  end if;
  if exists (select 1 from auth.users where id = target_id) then
    raise exception 'purged_auth_identity_still_exists';
  end if;
  if exists (select 1 from public.goals where user_id = target_id)
     or exists (select 1 from public.tasks where user_id = target_id)
     or exists (select 1 from public.focus_sessions where user_id = target_id)
     or exists (select 1 from public.focus_nodes where user_id = target_id)
     or exists (select 1 from public.focus_chain_records where user_id = target_id)
     or exists (select 1 from public.focus_appointments where user_id = target_id)
     or exists (select 1 from public.appointment_chain_records where user_id = target_id)
     or exists (select 1 from public.focus_precedent_rules where user_id = target_id)
     or exists (select 1 from public.focus_sync_sources where user_id = target_id)
     or exists (select 1 from public.calendar_sources where user_id = target_id)
     or exists (select 1 from public.calendar_blocks where user_id = target_id) then
    raise exception 'cloud_business_data_remained_after_auth_deletion';
  end if;
  if not exists (
    select 1 from public.goals
    where id = current_setting('t27.other_goal_id')::uuid
      and user_id = current_setting('t27.other_id')::uuid
  ) then
    raise exception 'other_user_data_was_removed';
  end if;
  if public.current_user_is_active() then
    raise exception 'purged_old_identity_was_treated_as_active';
  end if;
end
$completed_purge_probe$;

-- Only a fresh administrator grant can reuse the email, and the registration
-- trigger must create an entirely new identity with no old business rows.
set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('t27.admin_id'), true);
select public.admin_grant_registration_eligibility(
  current_setting('t27.target_email'),
  'email'
);
reset role;

do $fresh_identity_probe$
declare
  old_user_id uuid := current_setting('t27.target_id')::uuid;
  new_user_id uuid := gen_random_uuid();
  target_email text := current_setting('t27.target_email');
  consumed_user_id uuid;
begin
  if exists (
    select 1 from public.registration_eligibility
    where identifier = target_email
      and (used_at is not null or purge_completed_at is not null)
  ) then
    raise exception 'fresh_grant_did_not_reset_purged_eligibility';
  end if;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  begin
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at
    )
    values (
      '00000000-0000-0000-0000-000000000000',
      old_user_id,
      'authenticated',
      'authenticated',
      target_email,
      '',
      now(),
      now(),
      now()
    );
    raise exception 'purged_identity_recreation_was_allowed';
  exception
    when others then
      if sqlerrm <> 'purged identity cannot be recreated' then
        raise;
      end if;
  end;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    new_user_id,
    'authenticated',
    'authenticated',
    target_email,
    '',
    now(),
    now(),
    now()
  );

  if new_user_id = old_user_id then
    raise exception 'fresh_registration_reused_old_user_id';
  end if;
  select used_user_id into consumed_user_id
  from public.registration_eligibility
  where identifier = target_email and identifier_type = 'email';
  if consumed_user_id <> new_user_id then
    raise exception 'fresh_identity_did_not_consume_new_eligibility';
  end if;
  if exists (select 1 from public.goals where user_id = new_user_id) then
    raise exception 'fresh_identity_inherited_old_cloud_data';
  end if;
end
$fresh_identity_probe$;

do $privilege_probe$
begin
  if has_function_privilege(
    'authenticated',
    'public.admin_begin_user_purge(uuid, uuid)',
    'execute'
  ) then
    raise exception 'authenticated_can_begin_purge_directly';
  end if;
  if has_function_privilege(
    'anon',
    'public.admin_complete_user_purge(uuid)',
    'execute'
  ) then
    raise exception 'anon_can_complete_purge_directly';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.admin_delete_user_business_data(uuid)',
    'execute'
  ) then
    raise exception 'authenticated_can_delete_user_business_data_directly';
  end if;
  if not has_function_privilege(
    'service_role',
    'public.admin_begin_user_purge(uuid, uuid)',
    'execute'
  ) then
    raise exception 'service_role_cannot_begin_purge';
  end if;
end
$privilege_probe$;

rollback;
