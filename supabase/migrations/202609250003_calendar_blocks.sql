-- Ticket T20: user-owned, read-only Calendar Blocks imported from Android.

create table if not exists public.calendar_sources (
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  source_id text not null check (btrim(source_id) <> ''),
  display_name text not null check (btrim(display_name) <> ''),
  time_zone_id text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, source_id)
);

create table if not exists public.calendar_blocks (
  user_id uuid not null default auth.uid(),
  source_id text not null,
  source_event_id text not null,
  occurrence_id text not null,
  event_identity text not null,
  title text not null check (btrim(title) <> ''),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  is_all_day boolean not null default false,
  all_day_start_date date,
  all_day_end_date_exclusive date,
  availability text not null check (
    availability in ('busy', 'free', 'tentative', 'unknown')
  ),
  time_zone_id text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, source_id, occurrence_id),
  constraint calendar_blocks_source_same_user_fk
    foreign key (user_id, source_id)
    references public.calendar_sources(user_id, source_id) on delete cascade,
  constraint calendar_blocks_valid_interval
    check (ends_at > starts_at),
  constraint calendar_blocks_all_day_dates
    check (
      (is_all_day and all_day_start_date is not null
        and all_day_end_date_exclusive > all_day_start_date)
      or
      (not is_all_day and all_day_start_date is null
        and all_day_end_date_exclusive is null)
    )
);

alter table public.calendar_sources enable row level security;
alter table public.calendar_blocks enable row level security;

drop policy if exists "users can manage their calendar sources"
  on public.calendar_sources;
create policy "users can manage their calendar sources"
  on public.calendar_sources
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users can manage their calendar blocks"
  on public.calendar_blocks;
create policy "users can manage their calendar blocks"
  on public.calendar_blocks
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create index if not exists calendar_blocks_user_start_idx
  on public.calendar_blocks(user_id, starts_at);
create index if not exists calendar_blocks_user_identity_idx
  on public.calendar_blocks(user_id, event_identity);

comment on table public.calendar_blocks is
  'Read-only planning snapshots. Titles and time fields only; descriptions, attendees, and locations are never stored.';
