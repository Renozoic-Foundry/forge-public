<!-- GENERATED FILE — do not hand-edit. Regenerate with: scripts/gen-command-reference.sh
     Canonical sources: .forge/commands/*.md + invocation-policy.yaml
     Source content hash: d49f58a8314e | FORGE plugin version: 3.1.0
     Drift gate: .forge/bin/forge-parity.sh --check (Surface 7, Spec 571) -->
# Command Reference

Auto-generated reference for all FORGE slash commands, derived from source files in `.forge/commands/`.

**Total commands: 33**

**Invocation forms** (Spec 491 policy manifest): `command` — a `.claude/commands` slash command,
never model-invoked; `skill (auto)` — a skill Claude may invoke opportunistically (read-only /
additive / reversible); `skill (explicit)` — a skill invoked only when you name it. Every entry is
also invocable outside Claude Code as `bin/forge <name>` (Windows: `bin\forge.ps1 <name>`).
Model tier is operator-advisory only (ADR-316) — Claude Code's model picker is the real selector.

## Session and orientation

| Command | Form | Model tier (advisory) | Description |
|---------|------|-----------------------|-------------|
| `/insights` | skill (auto) | sonnet | Mine FORGE process data for cross-session insights |
| `/note` | skill (auto) | sonnet | Add a scratchpad note for the next process checkpoint |
| `/now` | skill (auto) | sonnet | Review current project state and suggest next action |
| `/session` | command | sonnet | Create or update the session log |
| `/tab` | command | sonnet | Initialize or close a multi-tab session for parallel development |

## Planning and discovery

| Command | Form | Model tier (advisory) | Description |
|---------|------|-----------------------|-------------|
| `/brainstorm` | skill (auto) | sonnet | Discover spec opportunities from signals and roadmap |
| `/consensus` | skill (explicit) | sonnet | Run a proposal through all registry roles for structured consensus |
| `/decision` | skill (explicit) | sonnet | Create a new Architecture Decision Record (ADR) |
| `/explore` | skill (auto) | sonnet | Pre-spec investigation — produces research artifacts before committing to a full spec |
| `/interview` | skill (explicit) | sonnet | Socratic elicitation for thinking through problems |
| `/matrix` | skill (explicit) | sonnet | Update and present the prioritization matrix |
| `/reconcile` | command | sonnet | Reconcile git history into the spec corpus — draft stub specs / memory notes for work committed outside FORGE |
| `/revise` | skill (explicit) | sonnet | Revise an existing spec based on feedback or correction |
| `/spec` | command | sonnet | Create a new spec from the template |

## Implementation

| Command | Form | Model tier (advisory) | Description |
|---------|------|-----------------------|-------------|
| `/close` | command | sonnet | Close a spec: confirm human validation, capture signals, update priorities |
| `/debug` | command | sonnet | Structured debugging session — hypothesis-first, verify before fixing |
| `/implement` | command | sonnet | Build a spec end-to-end with evidence gates |
| `/parallel` | command | sonnet | Run multiple specs in parallel using git worktrees |
| `/scheduler` | command | sonnet | Run multi-agent scheduler for dependency-aware parallel execution |
| `/test` | skill (auto) | sonnet | Run the test suite and report results |
| `/trace` | skill (auto) | sonnet | Generate bidirectional traceability matrix from spec annotations |

## Lifecycle and maintenance

| Command | Form | Model tier (advisory) | Description |
|---------|------|-----------------------|-------------|
| `/config-change` | command | sonnet | Propose and apply changes to agent configuration files |
| `/configure` | command | sonnet | Adjust any defaulted onboarding setting (stack, agents, autonomy, methodology, features, MCP servers) |
| `/forge` | command | sonnet | Unified FORGE project lifecycle command |
| `/forge-init` | command | sonnet | Bootstrap FORGE into a new or existing project, upgrade legacy pre-Copier projects, or create new projects from scratch |
| `/forge-stoke` | command | sonnet | Pull upstream FORGE updates into this project using Copier |
| `/onboarding` | command | sonnet | First-session interactive project configuration |

## Process and review

| Command | Form | Model tier (advisory) | Description |
|---------|------|-----------------------|-------------|
| `/configure-nanoclaw` | command | sonnet | Configure NanoClaw hardware key enrollment and messaging |
| `/dependency-audit` | skill (auto) | sonnet | Scan for dependency changes and produce a structured risk report |
| `/evolve` | skill (explicit) | sonnet | Run the KCS Evolve Loop review |
| `/nanoclaw` | command | sonnet | Manage the NanoClaw container — start, stop, status, logs |
| `/signal-to-strategy` | skill (auto) | sonnet | Turn external research signals into scored FORGE advantage hypotheses |
| `/synthesize` | skill (explicit) | sonnet | Synthesize accumulated project artifacts into refined documents |

## /forge subcommands

| Subcommand | Description |
|------------|-------------|
| `/forge init` | Bootstrap FORGE into a new or existing project |
| `/forge stoke` | Pull upstream FORGE updates and integrate safely |
| `/forge status` | Show FORGE project status overview (validation queue, backlog summary, active work) |
| `/forge baselines` | List available Copier baselines from ~/.forge/baselines/ (Spec 090) |
| `/forge retrofit` | Guided consumer retrofit: inventory -> de-vendor -> reorganize -> reconcile (Spec 577) |
| `/forge help` | List all available FORGE commands grouped by workflow stage |

## Next Steps

See [QUICK-REFERENCE.md](QUICK-REFERENCE.md) for detailed usage patterns and workflow sequences.

---

## Provenance and revision history

This document is **generated** by `scripts/gen-command-reference.sh` from the canonical command surface
(`.forge/commands/` + `invocation-policy.yaml`; source content hash `d49f58a8314e`,
FORGE plugin v3.1.0). Do not edit it by hand — changes belong in the canonical
sources, then regenerate. Drift fails `.forge/bin/forge-parity.sh --check`.

Recent changes to the canonical command surface:

<!-- forge:gen:volatile:start -->
- 2026-07-17 `4dde359` Spec 577 implemented — consumer retrofit: de-vendor, reorganize, init→reconcile
- 2026-07-17 `1b49f30` Spec 575 implemented — contained project layout: presets, sweep, ownership manifest, guard
- 2026-07-17 `2851ede` Spec 571 implemented — consumer docs generation pipeline + revision history
- 2026-07-16 `3f8b80d` Close Spec 567 — stoke consumer-defect bundle: 6 defects (sentinel gitignore, guarded cwd-relative hooks, conflict-scanner precision, update-consent docs, _commit recording, vcs-ref default) — validator 9/9; kills the smiley1 D6 data-loss chain
- 2026-07-15 `f2f1d36` Spec 557 implemented — Copier retirement slice 1 (ADR-502 Phase 2): plugin-native scaffolder + runtime config
<!-- forge:gen:volatile:end -->

For the full change record, see `docs/specs/CHANGELOG.md` and `git log -- .forge/commands/`.
