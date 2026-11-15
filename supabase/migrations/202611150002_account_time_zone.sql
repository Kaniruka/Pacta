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
-- Resulting invariants:
--   * initialize_profile_time_zone() is atomic. It inserts an empty-nickname row
--     when none exists, or fills time_zone_id only when it is still null, and
--     always returns the stored winner, so two devices that both read "no value"
--     cannot each decide a different account zone.
--   * save_profile_account() keeps the stored time zone when no zone argument is
--     given (nickname/avatar edits never re-assert a cached zone), and ignores an
--     older request that arrives late. A blank display name is accepted only
--     when the stored name is already unset and this call carries a time zone;
--     it can never clear an existing nickname and can never create a profile.

alter table public.profile_accounts
  add column if not exists time_zone_id text;

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
end
$constraint$;

comment on column public.profile_accounts.time_zone_id is
  'Account-level IANA display time zone shared by every device. Null means not recorded yet; display falls back to Etc/UTC, never to the device zone.';
comment on column public.profile_accounts.time_zone_updated_at is
  'When the stored time zone was requested. A newer request wins; an older request that arrives late is ignored.';

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
    'timeZoneId', stored.time_zone_id
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

-- Atomic first-migration step. Creating the row with an empty display name is
-- the only place an unset nickname may exist: it is not a fabricated name, and
-- every later save of that row still has to supply a real nickname or a zone.
create or replace function public.initialize_profile_time_zone(
  p_time_zone_id text,
  p_time_zone_requested_at timestamptz
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
  if p_time_zone_requested_at is null then
    raise exception 'time zone request time is required' using errcode = '22023';
  end if;

  insert into public.profile_accounts (
    user_id,
    display_name,
    time_zone_id,
    time_zone_updated_at,
    updated_at
  ) values (
    owner_id,
    '',
    zone_value,
    p_time_zone_requested_at,
    now()
  )
  on conflict (user_id) do update
    set time_zone_id = coalesce(
          profile_accounts.time_zone_id,
          excluded.time_zone_id
        ),
        time_zone_updated_at = case
          when profile_accounts.time_zone_id is null
            then excluded.time_zone_updated_at
          else profile_accounts.time_zone_updated_at
        end,
        updated_at = case
          when profile_accounts.time_zone_id is null
            then excluded.updated_at
          else profile_accounts.updated_at
        end
  returning * into stored;

  return public.profile_account_payload(stored);
end;
$$;
revoke all on function public.initialize_profile_time_zone(text, timestamptz)
  from public, anon;
grant execute on function public.initialize_profile_time_zone(text, timestamptz)
  to authenticated;

-- Replace the three-argument save rather than adding an overload: PostgREST
-- resolves RPCs by name, and an overload would make the same call ambiguous.
drop function if exists public.save_profile_account(text, text, boolean);
drop function if exists public.save_profile_account(
  text, text, boolean, text, timestamptz
);

create or replace function public.save_profile_account(
  p_display_name text,
  p_avatar_base64 text default null,
  p_clear_avatar boolean default false,
  p_time_zone_id text default null,
  p_time_zone_requested_at timestamptz default null
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
  zone_at timestamptz;
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

  -- Lock the row so the blank-name decision and the zone ordering decision are
  -- made against the same stored values the upsert will update.
  select * into stored
  from public.profile_accounts
  where user_id = owner_id
  for update;

  if name_value = '' then
    -- An unset nickname may stay unset during a time-zone-only save. It may
    -- never clear an existing nickname, and it may never create a profile row.
    if not found then
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
    if p_time_zone_requested_at is null then
      raise exception 'time zone request time is required'
        using errcode = '22023';
    end if;
    zone_at := p_time_zone_requested_at;
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
    time_zone_updated_at,
    updated_at
  ) values (
    owner_id,
    name_value,
    case when keep_avatar then null else mime_value end,
    case when keep_avatar then null else avatar_value end,
    zone_value,
    zone_at,
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
          when excluded.time_zone_updated_at is null
            then profile_accounts.time_zone_id
          when profile_accounts.time_zone_id is null
            then excluded.time_zone_id
          when profile_accounts.time_zone_updated_at is null
            then excluded.time_zone_id
          when excluded.time_zone_updated_at >= profile_accounts.time_zone_updated_at
            then excluded.time_zone_id
          else profile_accounts.time_zone_id
        end,
        time_zone_updated_at = case
          when excluded.time_zone_updated_at is null
            then profile_accounts.time_zone_updated_at
          when profile_accounts.time_zone_id is null
            then excluded.time_zone_updated_at
          when profile_accounts.time_zone_updated_at is null
            then excluded.time_zone_updated_at
          when excluded.time_zone_updated_at >= profile_accounts.time_zone_updated_at
            then excluded.time_zone_updated_at
          else profile_accounts.time_zone_updated_at
        end,
        updated_at = excluded.updated_at
  returning * into stored;

  return public.profile_account_payload(stored);
end;
$$;
revoke all on function public.save_profile_account(
  text, text, boolean, text, timestamptz
) from public, anon;
grant execute on function public.save_profile_account(
  text, text, boolean, text, timestamptz
) to authenticated;
