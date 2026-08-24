begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

insert into auth.users (id, email)
values
  ('55555555-5555-5555-5555-555555555555', 'sessions-one@example.test'),
  ('66666666-6666-6666-6666-666666666666', 'sessions-two@example.test');

set local role authenticated;
set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';

insert into public.goals (id, user_id, title, mutation_id)
values (
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
  '55555555-5555-5555-5555-555555555555',
  'Session Goal',
  'goal-session-one'
);
insert into public.tasks (id, user_id, goal_id, title, classification, mutation_id)
values (
  'ffffffff-ffff-ffff-ffff-ffffffffffff',
  '55555555-5555-5555-5555-555555555555',
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
  'Session Task',
  'both',
  'task-session-one'
);

select results_eq(
  $$insert into public.focus_sessions (
      id, user_id, task_id, mode, planned_seconds, started_at,
      actual_elapsed_seconds, outcome,
      completed_at, mutation_id
    ) values (
      '11111111-1111-1111-1111-111111111111',
      '55555555-5555-5555-5555-555555555555',
      'ffffffff-ffff-ffff-ffff-ffffffffffff',
      'elite',
      900,
      '2026-08-24T09:00:00Z',
      900,
      'completed',
      '2026-08-24T09:15:00Z',
      'session-one'
    ) returning outcome$$,
  $$values ('completed'::text)$$,
  'a User can create a completed Focus Session for their own Task'
);

select results_eq(
  $$select jsonb_array_length(
      (public.sync_focus_sessions(
        '55555555-5555-5555-5555-555555555555',
        '[{"entity_type":"node","entity_id":"22222222-2222-2222-2222-222222222222","mutation_id":"node-one","updated_at":"2026-08-24T09:15:00Z","payload":{"id":"22222222-2222-2222-2222-222222222222","user_id":"55555555-5555-5555-5555-555555555555","session_id":"11111111-1111-1111-1111-111111111111","task_id":"ffffffff-ffff-ffff-ffff-ffffffffffff","mode":"elite","elapsed_seconds":900,"created_at":"2026-08-24T09:15:00Z","mutation_id":"node-one"}}]'::jsonb
      ) -> 'accepted_mutation_ids')
    )$$,
  $$values (1)$$,
  'the system sync appends a Focus Node for a completed Session'
);

set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
select results_eq(
  $$select count(*)::integer from public.focus_sessions$$,
  $$values (0)$$,
  'the second User cannot read another User''s Focus Session'
);

set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
select results_eq(
  $$select jsonb_array_length(
      (public.sync_focus_sessions(
        '55555555-5555-5555-5555-555555555555',
        '[{"entity_type":"node","entity_id":"22222222-2222-2222-2222-222222222222","mutation_id":"node-one","updated_at":"2026-08-24T09:15:00Z","payload":{"id":"22222222-2222-2222-2222-222222222222","user_id":"55555555-5555-5555-5555-555555555555","session_id":"11111111-1111-1111-1111-111111111111","task_id":"ffffffff-ffff-ffff-ffff-ffffffffffff","mode":"elite","elapsed_seconds":900,"created_at":"2026-08-24T09:15:00Z","mutation_id":"node-one"}}]'::jsonb
      ) -> 'accepted_mutation_ids')
    )$$,
  $$values (1)$$,
  'replaying a Focus Node mutation is accepted without duplicating the Node'
);

select results_eq(
  $$select count(*)::integer from public.focus_nodes$$,
  $$values (1)$$,
  'replaying a Focus Node mutation leaves exactly one Node'
);

select * from finish();
rollback;
