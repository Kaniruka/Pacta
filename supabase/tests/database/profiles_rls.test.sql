begin;

create extension if not exists pgtap with schema extensions;

select plan(4);

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'user-one@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'user-two@example.test');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select results_eq(
  $$select user_id from public.profiles order by user_id$$,
  $$values ('11111111-1111-1111-1111-111111111111'::uuid)$$,
  'an authenticated User can read only their own profile'
);

select results_eq(
  $$update public.profiles
      set display_name = 'User One'
      where user_id = '11111111-1111-1111-1111-111111111111'
      returning user_id$$,
  $$values ('11111111-1111-1111-1111-111111111111'::uuid)$$,
  'an authenticated User can update their own profile'
);

select results_eq(
  $$update public.profiles
      set display_name = 'Compromised'
      where user_id = '22222222-2222-2222-2222-222222222222'
      returning user_id$$,
  $$select null::uuid where false$$,
  'an authenticated User cannot update another profile'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select results_eq(
  $$select user_id from public.profiles order by user_id$$,
  $$values ('22222222-2222-2222-2222-222222222222'::uuid)$$,
  'the second authenticated User has an isolated view'
);

select * from finish();
rollback;
