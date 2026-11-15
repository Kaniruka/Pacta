-- Trip ticket 02: account-level display time zone on the existing account
-- profile channel.
--
-- The time zone belongs to the account, not to a device: every device reads the
-- one stored value, and it travels with the profile row that is already excluded
-- from the business snapshot. This migration adds no device branch, no second
-- business snapshot table and no nickname: an account with no nickname yet may
-- still hold a time zone, and the row keeps an empty display_name instead of a
-- fabricated name.
--
-- Ordering contract (replaces any client wall-clock comparison):
--   * time_zone_revision is owned by this table. Every accepted time-zone write
--     increments it by one; no client may set or rewind it.
--   * A client that explicitly changes the zone sends the revision its choice is
--     based on. The write applies only while the stored revision still matches.
--   * A request based on a superseded revision never overwrites the newer value:
--     the stored winner and its revision are returned with
--     "timeZoneConflict": true, and the client adopts them. A later explicit
--     edit therefore uses the current revision and does not need to wait for any
--     timestamp, so a device with a fast clock cannot lock the account for a day.
--   * time_zone_updated_at records when the current value was accepted, using
--     the server clock (now()). It is audit information, never an ordering key.
--
-- Other invariants:
--   * initialize_profile_time_zone() fills only a still-empty account value and
--     is atomic, so two devices that both read "no value" cannot each decide a
--     different account zone.
--   * Both RPCs serialize first writes on the account identity with a
--     transaction-scoped advisory lock. A missing row cannot be locked with
--     SELECT ... FOR UPDATE, so without this lock two first writers could both
--     read "absent", and the later upsert would apply a stale decision over the
--     row the other writer just inserted. It inserts an empty-nickname row when none exists;
--     that is an unset nickname, not a fabricated name.
--   * save_profile_account() keeps the stored time zone when no zone argument is
--     given (nickname/avatar edits never re-assert a cached zone). A blank
--     display name is accepted only when the stored name is already unset and
--     this call carries a time zone; it can never clear an existing nickname and
--     can never create a profile. The legacy three-argument form remains valid
--     and never touches the stored zone or its revision.
--   * Both RPCs validate the value against the server's IANA catalog
--     (pg_timezone_names), not just its length.

alter table public.profile_accounts
  add column if not exists time_zone_id text;

alter table public.profile_accounts
  add column if not exists time_zone_revision bigint not null default 0;

alter table public.profile_accounts
  add column if not exists time_zone_updated_at timestamptz;

do $constraint$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profile_accounts_time_zone_shape'
      and conrelid = 'public.profile_accounts'::regclass
  ) then
    alter table public.profile_accounts
      add constraint profile_accounts_time_zone_shape
      check (
        time_zone_id is null
        or (
          char_length(time_zone_id) between 1 and 64
          and time_zone_id = btrim(time_zone_id)
        )
      );
  end if;
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profile_accounts_time_zone_revision_nonnegative'
      and conrelid = 'public.profile_accounts'::regclass
  ) then
    alter table public.profile_accounts
      add constraint profile_accounts_time_zone_revision_nonnegative
      check (time_zone_revision >= 0);
  end if;
end
$constraint$;

comment on column public.profile_accounts.time_zone_id is
  'Account-level IANA display time zone shared by every device. Null means not recorded yet; display falls back to Etc/UTC, never to the device zone.';
comment on column public.profile_accounts.time_zone_revision is
  'Server-owned revision of time_zone_id. A write applies only when the caller names the current revision; stale callers adopt the stored winner.';
comment on column public.profile_accounts.time_zone_updated_at is
  'When the current account time zone was accepted, in server time. Audit information only; ordering uses time_zone_revision.';

-- Server-side IANA membership. Length alone would accept "not/a-zone" and lock
-- a valid client out of its own account value.
create or replace function public.profile_time_zone_is_known(p_time_zone_id text)
returns boolean
language sql
stable
set search_path = public, pg_catalog
as $$
  select exists (
    select 1
    from pg_timezone_names
    where name = p_time_zone_id
  );
$$;
revoke all on function public.profile_time_zone_is_known(text)
  from public, anon, authenticated;

-- One payload shape for reads, saves and initialization.
create or replace function public.profile_account_payload(
  stored public.profile_accounts
)
returns jsonb
language sql
stable
set search_path = public, pg_catalog
as $$
  select jsonb_build_object(
    'displayName', stored.display_name,
    'avatarMimeType', stored.avatar_mime_type,
    'avatarBase64',
      case
        when stored.avatar_bytes is null then null
        else encode(stored.avatar_bytes, 'base64')
      end,
    'updatedAt', stored.updated_at,
    'timeZoneId', stored.time_zone_id,
    'timeZoneRevision', stored.time_zone_revision
  );
$$;
revoke all on function public.profile_account_payload(public.profile_accounts)
  from public, anon, authenticated;

create or replace function public.read_profile_account()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  owner_id uuid := auth.uid();
  stored public.profile_accounts;
begin
  if owner_id is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;
  if not public.current_user_is_active() then
    raise exception 'inactive user cannot read profile' using errcode = '42501';
  end if;
  select * into stored from public.profile_accounts where user_id = owner_id;
  if not found then
    return null;
  end if;
  return public.profile_account_payload(stored);
end;
$$;
revoke all on function public.read_profile_account() from public, anon;
grant execute on function public.read_profile_account() to authenticated;

-- The earlier draft took a client request time. Drop that signature instead of
-- leaving it next to the revision-based one, so the RPC name stays unambiguous.
drop function if exists public.initialize_profile_time_zone(text, timestamptz);

-- Atomic first-migration step. Creating the row with an empty display name is
-- the only place an unset nickname may exist: it is not a fabricated name, and
-- every later save of that row still has to supply a real nickname or a zone.
-- Only a still-null value is filled; an accepted value and its revision stay.
create or replace function public.initialize_profile_time_zone(
  p_time_zone_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  owner_id uuid := auth.uid();
  zone_value text := btrim(coalesce(p_time_zone_id, ''));
  stored public.profile_accounts;
begin
  if owner_id is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;
  if not public.current_user_is_active() then
    raise exception 'inactive user cannot initialize time zone'
      using errcode = '42501';
  end if;
  if char_length(zone_value) = 0 or char_length(zone_value) > 64 then
    raise exception 'time zone is required' using errcode = '22023';
  end if;
  if not public.profile_time_zone_is_known(zone_value) then
    raise exception 'time zone is not a known IANA identifier'
      using errcode = '22023';
  end if;

  -- Account-scoped transaction lock: serialize this first write with any other
  -- initialize/save for the same owner. The profile row may not exist yet, and
  -- a lock on a nonexistent row locks nothing; the lock key is the account.
  perform pg_advisory_xact_lock(
    hashtextextended('pacta.profile_accounts:' || owner_id::text, 0)
  );

  insert into public.profile_accounts (
    user_id,
    display_name,
    time_zone_id,
    time_zone_revision,
    time_zone_updated_at,
    updated_at
  ) values (
    owner_id,
    '',
    zone_value,
    1,
    now(),
    now()
  )
  on conflict (user_id) do update
    set time_zone_id = coalesce(
          profile_accounts.time_zone_id,
          excluded.time_zone_id
        ),
        time_zone_revision = case
          when profile_accounts.time_zone_id is null
            then profile_accounts.time_zone_revision + 1
          else profile_accounts.time_zone_revision
        end,
        time_zone_updated_at = case
          when profile_accounts.time_zone_id is null
            then now()
          else profile_accounts.time_zone_updated_at
        end,
        updated_at = case
          when profile_accounts.time_zone_id is null
            then now()
          else profile_accounts.updated_at
        end
  returning * into stored;

  return public.profile_account_payload(stored);
end;
$$;
revoke all on function public.initialize_profile_time_zone(text)
  from public, anon;
grant execute on function public.initialize_profile_time_zone(text)
  to authenticated;

-- Replace every earlier save signature rather than adding an overload:
-- PostgREST resolves RPCs by name, and an overload would make the same call
-- ambiguous. Defaults keep the legacy three-argument nickname/avatar call
-- working; that call passes no zone and therefore leaves the account zone and
-- its revision untouched.
drop function if exists public.save_profile_account(text, text, boolean);
drop function if exists public.save_profile_account(
  text, text, boolean, text, timestamptz
);

create or replace function public.save_profile_account(
  p_display_name text,
  p_avatar_base64 text default null,
  p_clear_avatar boolean default false,
  p_time_zone_id text default null,
  p_time_zone_revision bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  owner_id uuid := auth.uid();
  name_value text := btrim(coalesce(p_display_name, ''));
  keep_avatar boolean :=
    not coalesce(p_clear_avatar, false)
    and (p_avatar_base64 is null or btrim(p_avatar_base64) = '');
  zone_value text;
  zone_applied boolean := false;
  row_exists boolean;
  stored public.profile_accounts;
  avatar_value bytea;
  mime_value text;
begin
  if owner_id is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;
  if not public.current_user_is_active() then
    raise exception 'inactive user cannot save profile' using errcode = '42501';
  end if;
  if char_length(name_value) > 128 then
    raise exception 'display name is too long' using errcode = '22001';
  end if;

  -- Serialize this save with any first write for the same owner before deciding
  -- anything. The row lock below only protects an existing row; a concurrent
  -- initialize or first save could otherwise insert between this check and the
  -- upsert, and a precomputed "absent" decision would overwrite that winner.
  perform pg_advisory_xact_lock(
    hashtextextended('pacta.profile_accounts:' || owner_id::text, 0)
  );

  -- Lock the row so the blank-name decision and the revision comparison are
  -- made against the same stored values the upsert will update.
  select * into stored
  from public.profile_accounts
  where user_id = owner_id
  for update;
  row_exists := found;

  if name_value = '' then
    -- An unset nickname may stay unset during a time-zone-only save. It may
    -- never clear an existing nickname, and it may never create a profile row.
    if not row_exists then
      raise exception 'display name is required to create a profile'
        using errcode = '22023';
    end if;
    if stored.display_name <> '' then
      raise exception 'display name cannot be cleared' using errcode = '22023';
    end if;
    if p_time_zone_id is null then
      raise exception 'display name is required' using errcode = '22023';
    end if;
    name_value := stored.display_name;
  end if;

  if p_time_zone_id is not null then
    zone_value := btrim(p_time_zone_id);
    if char_length(zone_value) = 0 or char_length(zone_value) > 64 then
      raise exception 'time zone is invalid' using errcode = '22023';
    end if;
    if not public.profile_time_zone_is_known(zone_value) then
      raise exception 'time zone is not a known IANA identifier'
        using errcode = '22023';
    end if;
    if p_time_zone_revision is null or p_time_zone_revision < 0 then
      raise exception 'time zone revision is required' using errcode = '22023';
    end if;
    -- The one accepted ordering rule: a request may replace the stored value
    -- only while the revision it names is still current. A first value on an
    -- account that has none is always accepted, whatever revision is named.
    -- Branches stay explicit: reading a field of an unassigned record would
    -- depend on expression evaluation order.
    if not row_exists then
      zone_applied := true;
    elsif stored.time_zone_id is null then
      zone_applied := true;
    else
      zone_applied := stored.time_zone_revision = p_time_zone_revision;
    end if;
  end if;

  if keep_avatar then
    -- The stored binary is kept by the atomic upsert below, never by a prior
    -- read: a concurrent clear or avatar change cannot be resurrected by a
    -- display-name-only save.
    avatar_value := null;
    mime_value := null;
  elsif coalesce(p_clear_avatar, false) then
    avatar_value := null;
    mime_value := null;
  else
    begin
      avatar_value := decode(p_avatar_base64, 'base64');
    exception
      when others then
        raise exception 'avatar is not valid base64' using errcode = '22023';
    end;
    if octet_length(avatar_value) > 262144 then
      raise exception 'avatar is limited to 256 KB' using errcode = '22001';
    end if;
    mime_value := public.profile_avatar_mime(avatar_value);
    if mime_value is null then
      raise exception 'avatar must be a PNG or JPEG image'
        using errcode = '22023';
    end if;
  end if;

  insert into public.profile_accounts (
    user_id,
    display_name,
    avatar_mime_type,
    avatar_bytes,
    time_zone_id,
    time_zone_revision,
    time_zone_updated_at,
    updated_at
  ) values (
    owner_id,
    name_value,
    case when keep_avatar then null else mime_value end,
    case when keep_avatar then null else avatar_value end,
    zone_value,
    case when zone_applied then 1 else 0 end,
    case when zone_applied then now() else null end,
    now()
  )
  on conflict (user_id) do update
    set display_name = excluded.display_name,
        avatar_mime_type = case
          when keep_avatar then profile_accounts.avatar_mime_type
          else excluded.avatar_mime_type
        end,
        avatar_bytes = case
          when keep_avatar then profile_accounts.avatar_bytes
          else excluded.avatar_bytes
        end,
        time_zone_id = case
          when zone_applied then excluded.time_zone_id
          else profile_accounts.time_zone_id
        end,
        time_zone_revision = case
          when zone_applied then profile_accounts.time_zone_revision + 1
          else profile_accounts.time_zone_revision
        end,
        time_zone_updated_at = case
          when zone_applied then now()
          else profile_accounts.time_zone_updated_at
        end,
        updated_at = now()
  returning * into stored;

  return public.profile_account_payload(stored)
    || jsonb_build_object(
      'timeZoneConflict',
      p_time_zone_id is not null and not zone_applied
    );
end;
$$;
revoke all on function public.save_profile_account(
  text, text, boolean, text, bigint
) from public, anon;
grant execute on function public.save_profile_account(
  text, text, boolean, text, bigint
) to authenticated;
