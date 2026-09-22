-- Ticket T06: fixed appointment preparation, automatic focus handoff, and
-- the independent Appointment Chain record.

create table if not exists public.focus_appointments (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  task_id uuid not null,
  mode text not null check (mode in ('elite', 'regular')),
  duration_seconds integer not null check (duration_seconds > 0),
  started_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null check (status in ('active', 'succeeded', 'failed')),
  settled_at timestamptz,
  session_id uuid,
  failure_reason text,
  updated_at timestamptz not null,
  unique (id, user_id),
  constraint focus_appointments_task_same_user_fk
    foreign key (task_id, user_id) references public.tasks(id, user_id)
    on delete restrict,
  constraint focus_appointments_failure_reason_check
    check (
      status <> 'failed'
      or (
        failure_reason is not null
        and length(trim(failure_reason)) between 1 and 200
      )
    )
);

alter table public.focus_sessions
  add column if not exists appointment_id uuid;

alter table public.focus_sessions
  drop constraint if exists focus_sessions_appointment_same_user_fk;

alter table public.focus_sessions
  add constraint focus_sessions_appointment_same_user_fk
    foreign key (appointment_id, user_id)
    references public.focus_appointments(id, user_id)
    on delete restrict;

create table if not exists public.appointment_chain_records (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  current_consecutive integer not null default 0 check (current_consecutive >= 0),
  best_consecutive integer not null default 0 check (best_consecutive >= 0),
  updated_at timestamptz not null
);

alter table public.focus_appointments enable row level security;
alter table public.appointment_chain_records enable row level security;

drop policy if exists "users can manage focus appointments" on public.focus_appointments;
create policy "users can manage focus appointments" on public.focus_appointments
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users can manage appointment chain records" on public.appointment_chain_records;
create policy "users can manage appointment chain records" on public.appointment_chain_records
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create index if not exists focus_appointments_user_started_at_idx
  on public.focus_appointments(user_id, started_at desc);
