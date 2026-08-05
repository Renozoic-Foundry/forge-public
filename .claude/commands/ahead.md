---
name: ahead
description: "Momentum-framed alias for the FORGE orientation surface (dispatches to /now)"
workflow_stage: session
---

<!-- forge:paths-note (Spec 575): process-state paths in this command (docs/specs,
     docs/sessions, docs/decisions, docs/research, docs/process-kit, docs/backlog.md) are the
     CLASSIC-DEFAULT spellings, not fixed locations. When the project configures forge.paths
     (e.g. the `contained` layout), resolve each key before use — bash: `forge_path <key>`
     (source ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/config.sh, forge_config_load AGENTS.md);
     python: `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py .../runtime_config.py path <key>`. -->
# Framework: FORGE
Thin alias (Spec 610, following the Spec 587 F5 pattern). Purpose: `/forge:ahead` reframes the
orientation surface from "status snapshot" to **"what do I need to regain momentum"** — the
same question `/now` already answers, under a name that says so. Both spellings work
indefinitely; this spec does NOT deprecate or rename `/now` (Spec 610 Constraints).

Grammar class: `class_work_loop` (Session and orientation) — the same class as `/now`, NOT
`class_lifecycle`. This file copies `doctor.md`'s dispatch-by-reference BODY pattern, not its
classification.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /forge:ahead — Momentum-framed alias for /now (Spec 610).
  Usage: /forge:ahead [args]
  Dispatches to the same body as `/now` — zero duplicated logic. Use whichever name fits
  how you're thinking: `/now` for "where do things stand", `/forge:ahead` for "what's next".
  See: docs/QUICK-REFERENCE.md
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Dispatch-by-reference

Read `.forge/commands/now.md` and execute it exactly as written there, passing $ARGUMENTS
through unchanged. Do not duplicate its steps here — this file is a pointer, not a copy, so
the two can never drift (Spec 587 R1; asserted structurally by Spec 610 AC 8, which requires
this file to contain none of now.md's own `## [mechanical] Step` markers).
