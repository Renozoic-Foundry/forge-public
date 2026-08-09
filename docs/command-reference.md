<!-- GENERATED FILE — do not hand-edit. Regenerate with: scripts/gen-command-reference.sh
     Canonical sources: .forge/commands/*.md + invocation-policy.yaml
     Source content hash: e322073bf9e3 | FORGE plugin version: 4.1.0
     Drift gate: .forge/bin/forge-parity.sh --check (Surface 7, Spec 571) -->
# Command Reference

Auto-generated reference for all FORGE slash commands, derived from source files in `.forge/commands/`.

**Total commands: 32**

**Invocation forms** (Spec 491 policy manifest): `command` — a `.claude/commands` slash command,
never model-invoked; `skill (auto)` — a skill Claude may invoke opportunistically (read-only /
additive / reversible); `skill (explicit)` — a skill invoked only when you name it. Every entry is
also invocable outside Claude Code as `bin/forge <name>` (Windows: `bin\forge.ps1 <name>`).
Model tier is operator-advisory only (ADR-316) — Claude Code's model picker is the real selector.

**`/forge configure` is the primary configuration surface** (Spec 607); `/configure` and
`/config-change` remain valid direct dispatch names for it and `/forge config-change`
respectively — both keep working unchanged, the `/forge <sub>` spelling below is simply
what's advertised (Spec 580 lifecycle fold).

## Session and orientation

| Command | Form | Model tier (advisory) | Description |
|---------|------|-----------------------|-------------|
| `/forge:ahead` | command |  | Momentum-framed alias for the FORGE orientation surface (dispatches to /now) |
| `/note` | skill (auto) | haiku | Add a scratchpad note for the next process checkpoint |
| `/now` | skill (auto) | haiku | Review current project state and suggest next action |
| `/session` | command | haiku | Create or update the session log |
| `/tab` | command |  | Initialize or close a multi-tab session for parallel development |

## Planning and discovery

| Command | Form | Model tier (advisory) | Description |
|---------|------|-----------------------|-------------|
| `/brainstorm` | skill (auto) | haiku | Discover spec opportunities from signals and roadmap |
| `/consensus` | skill (explicit) | sonnet | Run a proposal through all registry roles for structured consensus |
| `/decision` | skill (explicit) |  | Create a new Architecture Decision Record (ADR) |
| `/explore` | skill (auto) | sonnet | Pre-spec investigation — produces research artifacts before committing to a full spec |
| `/interview` | skill (explicit) | sonnet | Socratic elicitation for thinking through problems |
| `/matrix` | skill (explicit) |  | Update and present the prioritization matrix |
| `/reconcile` | command |  | Reconcile git history into the spec corpus — draft stub specs / memory notes for work committed outside FORGE |
| `/revise` | skill (explicit) |  | Revise an existing spec based on feedback or correction |
| `/spec` | command | sonnet | Create a new spec from the template |

## Implementation

| Command | Form | Model tier (advisory) | Description |
|---------|------|-----------------------|-------------|
| `/close` | command | sonnet | Close a spec: confirm human validation, capture signals, update priorities |
| `/debug` | command |  | Structured debugging session — hypothesis-first, verify before fixing |
| `/implement` | command | sonnet | Build a spec end-to-end with evidence gates |
| `/parallel` | command |  | Run multiple specs in parallel using git worktrees |
| `/scheduler` | command |  | Run multi-agent scheduler for dependency-aware parallel execution |
| `/test` | skill (auto) |  | Run the test suite and report results |
| `/trace` | skill (auto) | sonnet | Generate bidirectional traceability matrix from spec annotations |

## Lifecycle and maintenance

| Command | Form | Model tier (advisory) | Description |
|---------|------|-----------------------|-------------|
| `/forge config-change` | command |  | Propose and apply changes to agent configuration files |
| `/forge configure` | command |  | Adjust any defaulted onboarding setting (stack, agents, autonomy, methodology, features, MCP servers) |
| `/forge:doctor` | command |  | Plugin-qualified escape hatch for the FORGE health diagnostic (dispatches to /forge doctor) |
| `/forge` | command |  | Unified FORGE project lifecycle command |
| `/forge init` | command |  | Bootstrap FORGE into a new or existing project, upgrade legacy pre-Copier projects, or create new projects from scratch |
| `/forge stoke` | command |  | Pull upstream FORGE updates into this project via the content-merge engine |
| `/forge onboarding` | command |  | First-session interactive project configuration |

## Process and review

| Command | Form | Model tier (advisory) | Description |
|---------|------|-----------------------|-------------|
| `/configure-nanoclaw` | command |  | Configure NanoClaw hardware key enrollment and messaging |
| `/evolve` | skill (explicit) |  | Run the KCS Evolve Loop review |
| `/nanoclaw` | command |  | Manage the NanoClaw container — start, stop, status, logs |
| `/synthesize` | skill (explicit) | sonnet | Synthesize accumulated project artifacts into refined documents |

## /forge subcommands

| Subcommand | Description |
|------------|-------------|
| `/forge init` | Bootstrap FORGE into a new or existing project |
| `/forge stoke` | Pull upstream FORGE updates and integrate safely |
| `/forge status` | Show FORGE project status overview (validation queue, backlog summary, active work) |
| `/forge baselines` | List available Copier baselines from ~/.forge/baselines/ (Spec 090) |
| `/forge retrofit` | Guided consumer retrofit: inventory -> de-vendor -> reorganize -> reconcile (Spec 577) |
| `/forge doctor` | Run the FORGE health diagnostic and route findings to the right fix (Spec 579) |
| `/forge update` | Single consumer update verb — skew probe + the plugin-update journey (Spec 587) |
| `/forge onboarding` | First-session interactive project configuration (Spec 580) |
| `/forge configure` | Adjust any defaulted onboarding setting (Spec 580) |
| `/forge config-change` | Propose an audited change to agent configuration files (Spec 580) |
| `/forge help` | List all available FORGE commands grouped by workflow stage |

## Next Steps

See [QUICK-REFERENCE.md](QUICK-REFERENCE.md) for detailed usage patterns and workflow sequences.

---

## Provenance and revision history

This document is **generated** by `scripts/gen-command-reference.sh` from the canonical command surface
(`.forge/commands/` + `invocation-policy.yaml`; source content hash `e322073bf9e3`,
FORGE plugin v4.1.0). Do not edit it by hand — changes belong in the canonical
sources, then regenerate. Drift fails `.forge/bin/forge-parity.sh --check`.

Recent changes to the canonical command surface:

<!-- forge:gen:volatile:start -->
- 2026-08-07 `42b1478a` Spec 636 implemented — /forge stoke apply gated by the ownership manifest (fail-closed), first-merge safety, installed-base backfill, manifest self-governance
- 2026-08-07 `9a83f8cd` Spec 635 implemented — stale public forge-init overlay deleted (delete+redirect), legacy-upgrade mode plugin-native, getting-started Python claim corrected
- 2026-08-07 `d21a8dd0` Close Spec 649 — autonomy promise conformance: reachable goal-mode exit, honest L3, worktree reconciliation
- 2026-08-07 `ac398932` Close Spec 670 — consumer render hygiene: dead scratchpad path, missing project README
- 2026-08-07 `75efb008` Spec 668 — exact-path staging for /configure and /forge init create-new
<!-- forge:gen:volatile:end -->

For the full change record, see `docs/specs/CHANGELOG.md` and `git log -- .forge/commands/`.
