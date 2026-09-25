-- Ticket T18: include immutable National Focus operation snapshots in the
-- existing per-user synchronization source boundary.

alter table public.focus_sync_sources
  drop constraint if exists focus_sync_sources_entity_type_check;

alter table public.focus_sync_sources
  add constraint focus_sync_sources_entity_type_check
  check (
    entity_type in (
      'focus_session',
      'focus_appointment',
      'national_focus_tree'
    )
  );

comment on column public.focus_sync_sources.payload is
  'Immutable, user-owned operation snapshot. National Focus tree sources retain cards, placement, library/deletion state, requirement versions, confirmations, failure snapshots, and statistics.';
