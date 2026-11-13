-- Rollback-only profile RLS, validation, and lifecycle checks for Issue #94.
-- Run against an isolated Supabase project after applying
-- 202611130002_profile_account.sql. Requires one administrator and one
-- non-administrator signed-in user. Every change, including the temporary
-- grant below, is rolled back; non-probe identities are never touched.
begin;

do $setup$
declare
  owner_id uuid;
  other_id uuid;
begin
  select id into owner_id
  from auth.users
  order by created_at
  limit 1;
  if owner_id is null then
    raise exception 'an isolated signed-in user is required';
  end if;
  select id into other_id
  from auth.users
  where id <> owner_id
  order by created_at desc
  limit 1;
  if other_id is null then
    other_id := gen_random_uuid();
  end if;
  delete from public.profile_accounts
  where user_id in (owner_id, other_id);
  perform set_config('profile_test.owner_id', owner_id::text, true);
  perform set_config('profile_test.other_id', other_id::text, true);
end
$setup$;

set local role authenticated;

do $owner_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('profile_test.owner_id'),
    true
  );
end
$owner_claim$;

-- An empty account reads as absent instead of inventing a name.
do $empty_read$
begin
  if public.read_profile_account() is not null then
    raise exception 'absent_profile_was_not_null';
  end if;
end
$empty_read$;

-- A bounded PNG avatar and a trimmed display name round-trip through base64.
do $save_round_trip$
declare
  saved jsonb;
begin
  saved := public.save_profile_account(
    '  小林  ',
    encode(
      decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
        'base64'
      ),
      'base64'
    ),
    false
  );
  if saved ->> 'displayName' <> '小林' then
    raise exception 'display_name_was_not_trimmed';
  end if;
  if saved ->> 'avatarMimeType' <> 'image/png' then
    raise exception 'avatar_mime_was_not_detected';
  end if;
  if saved ->> 'avatarBase64' is null then
    raise exception 'avatar_binary_was_not_stored';
  end if;
  if octet_length(decode(saved ->> 'avatarBase64', 'base64')) > 262144 then
    raise exception 'avatar_exceeded_size_limit';
  end if;
end
$save_round_trip$;

-- Saving without an avatar argument keeps the stored binary.
do $keep_avatar$
declare
  saved jsonb;
begin
  saved := public.save_profile_account('新名字', null, false);
  if saved ->> 'avatarBase64' is null then
    raise exception 'avatar_was_cleared_without_request';
  end if;
end
$keep_avatar$;

-- Explicit clear removes the binary and the mime type together.
do $clear_avatar$
declare
  saved jsonb;
begin
  saved := public.save_profile_account('新名字', null, true);
  if saved ->> 'avatarBase64' is not null
    or saved ->> 'avatarMimeType' is not null then
    raise exception 'avatar_was_not_cleared';
  end if;
end
$clear_avatar$;

-- A display-name-only save after a clear must not resurrect the old binary.
-- The keep semantics come from one atomic upsert, so a concurrent clear or
-- avatar change cannot be undone by a nickname update.
do $keep_after_clear$
declare
  saved jsonb;
begin
  saved := public.save_profile_account('清除后改名', null, false);
  if saved ->> 'avatarBase64' is not null
    or saved ->> 'avatarMimeType' is not null then
    raise exception 'kept_avatar_resurrected_after_clear';
  end if;
end
$keep_after_clear$;

-- Non-image and oversized binaries are rejected before any write.
do $reject_invalid_avatars$
begin
  begin
    perform public.save_profile_account(
      'x', encode('not an image'::bytea, 'base64'), false
    );
    raise exception 'non_image_avatar_was_accepted';
  exception
    when sqlstate '22023' then null;
  end;
  begin
    perform public.save_profile_account(
      'x',
      encode(decode(repeat('ff', 300000), 'hex'), 'base64'),
      false
    );
    raise exception 'oversized_avatar_was_accepted';
  exception
    when sqlstate '22001' then null;
  end;
  begin
    perform public.save_profile_account(repeat('名', 200), null, false);
    raise exception 'overlong_display_name_was_accepted';
  exception
    when sqlstate '22001' then null;
  end;
end
$reject_invalid_avatars$;

-- The table itself grants no direct client read, even for the owner.
do $no_direct_table_access$
begin
  begin
    perform count(*) from public.profile_accounts;
    raise exception 'direct_profile_table_read_was_allowed';
  exception
    when insufficient_privilege then null;
  end;
end
$no_direct_table_access$;

-- Another signed-in user cannot read or overwrite the owner's profile.
do $other_claim$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('profile_test.other_id'),
    true
  );
end
$other_claim$;

do $cross_user_isolation$
declare
  saved jsonb;
begin
  if public.read_profile_account() is not null then
    raise exception 'cross_user_profile_read_leak';
  end if;
  saved := public.save_profile_account('其他用户', null, false);
  if saved ->> 'displayName' <> '其他用户' then
    raise exception 'other_user_profile_was_not_scoped';
  end if;
end
$cross_user_isolation$;

-- The owner's stored profile survives another user's write.
do $owner_claim_again$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('profile_test.owner_id'),
    true
  );
end
$owner_claim_again$;

do $owner_profile_intact$
begin
  if public.read_profile_account() ->> 'displayName' <> '清除后改名' then
    raise exception 'owner_profile_was_overwritten_by_other_user';
  end if;
end
$owner_profile_intact$;

-- Owner-only RLS policies hold if a direct read grant is ever added.
reset role;
grant select on table public.profile_accounts to authenticated;
set local role authenticated;

do $owner_claim_for_rls$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('profile_test.owner_id'),
    true
  );
end
$owner_claim_for_rls$;

do $owner_visibility$
begin
  if not exists (
    select 1 from public.profile_accounts
    where user_id = current_setting('profile_test.owner_id')::uuid
  ) then
    raise exception 'owner_row_was_hidden_by_rls';
  end if;
  if exists (
    select 1 from public.profile_accounts
    where user_id <> current_setting('profile_test.owner_id')::uuid
  ) then
    raise exception 'rls_exposed_another_users_profile';
  end if;
end
$owner_visibility$;

do $other_claim_for_rls$
begin
  perform set_config(
    'request.jwt.claim.sub',
    current_setting('profile_test.other_id'),
    true
  );
end
$other_claim_for_rls$;

do $other_visibility$
begin
  if exists (
    select 1 from public.profile_accounts
    where user_id = current_setting('profile_test.owner_id')::uuid
  ) then
    raise exception 'rls_exposed_owner_profile_to_other_user';
  end if;
end
$other_visibility$;

reset role;
revoke select on table public.profile_accounts from authenticated;

-- Lifecycle removal is delegated to the Auth identity: the profile row and its
-- avatar binary must cascade when that identity is deleted. This checks the
-- wiring only; no probe identity or runtime test identity is deleted here.
do $identity_cascade$
begin
  if not exists (
    select 1
    from pg_constraint as constraint_row
    join pg_class as table_row on table_row.oid = constraint_row.conrelid
    join pg_namespace as schema_row on schema_row.oid = table_row.relnamespace
    where schema_row.nspname = 'public'
      and table_row.relname = 'profile_accounts'
      and constraint_row.contype = 'f'
      and constraint_row.confdeltype = 'c'
  ) then
    raise exception 'profile_accounts_does_not_cascade_from_auth_identity';
  end if;
end
$identity_cascade$;

rollback;
