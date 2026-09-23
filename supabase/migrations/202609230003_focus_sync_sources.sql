-- Ticket T10: retain immutable, idempotent source snapshots across devices.

create table if not exists public.focus_sync_sources (
  source_id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  device_id uuid not null,
  entity_type text not null
    check (entity_type in ('focus_session', 'focus_appointment')),
  entity_id uuid not null,
  parent_source_id uuid,
  occurred_at timestamptz not null,
  payload jsonb not null,
  unique (source_id, user_id)
);

alter table public.focus_sync_sources enable row level security;

drop policy if exists "users can read focus sync sources"
  on public.focus_sync_sources;
create policy "users can read focus sync sources"
  on public.focus_sync_sources
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "users can add focus sync sources"
  on public.focus_sync_sources;
create policy "users can add focus sync sources"
  on public.focus_sync_sources
  for insert to authenticated
  with check (user_id = auth.uid());

create index if not exists focus_sync_sources_entity_idx
  on public.focus_sync_sources(user_id, entity_type, entity_id, occurred_at);
