# Pacta MCP v1 interpretation

Current tools: `get_snapshot_metadata({expected_revision?})`, `get_national_focus_tree({expected_revision?})`, `get_national_focus_library({expected_revision?})`, `get_national_focus_card({card_id,expected_revision})`. Additional arguments, user selectors and arbitrary SQL are invalid. Available empty collections contain `cards: []`. `snapshot_changed` requires restarting the coherent read. `card_not_found` is not an empty collection.

A card has stable `id`, `name`, `is_in_tree`, `parent_id`, `state`, base `trigger_condition`, `action`, `scope`, `exception_notes`, `active_strengthening_level`, `effective_requirements`, `current_requirement_version`, `strengthening_levels`, `requirement_versions` and progress. Version entries identify the immutable effective requirement text, strengthening level and validity period; `effective_until: null` denotes the active version. Up to five user-created strengthening levels supplement the base. Selecting a level starts a version; it does not rewrite earlier versions.

- `lit`: uploaded Lit state.
- `pending_today_confirmation`: visually unlit, awaiting today's validity confirmation, without failure merely from this state.
- `extinguished`: formally extinguished, requiring separate manual lighting.
- Checkpoint: fixed 04:00 Beijing time (UTC+08:00), independent of device timezone. At settlement pending nodes fail; surviving lit nodes become pending for the next National Focus Day. The MCP only exposes the uploaded maintenance checkpoint; do not advance states using your current clock.
- Internalization Progress: cumulative successful National Focus Days displayed as a familiarity proxy, not measured habit formation, strengthening level or complete daily calendar. Current/best consecutive records are separate.

## Failure history

Use this procedure for failure review; structure-only review can stay with current tree/library evidence.

### Window and coherent pagination

The default is the recent 30 National Focus days represented by the uploaded maintenance checkpoint. Convert `maintenance.last_settled_checkpoint_at` to Beijing time (UTC+08:00); its date is inclusive `end_date`, and `start_date` is 29 calendar days earlier. For example, checkpoint `2026-10-21T20:00:00Z` is Beijing 2026-10-22 04:00, so request `2026-09-23` through `2026-10-22`. This window classifies recorded event timestamps, including missed confirmations recorded at that checkpoint; it does not assert when failed behavior occurred. Never substitute the agent's current date or upload time for this anchor. If maintenance/checkpoint is missing, report the unknown anchor and obtain an explicit date range; current structure analysis can continue.

`list_national_focus_failures({start_date,end_date,expected_revision?,limit?,cursor?})` accepts exact `YYYY-MM-DD` inclusive National Focus day start dates, at most 366 days per request. A date means 04:00 that day to 04:00 the next day in Beijing; an event exactly on the checkpoint belongs to the day beginning there. Set `expected_revision` to the acquired snapshot revision, including the first page. `limit` is 1–100 (default 30). Ordering is `checkpoint_at ASC`, then stable event `id ASC`.

Read returned `coverage`, `limitations`, `truncated` and `next_cursor`. Follow each opaque `next_cursor` with identical dates, limit and revision until it is null. If stopping early, disclose pages/events read, returned coverage, truncation and the remaining cursor; a first page is not the full window. Returned date bounds define the query coverage, not proof that the snapshot contains every historical event. An available `events: []` means no uploaded records in that range, not no real failures or complete history.

For an earlier-history request, use explicit earlier windows, splitting ranges exceeding 366 days. Report each window and its completion separately. Include historical cards regardless of current tree/library membership or today's effective rules. `snapshot_changed` on any page/detail invalidates the coherent analysis: discard prior pages, details and cursors, reacquire metadata/tree/library, recompute the default window from the new maintenance checkpoint (preserve explicitly requested dates), then restart history. A cursor mismatch/invalid argument is an input failure, not empty history.

### Frozen evidence and interpretation

`get_national_focus_failure({event_id,expected_revision})` returns `{metadata,event,limitations}` and the full frozen tree. Obtain it for every event used in a substantive finding; do not resolve a historical card through today's card details. `failure_not_found` means the requested event is unavailable, not that the history is empty. Missing/legacy/unsupported snapshot and auth/service errors retain their distinct recovery paths from the main skill.

Each event has stable `id`, `batch_id`, source `card_id`, `checkpoint_at`, `national_focus_date`, `cause`, original `failure_reason`, later editable `shared_explanation`, `review_disposition` and `tree_snapshot`. Cite revision, event ID, source and affected card IDs, plus frozen requirement version ID and number. Same-name cards remain distinct. Historical soft-deleted cards remain meaningful within this frozen evidence. Older optional rule/version/source fields can be null: label them `unknown` and constrain the finding, rather than borrowing current requirements. Missing required frozen data yields `unsupported_snapshot`; report the returned update/manual-upload recovery.

- One event is one independent failure source. Deduplicate by event ID across pages/windows; distinguish active extinguishing from the system's missed-confirmation cause. An active failure with no explanation has an unknown reason, not evidence of refusal or a particular behavior.
- Cascaded descendants are affected cards within the frozen tree, identified by `failure_source_card_id` and cascade fields; they are not additional independent failures. Describe the actual frozen edge/source relationship, without inferring that the child independently violated its rule.
- Multiple missed-confirmation events can share a `batch_id` and reflection. Keep their independent event count and the batch-level explanation separate. A missed confirmation proves the recorded confirmation failure, not that the action was not performed.
- Original `failure_reason` and later editable `shared_explanation` have different provenance. Quote/attribute each as such; reflection does not rewrite the original reason, frozen rule or outcome. Neither alone proves causation.
- Separate `pending_review` from accepted history in counts and conclusions. Do not silently treat unresolved records as accepted or discard them as nonexistent.

Finish with requested/returned window coverage, pages/events read, completion/truncation and missing evidence. Only uploaded failure records are available: cumulative successful days do not supply daily success logs, complete editing history, failure rates with a known denominator or measured habit formation. Keep observed records, hypotheses and manual suggestions separate; no history or recommendation mutates the App.
