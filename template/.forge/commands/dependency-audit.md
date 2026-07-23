---
name: dependency-audit
description: "[deprecated] Retired to a stub — see /implement's dependency-confirmation gate (Spec 587)"
workflow_stage: review
---

<!-- forge:paths-note (Spec 575): process-state paths in this command (docs/specs,
     docs/sessions, docs/decisions, docs/research, docs/process-kit, docs/backlog.md) are the
     CLASSIC-DEFAULT spellings, not fixed locations. When the project configures forge.paths
     (e.g. the `contained` layout), resolve each key before use — bash: `forge_path <key>`
     (source ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/config.sh, forge_config_load AGENTS.md);
     python: `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py .../runtime_config.py path <key>`. -->
# Framework: FORGE
**Deprecated (Spec 587, S2 MINOR — not removed):** this command's only real function —
flagging new/major-version dependency changes for review — already runs inline during
`/implement` (the dependency-confirmation gate, Requires-Confirmation: "Dependency additions" in
AGENTS.md § Boundaries) and is checklisted in
`docs/process-kit/dependency-vetting-checklist.md`. There is no separate action to take here.

Print:
```
/dependency-audit is deprecated (Spec 587). Dependency risk review now runs inline during
/implement (the dependency-confirmation gate) and is checklisted at
docs/process-kit/dependency-vetting-checklist.md. No separate command needed.
```
Stop — do not execute any further steps.
