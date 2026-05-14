---
name: forge
description: "Unified FORGE project lifecycle command"
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
    baselines     List available Copier baselines from ~/.forge/baselines/ (Spec 090)
    help          List all available FORGE commands grouped by workflow stage

  Examples:
    /forge init               — Bootstrap in current directory (detects greenfield vs brownfield)
    /forge init d:\new-proj   — Create new project with full FORGE scaffold
    /forge stoke              — Check for and apply upstream FORGE updates
    /forge status             — Show current project status
    /forge baselines          — List baseline YAMLs in ~/.forge/baselines/ (or %USERPROFILE%\.forge\baselines\ on Windows)
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
- `baselines`  → List Copier baselines available for `--data-file` use. Spec 090 baselines convention. Implementation:
   1. Resolve baselines directory: `$HOME/.forge/baselines/` on POSIX; `$env:USERPROFILE\.forge\baselines\` on Windows. Use platform-appropriate variable.
   2. If the directory does not exist: print `No baselines installed. See docs/process-kit/baseline-format.md for the format and docs/process-kit/baselines/python-fastapi.yaml for an example.` and exit 0 (graceful empty-state, AC 5).
   3. For each `*.yaml` file in the directory:
      a. Parse the YAML.
      b. Read `forge_baseline_name`, `forge_baseline_description`, `forge_baseline_version` (Spec 090 Req 3).
      c. If any required key is missing: print `<filename> — MALFORMED: missing <key>` (AC 6).
      d. Otherwise: print `<forge_baseline_name> (v<forge_baseline_version>) — <forge_baseline_description>`.
   4. After listing, print the invocation pattern reminder: `Apply with: copier copy <forge-template> <target> --data-file ~/.forge/baselines/<name>.yaml`
   5. Implementation MUST work in both bash (`$HOME`) and PowerShell (`$env:USERPROFILE`) — when running this subcommand, detect platform via `$IsWindows` (PowerShell) or `[ "$OSTYPE" =~ msys|cygwin ]` (bash), and use the platform-appropriate path. See `docs/process-kit/baseline-format.md` for full format + invocation + security model.
- `help`       → Print the full command listing from `docs/QUICK-REFERENCE.md` (Command Reference section): all FORGE commands grouped by workflow stage with descriptions. Include the typical workflow paths and quick start guidance.
- anything else → print the help block above and stop


## [mechanical] Tab-lane awareness directive (Spec 351)

Before emitting any next-action choice block in this command, consult the active-tab marker (Spec 353 primitive):

1. Read `.forge/state/active-tab-*.json` (primary). If present, extract `lane`. If `last_command_at` > 30 minutes ago, treat marker as **stale**.
2. If no marker, fall back to `docs/sessions/registry.md` rows with `Status = active` for the current session. Use the row's `Lane` column.
3. If neither yields an active lane: emit the choice block as today. No preamble, no filtering, no annotation. **Skip the rest of this directive.**
4. If an active lane is detected: emit the one-line preamble (`Tab lane: <lane>. Options below filtered to lane scope.` / `... Cross-lane options annotated.` / `... (stale ~Nm)...`) and apply the filter/annotate decision rules from `docs/process-kit/tab-lane-awareness-guide.md` § Per-lane decision rules.
5. Filtered rows are struck through with rank `—` (not silently dropped) so the operator can override by typing the keyword directly.

The guide is the single source of truth for which rows filter vs annotate per lane. This directive is intentionally short — the central guide encodes the rules so every emitter stays consistent.

