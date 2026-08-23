create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length
    check (display_name is null or char_length(display_name) between 1 and 120)
);

alter table public.profiles enable row level security;

revoke all on table public.profiles from anon, authenticated;
grant select, update on table public.profiles to authenticated;

create policy "Users can read their own profile"
  on public.profiles
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can update their own profile"
  on public.profiles
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (
    new.id,
    nullif(trim(new.raw_user_meta_data ->> 'display_name'), '')
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke all on function public.create_profile_for_new_user() from public;

create trigger create_profile_after_signup
  after insert on auth.users
  for each row execute function public.create_profile_for_new_user();

insert into public.profiles (user_id, display_name)
select
  id,
  nullif(trim(raw_user_meta_data ->> 'display_name'), '')
from auth.users
on conflict (user_id) do nothing;
