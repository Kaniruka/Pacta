import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler, hash, StoreError, type Store } from './handler.ts';

const issuer = 'https://example.supabase.co/functions/v1/national-focus-mcp';
const resource = `${issuer}/mcp`;
const token = `pacta_mcp_${'a'.repeat(64)}`;
const metadata = { contract_version: 1, status: 'available', revision: 2,
  source_device: { id: 'phone', name: 'Android' }, uploaded_at: '2026-10-21T01:00:00Z',
  data_updated_at: '2026-10-20T23:00:00Z', freshness: 'latest_manual_upload' };

function fixture() {
  const tables: Record<string, Record<string, unknown>[]> = {};
  let denied = false;
  let unavailable = false;
  let calls = 0;
  let value: unknown = metadata;
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
      throw new Error(`unexpected RPC ${name}`);
    },
  };
  const handle = createHandler({ issuer, store });
  return { tables, setDenied: () => { denied = true; }, setUnavailable: () => { unavailable = true; },
    setValue: (next: unknown) => { value = next; }, count: () => calls,
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
  assert.match(await pending.text(), /National Focus read-only/);
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

test('only the metadata tool is exposed and expected revision is enforced', async () => {
  const f = fixture();
  const listed = await (await f.mcp(rpc('tools/list'))).json();
  assert.deepEqual(listed.result.tools.map((t: { name: string }) => t.name), ['get_snapshot_metadata']);
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
