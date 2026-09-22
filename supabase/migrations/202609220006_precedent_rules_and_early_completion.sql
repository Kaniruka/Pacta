-- Ticket T05: centrally managed Precedent Rules and exception-approved early
-- completion of a Focus Session.

alter table public.focus_sessions
  add column if not exists completion_type text not null default 'countdown',
  add column if not exists completion_rule_text text;

alter table public.focus_sessions
  drop constraint if exists focus_sessions_completion_type_check,
  drop constraint if exists focus_sessions_completion_rule_check;

alter table public.focus_sessions
  add constraint focus_sessions_completion_type_check
    check (completion_type in ('countdown', 'precedent_rule')),
  add constraint focus_sessions_completion_rule_check
    check (
      (completion_type = 'countdown' and completion_rule_text is null)
      or (
        completion_type = 'precedent_rule'
        and status = 'completed'
        and length(trim(completion_rule_text)) between 1 and 500
      )
    );

create table if not exists public.focus_precedent_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  rule_text text not null check (length(trim(rule_text)) between 1 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (id, user_id)
);

alter table public.focus_precedent_rules enable row level security;

drop policy if exists "users can manage precedent rules" on public.focus_precedent_rules;
create policy "users can manage precedent rules" on public.focus_precedent_rules
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create index if not exists focus_precedent_rules_user_updated_at_idx
  on public.focus_precedent_rules(user_id, updated_at desc);
