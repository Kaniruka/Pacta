-- Ticket T10: synchronize the user's selected appointment configuration basis.

alter table public.focus_appointments
  add column if not exists configuration_basis_source_id uuid;
