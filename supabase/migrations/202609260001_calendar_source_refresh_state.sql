-- Ticket T21: synchronize source freshness across devices.
alter table public.calendar_sources
  add column if not exists is_stale boolean not null default false;
