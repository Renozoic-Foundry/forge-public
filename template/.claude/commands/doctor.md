---
name: doctor
description: "Plugin-qualified escape hatch for the FORGE health diagnostic (dispatches to /forge doctor)"
workflow_stage: lifecycle
---

<!-- forge:paths-note (Spec 575): process-state paths in this command (docs/specs,
     docs/sessions, docs/decisions, docs/research, docs/process-kit, docs/backlog.md) are the
     CLASSIC-DEFAULT spellings, not fixed locations. When the project configures forge.paths
     (e.g. the `contained` layout), resolve each key before use — bash: `forge_path <key>`
     (source ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/config.sh, forge_config_load AGENTS.md);
     python: `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py .../runtime_config.py path <key>`. -->
# Framework: FORGE
Thin alias (Spec 587, F5). Purpose: `/forge:doctor` resolves the FORGE health diagnostic even
in a **vendored-shadow** project — one where a stale project-local `.claude/commands/forge.md`
masks the plugin's `forge` dispatcher and its own `doctor` subcommand never heard of. The
plugin-qualified colon form (`/forge:doctor`) always resolves to THIS file, which can never be
shadowed by a project-local `forge.md` (different name). Bare `/doctor` is never used or
advertised — it collides with Claude Code's native `/doctor` (install health); this command is
reachable only as `/forge:doctor` (naming-policy exception: alias class, not a new top-level
verb — see `.forge/commands/invocation-policy.yaml` header).

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /forge:doctor — Plugin-qualified alias for the FORGE health diagnostic (Spec 587).
  Usage: /forge:doctor [args]
  Dispatches to the same body as `/forge doctor` — zero duplicated logic. Use this spelling
  when a project-local forge.md shadows the plugin's dispatcher (vendored-shadow projects).
  See: docs/process-kit/migration-decision-guide.md
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Dispatch-by-reference

Read `.forge/commands/forge.md` and execute its `doctor` dispatch branch (the `- \`doctor\`` row
under "Dispatch on the first word of $ARGUMENTS") exactly as written there, passing $ARGUMENTS
through unchanged. Do not duplicate its steps here — this file is a pointer, not a copy, so the
two can never drift (Spec 587 R1).
