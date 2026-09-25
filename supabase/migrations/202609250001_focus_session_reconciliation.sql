-- Ticket T11: persist independent configuration/outcome choices and merge
-- multiple immutable source branches into one synchronized session head.

alter table public.focus_sessions
  add column if not exists configuration_basis_source_id uuid,
  add column if not exists outcome_basis_source_id uuid;

alter table public.focus_sync_sources
  add column if not exists parent_source_ids uuid[] not null default '{}';

update public.focus_sync_sources
set parent_source_ids = array[parent_source_id]
where parent_source_id is not null
  and cardinality(parent_source_ids) = 0;
