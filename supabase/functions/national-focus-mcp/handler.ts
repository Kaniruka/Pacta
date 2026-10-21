// No external runtime dependencies: this public boundary is tested as HTTP.
import { projectNationalFocusMetadata, projectNationalFocusSnapshot, projectNationalFocusHistory, nationalFocusDateBounds } from './projection.ts';

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
const metadataTool = {
  name: 'get_snapshot_metadata',
  description: 'Read metadata of your latest manual cloud upload. Does not upload, settle, or read National Focus content. No snapshot requires a manual upload in Pacta.',
  inputSchema: { type: 'object', properties: { expected_revision: { type: 'integer', minimum: 1 } }, additionalProperties: false },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};
const treeTool = {
  name: 'get_national_focus_tree',
  description: 'Read every current National Focus Tree card with stable ids, parent relations, rules, strengthening levels, requirement versions, state, streaks and internalization progress from your latest manual upload. Does not recompute the current time or read failure history.',
  inputSchema: { type: 'object', properties: { expected_revision: { type: 'integer', minimum: 1 } }, additionalProperties: false },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};
const libraryTool = {
  name: 'get_national_focus_library',
  description: 'Read every current independent National Focus Library card with stable ids, rules, strengthening levels, requirement versions, state, streaks and internalization progress from your latest manual upload. Does not recompute the current time or read failure history.',
  inputSchema: { type: 'object', properties: { expected_revision: { type: 'integer', minimum: 1 } }, additionalProperties: false },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};
const cardTool = {
  name: 'get_national_focus_card',
  description: 'Read one current National Focus card by stable card_id. expected_revision is required so the result stays on the snapshot version you are analyzing. Includes rules, strengthening levels, requirement versions, state, streaks and internalization progress; does not read failure history.',
  inputSchema: { type: 'object', properties: {
    card_id: { type: 'string', minLength: 1, maxLength: 200 },
    expected_revision: { type: 'integer', minimum: 1 },
  }, required: ['card_id', 'expected_revision'], additionalProperties: false },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};
const historyTool = {
  name: 'list_national_focus_failures',
  description: 'Read independent failure events and frozen trees from the latest manual upload. Dates are inclusive National Focus days beginning at fixed Beijing 04:00 (UTC+08); maximum 366 days, limit 1–100 (default 30). Sort checkpoint ascending then event id in code-point order. Subsequent pages require the same revision, dates and limit. Cascaded nodes are not independent failures. Original reasons and editable batch reflections are separate. Historical omissions are disclosed; successful_days is not a daily success log.',
  inputSchema: { type: 'object', properties: {
    start_date: { type: 'string', format: 'date' }, end_date: { type: 'string', format: 'date' },
    limit: { type: 'integer', minimum: 1, maximum: 100 }, cursor: { type: 'string', maxLength: 4096 },
    expected_revision: { type: 'integer', minimum: 1 },
  }, required: ['start_date', 'end_date'], additionalProperties: false },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};
const failureTool = {
  name: 'get_national_focus_failure',
  description: 'Read one independent failure event by stable event_id at expected_revision, including the immutable historical tree/rules, original reason and separate later shared reflection. Soft-deleted cards remain interpretable. No event writes or complete success timeline.',
  inputSchema: { type: 'object', properties: {
    event_id: { type: 'string', minLength: 1, maxLength: 200 }, expected_revision: { type: 'integer', minimum: 1 },
  }, required: ['event_id', 'expected_revision'], additionalProperties: false },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};
const tools = [metadataTool, treeTool, libraryTool, cardTool, historyTool, failureTool];
const toolNames = new Set(tools.map((item) => item.name));

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
          return new Response(`Pacta 国策只读连接 / National Focus read-only connection\n\n在 Pacta App 登录，打开「我的 → 国策 AI 分析」，粘贴以下请求码，检查客户端并明确同意。\nSign in to Pacta, open My → National Focus AI, paste this request code, review and approve.\n\n${ticket}\n\n仅授权读取你本人最近手动上传的国策树、卡片库、规则与进度，失败事件及冻结树、原始原因和后续反思，以及快照元数据。有效期30分钟，不提供业务写入。\nRead only your latest manually uploaded National Focus tree, library, rules, progress, failure events with frozen trees, original reasons, later reflections and snapshot metadata. Expires in 30 minutes. No business writes.\n\n请求码5分钟有效。请只批准你自己刚在 Codex 发起的连接，不要批准他人发来的码。\nRequest expires in 5 minutes. Only approve a connection you initiated in Codex; never approve a code sent by someone else.\n\nApp 确认成功后刷新本页面以返回 Codex。取消则关闭页面。\nAfter App approval, refresh this page to return to Codex. Close to cancel.`, { headers: {
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
      const failure = (code: number, message: string) => reply(200, { jsonrpc: '2.0', id: b.id, error: { code, message,
        data: { recovery: 'Call tools/list for supported tools and their input schemas. Use a positive snapshot revision for card details; do not pass user selectors or SQL.' } } });
      if (b.method === 'initialize') {
        const requested = object(b.params) ? b.params.protocolVersion : undefined;
        const version = typeof requested === 'string' && ['2025-03-26', '2025-06-18', '2025-11-25'].includes(requested)
          ? requested : '2025-11-25';
        return result({ protocolVersion: version,
          serverInfo: { name: 'pacta-national-focus', version: '1.0.0' }, capabilities: { tools: {} } });
      }
      if (b.method === 'ping') return result({});
      if (b.method === 'tools/list') return result({ tools });
      if (b.method !== 'tools/call') return failure(-32601, 'Method not found');
      if (!object(b.params) || typeof b.params.name !== 'string' || !toolNames.has(b.params.name)) return failure(-32602, 'Unknown tool');
      const name = b.params.name;
      const args = b.params.arguments ?? {};
      const isHistory = name === historyTool.name || name === failureTool.name;
      const allowedKeys = name === historyTool.name
        ? new Set(['start_date', 'end_date', 'limit', 'cursor', 'expected_revision'])
        : name === failureTool.name ? new Set(['event_id', 'expected_revision'])
        : name === cardTool.name ? new Set(['card_id', 'expected_revision']) : new Set(['expected_revision']);
      if (!object(args) || Object.keys(args).some((k) => !allowedKeys.has(k))
        || (args.expected_revision !== undefined && (!Number.isSafeInteger(args.expected_revision) || Number(args.expected_revision) < 1))
        || (name === cardTool.name && (typeof args.card_id !== 'string' || !args.card_id.trim() || args.card_id.length > 200
          || !Number.isSafeInteger(args.expected_revision) || Number(args.expected_revision) < 1))) {
        return failure(-32602, 'Invalid tool arguments');
      }
      const toolResult = (value: unknown, isError = false) => result({ isError,
        content: [{ type: 'text', text: JSON.stringify(value) }], structuredContent: value });
      try {
        if (name === metadataTool.name) {
          let value = metadata;
          if (args.expected_revision !== undefined) value = await store.rpc('read_national_focus_mcp_metadata', {
            p_token_hash: tokenHash, p_expected_revision: args.expected_revision,
          });
          return toolResult(projectNationalFocusMetadata(value));
        }
        if (isHistory) {
          const detail = name === failureTool.name;
          const limit = args.limit === undefined ? 30 : args.limit;
          const bounds = detail ? null : nationalFocusDateBounds(args.start_date as string, args.end_date as string);
          if ((detail && (typeof args.event_id !== 'string' || !args.event_id.trim() || args.event_id.length > 200
              || args.expected_revision === undefined))
            || (!detail && (!bounds || !Number.isSafeInteger(limit) || Number(limit) < 1 || Number(limit) > 100))
            || (args.cursor !== undefined && (typeof args.cursor !== 'string' || !args.cursor || args.cursor.length > 4096
              || args.expected_revision === undefined))) return failure(-32602, 'Invalid history arguments');
          let after: string | null = null;
          if (args.cursor !== undefined) {
            try {
              const cursor = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from(atob((args.cursor as string).replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0))));
              if (!object(cursor) || cursor.revision !== args.expected_revision || cursor.start_date !== args.start_date
                || cursor.end_date !== args.end_date || cursor.limit !== limit || typeof cursor.after_event_id !== 'string') {
                return failure(-32602, 'Cursor does not match query or revision');
              }
              after = cursor.after_event_id;
            } catch { return failure(-32602, 'Invalid cursor'); }
          }
          const rawHistory = await store.rpc('read_national_focus_mcp_history_snapshot', {
            p_token_hash: tokenHash, ...(args.expected_revision === undefined ? {} : { p_expected_revision: args.expected_revision }),
          });
          const history = projectNationalFocusHistory(rawHistory);
          if (args.expected_revision !== undefined && history.metadata.revision !== args.expected_revision) {
            return toolResult({ metadata: history.metadata, error: { code: 'snapshot_changed', recovery: 'Read metadata again and restart history queries.' } }, true);
          }
          const limitations = 'Only uploaded failure events are available; historical omissions are possible. Cumulative successful days are not daily success logs or a complete audit timeline. Frozen trees and original reasons are separate from editable batch reflections.';
          if (detail) {
            const event = history.events.find((item) => item.id === args.event_id) ?? null;
            return toolResult({ metadata: history.metadata, event, limitations,
              ...(history.metadata.status === 'available' && !event ? { error: { code: 'failure_not_found', recovery: 'List failures at this revision and use a returned event id.' } } : {}) }, history.metadata.status === 'available' && !event);
          }
          const events = history.events.filter((item) => Date.parse(item.checkpoint_at) >= bounds!.start_at
            && Date.parse(item.checkpoint_at) < bounds!.end_before);
          const offset = after === null ? 0 : events.findIndex((item) => item.id === after) + 1;
          if (after !== null && offset === 0) return failure(-32602, 'Cursor event is outside this query');
          const page = events.slice(offset, offset + Number(limit));
          const truncated = offset + page.length < events.length;
          const nextCursor = truncated ? btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify({ revision: history.metadata.revision,
            start_date: args.start_date, end_date: args.end_date, limit,
            after_event_id: page.at(-1)!.id })))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '') : null;
          return toolResult({ metadata: history.metadata, events: page, limitations,
            coverage: { start_date: args.start_date, end_date: args.end_date,
              start_at: new Date(bounds!.start_at).toISOString(), end_before: new Date(bounds!.end_before).toISOString(),
              timezone: 'UTC+08:00', checkpoint: '04:00', ordering: 'checkpoint_at ASC, id ASC (code-point)' },
            next_cursor: nextCursor, truncated });
        }
        const raw = await store.rpc('read_national_focus_mcp_snapshot', {
          p_token_hash: tokenHash,
          ...(args.expected_revision === undefined ? {} : { p_expected_revision: args.expected_revision }),
        });
        const projected = projectNationalFocusSnapshot(raw);
        if (args.expected_revision !== undefined && projected.metadata.revision !== args.expected_revision) {
          return toolResult({ metadata: projectNationalFocusMetadata(metadata), error: {
            code: 'snapshot_changed', recovery: 'Read metadata again and restart analysis against the new revision.',
          } }, true);
        }
        if (name === treeTool.name) {
          return toolResult({ metadata: projected.metadata,
            cards: projected.cards.filter((card) => card.is_in_tree), maintenance: projected.maintenance });
        }
        if (name === libraryTool.name) {
          return toolResult({ metadata: projected.metadata,
            cards: projected.cards.filter((card) => !card.is_in_tree), maintenance: projected.maintenance });
        }
        const card = projected.cards.find((item) => item.id === args.card_id) ?? null;
        if (projected.metadata.status !== 'available' || card) {
          return toolResult({ metadata: projected.metadata, card, maintenance: projected.maintenance });
        }
        return toolResult({ metadata: projected.metadata, card: null, maintenance: projected.maintenance,
          error: { code: 'card_not_found', recovery: 'Check card_id, then read the current tree or library at this revision.' } }, true);
      } catch (e) {
        if (e instanceof StoreError && e.code === 'PT409') return toolResult({ metadata: projectNationalFocusMetadata(metadata),
          error: { code: 'snapshot_changed', recovery: 'Read metadata again and restart analysis against the new revision.' } }, true);
        throw e;
      }
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
