-- Ticket T02: user-owned Goals and Tasks with ordinary metadata sync.

create table if not exists public.goals (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null check (btrim(title) <> ''),
  classification text not null check (classification in ('elite', 'regular', 'both')),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  unique (id, user_id)
);

create table if not exists public.tasks (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  goal_id uuid not null,
  title text not null check (btrim(title) <> ''),
  classification text not null check (classification in ('elite', 'regular', 'both')),
  estimated_minutes integer check (estimated_minutes is null or estimated_minutes > 0),
  deadline timestamptz,
  is_complete boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  unique (id, user_id),
  constraint tasks_goal_same_user_fk
    foreign key (goal_id, user_id) references public.goals(id, user_id)
    on delete cascade
);

alter table public.goals enable row level security;
alter table public.tasks enable row level security;

drop policy if exists "users can manage their goals" on public.goals;
create policy "users can manage their goals" on public.goals
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users can manage their tasks" on public.tasks;
create policy "users can manage their tasks" on public.tasks
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create index if not exists goals_user_updated_at_idx
  on public.goals(user_id, updated_at);
create index if not exists tasks_user_goal_updated_at_idx
  on public.tasks(user_id, goal_id, updated_at);
