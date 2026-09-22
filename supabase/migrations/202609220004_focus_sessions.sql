-- Ticket T03: durable focus sessions, generated nodes, chain records, and
-- effective time contributed to the owning task.

alter table public.tasks
  add column if not exists focus_progress_seconds integer not null default 0;

create table if not exists public.focus_sessions (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  task_id uuid not null,
  mode text not null check (mode in ('elite', 'regular')),
  duration_seconds integer not null check (duration_seconds > 0),
  started_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null check (status in ('active', 'completed')),
  completed_at timestamptz,
  effective_seconds integer not null default 0 check (effective_seconds >= 0),
  unique (id, user_id),
  constraint focus_sessions_task_same_user_fk
    foreign key (task_id, user_id) references public.tasks(id, user_id)
    on delete restrict
);

create table if not exists public.focus_nodes (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  session_id uuid not null,
  task_id uuid not null,
  mode text not null check (mode in ('elite', 'regular')),
  created_at timestamptz not null,
  effective_seconds integer not null check (effective_seconds > 0),
  unique (id, user_id),
  constraint focus_nodes_session_same_user_fk
    foreign key (session_id, user_id) references public.focus_sessions(id, user_id)
    on delete cascade,
  constraint focus_nodes_task_same_user_fk
    foreign key (task_id, user_id) references public.tasks(id, user_id)
    on delete restrict
);

create table if not exists public.focus_chain_records (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  mode text not null check (mode in ('elite', 'regular')),
  current_consecutive integer not null default 0 check (current_consecutive >= 0),
  best_consecutive integer not null default 0 check (best_consecutive >= 0),
  updated_at timestamptz not null,
  primary key (user_id, mode)
);

alter table public.tasks enable row level security;
alter table public.focus_sessions enable row level security;
alter table public.focus_nodes enable row level security;
alter table public.focus_chain_records enable row level security;

drop policy if exists "users can manage focus sessions" on public.focus_sessions;
create policy "users can manage focus sessions" on public.focus_sessions
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users can manage focus nodes" on public.focus_nodes;
create policy "users can manage focus nodes" on public.focus_nodes
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users can manage focus chain records" on public.focus_chain_records;
create policy "users can manage focus chain records" on public.focus_chain_records
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create index if not exists focus_sessions_user_started_at_idx
  on public.focus_sessions(user_id, started_at desc);
create index if not exists focus_nodes_user_created_at_idx
  on public.focus_nodes(user_id, created_at desc);
