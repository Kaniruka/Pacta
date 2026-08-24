begin;

create extension if not exists pgtap with schema extensions;

select plan(7);

insert into auth.users (id, email)
values
  ('33333333-3333-3333-3333-333333333333', 'goals-one@example.test'),
  ('44444444-4444-4444-4444-444444444444', 'goals-two@example.test');

set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

select results_eq(
  $$insert into public.goals (id, user_id, title, mutation_id)
    values (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '33333333-3333-3333-3333-333333333333',
      'First Goal',
      'goal-one'
    )
    returning title$$,
  $$values ('First Goal'::text)$$,
  'a User can create their own Goal'
);

select results_eq(
  $$insert into public.tasks (
      id, user_id, goal_id, title, classification, mutation_id
    ) values (
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      '33333333-3333-3333-3333-333333333333',
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'First Task',
      'both',
      'task-one'
    ) returning title$$,
  $$values ('First Task'::text)$$,
  'a User can create a Task under their own Goal'
);

select results_eq(
  $$update public.tasks
      set focus_progress_seconds = 3600
      where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
      returning completed_at$$,
  $$values (null::timestamptz)$$,
  'Focus Progress does not set explicit Task completion'
);

select results_eq(
  $$select title from public.goals order by title$$,
  $$values ('First Goal'::text)$$,
  'a User can read only their own Goal'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';

select results_eq(
  $$insert into public.goals (id, user_id, title, mutation_id)
    values (
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      '44444444-4444-4444-4444-444444444444',
      'Second Goal',
      'goal-two'
    ) returning title$$,
  $$values ('Second Goal'::text)$$,
  'the second User can create their own Goal'
);

select results_eq(
  $$select title from public.goals order by title$$,
  $$values ('Second Goal'::text)$$,
  'the second User has an isolated Goal view'
);

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

select throws_ok(
  $$insert into public.tasks (
      id, user_id, goal_id, title, classification, mutation_id
    ) values (
      'dddddddd-dddd-dddd-dddd-dddddddddddd',
      '33333333-3333-3333-3333-333333333333',
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'Cross-owner Task',
      'regular',
      'cross-owner'
    )$$,
  '23503',
  null,
  'a Task cannot reference another User''s Goal'
);

select * from finish();
rollback;
