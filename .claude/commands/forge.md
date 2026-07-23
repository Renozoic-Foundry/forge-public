---
name: forge
description: "Unified FORGE project lifecycle command"
workflow_stage: lifecycle
---

<!-- forge:paths-note (Spec 575): process-state paths in this command (docs/specs,
     docs/sessions, docs/decisions, docs/research, docs/process-kit, docs/backlog.md) are the
     CLASSIC-DEFAULT spellings, not fixed locations. When the project configures forge.paths
     (e.g. the `contained` layout), resolve each key before use — bash: `forge_path <key>`
     (source ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/config.sh, forge_config_load AGENTS.md);
     python: `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py .../runtime_config.py path <key>`. -->
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
    retrofit      Guided consumer retrofit: inventory -> de-vendor -> reorganize -> reconcile (Spec 577)
    doctor        Run the FORGE health diagnostic and route findings to the right fix (Spec 579)
    update        Single consumer update verb — skew probe + the plugin-update journey (Spec 587)
    onboarding    First-session interactive project configuration (Spec 580)
    configure     Adjust any defaulted onboarding setting (Spec 580)
    config-change Propose an audited change to agent configuration files (Spec 580)
    help          List all available FORGE commands grouped by workflow stage

  Examples:
    /forge init               — Bootstrap in current directory (detects greenfield vs brownfield)
    /forge init d:\new-proj   — Create new project with full FORGE scaffold
    /forge stoke              — Check for and apply upstream FORGE updates
    /forge status             — Show current project status
    /forge baselines          — List baseline YAMLs in ~/.forge/baselines/ (or %USERPROFILE%\.forge\baselines\ on Windows)
    /forge doctor             — Health check: environment, config, layout, plugin freshness
    /forge update             — Skew probe + the plugin-update journey, one verb
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
- `retrofit`   → Guided retrofit flow (Spec 577). Phases via `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/retrofit.py <phase> [--apply]` — ALWAYS dry-run first and show the operator the full action list. Order: `inventory` (read-only; present the classification, collect dispositions for vendored-modified / vendored-no-counterpart / ambiguous — NEVER guess); `devendor` (file deletion — before displaying the removal list, runs a shadow-delete + smoke-test reverse-reference scan (Spec 595): a disposable git worktree at the current commit, simulated removal of the pristine set, and a bounded smoke check, surfacing any `orphaned-consumers` — out-of-prefix files like `bin/forge` that would break — as their own labeled bucket, never auto-removed; requires explicit operator confirmation (yes/no) after displaying the removal list; refuses without an installed plugin/runtime; before applying, re-confirm team composition: if ANY non-Claude developers, require the FORGE runtime (Spec 576) installed or explicit Claude-only acceptance); `reorganize` (git mv to the contained layout + forge.paths + ownership manifest; then run scripts/check-doc-links.py + forge-doctor D-PATHS and show results); `reconcile` (bounded /reconcile offer: last-90-days / last-200-commits / full-history / skip — planting the reconcile-pending marker on "later"). Each phase commits with explicit paths; each is independently skippable; rollback via .forge/lib/migration-snapshot.sh restore. See docs/process-kit/retrofit-runbook.md.
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
- `doctor`     → FORGE health diagnostic + journey router (Spec 579). READ-ONLY end to end — this subcommand never mutates state; fixes run only through their own commands after an explicit operator choice.
   1. **Resolve + run the engine**: `bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-doctor.sh` (pass remaining arguments through). If the script is absent at the resolved runtime root (pre-Spec-520 consumer): print `forge-doctor.sh not found at <resolved root> — your installed FORGE runtime predates the doctor (Spec 520). Update the plugin: claude plugin marketplace update && claude plugin update forge.` and stop (AC10 degrade path — no stack trace, no silent no-op).
   2. **Present findings faithfully**: severity-ordered, the D-PATHS section included, and the doctor's exit code stated verbatim in the output (Grounded-progress rule — never summarize a FAIL away).
   3. **Version-skew finding (runs even when the engine is absent)**: when BOTH a plugin payload version (`${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` `version`) and a resolved runtime/checkout version (runtime root's `.claude-plugin/plugin.json`, or `git -C <runtime root> describe --tags` for checkout runtimes) are discoverable and DIFFER: report it as the FIRST finding, naming both versions, and recommend `claude plugin marketplace update && claude plugin update forge` as the FIRST action — stale caches mask newer capability (observed 2026-07-19: a 3.0.0 cache hid `retrofit` from `/forge help`). Silent when only one side is discoverable or versions match.
   4. **Stale user-surface finding (Spec 579 bootstrap wind-down)**: if `${HOME:-$USERPROFILE}/.claude/commands/forge-bootstrap.md` exists AND the FORGE plugin is installed (CLAUDE_PLUGIN_ROOT resolves): report `stale user-level forge-bootstrap.md — the plugin supersedes it; delete ${HOME:-$USERPROFILE}/.claude/commands/forge-bootstrap.md (re-plant later with install.sh --legacy-bootstrap if genuinely needed)`. Skip silently when neither HOME nor USERPROFILE is set (CI/sandbox).
   5. **Journey routing — ONE choice block, only when a migration-relevant finding is present** (healthy projects get findings + no choice block; zero added friction). Map (short form of `docs/process-kit/migration-decision-guide.md` — the single source):
      - D-PATHS pre-migration WARN or SPLIT-BRAIN HIGH → offer `/forge retrofit` (phase 3 layout-only, or full four-phase for vendored pre-v3 trees).
      - Vendored framework files present (pre-v3 tree) → offer `/forge retrofit` (full).
      - Copier-scaffold consumer behind upstream → offer `/forge stoke`.
      - No FORGE at all → offer `/forge init`.
      - Version skew (step 3) → the plugin update is the FIRST recommended action, ahead of any other fix.
      Choice block (Spec 320 format, Rationale column, safety-rule token where the offered fix is destructive — retrofit de-vendor): rows = the ONE mapped fix, `details` (open the migration-decision-guide), `not now` (end — no state change). NEVER auto-run a fix; never chain without the explicit choice.
- `update`     → Single consumer update verb (Spec 587, F5 — field report rec #2). Wraps the
  five-step plugin-update journey behind one command. READ-ONLY probe first; any mutating step
  runs only behind an explicit yes/no — this subcommand never mutates on its own.
   1. **Skew probe** (reuses the doctor engine — same detection as `/forge doctor` step 3):
      resolve BOTH a plugin payload version (`${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`
      `version`) and a resolved runtime/checkout version (runtime root's
      `.claude-plugin/plugin.json`, or `git -C <runtime root> describe --tags` for checkout
      runtimes). If the doctor engine's version-skew detection is unavailable because
      `forge-doctor.sh` is absent at the resolved runtime root, print the same degrade message
      as `/forge doctor` step 1 (`forge-doctor.sh not found ... update the plugin: claude
      plugin marketplace update && claude plugin update forge.`) and stop.
   2. **Report the probe result first, always** — this line comes before anything else in the
      output: `Plugin cache: <payload version> | Runtime: <runtime version> | <current | STALE>`.
   3. **No skew (versions match or only one side discoverable)**: report "Plugin cache is
      current — no update needed." and stop. No choice block.
   4. **Skew found**: print the five-step update journey (single source:
      `docs/process-kit/migration-decision-guide.md` § update verb; cache-copy model stated —
      editing `template/` in place does nothing until re-cached):
      1. `claude plugin marketplace update` — refresh the marketplace index
      2. `claude plugin update forge` — pull the newer cached version
      3. `/reload-plugins` — the harness must reload the plugin payload into the running
         session; this step cannot be run by this command, only by the operator's own session
      4. Re-run `/forge doctor` — confirm the version-skew finding has cleared
      5. If skew persists after steps 1-4: `claude plugin uninstall forge` then `claude plugin
         install forge@<marketplace>` — a full reinstall; stale caches occasionally survive an
         `update` alone
   5. **Confirmation gate**: check whether the `claude` CLI is available on PATH
      (`command -v claude` / `Get-Command claude`). Present a Choice Block (Spec 025/320
      format): `run` (execute steps 1-2 now via the `claude` CLI, then print steps 3-5 as the
      operator's manual follow-ups — ONLY offered when the CLI is available) / `print-only`
      (show the chain; no execution) / `not now` (end — no state change). NEVER execute step 1
      or 2 without this explicit yes/no, and NEVER attempt steps 3 or 5 programmatically — step
      3 is harness-only and step 5 is destructive-adjacent (uninstall).
   6. **Exit code**: state it verbatim — 0 when the probe completed and the operator was shown
      or asked about the chain (skew or no skew), non-zero only if the doctor engine was
      entirely unreachable (step 1 degrade path).
- `onboarding` → Read `.forge/commands/onboarding.md` and execute it. Pass remaining arguments. (Spec 580 lifecycle fold — same canonical body as the top-level form.)
- `configure`  → Read `.forge/commands/configure.md` and execute it. Pass remaining arguments. (Spec 580 lifecycle fold.)
- `config-change` → Read `.forge/commands/config-change.md` and execute it. Pass remaining arguments. (Spec 580 lifecycle fold — the audited self-modification path; distinct from `configure` by design: rule-file edits carry the ADR-046 cool-down + audit ledger.)
- `help`       → Print the full command listing from `docs/QUICK-REFERENCE.md` (Command Reference section): all FORGE commands grouped by workflow stage with descriptions. Include the typical workflow paths and quick start guidance. Open with the three-line invocation grammar (work-loop verbs top-level; lifecycle via `/forge <sub>`; `/forge:<name>` = plugin-qualified spellings, used only on name collision) and link `docs/process-kit/migration-decision-guide.md` for migrate/upgrade routing.
- anything else → print the help block above and stop


## [mechanical] Tab-lane awareness directive (Spec 351)

Before emitting any next-action choice block in this command, consult the active-tab marker (Spec 353 primitive):

1. Read `.forge/state/active-tab-*.json` (primary). If present, extract `lane`. If `last_command_at` > 30 minutes ago, treat marker as **stale**.
2. If no marker, fall back to `docs/sessions/registry.md` rows with `Status = active` for the current session. Use the row's `Lane` column.
3. If neither yields an active lane: emit the choice block as today. No preamble, no filtering, no annotation. **Skip the rest of this directive.**
4. If an active lane is detected: emit the one-line preamble (`Tab lane: <lane>. Options below filtered to lane scope.` / `... Cross-lane options annotated.` / `... (stale ~Nm)...`) and apply the filter/annotate decision rules from `docs/process-kit/tab-lane-awareness-guide.md` § Per-lane decision rules.
5. Filtered rows are struck through with rank `—` (not silently dropped) so the operator can override by typing the keyword directly.

The guide is the single source of truth for which rows filter vs annotate per lane. This directive is intentionally short — the central guide encodes the rules so every emitter stays consistent.

