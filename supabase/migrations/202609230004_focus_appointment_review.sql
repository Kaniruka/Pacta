-- Ticket T10: keep concurrent appointment configuration changes unresolved.

alter table public.focus_appointments
  add column if not exists review_disposition text not null default 'accepted',
  add column if not exists review_disposition_updated_at timestamptz;

alter table public.focus_appointments
  drop constraint if exists focus_appointments_review_disposition_check;

alter table public.focus_appointments
  add constraint focus_appointments_review_disposition_check
    check (review_disposition in ('accepted', 'pending_review', 'duplicate'));
