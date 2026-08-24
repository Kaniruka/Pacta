create table public.focus_sessions (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  task_id uuid not null,
  mode text not null,
  planned_seconds integer not null,
  started_at timestamptz not null,
  actual_elapsed_seconds integer not null default 0,
  outcome text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  mutation_id text not null,
  primary key (id, user_id),
  constraint focus_sessions_task_owner_fk
    foreign key (task_id, user_id)
    references public.tasks (id, user_id)
    on delete cascade,
  constraint focus_sessions_mode check (mode in ('elite', 'regular')),
  constraint focus_sessions_planned_positive check (planned_seconds > 0),
  constraint focus_sessions_elapsed_range
    check (actual_elapsed_seconds between 0 and planned_seconds),
  constraint focus_sessions_outcome check (outcome is null or outcome = 'completed'),
  constraint focus_sessions_completed_consistency check (
    (outcome is null and completed_at is null and actual_elapsed_seconds = 0)
    or (
      outcome = 'completed'
      and completed_at is not null
      and actual_elapsed_seconds = planned_seconds
      and completed_at >= started_at + make_interval(secs => planned_seconds)
    )
  ),
  constraint focus_sessions_mutation_id_length
    check (char_length(mutation_id) between 1 and 200)
);

create table public.focus_nodes (
  id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  session_id uuid not null,
  task_id uuid not null,
  mode text not null,
  elapsed_seconds integer not null,
  created_at timestamptz not null default now(),
  mutation_id text not null,
  primary key (id, user_id),
  constraint focus_nodes_session_owner_fk
    foreign key (session_id, user_id)
    references public.focus_sessions (id, user_id)
    on delete cascade,
  constraint focus_nodes_task_owner_fk
    foreign key (task_id, user_id)
    references public.tasks (id, user_id)
    on delete cascade,
  constraint focus_nodes_session_unique unique (session_id, user_id),
  constraint focus_nodes_mode check (mode in ('elite', 'regular')),
  constraint focus_nodes_elapsed_positive check (elapsed_seconds > 0),
  constraint focus_nodes_mutation_id_length
    check (char_length(mutation_id) between 1 and 200)
);

create index focus_sessions_user_updated_idx
  on public.focus_sessions (user_id, updated_at);
create index focus_nodes_user_created_idx
  on public.focus_nodes (user_id, created_at);

alter table public.focus_sessions enable row level security;
alter table public.focus_nodes enable row level security;

revoke all on table public.focus_sessions, public.focus_nodes from anon, authenticated;
grant select, insert, update on table public.focus_sessions to authenticated;
grant select on table public.focus_nodes to authenticated;

create policy "Users can read their own focus sessions"
  on public.focus_sessions
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can create their own focus sessions"
  on public.focus_sessions
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update their own focus sessions"
  on public.focus_sessions
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users can read their own focus nodes"
  on public.focus_nodes
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.sync_focus_sessions(
  p_user_id uuid,
  p_mutations jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  mutation jsonb;
  payload jsonb;
  accepted jsonb := '[]'::jsonb;
  sessions_snapshot jsonb;
  nodes_snapshot jsonb;
  entity_type text;
  entity_id uuid;
  mutation_id text;
  updated_at timestamptz;
  session_task_id uuid;
  session_mode text;
  session_outcome text;
  session_elapsed_seconds integer;
  session_planned_seconds integer;
begin
  if p_user_id is distinct from (select auth.uid()) then
    raise exception 'The requested User does not match the authenticated User';
  end if;

  for mutation in
    select value from jsonb_array_elements(coalesce(p_mutations, '[]'::jsonb))
    where value ->> 'entity_type' = 'session'
  loop
    payload := mutation -> 'payload';
    entity_id := (payload ->> 'id')::uuid;
    mutation_id := mutation ->> 'mutation_id';
    updated_at := (mutation ->> 'updated_at')::timestamptz;
    insert into public.focus_sessions (
      id, user_id, task_id, mode, planned_seconds, started_at,
      actual_elapsed_seconds, outcome, completed_at, created_at, updated_at,
      mutation_id
    ) values (
      entity_id,
      p_user_id,
      (payload ->> 'task_id')::uuid,
      payload ->> 'mode',
      (payload ->> 'planned_seconds')::integer,
      (payload ->> 'started_at')::timestamptz,
      coalesce((payload ->> 'actual_elapsed_seconds')::integer, 0),
      payload ->> 'outcome',
      nullif(payload ->> 'completed_at', '')::timestamptz,
      (payload ->> 'created_at')::timestamptz,
      updated_at,
      mutation_id
    )
    on conflict (id, user_id) do update set
      task_id = excluded.task_id,
      mode = excluded.mode,
      planned_seconds = excluded.planned_seconds,
      started_at = excluded.started_at,
      actual_elapsed_seconds = excluded.actual_elapsed_seconds,
      outcome = excluded.outcome,
      completed_at = excluded.completed_at,
      created_at = excluded.created_at,
      updated_at = excluded.updated_at,
      mutation_id = excluded.mutation_id
    where (excluded.updated_at, excluded.mutation_id)
      > (focus_sessions.updated_at, focus_sessions.mutation_id);
    accepted := accepted || jsonb_build_array(mutation_id);
  end loop;

  for mutation in
    select value from jsonb_array_elements(coalesce(p_mutations, '[]'::jsonb))
    where value ->> 'entity_type' = 'node'
  loop
    payload := mutation -> 'payload';
    entity_id := (payload ->> 'id')::uuid;
    mutation_id := mutation ->> 'mutation_id';
    updated_at := (payload ->> 'created_at')::timestamptz;
    select task_id, mode, outcome, actual_elapsed_seconds, planned_seconds
      into session_task_id, session_mode, session_outcome,
        session_elapsed_seconds, session_planned_seconds
      from public.focus_sessions
     where id = (payload ->> 'session_id')::uuid
       and user_id = p_user_id;
    if not found
       or session_outcome <> 'completed'
       or session_elapsed_seconds <> session_planned_seconds
       or session_task_id <> (payload ->> 'task_id')::uuid
       or session_mode <> (payload ->> 'mode')
       or (payload ->> 'elapsed_seconds')::integer <> session_elapsed_seconds then
      raise exception 'A Focus Node requires the matching completed Focus Session';
    end if;
    insert into public.focus_nodes (
      id, user_id, session_id, task_id, mode, elapsed_seconds, created_at,
      mutation_id
    ) values (
      entity_id,
      p_user_id,
      (payload ->> 'session_id')::uuid,
      (payload ->> 'task_id')::uuid,
      payload ->> 'mode',
      (payload ->> 'elapsed_seconds')::integer,
      updated_at,
      mutation_id
    )
    on conflict (id, user_id) do nothing;
    accepted := accepted || jsonb_build_array(mutation_id);
  end loop;

  select coalesce(jsonb_agg(to_jsonb(session_row) order by session_row.created_at), '[]'::jsonb)
    into sessions_snapshot
    from public.focus_sessions as session_row
   where session_row.user_id = p_user_id;
  select coalesce(jsonb_agg(to_jsonb(node_row) order by node_row.created_at), '[]'::jsonb)
    into nodes_snapshot
    from public.focus_nodes as node_row
   where node_row.user_id = p_user_id;

  return jsonb_build_object(
    'sessions', sessions_snapshot,
    'nodes', nodes_snapshot,
    'accepted_mutation_ids', accepted
  );
end;
$$;

revoke all on function public.sync_focus_sessions(uuid, jsonb) from public;
grant execute on function public.sync_focus_sessions(uuid, jsonb) to authenticated;
