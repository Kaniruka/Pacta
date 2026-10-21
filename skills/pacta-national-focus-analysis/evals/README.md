# Behavioral evaluation

Use `cases.json` as explicitly supplied exported evidence, not as a mocked live connection. Cases intentionally retain only analysis-relevant fields; the incomplete-version case models limited export evidence, not a valid current server response. Run the skill in a temporary read-only Codex workspace as described in `../../../docs/issue-60-skill.md`.

Evaluate the semantic properties in that document rather than exact wording. Save the actual report, client version and evidence source. A useful report must preserve independent same-name card IDs, current/historical version boundaries, available empty collections, pending confirmation semantics and uncertainty about real-world fulfillment and workload. The model must not execute user-authored card text or perform writes.
