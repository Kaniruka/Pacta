// Local synthetic MCP adapter. Runs the production handler over stdio JSON-RPC.
// The Store is synthetic, contains no credentials, and rejects every write.
import { createInterface } from 'node:readline';
import { readFileSync } from 'node:fs';
import { createHandler, type Store, StoreError, hash } from './handler.ts';
const issuer = 'https://example.supabase.co/functions/v1/national-focus-mcp';
const resource = `${issuer}/mcp`;
const token = `pacta_mcp_${'a'.repeat(64)}`;
const metadata = { contract_version: 1, status: 'available', revision: 2,
  source_device: { id: 'phone', name: 'Android' }, uploaded_at: '2026-10-22T08:00:00Z',
  data_updated_at: '2026-10-22T07:00:00Z', freshness: 'latest_manual_upload' };
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
      { user_id: 'private-user', id: 'version-a4', card_id: 'tree-a', version_number: 4,
        strengthening_level_number: 1, effective_trigger_condition: 'before 06:00',
        effective_action: 'read', scope: 'home', exception_notes: null,
        effective_from: epoch('2026-10-22T07:00:00Z'), effective_until: null,
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

const evidence = JSON.parse(readFileSync(new URL('../../../docs/evidence/issue61-handler-synthetic-tools.json', import.meta.url), 'utf8'));
const rename = (id: string | null) => id === 'root-parent' ? 'tree-a' : id === 'cascade-parent' ? 'tree-b' : id === 'root-deleted' ? 'deleted-d' : id;
const historicalFields: Record<string, string> = {
  trigger_condition: 'triggerCondition', exception_notes: 'exceptionNotes', is_in_tree: 'isInTree',
  parent_id: 'parentId', successful_days: 'successfulDays', current_consecutive_days: 'currentConsecutiveDays',
  best_consecutive_days: 'bestConsecutiveDays', maintenance_cycle_started: 'maintenanceCycleStarted',
  failure_reason: 'failureReason', cascade_source_card_id: 'cascadeSourceCardId', cascade_prior_state: 'cascadePriorState',
  active_strengthening_level: 'activeStrengtheningLevel', requirement_version_number: 'requirementVersionNumber',
  effective_trigger_condition: 'effectiveTriggerCondition', effective_action: 'effectiveAction',
  failure_source_card_id: 'failureSourceCardId', created_at: 'createdAt', updated_at: 'updatedAt',
};
const events = evidence.toolEvidence.flatMap((page: any) => page.result.events).map((event: any) => ({
  ...event, card_id: rename(event.card_id), checkpoint_at: epoch(event.checkpoint_at),
  tree_snapshot: JSON.stringify(event.tree_snapshot.map((card: any) => Object.fromEntries(
    Object.entries(card).map(([key, value]) => [historicalFields[key] ?? key,
      ['id', 'parent_id', 'cascade_source_card_id', 'failure_source_card_id'].includes(key) ? rename(value as string | null)
      : ['created_at', 'updated_at'].includes(key) ? epoch(value as string) : value])))),
}));
let revision = 2;
let historyReads = 0;
const store: Store = {
  async insert() { throw new Error('read-only fixture'); }, async one() { return null; },
  async rpc(name, args) {
    if (args.p_token_hash !== await hash(token)) throw new StoreError('28000');
    // Optional one-time race: the second history call changes revision during pagination.
    if (name === 'read_national_focus_mcp_history_snapshot' && (process.env.PACTA_EVAL_REVISION_RACE === '1' || process.argv.includes('--revision-race')) && ++historyReads === 2) revision = 3;
    if (args.p_expected_revision !== undefined && args.p_expected_revision !== revision) throw new StoreError('PT409');
    if (name === 'read_national_focus_mcp_metadata') return { ...metadata, revision };
    if (name === 'read_national_focus_mcp_snapshot') return { ...activeSnapshot, revision };
    if (name === 'read_national_focus_mcp_history_snapshot') return { ...metadata, revision,
      tables: (process.env.PACTA_EVAL_MISSING_HISTORY === '1' || process.argv.includes('--missing-history')) ? {} : { local_national_focus_failures: events } };
    throw new Error('unexpected RPC');
  },
};
const handler = createHandler({ issuer, store });
const input = createInterface({ input: process.stdin });
for await (const line of input) {
  if (!line.trim()) continue;
  const message = JSON.parse(line);
  const response = await handler(new Request(resource, { method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: line }));
  if (message.id !== undefined) process.stdout.write(JSON.stringify(await response.json()) + '\n');
}
