import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler, hash, StoreError, type Store } from './handler.ts';
import { BUNDLED_SKILLS } from './skills_bundle.ts';

const issuer = 'https://example.supabase.co/functions/v1/national-focus-mcp';
const readonlyUrl = `${issuer}/mcp/readonly`;
const readwriteUrl = `${issuer}/mcp/readwrite`;
const aliasUrl = `${issuer}/mcp`;
const roToken = `pacta_mcp_${'a'.repeat(64)}`;
const rwToken = `pacta_mcp_${'b'.repeat(64)}`;
const ownerId = '11111111-1111-1111-1111-111111111111';

const epoch = (value: string) => Math.floor(Date.parse(value) / 1000);

function baseSnapshot() {
  return {
    contract_version: 1,
    status: 'available',
    revision: 2,
    source_device: { id: 'phone', name: 'Android' },
    uploaded_at: '2026-10-21T01:00:00Z',
    data_updated_at: '2026-10-20T23:00:00Z',
    freshness: 'latest_manual_upload',
    tables: {
      local_national_focus_cards: [
        {
          user_id: ownerId,
          id: 'tree-a',
          name: 'Shared name',
          trigger_condition: 'before 07:00',
          action: 'read',
          scope: 'home',
          exception_notes: null,
          is_in_tree: 1,
          parent_id: null,
          state: 'lit',
          successful_days: 60,
          current_consecutive_days: 4,
          best_consecutive_days: 9,
          maintenance_cycle_started: 1,
          failure_reason: null,
          cascade_source_card_id: null,
          cascade_prior_state: null,
          review_disposition: 'accepted',
          active_strengthening_level: 1,
          icon_key: 'lucide:book-open',
          created_at: epoch('2026-10-01T00:00:00Z'),
          updated_at: epoch('2026-10-20T00:00:00Z'),
          deleted_at: null,
        },
        {
          user_id: ownerId,
          id: 'tree-b',
          name: 'Shared name',
          trigger_condition: '',
          action: 'review',
          scope: null,
          exception_notes: 'skip when ill',
          is_in_tree: 1,
          parent_id: 'tree-a',
          state: 'pending_today_confirmation',
          successful_days: 2,
          current_consecutive_days: 2,
          best_consecutive_days: 2,
          maintenance_cycle_started: 1,
          failure_reason: null,
          cascade_source_card_id: null,
          cascade_prior_state: null,
          review_disposition: 'accepted',
          active_strengthening_level: null,
          icon_key: null,
          created_at: epoch('2026-10-02T00:00:00Z'),
          updated_at: epoch('2026-10-20T00:00:00Z'),
          deleted_at: null,
        },
        {
          user_id: ownerId,
          id: 'tree-extinguished',
          name: 'Extinguished root',
          trigger_condition: '',
          action: 'stretch',
          scope: null,
          exception_notes: null,
          is_in_tree: 1,
          parent_id: null,
          state: 'extinguished',
          successful_days: 1,
          current_consecutive_days: 0,
          best_consecutive_days: 1,
          maintenance_cycle_started: 1,
          failure_reason: 'missed',
          cascade_source_card_id: null,
          cascade_prior_state: null,
          review_disposition: 'accepted',
          active_strengthening_level: null,
          icon_key: null,
          created_at: epoch('2026-10-03T00:00:00Z'),
          updated_at: epoch('2026-10-20T00:00:00Z'),
          deleted_at: null,
        },
        {
          user_id: ownerId,
          id: 'library-c',
          name: 'Library card',
          trigger_condition: '',
          action: 'practice',
          scope: null,
          exception_notes: null,
          is_in_tree: 0,
          parent_id: null,
          state: 'extinguished',
          successful_days: 0,
          current_consecutive_days: 0,
          best_consecutive_days: 0,
          maintenance_cycle_started: 0,
          failure_reason: null,
          cascade_source_card_id: null,
          cascade_prior_state: null,
          review_disposition: 'accepted',
          active_strengthening_level: null,
          icon_key: null,
          created_at: epoch('2026-10-04T00:00:00Z'),
          updated_at: epoch('2026-10-20T00:00:00Z'),
          deleted_at: null,
        },
        {
          user_id: ownerId,
          id: 'deleted-d',
          name: 'Deleted card',
          trigger_condition: '',
          action: 'deleted',
          scope: null,
          exception_notes: null,
          is_in_tree: 0,
          parent_id: null,
          state: 'extinguished',
          successful_days: 0,
          current_consecutive_days: 0,
          best_consecutive_days: 0,
          maintenance_cycle_started: 0,
          failure_reason: null,
          cascade_source_card_id: null,
          cascade_prior_state: null,
          review_disposition: 'accepted',
          active_strengthening_level: null,
          icon_key: null,
          created_at: epoch('2026-10-05T00:00:00Z'),
          updated_at: epoch('2026-10-20T00:00:00Z'),
          deleted_at: epoch('2026-10-20T00:00:00Z'),
        },
      ],
      local_national_focus_strengthening_levels: [
        {
          user_id: ownerId,
          card_id: 'tree-a',
          level_number: 1,
          trigger_condition_override: 'before 06:00',
          action_override: null,
          created_at: epoch('2026-10-01T00:00:00Z'),
          updated_at: epoch('2026-10-20T00:00:00Z'),
        },
      ],
      local_national_focus_maintenance: [
        { user_id: ownerId, last_settled_checkpoint_at: epoch('2026-10-21T20:00:00Z') },
      ],
    },
  };
}

function fixture() {
  let denied = false;
  let unavailable = false;
  let snapshot = baseSnapshot();
  const auditLogs: Array<Record<string, unknown>> = [];
  let nextCardIndex = 1;

  const checkToken = async (tokenHash: unknown, requiredScope: unknown) => {
    const roHash = await hash(roToken);
    const rwHash = await hash(rwToken);
    if (denied) throw new StoreError('28000');
    if (tokenHash === rwHash) {
      return { grant_id: 'grant-rw', user_id: ownerId, label: 'Antigravity RW', scope: 'national_focus:readwrite' };
    }
    if (tokenHash === roHash) {
      if (requiredScope === 'national_focus:readwrite') throw new StoreError('42501');
      return { grant_id: 'grant-ro', user_id: ownerId, label: 'Codex Read', scope: 'national_focus:read' };
    }
    throw new StoreError('28000');
  };

  const store: Store = {
    async rpc(name, args) {
      if (unavailable) throw new StoreError('unavailable');
      if (name === 'verify_national_focus_mcp_grant') {
        return checkToken(args.p_token_hash, args.p_required_scope);
      }
      if (name === 'read_national_focus_mcp_metadata') {
        await checkToken(args.p_token_hash, args.p_required_scope);
        if (args.p_expected_revision !== undefined && args.p_expected_revision !== snapshot.revision) {
          throw new StoreError('PT409');
        }
        return {
          contract_version: snapshot.contract_version,
          status: snapshot.status,
          revision: snapshot.revision,
          source_device: snapshot.source_device,
          uploaded_at: snapshot.uploaded_at,
          data_updated_at: snapshot.data_updated_at,
          freshness: snapshot.freshness,
        };
      }
      if (name === 'read_national_focus_mcp_snapshot') {
        await checkToken(args.p_token_hash, 'national_focus:read');
        if (args.p_expected_revision !== undefined && args.p_expected_revision !== snapshot.revision) {
          throw new StoreError('PT409');
        }
        return snapshot;
      }
      if (name === 'record_national_focus_mcp_audit') {
        auditLogs.push(args);
        return null;
      }
      if (name === 'write_national_focus_mcp_snapshot') {
        const grant = await checkToken(args.p_token_hash, 'national_focus:readwrite');
        if (args.p_expected_revision !== snapshot.revision) throw new StoreError('PT409');
        snapshot = {
          ...snapshot,
          revision: snapshot.revision + 1,
          source_device: { id: `mcp:${grant.grant_id}`, name: `MCP · ${grant.label}` },
          uploaded_at: '2026-10-21T02:00:00Z',
          data_updated_at: '2026-10-21T02:00:00Z',
          tables: {
            ...snapshot.tables,
            local_national_focus_cards: args.p_cards as typeof snapshot.tables.local_national_focus_cards,
            local_national_focus_strengthening_levels:
              args.p_strengthening_levels as typeof snapshot.tables.local_national_focus_strengthening_levels,
          },
        };
        auditLogs.push({
          p_tool_name: args.p_tool_name,
          p_action_kind: 'write',
          p_summary: args.p_summary,
          p_snapshot_revision: snapshot.revision,
        });
        return {
          contract_version: snapshot.contract_version,
          status: snapshot.status,
          revision: snapshot.revision,
          source_device: snapshot.source_device,
          uploaded_at: snapshot.uploaded_at,
          data_updated_at: snapshot.data_updated_at,
          freshness: snapshot.freshness,
        };
      }
      throw new Error(`Unexpected RPC ${name}`);
    },
  };

  const handle = createHandler({
    issuer,
    store,
    now: () => new Date('2026-10-21T02:00:00Z'),
    newCardId: () => `new-card-${nextCardIndex++}`,
  });

  const post = (endpoint: string, body: unknown, token = roToken) =>
    handle(
      new Request(endpoint, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      }),
    );

  return {
    handle,
    post,
    auditLogs,
    setDenied: () => {
      denied = true;
    },
    setUnavailable: () => {
      unavailable = true;
    },
    bumpRevision: () => {
      snapshot.revision += 1;
    },
    getSnapshot: () => snapshot,
  };
}

const rpc = (method: string, params?: unknown) => ({ jsonrpc: '2.0', id: 1, method, params });

test('rejects unauthenticated requests and legacy OAuth DCR endpoints', async () => {
  const f = fixture();
  const missingAuth = await f.handle(new Request(readonlyUrl, { method: 'POST', body: '{}' }));
  assert.equal(missingAuth.status, 401);

  const legacyOAuth = await f.handle(new Request(`${issuer}/register`, { method: 'POST', body: '{}' }));
  assert.equal(legacyOAuth.status, 404);
});

test('readonly token works on /mcp and /mcp/readonly, and is rejected with 403 on /mcp/readwrite', async () => {
  const f = fixture();
  const initAlias = await (await f.post(aliasUrl, rpc('initialize'))).json();
  assert.match(initAlias.result.instructions, /Endpoint mode: readonly/);
  assert.match(initAlias.result.instructions, /better-national-focus/);
  assert.match(initAlias.result.instructions, /include_references/);

  const roTools = await (await f.post(readonlyUrl, rpc('tools/list'))).json();
  const names = roTools.result.tools.map((t: { name: string }) => t.name);
  assert.ok(names.includes('list_skills'));
  assert.ok(!names.includes('create_national_focus_card'));

  const escalated = await f.post(readwriteUrl, rpc('tools/list'), roToken);
  assert.equal(escalated.status, 403);
  assert.equal((await escalated.json()).error, 'insufficient_scope');
});

test('exposes bundled skills via tools, resources, and prompts', async () => {
  const f = fixture();
  assert.ok(BUNDLED_SKILLS.some((s) => s.name === 'better-national-focus'));

  const listSkills = await (await f.post(readonlyUrl, rpc('tools/call', { name: 'list_skills', arguments: {} }))).json();
  assert.equal(listSkills.result.isError, false);
  assert.equal(listSkills.result.structuredContent.skills[0].name, 'better-national-focus');

  const getRef = await (
    await f.post(
      readonlyUrl,
      rpc('tools/call', {
        name: 'get_skill',
        arguments: { name: 'better-national-focus', reference: 'references/card-design.md' },
      }),
    )
  ).json();
  assert.match(getRef.result.structuredContent.content, /国策卡设计法/);

  const getAll = await (
    await f.post(
      readonlyUrl,
      rpc('tools/call', {
        name: 'get_skill',
        arguments: { name: 'better-national-focus', include_references: true },
      }),
    )
  ).json();
  assert.match(getAll.result.structuredContent.content, /更好的国策/);
  assert.equal(getAll.result.structuredContent.references.length, 2);
  assert.match(getAll.result.structuredContent.references[0].content, /国策卡设计法/);
  assert.match(getAll.result.structuredContent.references[1].content, /国策树结构/);

  const treeRead = await (
    await f.post(readonlyUrl, rpc('tools/call', { name: 'get_national_focus_tree', arguments: { expected_revision: 2 } }))
  ).json();
  assert.equal(treeRead.result.structuredContent.skill_guidance.recommended_skill, 'better-national-focus');

  const resList = await (await f.post(readonlyUrl, rpc('resources/list'))).json();
  assert.ok(resList.result.resources.some((r: { uri: string }) => r.uri === 'pacta://skills/better-national-focus/SKILL.md'));

  const resRead = await (
    await f.post(readonlyUrl, rpc('resources/read', { uri: 'pacta://skills/better-national-focus/SKILL.md' }))
  ).json();
  assert.match(resRead.result.contents[0].text, /更好的国策/);

  const promptList = await (await f.post(readonlyUrl, rpc('prompts/list'))).json();
  assert.equal(promptList.result.prompts.length, 3);

  const promptGet = await (
    await f.post(readonlyUrl, rpc('prompts/get', { name: 'design_or_optimize_national_focus', arguments: { goal: '早睡' } }))
  ).json();
  assert.equal(promptGet.result.messages[0].content.type, 'resource');
  assert.match(promptGet.result.messages[0].content.resource.text, /更好的国策/);
  assert.equal(promptGet.result.messages[1].content.type, 'resource');
  assert.match(promptGet.result.messages[1].content.resource.text, /国策卡设计法/);
  assert.match(promptGet.result.messages[2].content.text, /早睡/);
});

test('readwrite creates, updates, moves, soft-deletes and restores cards with CAS and audit logs', async () => {
  const f = fixture();

  // 1. Create card in library
  const created = await (
    await f.post(
      readwriteUrl,
      rpc('tools/call', {
        name: 'create_national_focus_card',
        arguments: {
          expected_revision: 2,
          name: '先发制人',
          action: '起床后 30 分钟内禁用娱乐 App；仅做洗漱与早餐',
          icon_key: 'lucide:sunrise',
          strengthening_levels: [{ level_number: 1, action_override: '起床后 45 分钟内禁用娱乐 App' }],
          active_strengthening_level: 1,
        },
      }),
      rwToken,
    )
  ).json();
  assert.equal(created.result.isError, false);
  assert.equal(created.result.structuredContent.metadata.revision, 3);
  assert.equal(created.result.structuredContent.card.id, 'new-card-1');
  assert.equal(created.result.structuredContent.card.is_in_tree, false);
  assert.equal(created.result.structuredContent.card.state, 'extinguished');
  assert.equal(created.result.structuredContent.card.icon_key, 'lucide:sunrise');
  assert.equal(created.result.structuredContent.card.effective_requirements.action, '起床后 45 分钟内禁用娱乐 App');

  // 2. Stale CAS revision is rejected with snapshot_changed
  const stale = await (
    await f.post(
      readwriteUrl,
      rpc('tools/call', {
        name: 'update_national_focus_card',
        arguments: { expected_revision: 2, card_id: 'new-card-1', name: '过时版本' },
      }),
      rwToken,
    )
  ).json();
  assert.equal(stale.result.isError, true);
  assert.equal(stale.result.structuredContent.error.code, 'snapshot_changed');

  // 3. Forbidden runtime field is rejected
  const forbidden = await (
    await f.post(
      readwriteUrl,
      rpc('tools/call', {
        name: 'update_national_focus_card',
        arguments: { expected_revision: 3, card_id: 'tree-a', state: 'lit' },
      }),
      rwToken,
    )
  ).json();
  assert.equal(forbidden.error.code, -32602);

  // 4. Reject placing lit/pending branch under extinguished parent
  const badMove = await (
    await f.post(
      readwriteUrl,
      rpc('tools/call', {
        name: 'move_national_focus_card',
        arguments: { expected_revision: 3, card_id: 'tree-a', is_in_tree: true, parent_id: 'tree-extinguished' },
      }),
      rwToken,
    )
  ).json();
  assert.equal(badMove.result.isError, true);
  assert.equal(badMove.result.structuredContent.error.code, 'invalid_tree_placement');

  // 5. Move new card into tree under tree-a
  const movedIn = await (
    await f.post(
      readwriteUrl,
      rpc('tools/call', {
        name: 'move_national_focus_card',
        arguments: { expected_revision: 3, card_id: 'new-card-1', is_in_tree: true, parent_id: 'tree-a' },
      }),
      rwToken,
    )
  ).json();
  assert.equal(movedIn.result.isError, false);
  assert.equal(movedIn.result.structuredContent.metadata.revision, 4);
  assert.equal(movedIn.result.structuredContent.card.is_in_tree, true);
  assert.equal(movedIn.result.structuredContent.card.parent_id, 'tree-a');

  // 6. Move lit tree-a branch back to library transitions lit/pending nodes to pending_today_confirmation
  const movedOut = await (
    await f.post(
      readwriteUrl,
      rpc('tools/call', {
        name: 'move_national_focus_card',
        arguments: { expected_revision: 4, card_id: 'tree-a', is_in_tree: false },
      }),
      rwToken,
    )
  ).json();
  assert.equal(movedOut.result.isError, false);
  assert.equal(movedOut.result.structuredContent.metadata.revision, 5);
  assert.equal(movedOut.result.structuredContent.card.state, 'pending_today_confirmation');

  // 7. Soft-delete and restore library-c
  const softDeleted = await (
    await f.post(
      readwriteUrl,
      rpc('tools/call', {
        name: 'set_national_focus_card_deleted',
        arguments: { expected_revision: 5, card_id: 'library-c', deleted: true },
      }),
      rwToken,
    )
  ).json();
  assert.equal(softDeleted.result.isError, false);
  assert.equal(softDeleted.result.structuredContent.metadata.revision, 6);

  const restored = await (
    await f.post(
      readwriteUrl,
      rpc('tools/call', {
        name: 'set_national_focus_card_deleted',
        arguments: { expected_revision: 6, card_id: 'library-c', deleted: false },
      }),
      rwToken,
    )
  ).json();
  assert.equal(restored.result.isError, false);
  assert.equal(restored.result.structuredContent.metadata.revision, 7);
  assert.ok(f.auditLogs.some((entry) => entry.p_action_kind === 'write' && entry.p_snapshot_revision === 7));
});
