// No external runtime dependencies: this public boundary is tested as HTTP.
import {
  projectNationalFocusMetadata,
  projectNationalFocusSnapshot,
  projectNationalFocusHistory,
  nationalFocusDateBounds,
} from './projection.ts';
import {
  applyCreateCard,
  applyUpdateCard,
  applyMoveCard,
  applySetCardDeleted,
  MutationError,
} from './mutations.ts';
import { BUNDLED_SKILLS } from './skills_bundle.ts';

export const READONLY_SCOPE = 'national_focus:read';
export const READWRITE_SCOPE = 'national_focus:readwrite';

export type McpEndpointMode = 'readonly' | 'readwrite';

export interface Store {
  rpc(name: string, args: Record<string, unknown>): Promise<unknown>;
}

export interface Config {
  issuer: string;
  store: Store;
  now?: () => Date;
  newCardId?: () => string;
}

export class StoreError extends Error {
  code: string;
  constructor(code: string) {
    super('Service operation failed');
    this.code = code;
  }
}

const object = (v: unknown): v is Record<string, unknown> =>
  v !== null && typeof v === 'object' && !Array.isArray(v);

export async function hash(value: string): Promise<string> {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))),
    (v) => v.toString(16).padStart(2, '0'),
  ).join('');
}

const metadataTool = {
  name: 'get_snapshot_metadata',
  description:
    'Read metadata of your latest cloud upload. Does not upload, settle, or read National Focus content.',
  inputSchema: {
    type: 'object',
    properties: { expected_revision: { type: 'integer', minimum: 1 } },
    additionalProperties: false,
  },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};

const treeTool = {
  name: 'get_national_focus_tree',
  description:
    'Read every current National Focus Tree card with stable ids, parent relations, rules, strengthening levels, custom icon keys (icon_key), state, streaks and internalization progress. For design or structural review, load built-in skill better-national-focus via get_skill(name: "better-national-focus", include_references: true) or pacta://skills/better-national-focus/SKILL.md.',
  inputSchema: {
    type: 'object',
    properties: { expected_revision: { type: 'integer', minimum: 1 } },
    additionalProperties: false,
  },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};

const libraryTool = {
  name: 'get_national_focus_library',
  description:
    'Read every current independent National Focus Library card with stable ids, rules, strengthening levels, custom icon keys (icon_key), state, streaks and internalization progress. Load built-in skill better-national-focus via get_skill(name: "better-national-focus", include_references: true) before designing or reorganizing cards.',
  inputSchema: {
    type: 'object',
    properties: { expected_revision: { type: 'integer', minimum: 1 } },
    additionalProperties: false,
  },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};

const cardTool = {
  name: 'get_national_focus_card',
  description:
    'Read one current National Focus card by stable card_id at expected_revision.',
  inputSchema: {
    type: 'object',
    properties: {
      card_id: { type: 'string', minLength: 1, maxLength: 200 },
      expected_revision: { type: 'integer', minimum: 1 },
    },
    required: ['card_id', 'expected_revision'],
    additionalProperties: false,
  },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};

const historyTool = {
  name: 'list_national_focus_failures',
  description:
    'Read independent failure events and frozen trees from the latest cloud upload. Dates are inclusive YYYY-MM-DD National Focus days beginning at 04:00 UTC+08:00; maximum 366 days, limit 1–100 (default 30).',
  inputSchema: {
    type: 'object',
    properties: {
      start_date: { type: 'string', format: 'date' },
      end_date: { type: 'string', format: 'date' },
      limit: { type: 'integer', minimum: 1, maximum: 100 },
      cursor: { type: 'string', maxLength: 4096 },
      expected_revision: { type: 'integer', minimum: 1 },
    },
    required: ['start_date', 'end_date'],
    additionalProperties: false,
  },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};

const failureTool = {
  name: 'get_national_focus_failure',
  description:
    'Read one independent failure event by stable event_id at expected_revision, including the immutable frozen tree/rules, original reason, and editable shared reflection.',
  inputSchema: {
    type: 'object',
    properties: {
      event_id: { type: 'string', minLength: 1, maxLength: 200 },
      expected_revision: { type: 'integer', minimum: 1 },
    },
    required: ['event_id', 'expected_revision'],
    additionalProperties: false,
  },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};

const listSkillsTool = {
  name: 'list_skills',
  description:
    'List built-in Pacta skills (including better-national-focus) and their reference paths.',
  inputSchema: { type: 'object', properties: {}, additionalProperties: false },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};

const getSkillTool = {
  name: 'get_skill',
  description:
    'Read a built-in skill SKILL.md, a specific reference file, or the skill together with all references (include_references: true).',
  inputSchema: {
    type: 'object',
    properties: {
      name: { type: 'string', minLength: 1, maxLength: 100 },
      reference: { type: 'string', minLength: 1, maxLength: 200 },
      include_references: { type: 'boolean' },
    },
    required: ['name'],
    additionalProperties: false,
  },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
};

const strengtheningLevelSchema = {
  type: 'object',
  properties: {
    level_number: { type: 'integer', minimum: 1, maximum: 5 },
    action_override: { type: ['string', 'null'] },
    trigger_condition_override: { type: ['string', 'null'] },
  },
  required: ['level_number'],
  additionalProperties: false,
};

const createCardTool = {
  name: 'create_national_focus_card',
  description:
    'Create a new National Focus card in the Library (extinguished, zeroed counters) with CAS expected_revision and automatic cloud backup. Follow the 4-field rule design principles in built-in skill better-national-focus (get_skill).',
  inputSchema: {
    type: 'object',
    properties: {
      expected_revision: { type: 'integer', minimum: 1 },
      name: { type: 'string', minLength: 1, maxLength: 120 },
      action: { type: 'string', minLength: 1, maxLength: 2000 },
      exception_notes: { type: ['string', 'null'], maxLength: 2000 },
      icon_key: { type: ['string', 'null'], maxLength: 100 },
      strengthening_levels: { type: 'array', maxItems: 5, items: strengtheningLevelSchema },
      active_strengthening_level: { type: ['integer', 'null'], minimum: 1, maximum: 5 },
    },
    required: ['expected_revision', 'name', 'action'],
    additionalProperties: false,
  },
  annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
};

const updateCardTool = {
  name: 'update_national_focus_card',
  description:
    'Update editable fields of an existing non-deleted National Focus card (name, action, exception_notes, icon_key, strengthening_levels, active_strengthening_level) following better-national-focus. Never alters state, streaks, or successful_days.',
  inputSchema: {
    type: 'object',
    properties: {
      expected_revision: { type: 'integer', minimum: 1 },
      card_id: { type: 'string', minLength: 1, maxLength: 200 },
      name: { type: 'string', minLength: 1, maxLength: 120 },
      action: { type: 'string', minLength: 1, maxLength: 2000 },
      exception_notes: { type: ['string', 'null'], maxLength: 2000 },
      icon_key: { type: ['string', 'null'], maxLength: 100 },
      strengthening_levels: { type: 'array', maxItems: 5, items: strengtheningLevelSchema },
      active_strengthening_level: { type: ['integer', 'null'], minimum: 1, maximum: 5 },
    },
    required: ['expected_revision', 'card_id'],
    additionalProperties: false,
  },
  annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
};

const moveCardTool = {
  name: 'move_national_focus_card',
  description:
    'Place a card into the National Focus Tree (with optional parent_id) or move a card branch back to the Library, following mounting trade-offs in better-national-focus. Rejects cycles and placing lit/pending branches under an extinguished parent.',
  inputSchema: {
    type: 'object',
    properties: {
      expected_revision: { type: 'integer', minimum: 1 },
      card_id: { type: 'string', minLength: 1, maxLength: 200 },
      is_in_tree: { type: 'boolean' },
      parent_id: { type: ['string', 'null'], maxLength: 200 },
    },
    required: ['expected_revision', 'card_id', 'is_in_tree'],
    additionalProperties: false,
  },
  annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
};

const setCardDeletedTool = {
  name: 'set_national_focus_card_deleted',
  description:
    'Soft-delete a Library card (must not be in tree) or restore a soft-deleted card to the Library. Preserves failure history; never hard-deletes.',
  inputSchema: {
    type: 'object',
    properties: {
      expected_revision: { type: 'integer', minimum: 1 },
      card_id: { type: 'string', minLength: 1, maxLength: 200 },
      deleted: { type: 'boolean' },
    },
    required: ['expected_revision', 'card_id', 'deleted'],
    additionalProperties: false,
  },
  annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false },
};

const READONLY_TOOLS = [
  metadataTool,
  treeTool,
  libraryTool,
  cardTool,
  historyTool,
  failureTool,
  listSkillsTool,
  getSkillTool,
];

const READWRITE_TOOLS = [
  ...READONLY_TOOLS,
  createCardTool,
  updateCardTool,
  moveCardTool,
  setCardDeletedTool,
];

const WRITE_TOOL_NAMES = new Set([
  createCardTool.name,
  updateCardTool.name,
  moveCardTool.name,
  setCardDeletedTool.name,
]);

const PROMPTS = [
  {
    name: 'analyze_national_focus_tree',
    description: '读取当前国策树与卡片库，应用 better-national-focus 方法论评估规则清晰度、低谷存活度与挂载结构。',
    arguments: [],
  },
  {
    name: 'review_national_focus_failures',
    description: '基于近 30 个国策日的失败记录与冻结树快照复盘失效原因，区分主动熄灭、漏确认与连带影响。',
    arguments: [
      {
        name: 'days',
        description: '可选回顾天数（1–366，默认 30）',
        required: false,
      },
    ],
  },
  {
    name: 'design_or_optimize_national_focus',
    description: '根据用户困扰或目标设计可直接填入（或在读写模式下写入）Pacta 的国策卡与树结构。',
    arguments: [
      {
        name: 'goal',
        description: '用户希望解决的困扰或拆解的目标',
        required: true,
      },
    ],
  },
];

function buildResources() {
  const resources: Array<{ uri: string; name: string; description: string; mimeType: string }> = [];
  for (const skill of BUNDLED_SKILLS) {
    resources.push({
      uri: skill.uri,
      name: `${skill.name} / SKILL.md`,
      description: skill.description,
      mimeType: 'text/markdown',
    });
    for (const ref of skill.references) {
      resources.push({
        uri: ref.uri,
        name: `${skill.name} / ${ref.path}`,
        description: `Reference for ${skill.name}: ${ref.path}`,
        mimeType: 'text/markdown',
      });
    }
  }
  return resources;
}

function readResourceByUri(uri: string): { uri: string; mimeType: string; text: string } | null {
  for (const skill of BUNDLED_SKILLS) {
    if (skill.uri === uri) {
      return { uri, mimeType: 'text/markdown', text: skill.skill_md };
    }
    for (const ref of skill.references) {
      if (ref.uri === uri) {
        return { uri, mimeType: 'text/markdown', text: ref.content };
      }
    }
  }
  return null;
}

const SKILL_GUIDANCE = {
  recommended_skill: 'better-national-focus',
  load_via_tool: 'get_skill({ "name": "better-national-focus", "include_references": true })',
  resources: BUNDLED_SKILLS.flatMap((s) => [s.uri, ...s.references.map((r) => r.uri)]),
};

function buildPromptSkillMessages(referencePath: string) {
  const skill = BUNDLED_SKILLS.find((s) => s.name === 'better-national-focus') ?? BUNDLED_SKILLS[0];
  if (!skill) return [];
  const messages: Array<{
    role: 'user';
    content: { type: 'resource'; resource: { uri: string; mimeType: string; text: string } };
  }> = [
    {
      role: 'user',
      content: {
        type: 'resource',
        resource: { uri: skill.uri, mimeType: 'text/markdown', text: skill.skill_md },
      },
    },
  ];
  const ref = skill.references.find((r) => r.path === referencePath);
  if (ref) {
    messages.push({
      role: 'user',
      content: {
        type: 'resource',
        resource: { uri: ref.uri, mimeType: 'text/markdown', text: ref.content },
      },
    });
  }
  return messages;
}

function buildInstructions(mode: McpEndpointMode): string {
  const skillsSummary = BUNDLED_SKILLS.map((s) => {
    const refs = s.references.map((r) => r.path).join(', ');
    return `${s.name} (${s.uri}${refs ? `; references: ${refs}` : ''}): ${s.description}`;
  }).join(' | ');
  return [
    'Pacta National Focus MCP v2.',
    `Endpoint mode: ${mode}.`,
    'Snapshots reflect the latest cloud upload (not live offline device state).',
    'Always start with get_snapshot_metadata, then pass its revision as expected_revision to every subsequent call; on snapshot_changed, discard partial results and restart from metadata.',
    `Built-in skills (auto-load before designing, splitting, redesigning, or reviewing National Focus cards and trees): ${skillsSummary}. Call get_skill({ "name": "better-national-focus", "include_references": true }) or read pacta://skills/better-national-focus/SKILL.md.`,
    mode === 'readwrite'
      ? 'Write tools (create_national_focus_card, update_national_focus_card, move_national_focus_card, set_national_focus_card_deleted) require expected_revision, create an automatic cloud history backup, and never alter lighting state, streaks, successful_days, or failure history. Remind the user to manually download in Pacta App if they want cloud edits on their device.'
      : 'This endpoint is strictly read-only; propose edits as 4-field card drafts for the user to apply manually.',
  ].join(' ');
}

export function createHandler(config: Config): (request: Request) => Promise<Response> {
  const { store } = config;
  const now = config.now ?? (() => new Date());
  const newCardId = config.newCardId ?? (() => crypto.randomUUID());
  const issuer = config.issuer.replace(/\/$/, '');

  const reply = (status: number, body: unknown, extra: Record<string, string> = {}) =>
    new Response(body === undefined ? null : JSON.stringify(body), {
      status,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
        'Referrer-Policy': 'no-referrer',
        ...extra,
      },
    });

  const unauthorized = () =>
    reply(401, {
      error: 'invalid_token',
      recovery: 'Create or renew a connection token in Pacta App: My -> National Focus AI Analysis.',
    });

  const forbiddenScope = () =>
    reply(403, {
      error: 'insufficient_scope',
      recovery: 'This token is read-only. Create a read-write token in Pacta App or connect to /mcp/readonly.',
    });

  return async (request) => {
    const url = new URL(request.url);
    const origin = request.headers.get('Origin');
    try {
      if (origin) return reply(403, { error: 'origin_denied' });

      const fullPrefix = new URL(issuer).pathname;
      const workerPrefix = `/${fullPrefix.split('/').filter(Boolean).at(-1)}`;
      const prefix = [fullPrefix, workerPrefix].find((p) => url.pathname.startsWith(`${p}/`));
      if (!prefix) return reply(404, { error: 'not_found' });

      const path = url.pathname.slice(prefix.length);
      let mode: McpEndpointMode | null = null;
      if (path === '/mcp' || path === '/mcp/readonly') {
        mode = 'readonly';
      } else if (path === '/mcp/readwrite') {
        mode = 'readwrite';
      } else {
        return reply(404, { error: 'not_found' });
      }

      const token = request.headers
        .get('Authorization')
        ?.match(/^Bearer (pacta_mcp_[a-f0-9]{64})$/)?.[1];
      if (!token) return unauthorized();

      const requiredScope = mode === 'readwrite' ? READWRITE_SCOPE : READONLY_SCOPE;
      const tokenHash = await hash(token);
      const metadata = await store.rpc('read_national_focus_mcp_metadata', {
        p_token_hash: tokenHash,
        p_required_scope: requiredScope,
      });

      if (request.method === 'GET' || request.method === 'DELETE') {
        return reply(405, { error: 'method_not_allowed' }, { Allow: 'POST' });
      }
      if (request.method !== 'POST') {
        return reply(405, { error: 'method_not_allowed' });
      }

      const b = await request.json();
      if (
        !object(b)
        || b.jsonrpc !== '2.0'
        || typeof b.method !== 'string'
        || (b.id !== undefined && typeof b.id !== 'string' && typeof b.id !== 'number')
      ) {
        return reply(400, { jsonrpc: '2.0', id: null, error: { code: -32600, message: 'Invalid request' } });
      }
      if (b.id === undefined) return reply(202, undefined);

      const result = (value: unknown) => reply(200, { jsonrpc: '2.0', id: b.id, result: value });
      const failure = (code: number, message: string) =>
        reply(200, {
          jsonrpc: '2.0',
          id: b.id,
          error: {
            code,
            message,
            data: {
              recovery:
                'Call tools/list for supported tools and schemas. Pass a positive expected_revision for details or mutations.',
            },
          },
        });

      if (b.method === 'initialize') {
        const requested = object(b.params) ? b.params.protocolVersion : undefined;
        const version =
          typeof requested === 'string' && ['2025-03-26', '2025-06-18', '2025-11-25'].includes(requested)
            ? requested
            : '2025-11-25';
        return result({
          protocolVersion: version,
          serverInfo: { name: 'pacta-national-focus', version: '2.0.0' },
          capabilities: { tools: {}, resources: {}, prompts: {} },
          instructions: buildInstructions(mode),
        });
      }

      if (b.method === 'ping') return result({});

      const activeTools = mode === 'readwrite' ? READWRITE_TOOLS : READONLY_TOOLS;
      const activeToolNames = new Set(activeTools.map((item) => item.name));

      if (b.method === 'tools/list') return result({ tools: activeTools });

      if (b.method === 'resources/list') {
        return result({ resources: buildResources() });
      }

      if (b.method === 'resources/read') {
        const uri = object(b.params) ? b.params.uri : undefined;
        if (typeof uri !== 'string' || !uri) return failure(-32602, 'Invalid resource uri');
        const content = readResourceByUri(uri);
        if (!content) return failure(-32602, 'Unknown resource uri');
        return result({ contents: [content] });
      }

      if (b.method === 'prompts/list') {
        return result({ prompts: PROMPTS });
      }

      if (b.method === 'prompts/get') {
        const promptName = object(b.params) ? b.params.name : undefined;
        const promptArgs = object(b.params) && object(b.params.arguments) ? b.params.arguments : {};
        if (promptName === 'analyze_national_focus_tree') {
          return result({
            description: PROMPTS[0].description,
            messages: [
              ...buildPromptSkillMessages('references/tree-and-recovery.md'),
              {
                role: 'user',
                content: {
                  type: 'text',
                  text: [
                    '已附带 better-national-focus 技能与树结构指南。',
                    '请调用 get_snapshot_metadata 获取 revision，并在同一 revision 下读取 get_national_focus_tree 与 get_national_focus_library。',
                    '按「事实 → 可能解释 → 可试行调整」分析规则清晰度、低谷存活度与树挂载结构；引用稳定 card_id，不编造未提供的数据。',
                  ].join('\n'),
                },
              },
            ],
          });
        }
        if (promptName === 'review_national_focus_failures') {
          const daysRaw = promptArgs.days;
          const days = typeof daysRaw === 'string' && /^\d+$/.test(daysRaw) ? Number(daysRaw) : 30;
          const boundedDays = Math.min(366, Math.max(1, days));
          return result({
            description: PROMPTS[1].description,
            messages: [
              ...buildPromptSkillMessages('references/tree-and-recovery.md'),
              {
                role: 'user',
                content: {
                  type: 'text',
                  text: [
                    '已附带 better-national-focus 技能与失败复盘指南。',
                    `请调用 get_snapshot_metadata 获取 revision，读取当前树与卡片库后，结合 maintenance.last_settled_checkpoint_at 锚定近 ${boundedDays} 个国策日窗口，通过 list_national_focus_failures（按 cursor 翻完分页）与 get_national_focus_failure 读取冻结快照。`,
                    '区分主动熄灭、未完成今日确认与级联连带熄灭，分开原始原因与后续反思；输出「事实 → 可能解释 → 可试行调整」。',
                  ].join('\n'),
                },
              },
            ],
          });
        }
        if (promptName === 'design_or_optimize_national_focus') {
          const goal = typeof promptArgs.goal === 'string' && promptArgs.goal.trim()
            ? promptArgs.goal.trim()
            : '（请向用户确认具体困扰或目标）';
          return result({
            description: PROMPTS[2].description,
            messages: [
              ...buildPromptSkillMessages('references/card-design.md'),
              {
                role: 'user',
                content: {
                  type: 'text',
                  text: [
                    '已附带 better-national-focus 技能与卡片设计指南。',
                    `围绕目标「${goal}」，先读取当前国策树与卡片库（如快照可用）评估现有基础，再设计低阻力、可自判、过低谷日的 4 字段卡片草案与建议挂载方案。`,
                    mode === 'readwrite'
                      ? '若用户确认采纳，再使用受限写入工具创建或更新卡片，并提醒用户在 Pacta App 手动从云端更新本机。'
                      : '当前为只读连接，给出 4 字段卡面草案供用户在 App 内手动填写。',
                  ].join('\n'),
                },
              },
            ],
          });
        }
        return failure(-32602, 'Unknown prompt');
      }

      if (b.method !== 'tools/call') return failure(-32601, 'Method not found');
      if (
        !object(b.params)
        || typeof b.params.name !== 'string'
        || !activeToolNames.has(b.params.name)
      ) {
        return failure(-32602, 'Unknown tool');
      }

      const name = b.params.name;
      const args = b.params.arguments ?? {};
      if (!object(args)) return failure(-32602, 'Invalid tool arguments');

      const toolResult = (value: unknown, isError = false) =>
        result({
          isError,
          content: [{ type: 'text', text: JSON.stringify(value) }],
          structuredContent: value,
        });

      const auditRead = async (summary: string, rev: unknown) => {
        try {
          await store.rpc('record_national_focus_mcp_audit', {
            p_token_hash: tokenHash,
            p_tool_name: name,
            p_action_kind: 'read',
            p_summary: summary,
            p_snapshot_revision: typeof rev === 'number' && Number.isSafeInteger(rev) ? rev : null,
          });
        } catch {
          // Best-effort read audit never masks successful reads.
        }
      };

      if (name === listSkillsTool.name) {
        if (Object.keys(args).length > 0) return failure(-32602, 'Invalid tool arguments');
        return toolResult({
          skills: BUNDLED_SKILLS.map((s) => ({
            name: s.name,
            description: s.description,
            uri: s.uri,
            references: s.references.map((r) => ({ path: r.path, uri: r.uri })),
          })),
        });
      }

      if (name === getSkillTool.name) {
        const allowed = new Set(['name', 'reference', 'include_references']);
        if (
          Object.keys(args).some((k) => !allowed.has(k))
          || typeof args.name !== 'string'
          || !args.name.trim()
          || (args.reference !== undefined && typeof args.reference !== 'string')
          || (args.include_references !== undefined && typeof args.include_references !== 'boolean')
        ) {
          return failure(-32602, 'Invalid tool arguments');
        }
        const skill = BUNDLED_SKILLS.find((s) => s.name === args.name || s.slug === args.name);
        if (!skill) {
          return toolResult({ error: { code: 'skill_not_found', message: `Skill "${args.name}" not found.` } }, true);
        }
        if (args.reference !== undefined) {
          const ref = skill.references.find((r) => r.path === args.reference || r.uri === args.reference);
          if (!ref) {
            return toolResult({
              error: { code: 'reference_not_found', message: `Reference "${args.reference}" not found.` },
            }, true);
          }
          return toolResult({ name: skill.name, path: ref.path, uri: ref.uri, content: ref.content });
        }
        const includeRefs = args.include_references === true;
        return toolResult({
          name: skill.name,
          description: skill.description,
          uri: skill.uri,
          content: skill.skill_md,
          references: skill.references.map((r) => ({
            path: r.path,
            uri: r.uri,
            ...(includeRefs ? { content: r.content } : {}),
          })),
        });
      }

      try {
        if (WRITE_TOOL_NAMES.has(name)) {
          const writeAllowedKeys =
            name === createCardTool.name
              ? new Set([
                  'expected_revision',
                  'name',
                  'action',
                  'exception_notes',
                  'icon_key',
                  'strengthening_levels',
                  'active_strengthening_level',
                ])
              : name === updateCardTool.name
                ? new Set([
                    'expected_revision',
                    'card_id',
                    'name',
                    'action',
                    'exception_notes',
                    'icon_key',
                    'strengthening_levels',
                    'active_strengthening_level',
                  ])
                : name === moveCardTool.name
                  ? new Set(['expected_revision', 'card_id', 'is_in_tree', 'parent_id'])
                  : new Set(['expected_revision', 'card_id', 'deleted']);
          if (Object.keys(args).some((k) => !writeAllowedKeys.has(k))) {
            return failure(-32602, 'Invalid or forbidden write arguments');
          }
          if (
            !Number.isSafeInteger(args.expected_revision)
            || Number(args.expected_revision) < 1
          ) {
            return failure(-32602, 'expected_revision is required for write tools');
          }
          const grantInfo = await store.rpc('verify_national_focus_mcp_grant', {
            p_token_hash: tokenHash,
            p_required_scope: READWRITE_SCOPE,
          }) as Record<string, unknown>;
          const ownerId = String(grantInfo.user_id ?? '');
          if (!ownerId) return unauthorized();

          const raw = await store.rpc('read_national_focus_mcp_snapshot', {
            p_token_hash: tokenHash,
            p_expected_revision: args.expected_revision,
          }) as Record<string, unknown>;
          const currentMeta = projectNationalFocusMetadata(raw);
          if (currentMeta.status !== 'available') {
            return toolResult({
              metadata: currentMeta,
              error: {
                code: currentMeta.status,
                recovery: 'Ensure a v4 Cloud Data Snapshot is uploaded in Pacta App before writing.',
              },
            }, true);
          }
          if (currentMeta.revision !== args.expected_revision) {
            return toolResult({
              metadata: currentMeta,
              error: { code: 'snapshot_changed', recovery: 'Read metadata again and retry against the new revision.' },
            }, true);
          }

          const rawTables = raw.tables as Record<string, unknown>;
          const nowEpoch = Math.floor(now().getTime() / 1000);
          let outcome;
          if (name === createCardTool.name) {
            outcome = applyCreateCard(rawTables, ownerId, args, nowEpoch, newCardId);
          } else if (name === updateCardTool.name) {
            outcome = applyUpdateCard(rawTables, ownerId, args, nowEpoch);
          } else if (name === moveCardTool.name) {
            outcome = applyMoveCard(rawTables, args, nowEpoch);
          } else {
            outcome = applySetCardDeleted(rawTables, args, nowEpoch);
          }

          const updatedMetaRaw = await store.rpc('write_national_focus_mcp_snapshot', {
            p_token_hash: tokenHash,
            p_expected_revision: args.expected_revision,
            p_cards: outcome.cards,
            p_strengthening_levels: outcome.strengtheningLevels,
            p_tool_name: name,
            p_summary: outcome.summary,
          });
          const updatedMeta = projectNationalFocusMetadata(updatedMetaRaw);
          const projected = projectNationalFocusSnapshot({
            ...updatedMeta,
            tables: {
              local_national_focus_cards: outcome.cards,
              local_national_focus_strengthening_levels: outcome.strengtheningLevels,
              local_national_focus_maintenance: rawTables.local_national_focus_maintenance ?? [],
            },
          });
          const mutatedCard = projected.cards.find((c) => c.id === outcome.mutatedCardId) ?? null;
          return toolResult({
            metadata: updatedMeta,
            card: mutatedCard,
            summary: outcome.summary,
            reminder: 'Cloud snapshot updated with automatic backup. Manually download in Pacta App to apply to a device.',
          });
        }

        const isHistory = name === historyTool.name || name === failureTool.name;
        const allowedKeys =
          name === historyTool.name
            ? new Set(['start_date', 'end_date', 'limit', 'cursor', 'expected_revision'])
            : name === failureTool.name
              ? new Set(['event_id', 'expected_revision'])
              : name === cardTool.name
                ? new Set(['card_id', 'expected_revision'])
                : new Set(['expected_revision']);
        if (
          Object.keys(args).some((k) => !allowedKeys.has(k))
          || (args.expected_revision !== undefined
            && (!Number.isSafeInteger(args.expected_revision) || Number(args.expected_revision) < 1))
          || (name === cardTool.name
            && (typeof args.card_id !== 'string'
              || !args.card_id.trim()
              || args.card_id.length > 200
              || !Number.isSafeInteger(args.expected_revision)
              || Number(args.expected_revision) < 1))
        ) {
          return failure(-32602, 'Invalid tool arguments');
        }

        if (name === metadataTool.name) {
          let value = metadata;
          if (args.expected_revision !== undefined) {
            value = await store.rpc('read_national_focus_mcp_metadata', {
              p_token_hash: tokenHash,
              p_expected_revision: args.expected_revision,
              p_required_scope: requiredScope,
            });
          }
          const projectedMeta = projectNationalFocusMetadata(value);
          await auditRead('读取云端快照元数据', projectedMeta.revision);
          return toolResult(projectedMeta);
        }

        if (isHistory) {
          const detail = name === failureTool.name;
          const limit = args.limit === undefined ? 30 : args.limit;
          const bounds = detail
            ? null
            : nationalFocusDateBounds(args.start_date as string, args.end_date as string);
          if (
            (detail
              && (typeof args.event_id !== 'string'
                || !args.event_id.trim()
                || args.event_id.length > 200
                || args.expected_revision === undefined))
            || (!detail && (!bounds || !Number.isSafeInteger(limit) || Number(limit) < 1 || Number(limit) > 100))
            || (args.cursor !== undefined
              && (typeof args.cursor !== 'string'
                || !args.cursor
                || args.cursor.length > 4096
                || args.expected_revision === undefined))
          ) {
            return failure(-32602, 'Invalid history arguments');
          }
          let after: string | null = null;
          if (args.cursor !== undefined) {
            try {
              const cursor = JSON.parse(
                new TextDecoder('utf-8', { fatal: true }).decode(
                  Uint8Array.from(
                    atob((args.cursor as string).replace(/-/g, '+').replace(/_/g, '/')),
                    (c) => c.charCodeAt(0),
                  ),
                ),
              );
              if (
                !object(cursor)
                || cursor.revision !== args.expected_revision
                || cursor.start_date !== args.start_date
                || cursor.end_date !== args.end_date
                || cursor.limit !== limit
                || typeof cursor.after_event_id !== 'string'
              ) {
                return failure(-32602, 'Cursor does not match query or revision');
              }
              after = cursor.after_event_id;
            } catch {
              return failure(-32602, 'Invalid cursor');
            }
          }
          const rawHistory = await store.rpc('read_national_focus_mcp_history_snapshot', {
            p_token_hash: tokenHash,
            ...(args.expected_revision === undefined ? {} : { p_expected_revision: args.expected_revision }),
          });
          const history = projectNationalFocusHistory(rawHistory);
          if (args.expected_revision !== undefined && history.metadata.revision !== args.expected_revision) {
            return toolResult(
              {
                metadata: history.metadata,
                error: { code: 'snapshot_changed', recovery: 'Read metadata again and restart history queries.' },
              },
              true,
            );
          }
          const limitations =
            'Only uploaded failure events are available; historical omissions are possible. Cumulative successful days are not daily success logs or a complete audit timeline. Frozen trees and original reasons are separate from editable batch reflections.';
          if (detail) {
            const event = history.events.find((item) => item.id === args.event_id) ?? null;
            await auditRead(`读取失败事件 ${String(args.event_id)}`, history.metadata.revision);
            return toolResult(
              {
                metadata: history.metadata,
                event,
                limitations,
                ...(history.metadata.status === 'available' && !event
                  ? {
                      error: {
                        code: 'failure_not_found',
                        recovery: 'List failures at this revision and use a returned event id.',
                      },
                    }
                  : {}),
              },
              history.metadata.status === 'available' && !event,
            );
          }
          const events = history.events.filter(
            (item) => Date.parse(item.checkpoint_at) >= bounds!.start_at && Date.parse(item.checkpoint_at) < bounds!.end_before,
          );
          const offset = after === null ? 0 : events.findIndex((item) => item.id === after) + 1;
          if (after !== null && offset === 0) return failure(-32602, 'Cursor event is outside this query');
          const page = events.slice(offset, offset + Number(limit));
          const truncated = offset + page.length < events.length;
          const nextCursor = truncated
            ? btoa(
                String.fromCharCode(
                  ...new TextEncoder().encode(
                    JSON.stringify({
                      revision: history.metadata.revision,
                      start_date: args.start_date,
                      end_date: args.end_date,
                      limit,
                      after_event_id: page.at(-1)!.id,
                    }),
                  ),
                ),
              )
                .replace(/\+/g, '-')
                .replace(/\//g, '_')
                .replace(/=+$/, '')
            : null;
          await auditRead(`查询失败记录 ${args.start_date}..${args.end_date}`, history.metadata.revision);
          return toolResult({
            metadata: history.metadata,
            events: page,
            limitations,
            coverage: {
              start_date: args.start_date,
              end_date: args.end_date,
              start_at: new Date(bounds!.start_at).toISOString(),
              end_before: new Date(bounds!.end_before).toISOString(),
              timezone: 'UTC+08:00',
              checkpoint: '04:00',
              ordering: 'checkpoint_at ASC, id ASC (code-point)',
            },
            next_cursor: nextCursor,
            truncated,
          });
        }

        const raw = await store.rpc('read_national_focus_mcp_snapshot', {
          p_token_hash: tokenHash,
          ...(args.expected_revision === undefined ? {} : { p_expected_revision: args.expected_revision }),
        });
        const projected = projectNationalFocusSnapshot(raw);
        if (args.expected_revision !== undefined && projected.metadata.revision !== args.expected_revision) {
          return toolResult(
            {
              metadata: projectNationalFocusMetadata(metadata),
              error: {
                code: 'snapshot_changed',
                recovery: 'Read metadata again and restart analysis against the new revision.',
              },
            },
            true,
          );
        }
        if (name === treeTool.name) {
          await auditRead('读取国策树', projected.metadata.revision);
          return toolResult({
            metadata: projected.metadata,
            cards: projected.cards.filter((card) => card.is_in_tree),
            maintenance: projected.maintenance,
            skill_guidance: SKILL_GUIDANCE,
          });
        }
        if (name === libraryTool.name) {
          await auditRead('读取国策卡片库', projected.metadata.revision);
          return toolResult({
            metadata: projected.metadata,
            cards: projected.cards.filter((card) => !card.is_in_tree),
            maintenance: projected.maintenance,
            skill_guidance: SKILL_GUIDANCE,
          });
        }
        const card = projected.cards.find((item) => item.id === args.card_id) ?? null;
        await auditRead(`读取国策卡 ${String(args.card_id)}`, projected.metadata.revision);
        if (projected.metadata.status !== 'available' || card) {
          return toolResult({
            metadata: projected.metadata,
            card,
            maintenance: projected.maintenance,
          });
        }
        return toolResult(
          {
            metadata: projected.metadata,
            card: null,
            maintenance: projected.maintenance,
            error: { code: 'card_not_found', recovery: 'Check card_id, then read the current tree or library at this revision.' },
          },
          true,
        );
      } catch (e) {
        if (e instanceof MutationError) {
          return toolResult(
            {
              metadata: projectNationalFocusMetadata(metadata),
              error: { code: e.code, message: e.message },
            },
            true,
          );
        }
        if (e instanceof StoreError && e.code === 'PT409') {
          return toolResult(
            {
              metadata: projectNationalFocusMetadata(metadata),
              error: { code: 'snapshot_changed', recovery: 'Read metadata again and restart analysis against the new revision.' },
            },
            true,
          );
        }
        throw e;
      }
    } catch (e) {
      if (e instanceof SyntaxError) return reply(400, { error: 'invalid_request' });
      if (e instanceof StoreError) {
        if (e.code === 'PT429') return reply(429, { error: 'temporarily_unavailable' });
        if (e.code === '28000') return unauthorized();
        if (e.code === '42501') return forbiddenScope();
        if (e.code === 'PT426') {
          return reply(409, {
            error: 'unsupported_snapshot',
            recovery: 'Update Pacta and manually upload a v4 snapshot before using MCP writes.',
          });
        }
        if (e.code === '22023') return reply(400, { error: 'invalid_request' });
      }
      return reply(503, { error: 'service_unavailable', recovery: 'Retry later. No business data was changed.' });
    }
  };
}
