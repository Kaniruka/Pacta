// No external runtime dependencies: this public boundary is tested as HTTP.
export const SCOPE = 'national_focus:read';
export interface Store {
  insert(table: string, value: Record<string, unknown>): Promise<void>;
  one(table: string, field: string, value: string): Promise<Record<string, unknown> | null>;
  rpc(name: string, args: Record<string, unknown>): Promise<unknown>;
}
export interface Config { issuer: string; store: Store }
export class StoreError extends Error {
  constructor(public code: string) { super('Service operation failed'); }
}
const object = (v: unknown): v is Record<string, unknown> =>
  v !== null && typeof v === 'object' && !Array.isArray(v);
const random = () => Array.from(crypto.getRandomValues(new Uint8Array(32)),
  (v) => v.toString(16).padStart(2, '0')).join('');
export async function hash(value: string): Promise<string> {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',
    new TextEncoder().encode(value))), (v) => v.toString(16).padStart(2, '0')).join('');
}
async function challenge(value: string): Promise<string> {
  const bytes = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function redirectAllowed(value: unknown): value is string {
  if (typeof value !== 'string' || value.length > 2048) return false;
  try {
    const u = new URL(value);
    // Only desktop loopback OAuth clients in T1. Exact registered URI is bound
    // through approval and exchange; no redirects to arbitrary web origins.
    return u.protocol === 'http:' && ['127.0.0.1', '[::1]', 'localhost'].includes(u.hostname)
      && !!u.port && !u.username && !u.password && !u.hash && !u.search;
  } catch { return false; }
}
const tool = {
  name: 'get_snapshot_metadata',
  description: 'Read metadata of your latest manual cloud upload. Does not upload, settle, or read National Focus content. No snapshot requires a manual upload in Pacta.',
  inputSchema: { type: 'object', properties: { expected_revision: { type: 'integer', minimum: 1 } }, additionalProperties: false },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};

export function createHandler(config: Config): (request: Request) => Promise<Response> {
  const { store } = config;
  const issuer = config.issuer.replace(/\/$/, '');
  const resource = `${issuer}/mcp`;
  const reply = (status: number, body: unknown, extra: Record<string, string> = {}) =>
    new Response(body === undefined ? null : JSON.stringify(body), { status, headers: {
      'Content-Type': 'application/json', 'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', ...extra,
    } });
  const oauthError = (name: string, status = 400) => reply(status, { error: name });
  const unauthorized = () => reply(401, { error: 'invalid_token', recovery: 'Run codex mcp login pacta-national-focus again; check App connection and user status.' }, {
    'WWW-Authenticate': `Bearer resource_metadata="${issuer}/resource-metadata", scope="${SCOPE}", error="invalid_token"`,
  });
  return async (request) => {
    const url = new URL(request.url);
    const origin = request.headers.get('Origin');
    try {
      if (origin) return reply(403, { error: 'origin_denied' });
      // Hosted Supabase strips /functions/v1 before forwarding to the worker.
      // Local gateways may preserve it. Both prefixes derive from trusted config.
      const fullPrefix = new URL(issuer).pathname;
      const workerPrefix = `/${fullPrefix.split('/').filter(Boolean).at(-1)}`;
      const prefix = [fullPrefix, workerPrefix].find((p) => url.pathname.startsWith(`${p}/`));
      if (!prefix) return reply(404, { error: 'not_found' });
      const path = url.pathname.slice(prefix.length);
      if (request.method === 'GET' && path === '/resource-metadata') return reply(200, {
        resource, authorization_servers: [issuer], scopes_supported: [SCOPE], bearer_methods_supported: ['header'],
      });
      if (request.method === 'GET' && path === '/.well-known/openid-configuration') return reply(200, {
        issuer, authorization_endpoint: `${issuer}/authorize`, token_endpoint: `${issuer}/token`,
        registration_endpoint: `${issuer}/register`, response_types_supported: ['code'],
        grant_types_supported: ['authorization_code'], code_challenge_methods_supported: ['S256'],
        token_endpoint_auth_methods_supported: ['none'], scopes_supported: [SCOPE],
      });
      if (request.method === 'POST' && path === '/register') {
        const b = await request.json();
        if (!object(b) || (b.token_endpoint_auth_method !== undefined && b.token_endpoint_auth_method !== 'none')
          || !Array.isArray(b.redirect_uris) || b.redirect_uris.length < 1 || b.redirect_uris.length > 4
          || !b.redirect_uris.every(redirectAllowed)
          || (b.grant_types !== undefined && (!Array.isArray(b.grant_types)
            || !b.grant_types.includes('authorization_code')
            || b.grant_types.some((v) => v !== 'authorization_code' && v !== 'refresh_token')))
          || (b.response_types !== undefined && JSON.stringify(b.response_types) !== '["code"]')) {
          return oauthError('invalid_client_metadata');
        }
        const clientId = random();
        const name = typeof b.client_name === 'string' ? b.client_name.trim().slice(0, 80) : 'Codex';
        await store.insert('national_focus_mcp_clients', { id: clientId, redirect_uris: b.redirect_uris, client_name: name || 'Codex' });
        return reply(201, { client_id: clientId, client_name: name || 'Codex', redirect_uris: b.redirect_uris,
          token_endpoint_auth_method: 'none', grant_types: ['authorization_code'], response_types: ['code'] });
      }
      if (request.method === 'GET' && path === '/authorize') {
        const ticket = url.searchParams.get('request');
        if (ticket) {
          if (!/^[a-f0-9]{64}$/.test(ticket)) return oauthError('invalid_request');
          const r = await store.one('national_focus_mcp_requests', 'request_hash', await hash(ticket));
          if (!r || r.consumed_at || Date.parse(String(r.expires_at)) <= Date.now()) return oauthError('invalid_request');
          if (r.grant_id && r.code_value) {
            const target = new URL(String(r.redirect_uri));
            target.searchParams.set('code', String(r.code_value));
            target.searchParams.set('state', String(r.state));
            target.searchParams.set('iss', issuer);
            return new Response(null, { status: 302, headers: { Location: target.toString(), 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' } });
          }
          return new Response(`Pacta 国策只读连接 / National Focus read-only connection\n\n在 Pacta App 登录，打开「我的 → 国策 AI 分析」，粘贴以下请求码，检查客户端并明确同意。\nSign in to Pacta, open My → National Focus AI, paste this request code, review and approve.\n\n${ticket}\n\n仅授权你本人最近手动上传的云快照元数据。有效期30分钟，不提供业务写入。\nOnly your latest manually uploaded snapshot metadata. Expires in 30 minutes. No business writes.\n\n请求码5分钟有效。请只批准你自己刚在 Codex 发起的连接，不要批准他人发来的码。\nRequest expires in 5 minutes. Only approve a connection you initiated in Codex; never approve a code sent by someone else.\n\nApp 确认成功后刷新本页面以返回 Codex。取消则关闭页面。\nAfter App approval, refresh this page to return to Codex. Close to cancel.`, { headers: {
            'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store',
            'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff',
          } });
        }
        const p = url.searchParams;
        const client = await store.one('national_focus_mcp_clients', 'id', p.get('client_id') ?? '');
        const redirect = p.get('redirect_uri') ?? '';
        const state = p.get('state') ?? '';
        const pkce = p.get('code_challenge') ?? '';
        if (!client || !Array.isArray(client.redirect_uris) || !client.redirect_uris.includes(redirect)
          || !redirectAllowed(redirect) || p.get('response_type') !== 'code' || p.get('scope') !== SCOPE
          || p.get('resource') !== resource || p.get('code_challenge_method') !== 'S256'
          || !/^[A-Za-z0-9_-]{43}$/.test(pkce) || state.length < 16 || state.length > 1024) {
          return oauthError('invalid_request');
        }
        const ticketValue = random();
        await store.insert('national_focus_mcp_requests', {
          request_hash: await hash(ticketValue), client_id: client.id, redirect_uri: redirect,
          resource, code_challenge: pkce, state,
        });
        const target = new URL(`${issuer}/authorize`);
        target.searchParams.set('request', ticketValue);
        return new Response(null, { status: 302, headers: { Location: target.toString(), 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' } });
      }
      if (request.method === 'POST' && path === '/token') {
        const b = new URLSearchParams(await request.text());
        const verifier = b.get('code_verifier') ?? '';
        if (!/^[a-f0-9]{64}$/.test(b.get('client_id') ?? '')
          || !/^[a-f0-9]{64}$/.test(b.get('code') ?? '') || !redirectAllowed(b.get('redirect_uri'))
          || b.get('grant_type') !== 'authorization_code' || !/^[A-Za-z0-9._~-]{43,128}$/.test(verifier)
          || b.get('resource') !== resource) return oauthError('invalid_grant');
        const token = `pacta_mcp_${random()}`;
        const data = await store.rpc('exchange_national_focus_mcp_code', {
          p_code_hash: await hash(b.get('code') ?? ''), p_client_id: b.get('client_id'),
          p_redirect_uri: b.get('redirect_uri'), p_resource: resource,
          p_code_challenge: await challenge(verifier), p_token_hash: await hash(token),
        }) as Record<string, unknown>;
        return reply(200, { access_token: token, token_type: 'Bearer', ...data });
      }
      if (path !== '/mcp') return reply(404, { error: 'not_found' });
      const token = request.headers.get('Authorization')?.match(/^Bearer (pacta_mcp_[a-f0-9]{64})$/)?.[1];
      if (!token) return unauthorized();
      // Even initialize/list/notifications must fail after revoke or suspension.
      const tokenHash = await hash(token);
      const metadata = await store.rpc('read_national_focus_mcp_metadata', { p_token_hash: tokenHash });
      if (request.method === 'GET' || request.method === 'DELETE') return reply(405, { error: 'method_not_allowed' }, { Allow: 'POST' });
      if (request.method !== 'POST') return reply(405, { error: 'method_not_allowed' });
      const b = await request.json();
      if (!object(b) || b.jsonrpc !== '2.0' || typeof b.method !== 'string'
        || (b.id !== undefined && typeof b.id !== 'string' && typeof b.id !== 'number')) {
        return reply(400, { jsonrpc: '2.0', id: null, error: { code: -32600, message: 'Invalid request' } });
      }
      if (b.id === undefined) return reply(202, undefined);
      const result = (value: unknown) => reply(200, { jsonrpc: '2.0', id: b.id, result: value });
      const failure = (code: number, message: string) => reply(200, { jsonrpc: '2.0', id: b.id, error: { code, message } });
      if (b.method === 'initialize') {
        const requested = object(b.params) ? b.params.protocolVersion : undefined;
        const version = typeof requested === 'string' && ['2025-03-26', '2025-06-18', '2025-11-25'].includes(requested)
          ? requested : '2025-11-25';
        return result({ protocolVersion: version,
          serverInfo: { name: 'pacta-national-focus', version: '1.0.0' }, capabilities: { tools: {} } });
      }
      if (b.method === 'ping') return result({});
      if (b.method === 'tools/list') return result({ tools: [tool] });
      if (b.method !== 'tools/call') return failure(-32601, 'Method not found');
      if (!object(b.params) || b.params.name !== tool.name) return failure(-32602, 'Unknown tool');
      const args = b.params.arguments ?? {};
      if (!object(args) || Object.keys(args).some((k) => k !== 'expected_revision')
        || (args.expected_revision !== undefined && (!Number.isSafeInteger(args.expected_revision) || Number(args.expected_revision) < 1))) {
        return failure(-32602, 'Invalid tool arguments');
      }
      let value = metadata;
      try {
        if (args.expected_revision !== undefined) value = await store.rpc('read_national_focus_mcp_metadata', {
          p_token_hash: tokenHash, p_expected_revision: args.expected_revision,
        });
      } catch (e) {
        if (e instanceof StoreError && e.code === 'PT409') return result({ isError: true,
          content: [{ type: 'text', text: JSON.stringify({ code: 'snapshot_changed', recovery: 'Read metadata again and restart analysis against the new revision.' }) }] });
        throw e;
      }
      return result({ content: [{ type: 'text', text: JSON.stringify(value) }], structuredContent: value });
    } catch (e) {
      if (e instanceof SyntaxError) return oauthError('invalid_request');
      if (e instanceof StoreError) {
        if (e.code === 'PT429') return oauthError('temporarily_unavailable', 429);
        if (e.code === '28000') return unauthorized();
        if (e.code === '42501') return oauthError('access_denied', 403);
        if (e.code === '22023') return oauthError(url.pathname.endsWith('/token') ? 'invalid_grant' : 'invalid_request');
      }
      // Do not forward database/Auth messages, payloads or credentials.
      return reply(503, { error: 'service_unavailable', recovery: 'Retry later. No business data was changed.' });
    }
  };
}
