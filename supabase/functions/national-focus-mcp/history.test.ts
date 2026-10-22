import { test } from 'node:test';
import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { createHandler, hash, StoreError, type Store } from './handler.ts';

const issuer = 'https://example.supabase.co/functions/v1/national-focus-mcp';
const resource = `${issuer}/mcp`;
const token = `pacta_mcp_${'a'.repeat(64)}`;
const metadata = { contract_version: 1, status: 'available', revision: 2,
  source_device: { id: 'phone', name: 'Android' }, uploaded_at: '2026-10-21T01:00:00Z',
  data_updated_at: '2026-10-20T23:00:00Z', freshness: 'latest_manual_upload' };
const epoch = (value: string) => Date.parse(value) / 1000;

function frozenTree(suffix: string) {
  return JSON.stringify([
    { id: `root-${suffix}`, name: 'Historical root', triggerCondition: 'before 07:00', action: 'read',
      scope: 'home', exceptionNotes: 'old exception', isInTree: true, parentId: null, state: 'extinguished',
      successfulDays: 12, currentConsecutiveDays: 0, bestConsecutiveDays: 12, maintenanceCycleStarted: true,
      failureReason: 'frozen card reason', cascadeSourceCardId: null, cascadePriorState: null,
      activeStrengtheningLevel: 2, requirementVersionNumber: 3, effectiveTriggerCondition: 'before 06:00',
      effectiveAction: 'read two pages', createdAt: epoch('2026-01-01T00:00:00Z'), updatedAt: epoch('2026-10-01T00:00:00Z'),
      privateUserId: 'must-not-leak-user', hiddenPayload: 'must-not-leak-frozen-payload' },
    { id: `cascade-${suffix}`, name: 'Historical cascade child', triggerCondition: '', action: 'review',
      scope: null, exceptionNotes: null, isInTree: true, parentId: `root-${suffix}`, state: 'extinguished',
      successfulDays: 3, currentConsecutiveDays: 0, bestConsecutiveDays: 3, maintenanceCycleStarted: false,
      failureReason: null, cascadeSourceCardId: `root-${suffix}`, cascadePriorState: 'lit',
      activeStrengtheningLevel: null, createdAt: epoch('2026-01-01T00:00:00Z'), updatedAt: epoch('2026-10-01T00:00:00Z') },
  ]);
}

function historyWithDamagedTree(damage: (tree: Record<string, unknown>[]) => void) {
  const snapshot = JSON.parse(JSON.stringify(rawHistory));
  const event = snapshot.tables.local_national_focus_failures.find((row: Record<string, unknown>) => row.id === 'event-b');
  const tree = JSON.parse(event.tree_snapshot);
  damage(tree);
  event.tree_snapshot = JSON.stringify(tree);
  return snapshot;
}

const rawHistory = {
  ...metadata,
  tables: {
    local_national_focus_failures: [
      { user_id: 'private-user-id', id: 'event-b', batch_id: 'batch-1', card_id: 'root-b',
        checkpoint_at: epoch('2026-10-21T20:00:00Z'), cause: 'active_extinguish',
        failure_reason: 'original reason', shared_explanation: 'later batch reflection',
        review_disposition: 'pending_review', tree_snapshot: frozenTree('b'),
        internal_admin_note: 'must-not-leak-event-secret' },
      { user_id: 'private-user-id', id: 'event-a', batch_id: 'batch-1', card_id: 'root-a',
        checkpoint_at: epoch('2026-10-20T20:00:00Z'), cause: 'missed_confirmation',
        failure_reason: null, shared_explanation: 'later batch reflection', review_disposition: 'accepted',
        tree_snapshot: frozenTree('a') },
      { user_id: 'private-user-id', id: 'event-c', batch_id: 'batch-2', card_id: 'root-c',
        checkpoint_at: epoch('2026-10-21T20:00:00Z'), cause: 'active_extinguish',
        failure_reason: null, shared_explanation: null, review_disposition: 'accepted',
        tree_snapshot: frozenTree('c') },
      { user_id: 'private-user-id', id: 'event-end', batch_id: 'batch-3', card_id: 'root-end',
        checkpoint_at: epoch('2026-10-22T20:00:00Z'), cause: 'active_extinguish',
        failure_reason: null, shared_explanation: null, review_disposition: 'accepted',
        tree_snapshot: frozenTree('end') },
    ],
    local_tasks: [{ id: 'private-task', title: 'out of scope' }],
  },
};

function fixture(ownerToken = token, ownerSnapshot: unknown = rawHistory) {
  const tables: Record<string, Record<string, unknown>[]> = {};
  let denied = false;
  let revokeBeforeHistory = false;
  let historyUnavailable = false;
  let snapshot: unknown = ownerSnapshot;
  let historyCalls = 0;
  let seenHistoryArgs: Record<string, unknown> | undefined;
  const store: Store = {
    async insert(table, value) { (tables[table] ??= []).push(value); },
    async one(table, field, value) { return tables[table]?.find((row) => row[field] === value) ?? null; },
    async rpc(name, args) {
      if (name === 'read_national_focus_mcp_metadata') {
        if (denied || args.p_token_hash !== await hash(ownerToken)) throw new StoreError('28000');
        if (args.p_expected_revision !== undefined && args.p_expected_revision !== 2) throw new StoreError('PT409');
        return metadata;
      }
      if (name === 'read_national_focus_mcp_history_snapshot') {
        historyCalls++;
        seenHistoryArgs = args;
        if (denied || revokeBeforeHistory || args.p_token_hash !== await hash(ownerToken)) throw new StoreError('28000');
        if (historyUnavailable) throw new Error('private database payload must not leak');
        if (args.p_expected_revision !== undefined && args.p_expected_revision !== 2) throw new StoreError('PT409');
        return snapshot;
      }
      throw new Error(`unexpected RPC ${name}`);
    },
  };
  const handle = createHandler({ issuer, store });
  return {
    tables,
    setDenied: () => { denied = true; },
    revokeBeforeHistory: () => { revokeBeforeHistory = true; },
    setHistoryUnavailable: () => { historyUnavailable = true; },
    setSnapshot: (value: unknown) => { snapshot = value; },
    historyCalls: () => historyCalls,
    historyArgs: () => seenHistoryArgs,
    call: (name: string, args: Record<string, unknown>) => handle(new Request(resource, {
      method: 'POST', headers: { Authorization: `Bearer ${ownerToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } }),
    })),
  };
}

async function toolResult(response: Response) {
  assert.equal(response.status, 200);
  return (await response.json()).result;
}

test('failure history uses inclusive Beijing days, stable pagination, and revision-bound cursors', async () => {
  const f = fixture();
  const args = { start_date: '2026-10-21', end_date: '2026-10-22', limit: 1, expected_revision: 2 };
  const first = await toolResult(await f.call('list_national_focus_failures', args));
  assert.deepEqual(first.structuredContent.events.map((event: { id: string }) => event.id), ['event-a']);
  assert.equal(first.structuredContent.events[0].national_focus_date, '2026-10-21');
  assert.deepEqual(first.structuredContent.coverage, {
    start_date: '2026-10-21', end_date: '2026-10-22',
    start_at: '2026-10-20T20:00:00.000Z', end_before: '2026-10-22T20:00:00.000Z',
    timezone: 'UTC+08:00', checkpoint: '04:00', ordering: 'checkpoint_at ASC, id ASC (code-point)',
  });
  assert.equal(first.structuredContent.truncated, true);
  assert.equal(typeof first.structuredContent.next_cursor, 'string');
  assert.equal(f.historyArgs()?.p_token_hash, await hash(token));
  assert.equal(f.historyArgs()?.p_expected_revision, 2);

  const second = await toolResult(await f.call('list_national_focus_failures', {
    ...args, cursor: first.structuredContent.next_cursor,
  }));
  assert.deepEqual(second.structuredContent.events.map((event: { id: string }) => event.id), ['event-b']);
  assert.equal(second.structuredContent.truncated, true);
  const third = await toolResult(await f.call('list_national_focus_failures', {
    ...args, cursor: second.structuredContent.next_cursor,
  }));
  assert.deepEqual(third.structuredContent.events.map((event: { id: string }) => event.id), ['event-c']);
  assert.equal(third.structuredContent.events[0].national_focus_date, '2026-10-22');
  assert.equal(third.structuredContent.truncated, false);
  assert.equal(third.structuredContent.next_cursor, null);
  assert.deepEqual(f.tables, {});
});

test('failure detail returns frozen fields, separate reflection, and excludes cascade-only events and unknown fields', async () => {
  const f = fixture();
  const listed = await toolResult(await f.call('list_national_focus_failures', {
    start_date: '2026-10-20', end_date: '2026-10-22', limit: 20, expected_revision: 2,
  }));
  assert.deepEqual(listed.structuredContent.events.map((event: { id: string }) => event.id), ['event-a', 'event-b', 'event-c']);
  const serialized = JSON.stringify(listed.structuredContent);
  for (const secret of ['private-user-id', 'private-task', 'must-not-leak-event-secret', 'must-not-leak-frozen-payload']) {
    assert.equal(serialized.includes(secret), false, `leaked ${secret}`);
  }
  const event = listed.structuredContent.events.find((item: { id: string }) => item.id === 'event-b');
  assert.equal(event.failure_reason, 'original reason');
  assert.equal(event.shared_explanation, 'later batch reflection');
  assert.equal(event.review_disposition, 'pending_review');
  assert.equal(event.tree_snapshot[0].effective_trigger_condition, 'before 06:00');
  assert.equal(event.tree_snapshot[0].effective_action, 'read two pages');
  assert.equal(event.tree_snapshot[0].requirement_version_number, 3);
  assert.equal(event.tree_snapshot[1].cascade_source_card_id, 'root-b');
  assert.equal(event.tree_snapshot[1].effective_trigger_condition, null);
  assert.equal(event.tree_snapshot[1].effective_action, null);
  assert.equal(event.tree_snapshot[1].requirement_version_number, null);
  assert.equal('privateUserId' in event.tree_snapshot[0], false);
  assert.equal(event.tree_snapshot.length, 2);

  const detail = await toolResult(await f.call('get_national_focus_failure', { event_id: 'event-b', expected_revision: 2 }));
  assert.equal(detail.structuredContent.event.id, 'event-b');
  assert.equal(detail.structuredContent.event.failure_reason, 'original reason');
  assert.equal(detail.structuredContent.event.shared_explanation, 'later batch reflection');
  assert.deepEqual(listed.structuredContent.events.slice(0, 2).map((item: { batch_id: string }) => item.batch_id), ['batch-1', 'batch-1']);
  assert.deepEqual(listed.structuredContent.events.slice(0, 2).map((item: { shared_explanation: string }) => item.shared_explanation),
    ['later batch reflection', 'later batch reflection']);
  const missing = await toolResult(await f.call('get_national_focus_failure', { event_id: 'cascade-b', expected_revision: 2 }));
  assert.equal(missing.isError, true);
  assert.equal(missing.structuredContent.error.code, 'failure_not_found');
});

test('history pages and details reject stale revisions without mixing snapshot contents', async () => {
  const f = fixture();
  const changed = await toolResult(await f.call('list_national_focus_failures', {
    start_date: '2026-10-20', end_date: '2026-10-22', expected_revision: 1,
  }));
  assert.equal(changed.isError, true);
  assert.equal(changed.structuredContent.error.code, 'snapshot_changed');
  assert.deepEqual(changed.structuredContent.events, undefined);
  const detail = await toolResult(await f.call('get_national_focus_failure', { event_id: 'event-a', expected_revision: 1 }));
  assert.equal(detail.isError, true);
  assert.equal(detail.structuredContent.error.code, 'snapshot_changed');
});

test('invalid dates, ranges, limits, revisions, and query-mismatched cursors fail before history reads', async () => {
  const f = fixture();
  const invalid = [
    { start_date: '2026-02-30', end_date: '2026-03-01' },
    { start_date: '2026-03-02', end_date: '2026-03-01' },
    { start_date: '2025-01-01', end_date: '2026-01-02' },
    { start_date: '2026-03-01', end_date: '2026-03-01', limit: 0 },
    { start_date: '2026-03-01', end_date: '2026-03-01', limit: 101 },
    { start_date: '2026-03-01', end_date: '2026-03-01', expected_revision: 0 },
  ];
  for (const args of invalid) {
    const response = await f.call('list_national_focus_failures', { expected_revision: 2, ...args });
    const body = await response.json();
    assert.equal(body.error.code, -32602);
  }
  assert.equal(f.historyCalls(), 0);

  for (const args of [
    { start_date: { toString: null }, end_date: '2026-03-01', expected_revision: 2 },
    { start_date: '2026-03-01', end_date: '2026-03-01', limit: null, expected_revision: 2 },
  ]) {
    const response = await f.call('list_national_focus_failures', args);
    const body = await response.json();
    assert.equal(response.status, 200);
    assert.equal(body.error.code, -32602);
  }
  assert.equal(f.historyCalls(), 0);

  const valid = await toolResult(await f.call('list_national_focus_failures', {
    start_date: '2026-10-20', end_date: '2026-10-22', limit: 1, expected_revision: 2,
  }));
  const cursor = valid.structuredContent.next_cursor;
  assert.equal(typeof cursor, 'string');
  const mismatched = await (await f.call('list_national_focus_failures', {
    start_date: '2026-10-20', end_date: '2026-10-21', limit: 1, expected_revision: 2, cursor,
  })).json();
  assert.equal(mismatched.error.code, -32602);
});

test('missing history is reported as unsupported data and revoked grants cannot read it', async () => {
  const f = fixture();
  f.setSnapshot({ ...metadata, tables: { local_national_focus_cards: [] } });
  const missing = await toolResult(await f.call('list_national_focus_failures', {
    start_date: '2026-10-20', end_date: '2026-10-22', expected_revision: 2,
  }));
  assert.equal(missing.structuredContent.metadata.status, 'unsupported_snapshot');
  assert.deepEqual(missing.structuredContent.events, []);

  f.setDenied();
  const revoked = await f.call('get_national_focus_failure', { event_id: 'event-a', expected_revision: 2 });
  assert.equal(revoked.status, 401);
  const body = await revoked.json();
  assert.equal(body.error, 'invalid_token');
  assert.equal(JSON.stringify(body).includes('original reason'), false);
});

test('an empty but supported history is an available snapshot with an empty page', async () => {
  const f = fixture();
  f.setSnapshot({ ...metadata, tables: { local_national_focus_failures: [] } });
  const page = await toolResult(await f.call('list_national_focus_failures', {
    start_date: '2026-10-20', end_date: '2026-10-22', expected_revision: 2,
  }));
  assert.equal(page.isError, false);
  assert.equal(page.structuredContent.metadata.status, 'available');
  assert.deepEqual(page.structuredContent.events, []);
  assert.equal(page.structuredContent.truncated, false);
  assert.equal(page.structuredContent.next_cursor, null);
});

test('a history service failure returns a generic error without database details', async () => {
  const f = fixture();
  f.setHistoryUnavailable();
  for (const response of [
    await f.call('list_national_focus_failures', {
      start_date: '2026-10-20', end_date: '2026-10-22', expected_revision: 2,
    }),
    await f.call('get_national_focus_failure', { event_id: 'event-a', expected_revision: 2 }),
  ]) {
    assert.equal(response.status, 503);
    const body = await response.json();
    assert.equal(body.error, 'service_unavailable');
    assert.equal(JSON.stringify(body).includes('private database payload'), false);
  }
});

test('revocation between metadata validation and the history RPC blocks both page and detail reads', async () => {
  for (const [name, args] of [
    ['list_national_focus_failures', { start_date: '2026-10-20', end_date: '2026-10-22', expected_revision: 2 }],
    ['get_national_focus_failure', { event_id: 'event-a', expected_revision: 2 }],
  ] as const) {
    const f = fixture();
    f.revokeBeforeHistory();
    const response = await f.call(name, args);
    assert.equal(response.status, 401);
    const body = await response.json();
    assert.equal(body.error, 'invalid_token');
    assert.equal(JSON.stringify(body).includes('original reason'), false);
    assert.equal(f.historyCalls(), 1);
  }
});

test('different delegate tokens receive only their own owner snapshot', async () => {
  const otherToken = `pacta_mcp_${'b'.repeat(64)}`;
  const otherSnapshot = JSON.parse(JSON.stringify(rawHistory));
  otherSnapshot.tables.local_national_focus_failures = [
    { ...otherSnapshot.tables.local_national_focus_failures[0], user_id: 'different-private-owner', id: 'owner-two-event',
      card_id: 'root-owner-two', tree_snapshot: frozenTree('owner-two') },
  ];
  const firstOwner = fixture();
  const secondOwner = fixture(otherToken, otherSnapshot);
  const query = { start_date: '2026-10-20', end_date: '2026-10-22', expected_revision: 2 };
  const first = await toolResult(await firstOwner.call('list_national_focus_failures', query));
  const second = await toolResult(await secondOwner.call('list_national_focus_failures', query));
  assert.deepEqual(first.structuredContent.events.map((event: { id: string }) => event.id), ['event-a', 'event-b', 'event-c']);
  assert.deepEqual(second.structuredContent.events.map((event: { id: string }) => event.id), ['owner-two-event']);
  assert.equal(firstOwner.historyArgs()?.p_token_hash, await hash(token));
  assert.equal(secondOwner.historyArgs()?.p_token_hash, await hash(otherToken));
  assert.equal(JSON.stringify(second.structuredContent).includes('private-user-id'), false);
});

test('malformed frozen parent, source, cascade references and cycles fail closed', async () => {
  const corruptions: Array<[string, (tree: Record<string, unknown>[]) => void]> = [
    ['dangling parent', (tree) => { tree[1].parentId = 'missing-parent'; }],
    ['dangling failure source', (tree) => { tree[0].failureSourceCardId = 'missing-source'; }],
    ['dangling cascade source', (tree) => { tree[1].cascadeSourceCardId = 'missing-source'; }],
    ['parent cycle', (tree) => { tree[0].parentId = tree[1].id; }],
  ];
  for (const [label, damage] of corruptions) {
    const f = fixture();
    f.setSnapshot(historyWithDamagedTree(damage));
    const result = await toolResult(await f.call('list_national_focus_failures', {
      start_date: '2026-10-20', end_date: '2026-10-22', expected_revision: 2,
    }));
    assert.equal(result.structuredContent.metadata.status, 'unsupported_snapshot', label);
    assert.deepEqual(result.structuredContent.events, [], label);
  }
});

test('Unicode event IDs use code-point order and survive cursor continuation', async () => {
  const supplementary = String.fromCodePoint(0x10000);
  const bmp = String.fromCodePoint(0xe000);
  const snapshot = JSON.parse(JSON.stringify(rawHistory));
  snapshot.tables.local_national_focus_failures = [
    { id: supplementary, batch_id: 'unicode-batch', card_id: 'root-supplementary',
      checkpoint_at: epoch('2026-10-21T20:00:00Z'), cause: 'missed_confirmation',
      failure_reason: null, shared_explanation: null, review_disposition: 'accepted',
      tree_snapshot: frozenTree('supplementary') },
    { id: bmp, batch_id: 'unicode-batch', card_id: 'root-bmp',
      checkpoint_at: epoch('2026-10-21T20:00:00Z'), cause: 'missed_confirmation',
      failure_reason: null, shared_explanation: null, review_disposition: 'accepted',
      tree_snapshot: frozenTree('bmp') },
  ];
  const f = fixture(token, snapshot);
  const args = { start_date: '2026-10-21', end_date: '2026-10-22', limit: 1, expected_revision: 2 };
  const first = await toolResult(await f.call('list_national_focus_failures', args));
  assert.deepEqual(first.structuredContent.events.map((event: { id: string }) => event.id), [bmp]);
  assert.equal(typeof first.structuredContent.next_cursor, 'string');
  const second = await toolResult(await f.call('list_national_focus_failures', {
    ...args, cursor: first.structuredContent.next_cursor,
  }));
  assert.deepEqual(second.structuredContent.events.map((event: { id: string }) => event.id), [supplementary]);
  assert.equal(second.structuredContent.next_cursor, null);
});


test('Issue61 synthetic replay: independent parent/child, cascade, deleted history and later reflection', async () => {
  const snapshot = JSON.parse(JSON.stringify(rawHistory));
  const parentTree = JSON.parse(frozenTree('parent'));
  parentTree[0].name = '同名国策';
  parentTree[1].name = '同名国策';
  const childTree = JSON.parse(JSON.stringify(parentTree));
  childTree[0].state = 'lit';
  childTree[0].failureReason = null;
  childTree[1].cascadeSourceCardId = null;
  childTree[1].cascadePriorState = null;
  childTree[1].failureReason = 'child independently failed';
  const deletedTree = JSON.parse(frozenTree('deleted'));
  // This card has no current-card row; history must be self-contained.
  const events = [
    { id: 'independent-parent', card_id: 'root-parent', cause: 'active_extinguish', tree: parentTree,
      failure_reason: 'original parent reason', shared_explanation: 'edited later, not original cause' },
    { id: 'independent-child', card_id: 'cascade-parent', cause: 'active_extinguish', tree: childTree,
      failure_reason: 'child independently failed', shared_explanation: null },
    { id: 'missed-confirmation', card_id: 'root-missed', cause: 'missed_confirmation',
      tree: JSON.parse(frozenTree('missed')), failure_reason: null, shared_explanation: null },
    { id: 'soft-deleted-history', card_id: 'root-deleted', cause: 'active_extinguish', tree: deletedTree,
      failure_reason: 'before soft deletion', shared_explanation: null },
  ].map(({ tree, ...event }) => ({ ...event, batch_id: 'synthetic-batch',
    checkpoint_at: epoch('2026-10-21T20:00:00Z'), review_disposition: 'accepted',
    tree_snapshot: JSON.stringify(tree) }));
  snapshot.tables.local_national_focus_failures = events;
  const f = fixture(token, snapshot);
  const query = { start_date: '2026-09-23', end_date: '2026-10-22', limit: 1, expected_revision: 2 };
  const collected: any[] = [];
  const toolEvidence: unknown[] = [];
  let cursor: string | null = null;
  let pages = 0;
  do {
    const result = await toolResult(await f.call('list_national_focus_failures', {
      ...query, ...(cursor ? { cursor } : {}),
    }));
    toolEvidence.push({ tool: 'list_national_focus_failures', arguments: {
      ...query, ...(cursor ? { cursor } : {}),
    }, result: result.structuredContent });
    assert.equal(result.structuredContent.metadata.status, 'available');
    assert.match(result.structuredContent.limitations, /historical omissions are possible/);
    assert.match(result.structuredContent.limitations, /not daily success logs/);
    assert.equal(result.structuredContent.coverage.start_date, '2026-09-23');
    collected.push(...result.structuredContent.events);
    cursor = result.structuredContent.next_cursor;
    assert.equal(result.structuredContent.truncated, cursor !== null);
    pages++;
  } while (cursor);
  assert.equal(pages, 4);
  assert.equal(new Set(collected.map((event) => event.id)).size, 4);
  const byId = new Map(collected.map((event) => [event.id, event]));
  const parent = byId.get('independent-parent');
  const child = byId.get('independent-child');
  assert.equal(parent.card_id, 'root-parent');
  assert.equal(child.card_id, 'cascade-parent');
  assert.equal(parent.tree_snapshot[1].cascade_source_card_id, 'root-parent');
  assert.equal(child.tree_snapshot[1].cascade_source_card_id, null);
  assert.equal(child.tree_snapshot[0].state, 'lit');
  assert.equal(parent.tree_snapshot[0].name, parent.tree_snapshot[1].name);
  assert.notEqual(parent.tree_snapshot[0].id, parent.tree_snapshot[1].id);
  assert.equal(parent.tree_snapshot[0].active_strengthening_level, 2);
  assert.equal(parent.tree_snapshot[0].requirement_version_number, 3);
  assert.equal(parent.tree_snapshot[0].effective_action, 'read two pages');
  assert.equal(parent.failure_reason, 'original parent reason');
  assert.equal(parent.shared_explanation, 'edited later, not original cause');
  assert.equal(byId.get('missed-confirmation').cause, 'missed_confirmation');
  assert.equal(byId.get('missed-confirmation').failure_reason, null);
  const deleted = await toolResult(await f.call('get_national_focus_failure', {
    event_id: 'soft-deleted-history', expected_revision: 2,
  }));
  if (process.env.PACTA_ISSUE61_EVIDENCE_PATH) {
    writeFileSync(process.env.PACTA_ISSUE61_EVIDENCE_PATH, JSON.stringify({
      label: 'Synthetic store; real createHandler HTTP JSON-RPC tools/call results; no deployed service',
      toolEvidence, detail: deleted.structuredContent,
    }, null, 2) + '\n');
  }
  assert.equal(deleted.structuredContent.event.card_id, 'root-deleted');
  assert.equal(deleted.structuredContent.event.tree_snapshot[0].effective_action, 'read two pages');
  assert.deepEqual(f.tables, {});
});

test('Issue61 an old cursor cannot continue after a revision change; restart discards prior pages', async () => {
  const f = fixture();
  const query = { start_date: '2026-09-23', end_date: '2026-10-22', limit: 1, expected_revision: 2 };
  const first = await toolResult(await f.call('list_national_focus_failures', query));
  assert.equal(first.structuredContent.truncated, true);
  f.setSnapshot({ ...rawHistory, revision: 3 });
  const stale = await toolResult(await f.call('list_national_focus_failures', {
    ...query, cursor: first.structuredContent.next_cursor,
  }));
  assert.equal(stale.isError, true);
  assert.equal(stale.structuredContent.error.code, 'snapshot_changed');
  assert.equal(stale.structuredContent.events, undefined);
  // New run with an isolated latest-revision store, never appending the old page.
  const store: Store = { async insert() { assert.fail('write'); }, async one() { return null; },
    async rpc(name) { return name === 'read_national_focus_mcp_metadata'
      ? { ...metadata, revision: 3 } : { ...rawHistory, revision: 3 }; } };
  const handle = createHandler({ issuer, store });
  const response = await handle(new Request(resource, { method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: {
      name: 'list_national_focus_failures', arguments: { ...query, expected_revision: 3, limit: 100 },
    } }),
  }));
  const restarted = await toolResult(response);
  assert.equal(restarted.structuredContent.metadata.revision, 3);
  assert.deepEqual(restarted.structuredContent.events.map((event: any) => event.id), ['event-a', 'event-b', 'event-c']);
  assert.equal(restarted.structuredContent.next_cursor, null);
});
