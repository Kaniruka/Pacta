create table public.goals (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  mutation_id text not null,
  primary key (id, user_id),
  constraint goals_title_length check (char_length(trim(title)) between 1 and 240),
  constraint goals_notes_length check (notes is null or char_length(notes) <= 4000),
  constraint goals_mutation_id_length check (char_length(mutation_id) between 1 and 200)
);

create table public.tasks (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  goal_id uuid not null,
  title text not null,
  notes text,
  deadline timestamptz,
  estimated_seconds integer,
  classification text not null,
  focus_progress_seconds integer not null default 0,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  mutation_id text not null,
  primary key (id, user_id),
  constraint tasks_goal_owner_fk
    foreign key (goal_id, user_id)
    references public.goals (id, user_id)
    on delete cascade,
  constraint tasks_title_length check (char_length(trim(title)) between 1 and 240),
  constraint tasks_notes_length check (notes is null or char_length(notes) <= 4000),
  constraint tasks_estimate_positive check (estimated_seconds is null or estimated_seconds > 0),
  constraint tasks_progress_non_negative check (focus_progress_seconds >= 0),
  constraint tasks_classification check (classification in ('elite', 'regular', 'both')),
  constraint tasks_mutation_id_length check (char_length(mutation_id) between 1 and 200)
);

create index goals_user_updated_idx on public.goals (user_id, updated_at);
create index tasks_user_goal_idx on public.tasks (user_id, goal_id);
create index tasks_user_deadline_idx on public.tasks (user_id, deadline);

alter table public.goals enable row level security;
alter table public.tasks enable row level security;

revoke all on table public.goals, public.tasks from anon, authenticated;
grant select, insert, update on table public.goals, public.tasks to authenticated;

create policy "Users can read their own goals"
  on public.goals
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can create their own goals"
  on public.goals
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update their own goals"
  on public.goals
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users can read their own tasks"
  on public.tasks
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can create their own tasks"
  on public.tasks
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update their own tasks"
  on public.tasks
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create or replace function public.sync_goal_tasks(
  p_user_id uuid,
  p_mutations jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  mutation jsonb;
  payload jsonb;
  accepted jsonb := '[]'::jsonb;
  goals_snapshot jsonb;
  tasks_snapshot jsonb;
  entity_type text;
  entity_id uuid;
  mutation_id text;
  updated_at timestamptz;
begin
  if p_user_id is distinct from (select auth.uid()) then
    raise exception 'The requested User does not match the authenticated User';
  end if;

  -- Goals are applied first so a Task can never arrive before its Goal.
  for mutation in
    select value from jsonb_array_elements(coalesce(p_mutations, '[]'::jsonb))
    where value ->> 'entity_type' = 'goal'
  loop
    payload := mutation -> 'payload';
    entity_id := (payload ->> 'id')::uuid;
    mutation_id := mutation ->> 'mutation_id';
    updated_at := (mutation ->> 'updated_at')::timestamptz;
    insert into public.goals (
      id, user_id, title, notes, created_at, updated_at, mutation_id
    ) values (
      entity_id,
      p_user_id,
      payload ->> 'title',
      payload ->> 'notes',
      (payload ->> 'created_at')::timestamptz,
      updated_at,
      mutation_id
    )
    on conflict (id, user_id) do update set
      title = excluded.title,
      notes = excluded.notes,
      created_at = excluded.created_at,
      updated_at = excluded.updated_at,
      mutation_id = excluded.mutation_id
    where (excluded.updated_at, excluded.mutation_id)
      > (goals.updated_at, goals.mutation_id);
    accepted := accepted || jsonb_build_array(mutation_id);
  end loop;

  for mutation in
    select value from jsonb_array_elements(coalesce(p_mutations, '[]'::jsonb))
    where value ->> 'entity_type' = 'task'
  loop
    payload := mutation -> 'payload';
    entity_id := (payload ->> 'id')::uuid;
    mutation_id := mutation ->> 'mutation_id';
    updated_at := (mutation ->> 'updated_at')::timestamptz;
    insert into public.tasks (
      id, user_id, goal_id, title, notes, deadline, estimated_seconds,
      classification, focus_progress_seconds, completed_at, created_at,
      updated_at, mutation_id
    ) values (
      entity_id,
      p_user_id,
      (payload ->> 'goal_id')::uuid,
      payload ->> 'title',
      payload ->> 'notes',
      nullif(payload ->> 'deadline', '')::timestamptz,
      (payload ->> 'estimated_seconds')::integer,
      payload ->> 'classification',
      coalesce((payload ->> 'focus_progress_seconds')::integer, 0),
      nullif(payload ->> 'completed_at', '')::timestamptz,
      (payload ->> 'created_at')::timestamptz,
      updated_at,
      mutation_id
    )
    on conflict (id, user_id) do update set
      goal_id = excluded.goal_id,
      title = excluded.title,
      notes = excluded.notes,
      deadline = excluded.deadline,
      estimated_seconds = excluded.estimated_seconds,
      classification = excluded.classification,
      focus_progress_seconds = excluded.focus_progress_seconds,
      completed_at = excluded.completed_at,
      created_at = excluded.created_at,
      updated_at = excluded.updated_at,
      mutation_id = excluded.mutation_id
    where (excluded.updated_at, excluded.mutation_id)
      > (tasks.updated_at, tasks.mutation_id);
    accepted := accepted || jsonb_build_array(mutation_id);
  end loop;

  select coalesce(jsonb_agg(to_jsonb(goal_row) order by goal_row.created_at), '[]'::jsonb)
    into goals_snapshot
    from public.goals as goal_row
   where goal_row.user_id = p_user_id;
  select coalesce(jsonb_agg(to_jsonb(task_row) order by task_row.created_at), '[]'::jsonb)
    into tasks_snapshot
    from public.tasks as task_row
   where task_row.user_id = p_user_id;

  return jsonb_build_object(
    'goals', goals_snapshot,
    'tasks', tasks_snapshot,
    'accepted_mutation_ids', accepted
  );
end;
$$;

revoke all on function public.sync_goal_tasks(uuid, jsonb) from public;
grant execute on function public.sync_goal_tasks(uuid, jsonb) to authenticated;
