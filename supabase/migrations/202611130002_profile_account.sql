-- Issue #94: account profile (display name and one bounded avatar binary).
--
-- The profile is account identity, not business data: it lives in its own table
-- so restoring a business snapshot can never rewind it, and it is owned by the
-- authenticated identity through RLS plus owner-scoped RPCs.
--
-- Lifecycle: profile_accounts.user_id references auth.users(id) on delete
-- cascade. Explicit account purge deletes the Auth identity, so the profile row
-- and its avatar binary are removed by the database itself. This migration
-- deliberately does not replace admin_delete_user_business_data(), because the
-- backup/history migration extends that function; the FK keeps both migrations
-- composable.

create or replace function public.profile_avatar_mime(p_bytes bytea)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when p_bytes is null or octet_length(p_bytes) < 4 then null
    when get_byte(p_bytes, 0) = 137
      and get_byte(p_bytes, 1) = 80
      and get_byte(p_bytes, 2) = 78
      and get_byte(p_bytes, 3) = 71 then 'image/png'
    when get_byte(p_bytes, 0) = 255
      and get_byte(p_bytes, 1) = 216
      and get_byte(p_bytes, 2) = 255 then 'image/jpeg'
    else null
  end;
$$;
revoke all on function public.profile_avatar_mime(bytea) from public, anon, authenticated;

create table if not exists public.profile_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  avatar_mime_type text,
  avatar_bytes bytea,
  updated_at timestamptz not null default now(),
  constraint profile_accounts_display_name_trimmed
    check (display_name = btrim(display_name)),
  -- The client limits names to 32 user-perceived characters; the server bound
  -- stays wider so multi-codepoint names are not rejected by code-unit count.
  constraint profile_accounts_display_name_length
    check (char_length(display_name) <= 128),
  constraint profile_accounts_avatar_pair
    check ((avatar_bytes is null) = (avatar_mime_type is null)),
  constraint profile_accounts_avatar_mime
    check (avatar_mime_type is null or avatar_mime_type in ('image/png', 'image/jpeg')),
  constraint profile_accounts_avatar_size
    check (avatar_bytes is null or octet_length(avatar_bytes) between 1 and 262144),
  constraint profile_accounts_avatar_signature
    check (
      avatar_bytes is null
      or public.profile_avatar_mime(avatar_bytes) = avatar_mime_type
    )
);

comment on table public.profile_accounts is
  'Account display name and one bounded avatar binary. Never part of the business snapshot; removed with the Auth identity.';

alter table public.profile_accounts enable row level security;
revoke all on table public.profile_accounts from public, anon, authenticated;

-- Defense in depth: the table grants no direct client privileges, and every
-- owned row is still bounded by these policies if a grant is ever added.
drop policy if exists "active users can read own profile" on public.profile_accounts;
create policy "active users can read own profile"
  on public.profile_accounts
  for select to authenticated
  using (user_id = auth.uid() and public.current_user_is_active());

drop policy if exists "active users can insert own profile" on public.profile_accounts;
create policy "active users can insert own profile"
  on public.profile_accounts
  for insert to authenticated
  with check (user_id = auth.uid() and public.current_user_is_active());

drop policy if exists "active users can update own profile" on public.profile_accounts;
create policy "active users can update own profile"
  on public.profile_accounts
  for update to authenticated
  using (user_id = auth.uid() and public.current_user_is_active())
  with check (user_id = auth.uid() and public.current_user_is_active());

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
  return jsonb_build_object(
    'displayName', stored.display_name,
    'avatarMimeType', stored.avatar_mime_type,
    'avatarBase64',
      case
        when stored.avatar_bytes is null then null
        else encode(stored.avatar_bytes, 'base64')
      end,
    'updatedAt', stored.updated_at
  );
end;
$$;
revoke all on function public.read_profile_account() from public, anon;
grant execute on function public.read_profile_account() to authenticated;

create or replace function public.save_profile_account(
  p_display_name text,
  p_avatar_base64 text default null,
  p_clear_avatar boolean default false
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
    user_id, display_name, avatar_mime_type, avatar_bytes, updated_at
  ) values (
    owner_id,
    name_value,
    case when keep_avatar then null else mime_value end,
    case when keep_avatar then null else avatar_value end,
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
        updated_at = excluded.updated_at
  returning * into stored;

  return jsonb_build_object(
    'displayName', stored.display_name,
    'avatarMimeType', stored.avatar_mime_type,
    'avatarBase64',
      case
        when stored.avatar_bytes is null then null
        else encode(stored.avatar_bytes, 'base64')
      end,
    'updatedAt', stored.updated_at
  );
end;
$$;
revoke all on function public.save_profile_account(text, text, boolean)
  from public, anon;
grant execute on function public.save_profile_account(text, text, boolean)
  to authenticated;
