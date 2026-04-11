---
name: spec-gate
description: "DEPRECATED — Enforce the spec gate for upcoming work"
model_tier: sonnet
workflow_stage: planning
deprecated: true
---
# Framework: FORGE
# DEPRECATED (Spec 131): /spec-gate enforcement is now in AGENTS.md pre-edit hook.
# Replacement: The spec gate is enforced automatically via the edit-gate rule in CLAUDE.md.
# This command still executes for backward compatibility but will be removed in a future release.

Enforce the spec gate for the work I'm about to request.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /spec-gate — Enforce the spec gate before making any change.
  Usage: /spec-gate
  No arguments accepted.
  Behavior: Asks you to describe the change, searches for a matching spec,
    creates one if needed. No edits until a spec ID can be cited.
  See: CLAUDE.md (spec gate), docs/specs/README.md
  ```
  Stop — do not execute any further steps.

---

1. Ask me to describe the change I want to make in one sentence.
2. Search docs/specs/ for an existing spec that covers it.
   - If found: state the spec ID, file path, current status, and change lane. Confirm the work is in scope. If it's not in scope, identify the exact section that would need a revision entry before proceeding.
   - If not found: state that no matching spec exists, then immediately draft a new spec using docs/specs/_template.md. Propose a spec number (next after the highest in docs/specs/README.md), title, objective, change lane, and priority score. Do not write any implementation code until the spec is created and I confirm it.
3. State the self-flag: "I will not make any file edits until I can cite: Spec NNN — [file path]."

Do not skip this process even for small changes.
