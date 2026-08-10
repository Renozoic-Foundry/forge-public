# Agent Parallelism Guide

Last updated: 2026-03-13

## Purpose

Claude Code's Agent tool can run multiple independent tasks in parallel, reducing session wall-clock time. This guide identifies which workflow steps are independent and when parallel execution helps vs. hurts.

## When to use parallel agents

**Use when:**
- Multiple independent file reads are needed (e.g., read spec + read backlog + read session log)
- Multiple independent searches (e.g., grep for a pattern in different directories)
- Research tasks that don't depend on each other

**Avoid when:**
- Steps have data dependencies (e.g., read a file, then edit based on what was read)
- The combined output would overwhelm the context window
- The task is simple enough that sequential execution is faster than agent overhead

## Trade-offs

| Factor | Parallel agents | Sequential |
|--------|----------------|------------|
| Wall-clock time | Lower (tasks overlap) | Higher (tasks queue) |
| Context cost | Higher (agent results are verbose) | Lower (direct tool calls are compact) |
| Error handling | Harder (failures may be buried in agent output) | Easier (fail-fast, fix inline) |
| Debugging | Harder (interleaved outputs) | Easier (linear trace) |

**Rule of thumb:** Use parallel agents for 3+ independent reads/searches. Use sequential for edits and anything with dependencies.

## Parallelizable steps by command

### `/implement`
- **Parallel (step 1):** Read spec file + Read README.md + Read CHANGELOG.md (all needed for pre-implementation checklist)
- **Sequential:** All edit steps (each depends on file content read just before)
- **Parallel (step 6):** Update spec status + Update README + Update CHANGELOG + Update backlog (independent tracking file updates, but each requires a prior Read)

### `/close`
- **Parallel (step 1):** Read spec file + Read README.md + Read backlog.md (all needed for status checks)
- **Sequential:** Status transitions (each file edit depends on confirmation)
- **Parallel (step 6):** F1 AC spot-check + F4 backlog confirmation (independent checks)

### `/now`
- **Parallel (all reads):** Read README.md + Read backlog.md + Read latest session log + Read scratchpad (all independent orientation reads)

### `/session`
- **Parallel (step 1):** Read session template + Read error-log.md + Read insights-log.md + Read scratchpad.md (all needed for population)
- **Sequential:** Writing session log entries (depends on conversation mining)

### `/matrix`
- **Parallel (step 3-4):** Read all draft spec files for frontmatter comparison (independent reads)
- **Sequential:** Score verification and correction (depends on read results)

## Write-Permission Boundaries (Spec 237)

During `/parallel` execution, multiple agents run concurrently in isolated worktrees. Certain files are **orchestrator-only** — they must not be modified by individual agents because concurrent writes cause merge conflicts or data loss.

### Orchestrator-only files (agents must NOT write)

These files are shared tracking files that the orchestrator updates in a single post-merge pass:

| File | Reason |
|------|--------|
| `docs/backlog.md` | Rank/score changes from multiple agents collide |
| `docs/specs/README.md` | Status updates from multiple specs produce merge conflicts |
| `docs/specs/CHANGELOG.md` | Append-only log, but concurrent appends duplicate or interleave |
| `docs/sessions/*.md` | Session logs are operator-synthesized, not agent-written |
| `docs/sessions/signals.md` | Signal entries are captured post-merge by the orchestrator |
| `docs/sessions/scratchpad.md` | Shared scratchpad — orchestrator-only during parallel |

### Agent-writable files

Each agent may freely modify files within its spec's scope:

| File type | Example | Notes |
|-----------|---------|-------|
| Spec file | `docs/specs/NNN-*.md` | Only the agent's own spec |
| Implementation files | `src/`, `scripts/`, `template/` | As listed in Implementation Summary |
| Test files | `tests/` | For the agent's spec |
| Agent-local evidence | `tmp/evidence/SPEC-NNN-*/` | Gitignored, no conflict risk |

### Configuration files (case-by-case)

| File | During /parallel | Rationale |
|------|-----------------|-----------|
| `AGENTS.md` | Agent-writable if in spec scope | Config changes are rare; merge conflicts unlikely |
| `CLAUDE.md` | Orchestrator-only | Shared operating contract |
| `docs/process-kit/*.md` | Agent-writable if in spec scope | Distinct sections reduce conflict risk |

### Pre-flight enforcement

`/parallel` Step 3 scans each spec's Implementation Summary for orchestrator-only files. If found, the agent receives a warning but is not blocked — the orchestrator handles the post-merge update instead.

## Always-shared / cross-cutting file set (Spec 478)

`/parallel`'s merge step resolves the orchestrator-only files above in a single post-merge pass, so two lanes touching them do not corrupt each other. But `/matrix`'s **pre-flight** parallel-safety scan (Step 7 parallel-safe-batch detection, Step 11e file-scope isolation, Step 11j execute-all lane construction) decides "parallel-safe" by intersecting only the **declared** `Implementation Summary → Changed files` of each spec. `/implement` touches several cross-cutting files **implicitly** that specs rarely declare, so declared-file disjointness alone can falsely license a "parallel-safe" verdict.

This section is the **single canonical always-shared set**. `/matrix` references it by name — it MUST NOT maintain a second hard-coded copy (drift surface). The set is the union of:

1. **The Spec 237 orchestrator-only files table above** (`docs/backlog.md`, `docs/specs/README.md`, `docs/specs/CHANGELOG.md`, `docs/sessions/*.md`, `docs/sessions/signals.md`, `docs/sessions/scratchpad.md`). These are touched on virtually every `/implement` run (status/changelog/backlog rows, session log, signals), so any two specs plausibly collide on them.
2. **(Retired by Spec 558.)** The former second member — the update-manifest pair
   (`.forge/update-manifest.yaml` + its template mirror) — was retired with the Copier
   surface: `/implement` Step 4e (the manifest-classification gate that made it a shared
   write surface) fired only on `template/` changes and was retired in the same cutover.
   The always-shared set is now the Spec 237 table alone; the soft-overlap mechanism below
   remains for any member of that set.

| Always-shared file / glob | Source | Why pre-flight-shared |
|---------------------------|--------|-----------------------|
| Spec 237 orchestrator-only table (above) | Spec 237 | Tracking files touched on nearly every `/implement` run |

### How `/matrix` uses the set (soft-overlap, not a hard block)

When two specs are declared-file disjoint but one *declares* a member of the always-shared set explicitly, `/matrix` MUST surface a **soft-overlap warning** rather than asserting zero overlap. It does **not** block batching — the realistic case is additive tracking-file entries that `/parallel` merges cleanly. The warning tells the operator (and `/parallel`) to expect a possible merge touch, instead of a false "parallel-safe on disjoint files" guarantee. Genuinely disjoint specs that share **no** declared files and touch **no** member of the always-shared set remain declared parallel-safe — no false-overlap regression. (The pre-558 "manifest-touching via template/ paths" heuristic is retired with the manifest pair.)

## Batch-lane contract (Spec 475)

Prose launch instructions in the orchestrator tab do not bind lane sessions — the 2026-06-12 Sprint 1 batch proved it (SIG-BATCH-A/B: all 4 lane tabs ran full in-branch /close plus deferred-scope stub promotion). The batch-lane contract makes the binding an artifact: `/parallel` Step 6 writes `.forge/state/batch-lane.json` into each lane worktree, and lifecycle commands read it.

### Marker schema (v1)

```json
{
  "batch_id": "<batch id, e.g. YYYYMMDD-HHMM>",
  "spec_id": "NNN",
  "terminal_state": "implemented",
  "forbidden": ["/close", "deferred-scope promotion", "/spec stub creation", "pick-next recommendations"],
  "return_instruction": "<what the lane does at terminal state>",
  "created_at": "<ISO 8601>",
  "orchestrator_session": "<orchestrator tab/session id>"
}
```

The `forbidden` list is the v1 contract — evolve it additively (new entries extend; existing entries never silently change meaning). Schema changes ride a new spec (siblings: deferred 422/425 marker-schema bundle).

### Enforcement points

| Command | Behavior inside a marked worktree |
|---------|-----------------------------------|
| `/close` | Refuses before any gate (Step 0-bl); prints `return_instruction` + orchestrator pointer. Malformed marker = still refuse (fail closed). |
| `/implement` | Terminal step emits only the lane-complete instruction (mini session log, `/tab close`, report to orchestrator); pick-next suppressed. |
| `/spec` | Refuses NEW spec creation (Step 0-bl); candidates routed via `/note` to the orchestrator (spec-number collision prevention). `/revise` of the lane's assigned spec stays allowed. |
| `/parallel` | Writes the marker at worktree creation (multi-tab) or immediately after native-worktree spawn (L3+). |

### Lifecycle and staleness

- The marker lives and dies with the worktree — orchestrator merge + worktree cleanup removes it. No GC step needed.
- Markers older than **24 hours** are treated as stale: guards warn-and-proceed (an orphaned worktree should not permanently brick a tab). Delete the marker deliberately to clear the warning.
- Single-tab sessions never see any of this: every guard skips silently when no marker exists.
- Residual risk: these are prose guards executed by the lane agent. The Spec 470 gate-holding probe held 3/3 under headless L3; if a live batch shows a lane ignoring the artifact guard, that event triggers the hook-enforcement escalation spec (ADR-451 layer).

## Merge-safe shared artifacts (Spec 529)

Last verified: 2026-07-07

Every artifact written by parallel lanes is classified below. Classification basis:
AGENTS.md `multi_agent.agent_tier_rules` (Spec 134 write ownership) + the Spec 237
orchestrator-only table + the 2026-07-05 overnight-batch conflict evidence
(activity-log.jsonl ×2, spec Revision Logs ×2 — both hand-resolved).

**Posture (consensus 2026-07-07)**: sharding/orchestrator-ownership is the default for
multi-writer human-readable artifacts; `merge=union` is the EXCEPTION, applied only to
append-only line-oriented streams where duplication/reordering is provably harmless —
each attribute carries its safety argument in `.gitattributes`, and
`test-spec-529-merge-safety.sh` proves both zero-conflict merges AND no silent line
duplication (union's failure mode is invisible duplication, not visible conflict).

| Artifact | Written by lanes? | Classification | Rationale |
|----------|-------------------|----------------|-----------|
| `docs/sessions/activity-log.jsonl` | YES (`write_activity_log: true`) | **union** | Self-contained JSON lines, embedded `timestamp`; consumers sort/filter — interleave order immaterial |
| `.forge/state/security-gate.jsonl` | YES (gate verdicts per lane, Spec 497) | **union** | Append-only PASS/FAIL records keyed by ts+gate; aggregated per spec; no overwrite semantics |
| `docs/sessions/agent-file-registry.md` | YES (role-invocation log lines) | **union** | Single-line pipe-delimited appends with embedded timestamps; rows self-contained |
| `docs/sessions/doctor-history.jsonl` | YES (SessionStart hook per worktree, Spec 530) | **union** | Append-only JSONL; entry absorbed from Spec 530's forerunner attribute |
| Spec files (Revision Logs) | YES (each lane edits only ITS OWN spec) | **manual convention** | Union is UNSAFE on frontmatter-bearing files: two lanes editing the same `- Status:` line under union keep BOTH lines (silent corruption). Convention below |
| `docs/sessions/signals.md` | NO (`write_signals: false`) | orchestrator-only | Operator synthesizes; never a lane collision surface |
| `docs/sessions/scratchpad.md` | NO (`write_scratchpad: false`) | orchestrator-only | Same |
| Session logs (`YYYY-MM-DD-NNN.md`) | NO (`write_session_logs: false`) | orchestrator-only | Lanes write `parallel-NNN.md` mini-logs (distinct files — no collision) |
| `docs/backlog.md` / README index / CHANGELOG | NO (`write_backlog/specs_readme/specs_changelog: false`) | orchestrator-only | Renderer-owned or operator-owned (Specs 254/398) |
| `.forge/state/events/<id>/` | YES (per-spec streams) | n/a (gitignored, per-clone) | Never merged; Spec 534's renderer fallback covers cross-clone gaps |
| `.forge/state/score-audit.jsonl` | YES | n/a (gitignored) | Per-clone advisory sink |

**Sharding classification: EMPTY-BY-FINDING (AC1 third leg).** The audit found zero
artifacts requiring the sharding subsystem: every candidate named in the spec
(signals, scratchpad, CHANGELOG events) is orchestrator-only by the Spec 134 write
rules and therefore not a parallel collision surface. AC1's "one sharded artifact"
fixture leg is vacuously satisfied and this is recorded EXPLICITLY here and in the
spec's Revision Log (DA 2026-07-07 — never a silent AC reinterpretation). No appender
helper ships (COO constraint moot); the CTO >1-sharding-subsystem boundary is not
approached.

### Revision-Log merge convention (manual union)

When two branches both append Revision-Log entries to the SAME spec file and git
reports a conflict: keep BOTH entries, newest-first, delete the conflict markers —
never discard either side's entry. Frontmatter conflicts (e.g. both branches changed
`- Status:`) are resolved by the LIFECYCLE-LATER value (closed > implemented >
in-progress > draft) since lifecycle only moves forward. This stays manual by design:
spec files carry structured frontmatter where automatic union would silently keep
both sides of a same-line edit.

## Merge-time overlap reconciliation gate (Spec 602)

Last verified: 2026-07-29

Worktree isolation means two specs in the same `/parallel` batch that declare overlapping files
never see each other's edits until merge. Before Spec 602, nothing mechanically verified the
merged result was correct — overlap surfaced only when a human or the independent validator
happened to notice at `/close`, after the merge had already landed (see SIG-591-01, SIG-596-02,
SIG-597-CI-489). `/parallel` Step 9b closes that gap at the point the merge lands, not several
specs later.

**Placement**: Step 9b runs once per bundle, after Step 9 (sequential merge-back) has processed
every spec in `planned_specs`, and before Step 10 (shared-file consolidation).

**Algorithm — reused, not duplicated**: Step 9b computes declared-file overlap using the exact
same predicate `/now` Step 1b already uses for its unclosed-spec file-overlap surfacing (read each
spec's `## Implementation Summary` `Changed files` list, intersect the declared paths). The two
call sites differ only in input set and consequence:

| | `/now` Step 1b | `/parallel` Step 9b |
|---|---|---|
| Input set | implemented-but-unclosed specs | `planned_specs` merged in this batch |
| Consequence on overlap | advisory line only | re-run each spec's own Test Plan against the merged tree |
| Consequence on conflict | n/a (advisory never blocks) | halt batch finalization (mirrors Spec 498's "security-gate FAIL halts the chain") |

**Behavior by case**:
- **No declared-file overlap** (the common path): the gate is completely silent — no output, no
  test re-run, no swarm-budget advisory. Zero overhead on batches where specs don't collide.
- **Overlapping files, disjoint changed line ranges** (true-negative case): both specs' Test Plan
  commands are re-run against the merged tree and both pass — the gate reports a pass line and the
  batch proceeds with no operator intervention.
- **Overlapping files, genuinely conflicting changes**: at least one specs' Test Plan re-run fails.
  The gate reports which spec pair and file triggered it, and halts batch finalization — the
  operator resolves the conflict and re-runs from Step 9b before Step 10 can proceed. In `--batch`
  mode this is a mid-batch halt condition (same class as swarm-budget exhaustion or a `halt`
  conflict-resolution strategy firing).

**Swarm-budget advisory**: a one-line advisory referencing `docs/sessions/swarm-budget.yaml`
(Spec 042) is emitted ONLY when the gate actually re-runs tests (i.e., at least one overlapping
pair existed). Batches with no overlap never see this line — the incremental token/time cost is
surfaced exactly when it is incurred, not on every `/parallel` invocation.

**Scope boundary**: Step 9b targets only the declared-file-overlap case `/now` Step 1b already
detects. It does not redesign `/parallel`'s worktree isolation model, and it is not a
general-purpose merge-conflict-detection framework — conflicts outside declared-file overlap
(e.g., undeclared incidental edits) are out of scope, same as Spec 602's own Scope section.

## Spec-ID collision repair — the NNN[a-z] convention (Spec 532)

Last verified: 2026-07-07

`/spec` mints IDs as max+1 over the local ∪ remote-default-branch view
(`.forge/bin/spec-next-id.sh` — fetch-before-mint, Spec 532). The residual
true-race window (two clones minting after the same base before either pushes)
is caught by the CI backstop `check-spec-id-uniqueness.sh` in
`sync-and-lint.yml` — the PR run goes red on any duplicate `spec_id` or
filename-vs-frontmatter mismatch.

**Repair symmetry rule**: the **not-yet-merged side re-suffixes**; the side
already merged to the default branch always keeps its number. Never rewrite the
corpus, never renumber the merged spec. If neither side is merged yet, the
later-opened PR re-suffixes (or re-mints via `spec-next-id.sh`, which now sees
the other side after a fetch).

**Worked example** — the CI check fails your PR with
`DUPLICATE spec_id 540` naming your `docs/specs/540-my-feature.md` and an
already-merged `docs/specs/540-other-thing.md`:

```bash
git mv docs/specs/540-my-feature.md docs/specs/540a-my-feature.md
# Edit the file: change the `# Spec 540 - ...` header to `# Spec 540a - ...`
bash .forge/bin/check-spec-id-uniqueness.sh   # must print OK before re-push
```

The `NNN[a-z]` suffix grammar is first-class across the derived views
(Spec 493): suffixed specs render, index, and sort correctly — a repair is a
rename, not a schema exception.

**Multi-remote note**: `spec-next-id.sh` consults only the `origin` remote's
default branch (resolved dynamically, `main` fallback). In multi-remote
topologies the other remotes' spec corpora are invisible to the mint — the CI
backstop on each remote's own PR flow is the guarantee there.

**Merge-blocking note**: the CI backstop *detects* (red run). To make it
*block* merges, mark the `sync-and-lint` check as required in the host's
branch-protection settings — host-side config, outside FORGE's repo scope.

## Worktree isolation prohibitions + anti-forking audit (Spec 622)

**Worked example — SIG-OVN-06 (2026-07-15, consumer /parallel run)**: a spawned subagent
forked a SIBLING worktree it was never assigned and ran an out-of-scope `git restore`
inside it. No existing surface covered this shape: Spec 237 governs writes *inside* an
assigned worktree, Spec 476 guards commits, Spec 602 reconciles merge-time overlaps —
none prohibits or detects a subagent *creating additional worktrees*. The prohibitions
below are prompt-level text; SIG-OVN-06 is proof prose guidance can fail, which is why
the detection exists alongside them.

**The three dispatch-contract prohibitions** (carried verbatim in every /parallel dispatch
prompt — multi-tab instructions and L3+ native-Agent prompts alike):
1. Do NOT create worktrees or branches beyond the one assigned.
2. Do NOT run any `git worktree` subcommand.
3. Do NOT run `git restore` / `git checkout --` against paths outside the assigned spec's
   file scope.

**The advisory audit** (`.forge/lib/parallel-worktree-audit.sh <batch-id>`, /parallel
Step 9c; always exit 0, never blocks): compares `git worktree list` at merge time against
the run-scoped allowlist file (`.forge/state/parallel-created-worktrees-<batch-id>.json`,
created at bundle start with a `preexisting` capture, appended at every worktree creation
— including the L3+ as-soon-as-path-exists clause). Classification is
**attribution-not-exclusion**: sibling-batch paths print as `attributed:` lines (forged
allowlist content can relabel a line, never silence it); unexplained pre-existing
worktrees in `/parallel`'s namespace re-emit a persistent advisory every run (a rogue
worktree becomes permanently visible, never grandfathered); worktrees outside the
namespace (e.g. the harness's `.claude/worktrees/agent-*`) appear in one aggregate line
naming every path; a current-run worktree declared nowhere is a `foreign worktree`
advisory with an inspect-then-remove next action, in ANY namespace. The allowlist file is
preservation-aware: retained with `"preserved": true` whenever any batch worktree
survives merge cleanup, so the next run attributes leftovers instead of alarming on them.

**Accepted residual (consensus R2, CISO)**: a subagent that creates, uses, and removes a
worktree before merge-time capture evades the diff. Hook-level interception graduates to
its own spec on a recorded trigger: a SECOND foreign-worktree incident, or this detector
firing on any live /parallel run.
