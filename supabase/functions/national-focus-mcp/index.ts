import { createHandler, StoreError, type Store } from './handler.ts';

function key(legacy: string, collection: string): string {
  const value = Deno.env.get(legacy);
  if (value) return value;
  const entries = JSON.parse(Deno.env.get(collection) ?? '{}') as Record<string, string>;
  return entries.default ?? Object.values(entries)[0] ?? '';
}
const base = Deno.env.get('SUPABASE_URL')!;
const service = key('SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_SECRET_KEYS');
async function db(path: string, init: RequestInit = {}): Promise<unknown> {
  const response = await fetch(`${base}/rest/v1/${path}`, { ...init, headers: {
    apikey: service, Authorization: `Bearer ${service}`, 'Content-Type': 'application/json', ...init.headers,
  } });
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw new StoreError(error.code ?? 'unavailable');
  }
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}
const store: Store = {
  async insert(table, value) { await db(table, { method: 'POST', body: JSON.stringify(value), headers: { Prefer: 'return=minimal' } }); },
  async one(table, field, value) {
    const q = new URLSearchParams({ [field]: `eq.${value}`, limit: '1', select: '*' });
    return ((await db(`${table}?${q}`)) as Record<string, unknown>[])[0] ?? null;
  },
  rpc(name, args) { return db(`rpc/${name}`, { method: 'POST', body: JSON.stringify(args) }); },

};
const issuer = Deno.env.get('PACTA_MCP_PUBLIC_URL');
if (!base || !service || !issuer) throw new Error('MCP environment incomplete');
Deno.serve(createHandler({ issuer, store }));
