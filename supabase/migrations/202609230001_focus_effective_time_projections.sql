-- Ticket T08: preserve active intervals for timezone-aware activity queries and
-- the record disposition used by later focus-record reconciliation.

alter table public.focus_sessions
  add column if not exists effective_intervals jsonb not null default '[]'::jsonb,
  add column if not exists review_disposition text not null default 'accepted',
  add column if not exists review_disposition_updated_at timestamptz;

alter table public.focus_sessions
  drop constraint if exists focus_sessions_effective_intervals_array_check,
  drop constraint if exists focus_sessions_review_disposition_check;

alter table public.focus_sessions
  add constraint focus_sessions_effective_intervals_array_check
    check (jsonb_typeof(effective_intervals) = 'array'),
  add constraint focus_sessions_review_disposition_check
    check (review_disposition in ('accepted', 'pending_review', 'duplicate'));
