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
