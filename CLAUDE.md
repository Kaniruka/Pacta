# Claude Code instructions

Shared project instructions: @AGENTS.md

## Local execution

- This repository is developed on Windows. Use PowerShell for simple system commands.
- Prefer a one-off Python script for bulk file operations, Chinese text encoding, complex paths, or large text transformations.
- After the same execution approach fails twice, stop retrying it. Explain the cause, then choose a different approach instead of repeatedly changing paths, quoting, or escaping.
- Resolve and verify target paths before file operations, then inspect the result afterward.

## Maintenance

Keep cross-agent project rules in `AGENTS.md` and the documents it references. Keep this file limited to Claude Code compatibility so Codex and Claude do not drift.
