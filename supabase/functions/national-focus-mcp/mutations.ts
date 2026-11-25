type JsonObject = Record<string, unknown>;

export class MutationError extends Error {
  code: string;
  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

export interface StrengtheningLevelInput {
  level_number: number;
  action_override?: string | null;
  trigger_condition_override?: string | null;
}

export interface MutationOutcome {
  cards: JsonObject[];
  strengtheningLevels: JsonObject[];
  mutatedCardId: string;
  summary: string;
}

const MAX_STRENGTHENING_LEVELS = 5;
const FORBIDDEN_READWRITE_KEYS = new Set([
  'state',
  'successful_days',
  'current_consecutive_days',
  'best_consecutive_days',
  'maintenance_cycle_started',
  'failure_reason',
  'cascade_source_card_id',
  'cascade_prior_state',
  'review_disposition',
  'created_at',
  'user_id',
]);

const isObject = (value: unknown): value is JsonObject =>
  value !== null && typeof value === 'object' && !Array.isArray(value);

const isTruthyBool = (value: unknown): boolean =>
  value === true || value === 1;

function requiredTrimmed(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new MutationError('invalid_argument', `${field} must be a non-empty string.`);
  }
  return value.trim();
}

function optionalTrimmed(value: unknown, field: string): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') {
    throw new MutationError('invalid_argument', `${field} must be a string or null.`);
  }
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function nextEpochSeconds(previousUpdatedAt: unknown, nowEpoch: number): number {
  const prev = typeof previousUpdatedAt === 'number' && Number.isSafeInteger(previousUpdatedAt)
    ? previousUpdatedAt
    : 0;
  return Math.max(nowEpoch, prev + 1);
}

function normalizeStrengtheningLevels(rawLevels: unknown): StrengtheningLevelInput[] {
  if (!Array.isArray(rawLevels)) {
    throw new MutationError('invalid_argument', 'strengthening_levels must be an array.');
  }
  if (rawLevels.length > MAX_STRENGTHENING_LEVELS) {
    throw new MutationError(
      'invalid_argument',
      `At most ${MAX_STRENGTHENING_LEVELS} strengthening levels are allowed.`,
    );
  }
  const parsed: StrengtheningLevelInput[] = rawLevels.map((item) => {
    if (!isObject(item)) {
      throw new MutationError('invalid_argument', 'Each strengthening level must be an object.');
    }
    const levelNumber = item.level_number;
    if (!Number.isSafeInteger(levelNumber) || Number(levelNumber) < 1 || Number(levelNumber) > MAX_STRENGTHENING_LEVELS) {
      throw new MutationError('invalid_argument', 'level_number must be an integer between 1 and 5.');
    }
    const actionOverride = optionalTrimmed(item.action_override, 'action_override');
    const triggerOverride = optionalTrimmed(item.trigger_condition_override, 'trigger_condition_override');
    if (actionOverride === null && triggerOverride === null) {
      throw new MutationError(
        'invalid_argument',
        `Strengthening level ${levelNumber} must provide action_override or trigger_condition_override.`,
      );
    }
    return {
      level_number: Number(levelNumber),
      action_override: actionOverride,
      trigger_condition_override: triggerOverride,
    };
  });
  parsed.sort((a, b) => a.level_number - b.level_number);
  for (let i = 0; i < parsed.length; i++) {
    if (parsed[i].level_number !== i + 1) {
      throw new MutationError('invalid_argument', 'Strengthening level numbers must be contiguous starting at 1.');
    }
  }
  return parsed;
}

function validateActiveLevel(active: unknown, levels: StrengtheningLevelInput[]): number | null {
  if (active === undefined || active === null) return null;
  if (!Number.isSafeInteger(active) || Number(active) < 1 || Number(active) > MAX_STRENGTHENING_LEVELS) {
    throw new MutationError('invalid_argument', 'active_strengthening_level must be null or 1..5.');
  }
  if (!levels.some((lvl) => lvl.level_number === active)) {
    throw new MutationError('invalid_argument', 'active_strengthening_level does not exist in strengthening_levels.');
  }
  return Number(active);
}

function rejectForbiddenArgs(args: JsonObject): void {
  for (const key of Object.keys(args)) {
    if (FORBIDDEN_READWRITE_KEYS.has(key)) {
      throw new MutationError('forbidden_field', `Field "${key}" cannot be mutated via MCP.`);
    }
  }
}

function cloneTables(rawTables: JsonObject): { cards: JsonObject[]; levels: JsonObject[] } {
  const rawCards = rawTables.local_national_focus_cards;
  const rawLevels = rawTables.local_national_focus_strengthening_levels;
  if (!Array.isArray(rawCards) || !Array.isArray(rawLevels)) {
    throw new MutationError('unsupported_snapshot', 'Snapshot tables are malformed.');
  }
  return {
    cards: rawCards.map((row) => ({ ...(row as JsonObject) })),
    levels: rawLevels.map((row) => ({ ...(row as JsonObject) })),
  };
}

function findCard(cards: JsonObject[], cardId: string): JsonObject {
  const card = cards.find((row) => row.id === cardId);
  if (!card) {
    throw new MutationError('card_not_found', `National Focus card "${cardId}" was not found.`);
  }
  return card;
}

function collectDescendants(rootId: string, cards: JsonObject[]): JsonObject[] {
  const childrenByParent = new Map<string, JsonObject[]>();
  for (const row of cards) {
    if (row.deleted_at !== null || !isTruthyBool(row.is_in_tree)) continue;
    const parentId = typeof row.parent_id === 'string' ? row.parent_id : null;
    if (!parentId) continue;
    const list = childrenByParent.get(parentId) ?? [];
    list.push(row);
    childrenByParent.set(parentId, list);
  }
  const result: JsonObject[] = [];
  const stack = [...(childrenByParent.get(rootId) ?? [])];
  const seen = new Set<string>([rootId]);
  while (stack.length > 0) {
    const next = stack.pop()!;
    const id = String(next.id);
    if (seen.has(id)) continue;
    seen.add(id);
    result.push(next);
    for (const child of childrenByParent.get(id) ?? []) {
      stack.push(child);
    }
  }
  return result;
}

export function applyCreateCard(
  rawTables: JsonObject,
  ownerId: string,
  args: JsonObject,
  nowEpoch: number,
  newId: () => string = () => crypto.randomUUID(),
): MutationOutcome {
  rejectForbiddenArgs(args);
  const name = requiredTrimmed(args.name, 'name');
  const action = requiredTrimmed(args.action, 'action');
  const exceptionNotes = optionalTrimmed(args.exception_notes, 'exception_notes');
  const iconKey = optionalTrimmed(args.icon_key, 'icon_key');
  const normalizedLevels = args.strengthening_levels === undefined
    ? []
    : normalizeStrengtheningLevels(args.strengthening_levels);
  const activeLevel = validateActiveLevel(args.active_strengthening_level, normalizedLevels);

  const { cards, levels } = cloneTables(rawTables);
  const id = newId();
  cards.push({
    user_id: ownerId,
    id,
    name,
    trigger_condition: '',
    action,
    scope: null,
    exception_notes: exceptionNotes,
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
    active_strengthening_level: activeLevel,
    icon_key: iconKey,
    created_at: nowEpoch,
    updated_at: nowEpoch,
    deleted_at: null,
  });
  for (const level of normalizedLevels) {
    levels.push({
      user_id: ownerId,
      card_id: id,
      level_number: level.level_number,
      trigger_condition_override: level.trigger_condition_override ?? null,
      action_override: level.action_override ?? null,
      created_at: nowEpoch,
      updated_at: nowEpoch,
    });
  }
  return {
    cards,
    strengtheningLevels: levels,
    mutatedCardId: id,
    summary: `创建国策卡「${name}」`,
  };
}

export function applyUpdateCard(
  rawTables: JsonObject,
  ownerId: string,
  args: JsonObject,
  nowEpoch: number,
): MutationOutcome {
  rejectForbiddenArgs(args);
  const cardId = requiredTrimmed(args.card_id, 'card_id');
  const { cards, levels } = cloneTables(rawTables);
  const card = findCard(cards, cardId);
  if (card.deleted_at !== null) {
    throw new MutationError('card_deleted', 'Soft-deleted card must be restored before editing.');
  }

  const nextName = args.name !== undefined ? requiredTrimmed(args.name, 'name') : String(card.name);
  const nextAction = args.action !== undefined ? requiredTrimmed(args.action, 'action') : String(card.action);
  const nextExceptionNotes = args.exception_notes !== undefined
    ? optionalTrimmed(args.exception_notes, 'exception_notes')
    : (card.exception_notes as string | null);
  const nextIconKey = args.icon_key !== undefined
    ? optionalTrimmed(args.icon_key, 'icon_key')
    : (('icon_key' in card ? card.icon_key : null) as string | null);

  const existingCardLevels = levels
    .filter((lvl) => lvl.card_id === cardId)
    .sort((a, b) => Number(a.level_number) - Number(b.level_number));

  const nextLevelsInput: StrengtheningLevelInput[] = args.strengthening_levels !== undefined
    ? normalizeStrengtheningLevels(args.strengthening_levels)
    : existingCardLevels.map((lvl) => ({
        level_number: Number(lvl.level_number),
        action_override: (lvl.action_override as string | null) ?? null,
        trigger_condition_override: (lvl.trigger_condition_override as string | null) ?? null,
      }));

  const targetActive = args.active_strengthening_level !== undefined
    ? args.active_strengthening_level
    : card.active_strengthening_level;
  const nextActiveLevel = validateActiveLevel(targetActive, nextLevelsInput);
  const updatedAt = nextEpochSeconds(card.updated_at, nowEpoch);

  card.name = nextName;
  card.action = nextAction;
  card.exception_notes = nextExceptionNotes;
  card.icon_key = nextIconKey;
  card.active_strengthening_level = nextActiveLevel;
  card.updated_at = updatedAt;

  let finalLevels = levels;
  if (args.strengthening_levels !== undefined) {
    const createdAtByLevel = new Map<number, unknown>(
      existingCardLevels.map((lvl) => [Number(lvl.level_number), lvl.created_at]),
    );
    finalLevels = levels.filter((lvl) => lvl.card_id !== cardId);
    for (const lvl of nextLevelsInput) {
      finalLevels.push({
        user_id: ownerId,
        card_id: cardId,
        level_number: lvl.level_number,
        trigger_condition_override: lvl.trigger_condition_override ?? null,
        action_override: lvl.action_override ?? null,
        created_at: createdAtByLevel.get(lvl.level_number) ?? updatedAt,
        updated_at: updatedAt,
      });
    }
  }

  return {
    cards,
    strengtheningLevels: finalLevels,
    mutatedCardId: cardId,
    summary: `更新国策卡「${nextName}」`,
  };
}

export function applyMoveCard(
  rawTables: JsonObject,
  args: JsonObject,
  nowEpoch: number,
): MutationOutcome {
  rejectForbiddenArgs(args);
  const cardId = requiredTrimmed(args.card_id, 'card_id');
  if (typeof args.is_in_tree !== 'boolean') {
    throw new MutationError('invalid_argument', 'is_in_tree must be a boolean.');
  }
  const { cards, levels } = cloneTables(rawTables);
  const card = findCard(cards, cardId);
  if (card.deleted_at !== null) {
    throw new MutationError('card_deleted', 'Soft-deleted card must be restored before moving.');
  }

  if (args.is_in_tree) {
    const parentId = optionalTrimmed(args.parent_id, 'parent_id');
    const byId = new Map(cards.map((row) => [String(row.id), row]));
    let hasExtinguishedAncestor = false;
    if (parentId !== null) {
      if (parentId === cardId) {
        throw new MutationError('invalid_tree_placement', 'A card cannot be its own parent.');
      }
      const parent = byId.get(parentId);
      if (!parent || parent.deleted_at !== null || !isTruthyBool(parent.is_in_tree)) {
        throw new MutationError('invalid_tree_placement', 'Target parent must exist in the current tree.');
      }
      let cursor: string | null = parentId;
      const visited = new Set<string>();
      while (cursor !== null) {
        if (cursor === cardId) {
          throw new MutationError('invalid_tree_placement', 'Cannot place a card under its own descendant.');
        }
        if (visited.has(cursor)) {
          throw new MutationError('invalid_tree_placement', 'Existing tree contains a cycle.');
        }
        visited.add(cursor);
        const ancestor = byId.get(cursor);
        if (!ancestor || ancestor.deleted_at !== null || !isTruthyBool(ancestor.is_in_tree)) {
          throw new MutationError('invalid_tree_placement', 'Target ancestor chain is invalid.');
        }
        if (ancestor.state === 'extinguished') {
          hasExtinguishedAncestor = true;
        }
        cursor = typeof ancestor.parent_id === 'string' ? ancestor.parent_id : null;
      }
    }

    if (hasExtinguishedAncestor) {
      const branch = [card, ...collectDescendants(cardId, cards)];
      if (branch.some((node) => node.state === 'lit' || node.state === 'pending_today_confirmation')) {
        throw new MutationError(
          'invalid_tree_placement',
          'Cannot move a lit or pending branch under an extinguished parent.',
        );
      }
    }

    card.is_in_tree = 1;
    card.parent_id = parentId;
    card.updated_at = nextEpochSeconds(card.updated_at, nowEpoch);
    return {
      cards,
      strengtheningLevels: levels,
      mutatedCardId: cardId,
      summary: parentId === null
        ? `将「${card.name}」设为国策树根节点`
        : `将「${card.name}」移入国策树`,
    };
  }

  // Move card and all in-tree descendants back to library.
  if (isTruthyBool(card.is_in_tree)) {
    const branch = [card, ...collectDescendants(cardId, cards)];
    for (const node of branch) {
      const needsRelight =
        node.state === 'lit'
        || node.state === 'pending_today_confirmation'
        || node.cascade_prior_state === 'lit'
        || node.cascade_prior_state === 'pending_today_confirmation';
      node.is_in_tree = 0;
      node.parent_id = null;
      if (needsRelight) {
        node.state = 'pending_today_confirmation';
      }
      node.cascade_source_card_id = null;
      node.cascade_prior_state = null;
      node.updated_at = nextEpochSeconds(node.updated_at, nowEpoch);
    }
  }
  return {
    cards,
    strengtheningLevels: levels,
    mutatedCardId: cardId,
    summary: `将「${card.name}」移回卡片库`,
  };
}

export function applySetCardDeleted(
  rawTables: JsonObject,
  args: JsonObject,
  nowEpoch: number,
): MutationOutcome {
  rejectForbiddenArgs(args);
  const cardId = requiredTrimmed(args.card_id, 'card_id');
  if (typeof args.deleted !== 'boolean') {
    throw new MutationError('invalid_argument', 'deleted must be a boolean.');
  }
  const { cards, levels } = cloneTables(rawTables);
  const card = findCard(cards, cardId);

  if (args.deleted) {
    if (isTruthyBool(card.is_in_tree)) {
      throw new MutationError('invalid_card_state', 'Move the card to library before deleting.');
    }
    if (cards.some((row) => row.deleted_at === null && row.parent_id === cardId)) {
      throw new MutationError('invalid_card_state', 'Move child branch to library before deleting.');
    }
    if (card.deleted_at === null) {
      const ts = nextEpochSeconds(card.updated_at, nowEpoch);
      card.deleted_at = ts;
      card.updated_at = ts;
    }
    return {
      cards,
      strengtheningLevels: levels,
      mutatedCardId: cardId,
      summary: `软删除国策卡「${card.name}」`,
    };
  }

  if (card.deleted_at === null) {
    throw new MutationError('invalid_card_state', 'Card is not deleted.');
  }
  card.deleted_at = null;
  card.is_in_tree = 0;
  card.parent_id = null;
  card.updated_at = nextEpochSeconds(card.updated_at, nowEpoch);
  return {
    cards,
    strengtheningLevels: levels,
    mutatedCardId: cardId,
    summary: `恢复国策卡「${card.name}」到卡片库`,
  };
}
