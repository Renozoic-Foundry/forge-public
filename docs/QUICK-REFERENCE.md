<!-- GENERATED FILE — do not hand-edit. Regenerate with: scripts/gen-quick-reference.sh
     Canonical sources: .forge/commands/*.md + invocation-policy.yaml
     Source content hash: e322073bf9e3 | FORGE plugin version: 4.1.0
     Drift gate: .forge/bin/forge-parity.sh --check (Surface 7, Spec 571) -->
# FORGE Quick Reference

## Invocation grammar (Spec 579)

- **Work-loop verbs are top-level**: `/spec`, `/implement`, `/close`, `/now`, … — the daily delivery loop.
- **Project-lifecycle operations go through `/forge <sub>`**: `init`, `stoke`, `doctor`, `retrofit`, `status` — anything about the project's relationship to FORGE itself.
- **`/forge:<name>` colon forms** are the harness's plugin-qualified spellings of the same invocables — valid, never advertised, needed only when a name collides. Full routing map: `docs/process-kit/migration-decision-guide.md`.
- **`/forge configure` is the primary configuration surface** (Spec 607); `/configure` and `/config-change` remain valid direct dispatch names for it and `/forge config-change` respectively — both keep working unchanged, the `/forge <sub>` spelling above is simply what's advertised (Spec 580 lifecycle fold).

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
| `/forge:ahead` | Momentum-framed alias for the FORGE orientation surface (dispatches to /now) | command |
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
| `/forge config-change` | Propose and apply changes to agent configuration files | command |
| `/forge configure` | Adjust any defaulted onboarding setting (stack, agents, autonomy, methodology, features, MCP servers) | command |
| `/forge:doctor` | Plugin-qualified escape hatch for the FORGE health diagnostic (dispatches to /forge doctor) | command |
| `/forge` | Unified FORGE project lifecycle command | command |
| `/forge init` | Bootstrap FORGE into a new or existing project, upgrade legacy pre-Copier projects, or create new projects from scratch | command |
| `/forge stoke` | Pull upstream FORGE updates into this project via the content-merge engine | command |
| `/forge onboarding` | First-session interactive project configuration | command |

### Process and review

| Command | Purpose | Form |
|---------|---------|------|
| `/configure-nanoclaw` | Configure NanoClaw hardware key enrollment and messaging | command |
| `/evolve` | Run the KCS Evolve Loop review | skill (explicit) |
| `/nanoclaw` | Manage the NanoClaw container — start, stop, status, logs | command |
| `/synthesize` | Synthesize accumulated project artifacts into refined documents | skill (explicit) |

### /forge subcommands

| Subcommand | Purpose |
|------------|---------|
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

For new projects: `/forge init` → `/forge onboarding` → `/interview` → `/spec` → `/implement`

---

## Process-State Path Keys (`forge.paths.*`, Specs 564/575)

Path indirection for FORGE process state, with two named **layout presets** (Spec 575):
`classic` (the `docs/...` defaults below — what an absent block means) and `contained`
(everything under `.forge/project/` — the default for new scaffolds; keeps FORGE files
segregated from your solution's docs). Choose at `/forge init` (`--layout`), switch later via
`/forge configure` (config-only; physical moves ride the Spec 577 retrofit). Every scaffold also
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
