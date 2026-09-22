-- Ticket T04: pause-aware failed Focus Session outcomes, failure reasons, and
-- editable notes for generated Focus Nodes.

alter table public.focus_sessions
  add column if not exists paused_at timestamptz,
  add column if not exists paused_seconds integer not null default 0,
  add column if not exists pause_rule_text text,
  add column if not exists failure_reason text;

alter table public.focus_sessions
  drop constraint if exists focus_sessions_status_check;

alter table public.focus_sessions
  add constraint focus_sessions_status_check
  check (status in ('active', 'paused', 'completed', 'failed'));

alter table public.focus_sessions
  add constraint focus_sessions_pause_seconds_check
  check (paused_seconds >= 0),
  add constraint focus_sessions_pause_rule_check
  check (status <> 'paused' or length(trim(pause_rule_text)) > 0),
  add constraint focus_sessions_failure_reason_check
  check (status <> 'failed' or length(trim(failure_reason)) > 0);

alter table public.focus_nodes
  add column if not exists note text;

alter table public.focus_sessions enable row level security;
alter table public.focus_nodes enable row level security;
