<!-- GENERATED FILE — do not hand-edit. Regenerate with: scripts/gen-quick-reference.sh
     Canonical sources: .forge/commands/*.md + invocation-policy.yaml
     Source content hash: d49f58a8314e | FORGE plugin version: 3.1.0
     Drift gate: .forge/bin/forge-parity.sh --check (Surface 7, Spec 571) -->
# FORGE Quick Reference

## Core Commands

| Command | Purpose |
|---------|---------|
| `/now` | Review current project state and suggest next action |
| `/spec` | Create a new spec from the template |
| `/implement` | Build a spec end-to-end with evidence gates |
| `/close` | Close a spec: confirm human validation, capture signals, update priorities |

**When in doubt, run `/now`.**

## Change Lanes

| Lane | Use when |
|------|----------|
| `hotfix` | Critical fix needed immediately |
| `small-change` | Low-risk tweak, minimal review |
| `standard-feature` | New command, process addition, or cross-cutting change |
| `process-only` | Changes to docs/tracking only (no code) |

## Rules — Every change needs a spec. Every session ends with `/session`.

---

## Command Reference (by stage)

**Form** (Spec 491): `command` — slash command, never model-invoked; `skill (auto)` — Claude
may invoke it opportunistically (read-only / additive / reversible); `skill (explicit)` — invoked
only when you name it. All entries also run outside Claude Code as `bin/forge <name>`
(Windows: `bin\forge.ps1 <name>`).

### Session and orientation

| Command | Purpose | Form |
|---------|---------|------|
| `/insights` | Mine FORGE process data for cross-session insights | skill (auto) |
| `/note` | Add a scratchpad note for the next process checkpoint | skill (auto) |
| `/now` | Review current project state and suggest next action | skill (auto) |
| `/session` | Create or update the session log | command |
| `/tab` | Initialize or close a multi-tab session for parallel development | command |

### Planning and discovery

| Command | Purpose | Form |
|---------|---------|------|
| `/brainstorm` | Discover spec opportunities from signals and roadmap | skill (auto) |
| `/consensus` | Run a proposal through all registry roles for structured consensus | skill (explicit) |
| `/decision` | Create a new Architecture Decision Record (ADR) | skill (explicit) |
| `/explore` | Pre-spec investigation — produces research artifacts before committing to a full spec | skill (auto) |
| `/interview` | Socratic elicitation for thinking through problems | skill (explicit) |
| `/matrix` | Update and present the prioritization matrix | skill (explicit) |
| `/reconcile` | Reconcile git history into the spec corpus — draft stub specs / memory notes for work committed outside FORGE | command |
| `/revise` | Revise an existing spec based on feedback or correction | skill (explicit) |
| `/spec` | Create a new spec from the template | command |

### Implementation

| Command | Purpose | Form |
|---------|---------|------|
| `/close` | Close a spec: confirm human validation, capture signals, update priorities | command |
| `/debug` | Structured debugging session — hypothesis-first, verify before fixing | command |
| `/implement` | Build a spec end-to-end with evidence gates | command |
| `/parallel` | Run multiple specs in parallel using git worktrees | command |
| `/scheduler` | Run multi-agent scheduler for dependency-aware parallel execution | command |
| `/test` | Run the test suite and report results | skill (auto) |
| `/trace` | Generate bidirectional traceability matrix from spec annotations | skill (auto) |

### Lifecycle and maintenance

| Command | Purpose | Form |
|---------|---------|------|
| `/config-change` | Propose and apply changes to agent configuration files | command |
| `/configure` | Adjust any defaulted onboarding setting (stack, agents, autonomy, methodology, features, MCP servers) | command |
| `/forge` | Unified FORGE project lifecycle command | command |
| `/forge-init` | Bootstrap FORGE into a new or existing project, upgrade legacy pre-Copier projects, or create new projects from scratch | command |
| `/forge-stoke` | Pull upstream FORGE updates into this project using Copier | command |
| `/onboarding` | First-session interactive project configuration | command |

### Process and review

| Command | Purpose | Form |
|---------|---------|------|
| `/configure-nanoclaw` | Configure NanoClaw hardware key enrollment and messaging | command |
| `/dependency-audit` | Scan for dependency changes and produce a structured risk report | skill (auto) |
| `/evolve` | Run the KCS Evolve Loop review | skill (explicit) |
| `/nanoclaw` | Manage the NanoClaw container — start, stop, status, logs | command |
| `/signal-to-strategy` | Turn external research signals into scored FORGE advantage hypotheses | skill (auto) |
| `/synthesize` | Synthesize accumulated project artifacts into refined documents | skill (explicit) |

### /forge subcommands

| Subcommand | Purpose |
|------------|---------|
| `/forge init` | Bootstrap FORGE into a new or existing project |
| `/forge stoke` | Pull upstream FORGE updates and integrate safely |
| `/forge status` | Show FORGE project status overview (validation queue, backlog summary, active work) |
| `/forge baselines` | List available Copier baselines from ~/.forge/baselines/ (Spec 090) |
| `/forge retrofit` | Guided consumer retrofit: inventory -> de-vendor -> reorganize -> reconcile (Spec 577) |
| `/forge help` | List all available FORGE commands grouped by workflow stage |

**Role-value rollup (Spec 305)** — not a slash command; a helper subcommand:
`bash .forge/lib/score-audit.sh role-audit [--json]` (PowerShell: `pwsh .forge/lib/score-audit.ps1 role-audit`)
rolls up which advisory roles fired across `/spec`/`/implement`/`/close`/`/consensus`, their
recommendations, and operator acceptance (per-role dispatch count, acceptance %, avg concerns,
stage distribution). Reads the shared gitignored sink `.forge/state/score-audit.jsonl`. See
`docs/process-kit/role-dispatch-schema.md`.

### Typical Workflow

```
/now → /implement next → /close NNN → /session
```

For new projects: `/forge init` → `/onboarding` → `/interview` → `/spec` → `/implement`

---

## Process-State Path Keys (`forge.paths.*`, Specs 564/575)

Path indirection for FORGE process state, with two named **layout presets** (Spec 575):
`classic` (the `docs/...` defaults below — what an absent block means) and `contained`
(everything under `.forge/project/` — the default for new scaffolds; keeps FORGE files
segregated from your solution's docs). Choose at `/forge init` (`--layout`), switch later via
`/configure` (config-only; physical moves ride the Spec 577 retrofit). Every scaffold also
writes `.forge/ownership.yaml` — the machine-readable FORGE-vs-solution file partition
(`forge-py .forge/lib/ownership.py --list | --partition`). See the layout guide in process-kit.

Set under the `forge:` section of the AGENTS.md `## Runtime Configuration` YAML block;
absent keys keep the classic defaults (zero behavior change):

```yaml
forge:
  paths:
    specs: docs/specs            # default
    sessions: docs/sessions      # default
    decisions: docs/decisions    # default
    research: docs/research      # default
    process_kit: docs/process-kit  # default
    backlog: docs/backlog.md     # default
```

**Validation rules** (helpers exit nonzero, naming the offending key): values must be
repo-relative, forward-slash paths. Rejected: backslashes, POSIX absolutes (`/x`),
drive-letter paths (`C:/x`), UNC paths (`//server/share`), any `..` segment, and any
value that canonicalizes (symlinks resolved) outside the repo root.

**Resolution surfaces**: bash — `forge_path <key>` in `.forge/lib/config.sh`; python —
`forge-py .forge/lib/runtime_config.py path <key> [--dir DIR]` (exit 5 = invalid value,
3 = unknown key). Consumers resolve through these helpers only (sweep: Spec 565).

## Key References

- `CLAUDE.md` — Operating rules and project context (in your bootstrapped project)
- `AGENTS.md` — Agent roles, autonomy levels, evidence gates (in your bootstrapped project)
- `docs/process-kit/` — Scoring rubric, checklists, runbook, templates (in your bootstrapped project)

---

## Provenance and revision history

This document is **generated** by `scripts/gen-quick-reference.sh` from the canonical command surface
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
