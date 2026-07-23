<!-- GENERATED FILE — do not hand-edit. Regenerate with: scripts/gen-command-reference.sh
     Canonical sources: .forge/commands/*.md + invocation-policy.yaml
     Source content hash: 50db7d2841f8 | FORGE plugin version: 3.3.0
     Drift gate: .forge/bin/forge-parity.sh --check (Surface 7, Spec 571) -->
# Command Reference

Auto-generated reference for all FORGE slash commands, derived from source files in `.forge/commands/`.

**Total commands: 34**

**Invocation forms** (Spec 491 policy manifest): `command` — a `.claude/commands` slash command,
never model-invoked; `skill (auto)` — a skill Claude may invoke opportunistically (read-only /
additive / reversible); `skill (explicit)` — a skill invoked only when you name it. Every entry is
also invocable outside Claude Code as `bin/forge <name>` (Windows: `bin\forge.ps1 <name>`).
Model tier is operator-advisory only (ADR-316) — Claude Code's model picker is the real selector.

## Session and orientation

| Command | Form | Model tier (advisory) | Description |
|---------|------|-----------------------|-------------|
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
| `/forge config-change` | command | sonnet | Propose and apply changes to agent configuration files |
| `/forge configure` | command | sonnet | Adjust any defaulted onboarding setting (stack, agents, autonomy, methodology, features, MCP servers) |
| `/forge:doctor` | command | sonnet | Plugin-qualified escape hatch for the FORGE health diagnostic (dispatches to /forge doctor) |
| `/forge` | command | sonnet | Unified FORGE project lifecycle command |
| `/forge init` | command | sonnet | Bootstrap FORGE into a new or existing project, upgrade legacy pre-Copier projects, or create new projects from scratch |
| `/forge stoke` | command | sonnet | Pull upstream FORGE updates into this project using Copier |
| `/forge onboarding` | command | sonnet | First-session interactive project configuration |

## Process and review

| Command | Form | Model tier (advisory) | Description |
|---------|------|-----------------------|-------------|
| `/configure-nanoclaw` | command | sonnet | Configure NanoClaw hardware key enrollment and messaging |
| `/evolve` | skill (explicit) | sonnet | Run the KCS Evolve Loop review |
| `/nanoclaw` | command | sonnet | Manage the NanoClaw container — start, stop, status, logs |
| `/synthesize` | skill (explicit) | sonnet | Synthesize accumulated project artifacts into refined documents |

## Deprecated (invocation preserved, not advertised)

Retired names still resolve (S2 MINOR — no physical removal) but only print a
one-line redirect to their replacement. Not part of the active command surface.

| Former name | Redirects to |
|-------------|--------------|
| `/dependency-audit` | /implement dependency-confirmation gate + dependency-vetting-checklist.md |
| `/insights` | /evolve --insights |
| `/signal-to-strategy` | /brainstorm --strategy |

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
(`.forge/commands/` + `invocation-policy.yaml`; source content hash `50db7d2841f8`,
FORGE plugin v3.3.0). Do not edit it by hand — changes belong in the canonical
sources, then regenerate. Drift fails `.forge/bin/forge-parity.sh --check`.

Recent changes to the canonical command surface:

<!-- forge:gen:volatile:start -->
- 2026-07-21 `21f2222` WIP: merge specs 594-596 implementations, awaiting 597
- 2026-07-21 `f24b957` Close Spec 591 — Plugin-primary functional cutover: live six-key consent gate + stoke content-merge backend + classic deprecation signal
- 2026-07-20 `be7b00f` Spec 560 implemented — classic-mode consumer enumeration + opt-in stoke --to-plugin converter
- 2026-07-20 `79d1cc8` Merge Spec 587 — plugin surface quick-wins (parallel batch 20260720-1505)
- 2026-07-20 `677ce78` Spec 587 implemented — plugin-surface quick-wins: doctor alias, /forge update, near-dead skill folds, native-collision naming policy
<!-- forge:gen:volatile:end -->

For the full change record, see `docs/specs/CHANGELOG.md` and `git log -- .forge/commands/`.
