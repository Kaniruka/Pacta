import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler, hash, StoreError, type Store } from './handler.ts';

const issuer = 'https://example.supabase.co/functions/v1/national-focus-mcp';
const resource = `${issuer}/mcp`;
const token = `pacta_mcp_${'a'.repeat(64)}`;
const metadata = { contract_version: 1, status: 'available', revision: 2,
  source_device: { id: 'phone', name: 'Android' }, uploaded_at: '2026-10-21T01:00:00Z',
  data_updated_at: '2026-10-20T23:00:00Z', freshness: 'latest_manual_upload' };
const epoch = (value: string) => Date.parse(value) / 1000;
const activeSnapshot = {
  ...metadata,
  tables: {
    local_national_focus_cards: [
      { id: 'tree-a', name: 'Shared name', trigger_condition: 'before 07:00', action: 'read',
        scope: 'home', exception_notes: null, is_in_tree: 1, parent_id: null, state: 'lit',
        successful_days: 60, current_consecutive_days: 4, best_consecutive_days: 9,
        maintenance_cycle_started: 1, failure_reason: null, cascade_source_card_id: null,
        cascade_prior_state: null, active_strengthening_level: 1, deleted_at: null,
        user_id: 'private-user', token: 'private-token' },
      { id: 'tree-b', name: 'Shared name', trigger_condition: '', action: 'review',
        scope: null, exception_notes: 'skip when ill', is_in_tree: 1, parent_id: 'tree-a',
        state: 'pending_today_confirmation', successful_days: 2, current_consecutive_days: 2,
        best_consecutive_days: 2, maintenance_cycle_started: 1, failure_reason: null,
        cascade_source_card_id: null, cascade_prior_state: null, active_strengthening_level: null,
        deleted_at: null },
      { id: 'library-c', name: 'Library card', trigger_condition: '', action: 'practice',
        scope: null, exception_notes: null, is_in_tree: 0, parent_id: null, state: 'extinguished',
        successful_days: 0, current_consecutive_days: 0, best_consecutive_days: 0,
        maintenance_cycle_started: 0, failure_reason: null, cascade_source_card_id: null,
        cascade_prior_state: null, active_strengthening_level: null, deleted_at: null },
      { id: 'deleted-d', name: 'Deleted card', trigger_condition: '', action: 'deleted',
        scope: null, exception_notes: null, is_in_tree: 0, parent_id: null, state: 'extinguished',
        successful_days: 0, current_consecutive_days: 0, best_consecutive_days: 0,
        maintenance_cycle_started: 0, failure_reason: null, cascade_source_card_id: null,
        cascade_prior_state: null, active_strengthening_level: null, deleted_at: epoch('2026-10-20T00:00:00Z') },
    ],
    local_national_focus_strengthening_levels: [
      { user_id: 'private-user', card_id: 'tree-a', level_number: 1,
        trigger_condition_override: 'before 06:00', action_override: null,
        credential: { secret: 'nested-level-secret' } },
      { user_id: 'private-user', card_id: 'tree-a', level_number: 2,
        trigger_condition_override: null, action_override: 'read two pages' },
    ],
    local_national_focus_requirement_versions: [
      { user_id: 'private-user', id: 'version-a1', card_id: 'tree-a', version_number: 1,
        strengthening_level_number: null, effective_trigger_condition: 'before 07:00',
        effective_action: 'read', scope: 'home', exception_notes: null,
        effective_from: epoch('2026-01-01T00:00:00Z'), effective_until: epoch('2026-02-01T00:00:00Z') },
      { user_id: 'private-user', id: 'version-a2', card_id: 'tree-a', version_number: 2,
        strengthening_level_number: 1, effective_trigger_condition: 'before 06:00',
        effective_action: 'read', scope: 'home', exception_notes: null,
        effective_from: epoch('2026-02-01T00:00:00Z'), effective_until: null,
        tasks: [{ title: 'nested-version-task' }] },
      { user_id: 'private-user', id: 'version-b1', card_id: 'tree-b', version_number: 1,
        strengthening_level_number: null, effective_trigger_condition: '', effective_action: 'review',
        scope: null, exception_notes: 'skip when ill', effective_from: epoch('2026-03-01T00:00:00Z'), effective_until: null },
      { user_id: 'private-user', id: 'version-c1', card_id: 'library-c', version_number: 1,
        strengthening_level_number: null, effective_trigger_condition: '', effective_action: 'practice',
        scope: null, exception_notes: null, effective_from: epoch('2026-04-01T00:00:00Z'), effective_until: null },
    ],
    local_national_focus_maintenance: [
      { user_id: 'private-user', last_settled_checkpoint_at: epoch('2026-10-21T20:00:00Z'),
        admin: { token: 'nested-maintenance-secret' } },
    ],
    local_tasks: [{ id: 'private-task', title: 'not in scope' }],
  },
};

function fixture() {
  const tables: Record<string, Record<string, unknown>[]> = {};
  let denied = false;
  let unavailable = false;
  let calls = 0;
  let value: unknown = metadata;
  let snapshot: unknown = activeSnapshot;
  const store: Store = {
    async insert(table, value) { (tables[table] ??= []).push({ expires_at: new Date(Date.now() + 300000).toISOString(), ...value }); },
    async one(table, field, value) { return tables[table]?.find((r) => r[field] === value) ?? null; },
    async rpc(name, args) {
      calls++;
      if (unavailable) throw new StoreError('unavailable');
      if (name === 'read_national_focus_mcp_metadata') {
        if (denied || args.p_token_hash !== await hash(token)) throw new StoreError('28000');
        if (args.p_expected_revision !== undefined && args.p_expected_revision !== 2) throw new StoreError('PT409');
        return value;
      }
      if (name === 'read_national_focus_mcp_snapshot') {
        if (denied || args.p_token_hash !== await hash(token)) throw new StoreError('28000');
        if (args.p_expected_revision !== undefined && args.p_expected_revision !== 2) throw new StoreError('PT409');
        return snapshot;
      }
      throw new Error(`unexpected RPC ${name}`);
    },
  };
  const handle = createHandler({ issuer, store });
  return { tables, setDenied: () => { denied = true; }, setUnavailable: () => { unavailable = true; },
    setValue: (next: unknown) => { value = next; }, setSnapshot: (next: unknown) => { snapshot = next; }, count: () => calls,
    request: (path: string, options?: RequestInit) => handle(new Request(`${issuer}${path}`, options)),
    mcp: (body: unknown, auth = token) => handle(new Request(resource, { method: 'POST',
      headers: { Authorization: `Bearer ${auth}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) })),
  };
}
const rpc = (method: string, params?: unknown) => ({ jsonrpc: '2.0', id: 1, method, params });

test('public challenge discovers a path issuer and metadata without credentials', async () => {
  const f = fixture();
  const r = await f.request('/mcp', { method: 'POST', body: '{}' });
  assert.equal(r.status, 401);
  assert.match(r.headers.get('WWW-Authenticate')!, /resource_metadata="https:/);
  assert.equal((await (await f.request('/resource-metadata')).json()).resource, resource);
  const as = await (await f.request('/.well-known/openid-configuration')).json();
  assert.deepEqual(as.code_challenge_methods_supported, ['S256']);
  assert.equal(as.issuer, issuer);
  assert.equal(f.count(), 0);
});

test('discovery works through Supabase forwarded function paths', async () => {
  const store: Store = { async insert() {}, async one() { return null; }, async rpc() { throw new Error('not needed'); } };
  const handle = createHandler({ issuer, store });
  for (const prefix of ['/functions/v1/national-focus-mcp', '/national-focus-mcp']) {
    const r = await handle(new Request(`https://worker.internal${prefix}/resource-metadata`));
    assert.equal(r.status, 200);
    assert.equal((await r.json()).resource, resource);
  }
  assert.equal((await handle(new Request('https://worker.internal/other-function/resource-metadata'))).status, 404);
});

test('token exchange forwards only bound hashes and returns a separate credential', async () => {
  let seen = false;
  const verifier = 'v'.repeat(43);
  const store: Store = { async insert() {}, async one() { return null; }, async rpc(name, args) {
    assert.equal(name, 'exchange_national_focus_mcp_code');
    assert.equal(args.p_code_hash, await hash('c'.repeat(64)));
    assert.equal(args.p_client_id, 'b'.repeat(64));
    assert.equal(args.p_redirect_uri, 'http://127.0.0.1:3333/callback');
    assert.equal(args.p_resource, resource);
    assert.match(String(args.p_code_challenge), /^[A-Za-z0-9_-]{43}$/);
    assert.match(String(args.p_token_hash), /^[a-f0-9]{64}$/);
    assert.equal(JSON.stringify(args).includes(verifier), false);
    seen = true;
    return { expires_in: 1799, scope: 'national_focus:read' };
  } };
  const handle = createHandler({ issuer, store });
  const b = new URLSearchParams({ grant_type: 'authorization_code', code: 'c'.repeat(64),
    client_id: 'b'.repeat(64), code_verifier: verifier, redirect_uri: 'http://127.0.0.1:3333/callback', resource });
  const r = await handle(new Request(`${issuer}/token`, { method: 'POST', body: b }));
  assert.equal(r.status, 200);
  const result = await r.json();
  assert.equal(seen, true);
  assert.match(result.access_token, /^pacta_mcp_[a-f0-9]{64}$/);
  assert.equal(result.expires_in, 1799);
  assert.equal('refresh_token' in result, false);
  b.delete('client_id');
  assert.equal((await handle(new Request(`${issuer}/token`, { method: 'POST', body: b }))).status, 400);
});

test('DCR accepts exact public loopback clients and rejects open redirect targets', async () => {
  const f = fixture();
  for (const redirect of ['https://evil.example/callback', 'http://127.0.0.1:3333/cb#fragment',
    'http://user:pass@127.0.0.1:3333/cb', 'http://127.0.0.1:3333/cb?next=evil', 'http://127.0.0.1/cb']) {
    assert.equal((await f.request('/register', { method: 'POST', body: JSON.stringify({ token_endpoint_auth_method: 'none', redirect_uris: [redirect] }) })).status, 400);
  }
  const r = await f.request('/register', { method: 'POST', body: JSON.stringify({ client_name: 'Codex',
    token_endpoint_auth_method: 'none', redirect_uris: ['http://127.0.0.1:3333/callback'] }) });
  const registered = await r.json();
  assert.equal(r.status, 201);
  assert.match(registered.client_id, /^[a-f0-9]{64}$/);
  assert.equal('client_secret' in registered, false);
  const compatible = await f.request('/register', { method: 'POST', body: JSON.stringify({
    grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'],
    redirect_uris: ['http://localhost:3333/callback'],
  }) });
  assert.equal(compatible.status, 201);
  assert.deepEqual((await compatible.json()).grant_types, ['authorization_code']);
});

test('authorization waits for separate App approval and preserves exact callback/state', async () => {
  const f = fixture();
  const client = await (await f.request('/register', { method: 'POST', body: JSON.stringify({
    token_endpoint_auth_method: 'none', redirect_uris: ['http://127.0.0.1:3333/callback'] }) })).json();
  const p = new URLSearchParams({ client_id: client.client_id, redirect_uri: 'http://127.0.0.1:3333/callback',
    response_type: 'code', scope: 'national_focus:read', resource,
    code_challenge_method: 'S256', code_challenge: 'a'.repeat(43), state: 'request-state-123456' });
  const r = await f.request(`/authorize?${p}`);
  assert.equal(r.status, 302);
  const waiting = new URL(r.headers.get('Location')!);
  const ticket = waiting.searchParams.get('request')!;
  assert.match(ticket, /^[a-f0-9]{64}$/);
  const pending = await f.request(`/authorize?request=${ticket}`);
  assert.match(pending.headers.get('Content-Type')!, /text\/plain/);
  const disclosure = await pending.text();
  assert.match(disclosure, /National Focus read-only/);
  assert.match(disclosure, /National Focus tree, library, rules, progress and snapshot metadata/);
  assert.equal(f.tables.national_focus_mcp_grants, undefined);
  // Authenticated App's SQL approval is independently covered by the SQL probe.
  Object.assign(f.tables.national_focus_mcp_requests[0], { grant_id: 'approved', code_value: 'code' });
  const approved = await f.request(`/authorize?request=${ticket}`);
  const callback = new URL(approved.headers.get('Location')!);
  assert.equal(callback.origin, 'http://127.0.0.1:3333');
  assert.equal(callback.searchParams.get('state'), 'request-state-123456');
  assert.equal(callback.searchParams.get('iss'), issuer);
  p.set('redirect_uri', 'https://evil.example');
  assert.equal((await f.request(`/authorize?${p}`)).status, 400);
  p.set('redirect_uri', 'http://127.0.0.1:3333/callback');
  p.set('code_challenge_method', 'plain');
  assert.equal((await f.request(`/authorize?${p}`)).status, 400);
});

test('metadata and National Focus tools are exposed and metadata expected revision is enforced', async () => {
  const f = fixture();
  const listed = await (await f.mcp(rpc('tools/list'))).json();
  assert.deepEqual(listed.result.tools.map((t: { name: string }) => t.name), [
    'get_snapshot_metadata', 'get_national_focus_tree', 'get_national_focus_library', 'get_national_focus_card',
  ]);
  for (let i = 0; i < 2; i++) {
    const r = await (await f.mcp(rpc('tools/call', { name: 'get_snapshot_metadata', arguments: { expected_revision: 2 } }))).json();
    assert.deepEqual(r.result.structuredContent, metadata);
    assert.equal(JSON.stringify(r).includes('payload'), false);
  }
  const changed = await (await f.mcp(rpc('tools/call', { name: 'get_snapshot_metadata', arguments: { expected_revision: 1 } }))).json();
  assert.equal(changed.result.isError, true);
  assert.match(changed.result.content[0].text, /snapshot_changed/);
  assert.deepEqual(f.tables, {}); // reads allocate no authorizations or business writes
});

test('tree, library and card tools preserve National Focus detail while whitelisting every field', async () => {
  const f = fixture();
  f.setSnapshot(activeSnapshot);
  const tree = await (await f.mcp(rpc('tools/call', { name: 'get_national_focus_tree',
    arguments: { expected_revision: 2 } }))).json();
  const treeValue = tree.result.structuredContent;
  assert.deepEqual(treeValue.cards.map((card: { id: string }) => card.id), ['tree-a', 'tree-b']);
  assert.equal(treeValue.cards[1].parent_id, 'tree-a');
  assert.equal(treeValue.cards[0].internalization_progress_percent, 100 * (1 - Math.exp(-1)));
  assert.deepEqual(treeValue.cards[0].strengthening_levels, [
    { level_number: 1, trigger_condition_override: 'before 06:00', action_override: null },
    { level_number: 2, trigger_condition_override: null, action_override: 'read two pages' },
  ]);
  assert.deepEqual(treeValue.cards[0].requirement_versions.map((version: { id: string }) => version.id),
    ['version-a1', 'version-a2']);
  assert.equal(treeValue.maintenance.last_settled_checkpoint_at, '2026-10-21T20:00:00.000Z');
  assert.deepEqual(treeValue.metadata, metadata);

  const library = await (await f.mcp(rpc('tools/call', { name: 'get_national_focus_library', arguments: {} }))).json();
  assert.deepEqual(library.result.structuredContent.cards.map((card: { id: string }) => card.id), ['library-c']);

  const card = await (await f.mcp(rpc('tools/call', { name: 'get_national_focus_card',
    arguments: { card_id: 'tree-a', expected_revision: 2 } }))).json();
  assert.equal(card.result.structuredContent.card.id, 'tree-a');
  assert.equal(card.result.structuredContent.metadata.revision, 2);
  assert.equal(card.result.structuredContent.card.requirement_versions[1].effective_until, null);
  assert.equal(card.result.structuredContent.card.current_requirement_version.id, 'version-a2');
  assert.equal(card.result.structuredContent.card.effective_requirements.trigger_condition, 'before 06:00');
  assert.equal(card.result.structuredContent.error, undefined);

  const serialized = JSON.stringify({ tree: tree.result, library: library.result, card: card.result });
  for (const secret of ['private-user', 'private-token', 'deleted-d', 'Deleted card', 'local_tasks', 'private-task', 'payload', 'nested-level-secret', 'nested-version-task', 'nested-maintenance-secret']) {
    assert.equal(serialized.includes(secret), false, `leaked ${secret}`);
  }
  assert.deepEqual(f.tables, {});
});

test('content tools fail closed on malformed snapshot relations and preserve unavailable states', async () => {
  const f = fixture();
  const broken = structuredClone(activeSnapshot) as any;
  broken.tables.local_national_focus_cards[1].parent_id = 'missing-parent';
  f.setSnapshot(broken);
  const invalid = await (await f.mcp(rpc('tools/call', { name: 'get_national_focus_tree' }))).json();
  assert.equal(invalid.result.structuredContent.metadata.status, 'unsupported_snapshot');
  assert.deepEqual(invalid.result.structuredContent.cards, []);
  assert.equal(JSON.stringify(invalid).includes('private-token'), false);
  assert.equal(JSON.stringify(invalid).includes('tree-a'), false);

  const noSnapshot = { contract_version: 1, status: 'no_snapshot', revision: null,
    source_device: null, uploaded_at: null, recovery: 'Upload in Pacta.' };
  f.setSnapshot(noSnapshot);
  const unavailable = await (await f.mcp(rpc('tools/call', { name: 'get_national_focus_tree' }))).json();
  assert.equal(unavailable.result.structuredContent.metadata.status, 'no_snapshot');
  assert.deepEqual(unavailable.result.structuredContent.cards, []);

  const emptySnapshot = { ...metadata, tables: {
    local_national_focus_cards: [], local_national_focus_strengthening_levels: [],
    local_national_focus_requirement_versions: [], local_national_focus_maintenance: [],
  } };
  f.setSnapshot(emptySnapshot);
  const empty = await (await f.mcp(rpc('tools/call', { name: 'get_national_focus_tree' }))).json();
  assert.equal(empty.result.structuredContent.metadata.status, 'available');
  assert.deepEqual(empty.result.structuredContent.cards, []);
});

test('card lookup requires a pinned revision and changed snapshots return metadata with recovery', async () => {
  const f = fixture();
  const missingRevision = await (await f.mcp(rpc('tools/call', { name: 'get_national_focus_card',
    arguments: { card_id: 'tree-a' } }))).json();
  assert.equal(missingRevision.error.code, -32602);
  assert.match(missingRevision.error.data.recovery, /tools\/list/);

  const changed = await (await f.mcp(rpc('tools/call', { name: 'get_national_focus_card',
    arguments: { card_id: 'tree-a', expected_revision: 1 } }))).json();
  assert.equal(changed.result.isError, true);
  assert.equal(changed.result.structuredContent.metadata.revision, 2);
  assert.equal(changed.result.structuredContent.error.code, 'snapshot_changed');
  assert.match(changed.result.structuredContent.error.recovery, /Read metadata again/);
});

test('every MCP request rechecks delegate including initialize/list/notifications', async () => {
  const f = fixture();
  for (const method of ['initialize', 'tools/list', 'tools/call']) {
    assert.equal((await f.mcp(rpc(method), 'ordinary-app-jwt')).status, 401);
    assert.equal((await f.mcp(rpc(method), `pacta_mcp_${'b'.repeat(64)}`)).status, 401);
  }
  assert.equal((await f.mcp(rpc('initialize'))).status, 200);
  f.setDenied(); // revoked/expired/suspended all map to DB invalid_delegate
  for (const body of [rpc('initialize'), rpc('tools/list'), { jsonrpc: '2.0', method: 'notifications/initialized' }, rpc('tools/call')]) {
    assert.equal((await f.mcp(body)).status, 401);
  }
});

test('invalid inputs and unsupported writes cannot become arbitrary SQL/table reads', async () => {
  const f = fixture();
  for (const args of [{ user_id: 'other-user' }, { sql: 'select * from tasks' }, { expected_revision: -1 }, { expected_revision: 2.5 }]) {
    const r = await (await f.mcp(rpc('tools/call', { name: 'get_snapshot_metadata', arguments: args }))).json();
    assert.equal(r.error.code, -32602);
  }
  const r = await (await f.mcp(rpc('tools/call', { name: 'write_card' }))).json();
  assert.equal(r.error.code, -32602);
  assert.equal((await f.request('/mcp', { method: 'POST', headers: { Origin: 'https://evil.example' } })).status, 403);
  assert.equal((await f.request('/token', { method: 'POST', body: 'grant_type=authorization_code&code_verifier=short' })).status, 400);
});

test('no snapshot, old format and service errors remain distinct from an empty tree', async () => {
  const f = fixture();
  for (const status of ['no_snapshot', 'legacy_snapshot', 'unsupported_snapshot']) {
    f.setValue({ contract_version: 1, status, revision: null, uploaded_at: null });
    const r = await (await f.mcp(rpc('tools/call', { name: 'get_snapshot_metadata' }))).json();
    assert.equal(r.result.structuredContent.status, status);
    assert.equal(r.result.structuredContent.uploaded_at, null);
  }
  f.setUnavailable();
  assert.equal((await f.mcp(rpc('tools/list'))).status, 503);
});
