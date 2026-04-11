---
name: forge
description: "Unified FORGE project lifecycle command"
model_tier: sonnet
workflow_stage: lifecycle
---
# Framework: FORGE
Unified FORGE project lifecycle command. Manages bootstrap and upstream sync workflows.

If $ARGUMENTS is empty, `?`, or `help`:
  Print:
  ```
  /forge — Unified FORGE lifecycle command (Spec 024, updated Spec 131).
  Usage: /forge <subcommand> [args]

  Subcommands:
    init [path]   Bootstrap FORGE into a new or existing project
    stoke         Pull upstream FORGE updates and integrate safely
    status        Show FORGE project status overview (validation queue, backlog summary, active work)
    help          List all available FORGE commands grouped by workflow stage

  Examples:
    /forge init               — Bootstrap in current directory (detects greenfield vs brownfield)
    /forge init d:\new-proj   — Create new project with full FORGE scaffold
    /forge stoke              — Check for and apply upstream FORGE updates
    /forge status             — Show current project status
    /forge help               — List all commands

  To contribute improvements: open a GitHub issue or PR at the FORGE repo.
  See: CONTRIBUTING.md

  See: docs/process-kit/human-validation-runbook.md
  ```
  Stop — do not execute any further steps.

---

Dispatch on the first word of $ARGUMENTS:

- `init`       → Read `.forge/commands/forge-init.md` and execute it. Pass remaining arguments. This is the merged entry point for onboarding + bootstrap — it detects greenfield vs brownfield and runs the appropriate flow including first-session configuration.
- `stoke`      → Read `.forge/commands/forge-stoke.md` and execute it. Pass remaining arguments.
- `status`     → Run a condensed version of `/now`: read docs/specs/README.md for validation queue, docs/backlog.md for top-3 ranked specs, and the latest session log for active work summary. Present in a compact format without the full session brief or choice block. This is the "current forge overview" for quick status checks.
- `help`       → Print the full command listing from `docs/QUICK-REFERENCE.md` (Command Reference section): all FORGE commands grouped by workflow stage with descriptions. Include the typical workflow paths and quick start guidance.
- anything else → print the help block above and stop
