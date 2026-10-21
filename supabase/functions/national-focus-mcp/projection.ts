type JsonObject = Record<string, unknown>;

const object = (value: unknown): value is JsonObject =>
  value !== null && typeof value === 'object' && !Array.isArray(value);

const SNAPSHOT_RECOVERY = 'Update Pacta and manually upload a whole-data snapshot.';
const STATUS_VALUES = new Set([
  'available', 'no_snapshot', 'legacy_snapshot', 'unsupported_snapshot',
]);
const CARD_STATES = new Set(['lit', 'pending_today_confirmation', 'extinguished']);
const ISO_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/i;

export interface NationalFocusMetadata extends JsonObject {
  contract_version: 1;
  status: 'available' | 'no_snapshot' | 'legacy_snapshot' | 'unsupported_snapshot';
  revision: number | null;
}

export interface ProjectedNationalFocusCard extends JsonObject {
  id: string;
  name: string;
  trigger_condition: string;
  action: string;
  scope: string | null;
  exception_notes: string | null;
  is_in_tree: boolean;
  parent_id: string | null;
  state: string;
  successful_days: number;
  current_consecutive_days: number;
  best_consecutive_days: number;
  maintenance_cycle_started: boolean;
  failure_reason: string | null;
  cascade_source_card_id: string | null;
  cascade_prior_state: string | null;
  active_strengthening_level: number | null;
  internalization_progress_percent: number;
  effective_requirements: JsonObject;
  current_requirement_version: JsonObject;
  strengthening_levels: JsonObject[];
  requirement_versions: JsonObject[];
}

export interface NationalFocusProjection {
  metadata: NationalFocusMetadata;
  cards: ProjectedNationalFocusCard[];
  maintenance: { last_settled_checkpoint_at: string } | null;
}

interface CardRecord {
  id: string;
  name: string;
  trigger_condition: string;
  action: string;
  scope: string | null;
  exception_notes: string | null;
  is_in_tree: boolean;
  parent_id: string | null;
  state: string;
  successful_days: number;
  current_consecutive_days: number;
  best_consecutive_days: number;
  maintenance_cycle_started: boolean;
  failure_reason: string | null;
  cascade_source_card_id: string | null;
  cascade_prior_state: string | null;
  active_strengthening_level: number | null;
  deleted_at: string | null;
}

interface StrengtheningLevel {
  card_id: string;
  level_number: number;
  trigger_condition_override: string | null;
  action_override: string | null;
}

interface RequirementVersion {
  id: string;
  card_id: string;
  version_number: number;
  strengthening_level_number: number | null;
  effective_trigger_condition: string;
  effective_action: string;
  scope: string | null;
  exception_notes: string | null;
  effective_from: string;
  effective_until: string | null;
}

function fail(): never {
  throw new TypeError('Unsupported National Focus snapshot');
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function requiredString(row: JsonObject, key: string, allowEmpty = false): string {
  const value = row[key];
  if (typeof value !== 'string' || (!allowEmpty && value.trim().length === 0)) return fail();
  return value;
}

function nullableString(row: JsonObject, key: string): string | null {
  const value = row[key];
  if (value === null) return null;
  if (typeof value !== 'string') return fail();
  return value;
}

function requiredBoolean(row: JsonObject, key: string): boolean {
  const value = row[key];
  if (typeof value === 'boolean') return value;
  if (Number.isSafeInteger(value) && (value === 0 || value === 1)) return value === 1;
  return fail();
}

function integer(row: JsonObject, key: string, min = 0, max = Number.MAX_SAFE_INTEGER): number {
  const value = row[key];
  if (!Number.isSafeInteger(value) || Number(value) < min || Number(value) > max) return fail();
  return Number(value);
}

function nullableInteger(row: JsonObject, key: string, min: number, max: number): number | null {
  const value = row[key];
  if (value === null) return null;
  if (!Number.isSafeInteger(value) || Number(value) < min || Number(value) > max) return fail();
  return Number(value);
}

function timestamp(value: unknown, optional: boolean): string | null {
  if (optional && value === null) return null;
  // CloudSnapshotRepository serializes DateTime columns to epoch seconds.
  // Convert that stored value for MCP display without deriving any new time.
  if (Number.isSafeInteger(value)) {
    const date = new Date(Number(value) * 1000);
    if (Number.isNaN(date.getTime())) return fail();
    return date.toISOString();
  }
  if (typeof value !== 'string' || !ISO_TIMESTAMP.test(value) || Number.isNaN(Date.parse(value))) return fail();
  return value;
}

function timestampField(row: JsonObject, key: string, optional = false): string | null {
  return timestamp(row[key], optional);
}

function recordArray(tables: JsonObject, key: string): JsonObject[] {
  const value = tables[key];
  if (!Array.isArray(value) || !value.every(object)) return fail();
  return value;
}

function projectMetadata(value: unknown): NationalFocusMetadata {
  if (!object(value)) return fail();
  const status = value.status;
  if (value.contract_version !== 1 || typeof status !== 'string' || !STATUS_VALUES.has(status)) return fail();
  const revision = value.revision;
  if (revision !== null && (!Number.isSafeInteger(revision) || Number(revision) < 1)) return fail();

  const metadata: JsonObject = { contract_version: 1, status, revision };
  if ('source_device' in value) {
    const source = value.source_device;
    if (source === null) metadata.source_device = null;
    else {
      if (!object(source) || !nonEmptyString(source.id) || !nonEmptyString(source.name)) return fail();
      metadata.source_device = { id: source.id, name: source.name };
    }
  }
  for (const key of ['uploaded_at', 'data_updated_at'] as const) {
    if (key in value) metadata[key] = timestamp(value[key], true);
  }
  if ('freshness' in value) {
    if (!nonEmptyString(value.freshness)) return fail();
    metadata.freshness = value.freshness;
  }
  if ('recovery' in value) {
    if (!nonEmptyString(value.recovery)) return fail();
    metadata.recovery = value.recovery;
  }
  return metadata as NationalFocusMetadata;
}

function safeUnsupportedMetadata(value: unknown): NationalFocusMetadata {
  const fallback: JsonObject = {
    contract_version: 1,
    status: 'unsupported_snapshot',
    revision: null,
    source_device: null,
    uploaded_at: null,
    recovery: SNAPSHOT_RECOVERY,
  };
  if (object(value)) {
    if (Number.isSafeInteger(value.revision) && Number(value.revision) >= 1) fallback.revision = value.revision;
    if (value.source_device === null) fallback.source_device = null;
    else if (object(value.source_device) && nonEmptyString(value.source_device.id)
      && nonEmptyString(value.source_device.name)) {
      fallback.source_device = { id: value.source_device.id, name: value.source_device.name };
    }
    for (const key of ['uploaded_at', 'data_updated_at'] as const) {
      if (value[key] === null) fallback[key] = null;
      else if (typeof value[key] === 'string' && ISO_TIMESTAMP.test(value[key])
        && !Number.isNaN(Date.parse(value[key]))) fallback[key] = value[key];
    }
    if (nonEmptyString(value.freshness)) fallback.freshness = value.freshness;
  }
  return fallback as NationalFocusMetadata;
}

export function projectNationalFocusMetadata(value: unknown): NationalFocusMetadata {
  try {
    return projectMetadata(value);
  } catch {
    return safeUnsupportedMetadata(value);
  }
}

function projectCard(value: JsonObject): CardRecord {
  const state = requiredString(value, 'state');
  const cascadePriorState = nullableString(value, 'cascade_prior_state');
  if (!CARD_STATES.has(state) || (cascadePriorState !== null && !CARD_STATES.has(cascadePriorState))) return fail();
  const card: CardRecord = {
    id: requiredString(value, 'id'),
    name: requiredString(value, 'name'),
    trigger_condition: requiredString(value, 'trigger_condition', true),
    action: requiredString(value, 'action'),
    scope: nullableString(value, 'scope'),
    exception_notes: nullableString(value, 'exception_notes'),
    is_in_tree: requiredBoolean(value, 'is_in_tree'),
    parent_id: nullableString(value, 'parent_id'),
    state,
    successful_days: integer(value, 'successful_days'),
    current_consecutive_days: integer(value, 'current_consecutive_days'),
    best_consecutive_days: integer(value, 'best_consecutive_days'),
    maintenance_cycle_started: requiredBoolean(value, 'maintenance_cycle_started'),
    failure_reason: nullableString(value, 'failure_reason'),
    cascade_source_card_id: nullableString(value, 'cascade_source_card_id'),
    cascade_prior_state: cascadePriorState,
    active_strengthening_level: nullableInteger(value, 'active_strengthening_level', 1, 5),
    deleted_at: timestampField(value, 'deleted_at', true),
  };
  if (card.current_consecutive_days > card.best_consecutive_days) return fail();
  return card;
}

function projectStrengtheningLevel(value: JsonObject): StrengtheningLevel {
  const level: StrengtheningLevel = {
    card_id: requiredString(value, 'card_id'),
    level_number: integer(value, 'level_number', 1, 5),
    trigger_condition_override: nullableString(value, 'trigger_condition_override'),
    action_override: nullableString(value, 'action_override'),
  };
  if (level.trigger_condition_override === null && level.action_override === null) return fail();
  return level;
}

function projectRequirementVersion(value: JsonObject): RequirementVersion {
  const version = {
    id: requiredString(value, 'id'),
    card_id: requiredString(value, 'card_id'),
    version_number: integer(value, 'version_number', 1),
    strengthening_level_number: nullableInteger(value, 'strengthening_level_number', 1, 5),
    effective_trigger_condition: requiredString(value, 'effective_trigger_condition', true),
    effective_action: requiredString(value, 'effective_action'),
    scope: nullableString(value, 'scope'),
    exception_notes: nullableString(value, 'exception_notes'),
    effective_from: timestampField(value, 'effective_from')!,
    effective_until: timestampField(value, 'effective_until', true),
  };
  if (version.effective_until !== null
    && Date.parse(version.effective_until) < Date.parse(version.effective_from)) return fail();
  return version;
}

function publicRequirementVersion(version: RequirementVersion): JsonObject {
  return {
    id: version.id,
    version_number: version.version_number,
    strengthening_level_number: version.strengthening_level_number,
    effective_trigger_condition: version.effective_trigger_condition,
    effective_action: version.effective_action,
    scope: version.scope,
    exception_notes: version.exception_notes,
    effective_from: version.effective_from,
    effective_until: version.effective_until,
  };
}

function ensureTreeRelations(cards: Map<string, CardRecord>): void {
  const treeCards = [...cards.values()].filter((card) => card.deleted_at === null && card.is_in_tree);
  for (const card of treeCards) {
    if (card.parent_id === null) continue;
    const parent = cards.get(card.parent_id);
    if (!parent || parent.deleted_at !== null || !parent.is_in_tree || parent.id === card.id) return fail();
  }
  const colors = new Map<string, 0 | 1 | 2>();
  const visit = (card: CardRecord): void => {
    const color = colors.get(card.id) ?? 0;
    if (color === 1) return fail();
    if (color === 2) return;
    colors.set(card.id, 1);
    if (card.parent_id !== null) visit(cards.get(card.parent_id)!);
    colors.set(card.id, 2);
  };
  for (const card of treeCards) visit(card);
  for (const card of cards.values()) {
    if (card.deleted_at === null && !card.is_in_tree && card.parent_id !== null) return fail();
  }
}

function projectAvailableSnapshot(raw: JsonObject, metadata: NationalFocusMetadata): NationalFocusProjection {
  if (!object(raw.tables)) return fail();
  const tables = raw.tables;
  const rawCards = recordArray(tables, 'local_national_focus_cards').map(projectCard);
  const allCards = new Map<string, CardRecord>();
  for (const card of rawCards) {
    if (allCards.has(card.id)) return fail();
    allCards.set(card.id, card);
  }
  ensureTreeRelations(allCards);

  const levelsByCard = new Map<string, StrengtheningLevel[]>();
  const seenLevels = new Set<string>();
  for (const rawLevel of recordArray(tables, 'local_national_focus_strengthening_levels')) {
    const level = projectStrengtheningLevel(rawLevel);
    if (!allCards.has(level.card_id)) return fail();
    const key = `${level.card_id}\u0000${level.level_number}`;
    if (seenLevels.has(key)) return fail();
    seenLevels.add(key);
    const levels = levelsByCard.get(level.card_id) ?? [];
    levels.push(level);
    levelsByCard.set(level.card_id, levels);
  }
  for (const card of allCards.values()) {
    const levels = levelsByCard.get(card.id) ?? [];
    if (card.active_strengthening_level !== null
      && !levels.some((level) => level.level_number === card.active_strengthening_level)) return fail();
    levels.sort((a, b) => a.level_number - b.level_number);
  }

  const versionsByCard = new Map<string, RequirementVersion[]>();
  const seenVersionIds = new Set<string>();
  const seenVersions = new Set<string>();
  for (const rawVersion of recordArray(tables, 'local_national_focus_requirement_versions')) {
    const version = projectRequirementVersion(rawVersion);
    if (!allCards.has(version.card_id) || seenVersionIds.has(version.id)) return fail();
    const key = `${version.card_id}\u0000${version.version_number}`;
    if (seenVersions.has(key)) return fail();
    seenVersionIds.add(version.id);
    seenVersions.add(key);
    const versions = versionsByCard.get(version.card_id) ?? [];
    versions.push(version);
    versionsByCard.set(version.card_id, versions);
  }
  for (const versions of versionsByCard.values()) versions.sort((a, b) => a.version_number - b.version_number);

  const currentVersionByCard = new Map<string, RequirementVersion>();
  for (const card of allCards.values()) {
    if (card.deleted_at !== null) continue;
    const current = (versionsByCard.get(card.id) ?? []).filter((version) => version.effective_until === null);
    if (current.length !== 1) return fail();
    const version = current[0];
    const activeLevel = card.active_strengthening_level === null ? null
      : (levelsByCard.get(card.id) ?? []).find((level) => level.level_number === card.active_strengthening_level);
    const expectedTrigger = activeLevel?.trigger_condition_override ?? card.trigger_condition;
    const expectedAction = activeLevel?.action_override ?? card.action;
    if (version.strengthening_level_number !== card.active_strengthening_level
      || version.effective_trigger_condition !== expectedTrigger
      || version.effective_action !== expectedAction
      || version.scope !== card.scope || version.exception_notes !== card.exception_notes) return fail();
    currentVersionByCard.set(card.id, version);
  }

  const rawMaintenance = recordArray(tables, 'local_national_focus_maintenance');
  if (rawMaintenance.length > 1) return fail();
  const maintenance = rawMaintenance.length === 0 ? null : {
    last_settled_checkpoint_at: timestampField(rawMaintenance[0], 'last_settled_checkpoint_at')!,
  };

  const cards = [...allCards.values()]
    .filter((card) => card.deleted_at === null)
    .sort((a, b) => a.id.localeCompare(b.id))
    .map((card): ProjectedNationalFocusCard => ({
      id: card.id,
      name: card.name,
      trigger_condition: card.trigger_condition,
      action: card.action,
      scope: card.scope,
      exception_notes: card.exception_notes,
      is_in_tree: card.is_in_tree,
      parent_id: card.parent_id,
      state: card.state,
      successful_days: card.successful_days,
      current_consecutive_days: card.current_consecutive_days,
      best_consecutive_days: card.best_consecutive_days,
      maintenance_cycle_started: card.maintenance_cycle_started,
      failure_reason: card.failure_reason,
      cascade_source_card_id: card.cascade_source_card_id,
      cascade_prior_state: card.cascade_prior_state,
      active_strengthening_level: card.active_strengthening_level,
      internalization_progress_percent: 100 * (1 - Math.exp(-card.successful_days / 60)),
      effective_requirements: {
        strengthening_level_number: currentVersionByCard.get(card.id)!.strengthening_level_number,
        trigger_condition: currentVersionByCard.get(card.id)!.effective_trigger_condition,
        action: currentVersionByCard.get(card.id)!.effective_action,
        scope: currentVersionByCard.get(card.id)!.scope,
        exception_notes: currentVersionByCard.get(card.id)!.exception_notes,
      },
      current_requirement_version: publicRequirementVersion(currentVersionByCard.get(card.id)!),
      strengthening_levels: (levelsByCard.get(card.id) ?? []).map((level) => ({
        level_number: level.level_number,
        trigger_condition_override: level.trigger_condition_override,
        action_override: level.action_override,
      })),
      requirement_versions: (versionsByCard.get(card.id) ?? []).map(publicRequirementVersion),
    }));
  return { metadata, cards, maintenance };
}

/**
 * Projects the service-only SQL snapshot into the MCP contract. Only the
 * National Focus fields listed here can cross the public HTTP boundary.
 */
export function projectNationalFocusSnapshot(value: unknown): NationalFocusProjection {
  const raw = object(value) ? value : {};
  try {
    const metadata = projectMetadata(raw);
    if (metadata.status !== 'available') return { metadata, cards: [], maintenance: null };
    return projectAvailableSnapshot(raw, metadata);
  } catch {
    return { metadata: safeUnsupportedMetadata(raw), cards: [], maintenance: null };
  }
}

export interface ProjectedNationalFocusFailure extends JsonObject {
  id: string;
  batch_id: string;
  card_id: string;
  checkpoint_at: string;
  national_focus_date: string;
  cause: string;
  failure_reason: string | null;
  shared_explanation: string | null;
  review_disposition: string;
  tree_snapshot: JsonObject[];
}

export interface NationalFocusHistoryProjection {
  metadata: NationalFocusMetadata;
  events: ProjectedNationalFocusFailure[];
}

const DAY_MS = 86_400_000;
// Beijing 04:00 is the previous UTC calendar date at 20:00. No device clock
// or settlement is involved: these bounds only classify stored event instants.
export function nationalFocusDateBounds(start: unknown, end: unknown):
  { start_at: number; end_before: number } | null {
  const parse = (value: unknown): number | null => {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
    const instant = Date.parse(`${value}T00:00:00.000Z`);
    if (!Number.isFinite(instant) || new Date(instant).toISOString().slice(0, 10) !== value) return null;
    return instant;
  };
  const first = parse(start), last = parse(end);
  if (first === null || last === null || last < first || last - first >= 366 * DAY_MS) return null;
  return { start_at: first - 4 * 3_600_000, end_before: last + DAY_MS - 4 * 3_600_000 };
}

function compareCodePoints(a: string, b: string): number {
  const left = Array.from(a), right = Array.from(b);
  for (let i = 0; i < Math.min(left.length, right.length); i++) {
    const difference = left[i].codePointAt(0)! - right[i].codePointAt(0)!;
    if (difference !== 0) return difference;
  }
  return left.length - right.length;
}

function validateFrozenTree(cards: JsonObject[], sourceId: string): void {
  const byId = new Map(cards.map((card) => [card.id as string, card]));
  if (byId.size !== cards.length || !byId.has(sourceId)) return fail();
  for (const edge of ['parent_id', 'cascade_source_card_id', 'failure_source_card_id']) {
    const settled = new Set<string>();
    for (const card of cards) {
      const path = new Set<string>();
      let current: JsonObject | undefined = card;
      while (current) {
        const id = current.id as string;
        if (settled.has(id)) break;
        if (path.has(id)) return fail();
        path.add(id);
        const target = current[edge] as string | null;
        if (target === null) break;
        if (!byId.has(target)) return fail();
        // Independent failure sources point to themselves, unlike tree/cascade edges.
        if (edge === 'failure_source_card_id' && target === id) break;
        current = byId.get(target);
      }
      for (const id of path) settled.add(id);
    }
  }
}

function frozenCard(value: JsonObject): JsonObject {
  const state = requiredString(value, 'state');
  const prior = nullableString(value, 'cascadePriorState');
  if (!CARD_STATES.has(state) || (prior !== null && !CARD_STATES.has(prior))) return fail();
  const result: JsonObject = { state };
  const strings: Record<string, string> = {
    id: 'id', name: 'name', triggerCondition: 'trigger_condition', action: 'action',
  };
  for (const [source, target] of Object.entries(strings)) {
    result[target] = requiredString(value, source, source === 'triggerCondition');
  }
  const nullable: Record<string, string> = {
    scope: 'scope', exceptionNotes: 'exception_notes', parentId: 'parent_id',
    failureReason: 'failure_reason', cascadeSourceCardId: 'cascade_source_card_id',
  };
  for (const [source, target] of Object.entries(nullable)) result[target] = nullableString(value, source);
  // Older frozen snapshots lack these rule-version/failure-source fields.
  for (const [source, target] of Object.entries({
    effectiveTriggerCondition: 'effective_trigger_condition', effectiveAction: 'effective_action',
    failureSourceCardId: 'failure_source_card_id',
  })) result[target] = source in value ? nullableString(value, source) : null;
  result.cascade_prior_state = prior;
  result.is_in_tree = requiredBoolean(value, 'isInTree');
  result.maintenance_cycle_started = requiredBoolean(value, 'maintenanceCycleStarted');
  for (const [source, target] of Object.entries({
    successfulDays: 'successful_days', currentConsecutiveDays: 'current_consecutive_days',
    bestConsecutiveDays: 'best_consecutive_days',
  })) result[target] = integer(value, source);
  result.active_strengthening_level = 'activeStrengtheningLevel' in value
    ? nullableInteger(value, 'activeStrengtheningLevel', 1, 5) : null;
  result.requirement_version_number = 'requirementVersionNumber' in value
    ? nullableInteger(value, 'requirementVersionNumber', 1, Number.MAX_SAFE_INTEGER) : null;
  result.created_at = timestampField(value, 'createdAt');
  result.updated_at = timestampField(value, 'updatedAt');
  return result;
}

/** Whitelist only persisted failure facts; never merge with today's tree. */
export function projectNationalFocusHistory(value: unknown): NationalFocusHistoryProjection {
  const raw = object(value) ? value : {};
  try {
    const metadata = projectMetadata(raw);
    if (metadata.status !== 'available') return { metadata, events: [] };
    if (!object(raw.tables)) return fail();
    const seen = new Set<string>();
    const events = recordArray(raw.tables, 'local_national_focus_failures').map((row): ProjectedNationalFocusFailure => {
      const id = requiredString(row, 'id');
      if (seen.has(id)) return fail();
      seen.add(id);
      const cause = requiredString(row, 'cause');
      if (!['missed_confirmation', 'active_extinguish'].includes(cause)) return fail();
      const review = 'review_disposition' in row ? requiredString(row, 'review_disposition') : 'accepted';
      if (!['accepted', 'pending_review'].includes(review)) return fail();
      const checkpoint = timestampField(row, 'checkpoint_at')!;
      const encodedTree = row.tree_snapshot;
      if (typeof encodedTree !== 'string') return fail();
      const tree: unknown = JSON.parse(encodedTree);
      if (!Array.isArray(tree) || !tree.every(object)) return fail();
      const cards = tree.map(frozenCard);
      const cardId = requiredString(row, 'card_id');
      validateFrozenTree(cards, cardId);
      return {
        id, batch_id: requiredString(row, 'batch_id'), card_id: cardId,
        checkpoint_at: checkpoint,
        national_focus_date: new Date(Date.parse(checkpoint) + 4 * 3_600_000).toISOString().slice(0, 10),
        cause, failure_reason: nullableString(row, 'failure_reason'),
        shared_explanation: nullableString(row, 'shared_explanation'),
        review_disposition: review, tree_snapshot: cards,
      };
    });
    events.sort((a, b) => Date.parse(a.checkpoint_at) - Date.parse(b.checkpoint_at)
      || compareCodePoints(a.id, b.id));
    return { metadata, events };
  } catch {
    return { metadata: safeUnsupportedMetadata(raw), events: [] };
  }
}
