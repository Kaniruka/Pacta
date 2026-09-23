-- Ticket T09: keep Goals and Tasks available to history after deletion.

alter table public.goals
  add column if not exists deleted_at timestamptz;

alter table public.tasks
  add column if not exists deleted_at timestamptz;

create or replace function public.preserve_goal_task_deletion()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  deletion_started boolean := false;
  parent_deleted_at timestamptz;
begin
  if tg_table_name = 'goals' then
    if tg_op = 'UPDATE' then
      if old.deleted_at is not null then
        new.deleted_at := old.deleted_at;
      elsif new.deleted_at is not null then
        deletion_started := true;
      end if;
    elsif new.deleted_at is not null then
      deletion_started := true;
    end if;

    if deletion_started then
      update public.tasks as task
      set deleted_at = coalesce(task.deleted_at, new.deleted_at),
          updated_at = greatest(
            task.updated_at,
            new.updated_at,
            new.deleted_at
          )
      where task.user_id = new.user_id
        and task.goal_id = new.id;
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' and old.deleted_at is not null then
    new.deleted_at := old.deleted_at;
  end if;

  select goal.deleted_at
    into parent_deleted_at
    from public.goals as goal
    where goal.id = new.goal_id
      and goal.user_id = new.user_id;

  if parent_deleted_at is not null
    and (new.deleted_at is null or parent_deleted_at < new.deleted_at) then
    new.deleted_at := parent_deleted_at;
  end if;

  if new.deleted_at is not null then
    new.updated_at := greatest(new.updated_at, new.deleted_at);
  end if;
  return new;
end;
$function$;

revoke all on function public.preserve_goal_task_deletion() from public;

drop policy if exists "users can manage their goals" on public.goals;
drop policy if exists "users can read their goals" on public.goals;
drop policy if exists "users can insert their goals" on public.goals;
drop policy if exists "users can update their goals" on public.goals;
create policy "users can read their goals" on public.goals
  for select to authenticated
  using (user_id = auth.uid());
create policy "users can insert their goals" on public.goals
  for insert to authenticated
  with check (user_id = auth.uid());
create policy "users can update their goals" on public.goals
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users can manage their tasks" on public.tasks;
drop policy if exists "users can read their tasks" on public.tasks;
drop policy if exists "users can insert their tasks" on public.tasks;
drop policy if exists "users can update their tasks" on public.tasks;
create policy "users can read their tasks" on public.tasks
  for select to authenticated
  using (user_id = auth.uid());
create policy "users can insert their tasks" on public.tasks
  for insert to authenticated
  with check (user_id = auth.uid());
create policy "users can update their tasks" on public.tasks
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop trigger if exists preserve_goal_task_deletion on public.goals;
create trigger preserve_goal_task_deletion
before insert or update on public.goals
for each row execute function public.preserve_goal_task_deletion();

drop trigger if exists preserve_task_deletion on public.tasks;
create trigger preserve_task_deletion
before insert or update on public.tasks
for each row execute function public.preserve_goal_task_deletion();
