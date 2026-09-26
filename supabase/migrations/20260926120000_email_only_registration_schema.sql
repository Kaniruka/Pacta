-- Finalize registration eligibility around the only supported identifier.

delete from public.registration_eligibility
where identifier_type <> 'email';

alter table public.registration_eligibility
  drop constraint if exists registration_eligibility_identifier_type_check;

alter table public.registration_eligibility
  add constraint registration_eligibility_identifier_type_check
  check (identifier_type = 'email');
