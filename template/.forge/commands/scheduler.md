---
name: scheduler
description: "Run multi-agent scheduler for dependency-aware parallel execution"
model_tier: sonnet
workflow_stage: lifecycle
---
# Framework: FORGE
Run the multi-agent scheduler: wave-based dependency-aware parallel spec execution.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /scheduler — Wave-based dependency-aware parallel spec execution across the backlog.
  Usage: /scheduler [--max-concurrent N] [--dry-run] [--spec-filter <status>]
  Arguments:
    --max-concurrent N  — override max concurrent agents per wave (default: from config)
    --dry-run           — show wave plan and dependency graph without running
    --spec-filter       — filter specs to run (default: draft; options: draft|approved|all)
  Behavior:
    - Reads backlog and constructs a dependency graph from spec prerequisites
    - Computes waves via topological sort (Wave 1 = no deps, Wave 2 = deps in Wave 1, etc.)
    - Displays wave plan before execution for human confirmation
    - Executes waves sequentially; specs within each wave run in parallel
    - Failed specs propagate: dependents in later waves are skipped, independent specs continue
    - Budget ceiling enforced per wave (Spec 042)
    - Conflict detection runs for each wave batch (Spec 041)
  Config: docs/sessions/scheduler-config.yaml, docs/sessions/swarm-budget.yaml
  See: docs/specs/040-multi-agent-scheduler.md, docs/specs/183-wave-parallelism-scheduler.md
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Step 1 — Load scheduler config

Read `docs/sessions/scheduler-config.yaml` (skip silently if absent — use defaults).
Defaults:
- `max_concurrent: 3`
- `dependency_file: docs/sessions/scheduler-deps.yaml` (optional)
- `conflict_resolution: halt` (halt | worktree | queue)
- `notify_via: log-only`

Read `docs/sessions/swarm-budget.yaml` (skip silently if absent — no budget enforcement).
If present, extract:
- `swarm_ceiling_usd` — maximum total cost across all waves
- `wave_budget_ceiling` — maximum cost per wave (defaults to `swarm_ceiling_usd / estimated_wave_count` if not set)

Apply `--max-concurrent N` override if present in $ARGUMENTS.
Apply `--spec-filter` override (default: `draft`).

## [mechanical] Step 2 — Build dependency graph

1. Read `docs/backlog.md` — collect all specs with status matching `--spec-filter`.
2. For each spec, read its spec file (`docs/specs/NNN-*.md`) to extract:
   - **Prerequisites**: any spec IDs listed in the spec body under "Dependencies:", "Requires:", or "Blocked by:" or "Out of scope" mentions of "(Spec NNN)" — treat as soft dependency only if that spec is incomplete.
   - **Files in scope**: file list from Scope section (for conflict detection).
3. Build a directed acyclic graph (DAG):
   - Node: each spec ID
   - Edge A → B: spec B cannot start until spec A is complete
4. Report the dependency graph:
   ```
   Dependency Graph
   ================
   Nodes: N specs
   Edges: M dependencies
   Independent (no prerequisites): NNN, MMM, PPP
   Dependent: QQQ → NNN, RRR → MMM + PPP
   ```

## [mechanical] Step 3 — Compute waves (Spec 183)

Perform a layered topological sort to group specs into waves:

1. **Wave 1**: All specs with no incomplete prerequisites (independent specs).
2. **Wave 2**: All specs whose prerequisites are entirely in Wave 1.
3. **Wave N**: All specs whose prerequisites are entirely in Waves 1 through N-1.
4. Continue until all specs are assigned to a wave or identified as blocked (circular dependency or prerequisite outside the current batch).

**Max concurrency enforcement**: If a wave contains more specs than `max_concurrent`, split the wave into sub-batches:
- Wave 1a: first `max_concurrent` specs (parallel)
- Wave 1b: remaining specs (parallel, after Wave 1a completes)
- Sub-batches within a wave have no dependency ordering — they're split purely for concurrency limits.

**Permanently blocked specs**: Specs whose prerequisites are not in the batch at all (e.g., depend on a spec not matching `--spec-filter`) are flagged as permanently blocked and excluded from the wave plan.

Report:
```
Wave Plan
=========
Wave 1: Spec NNN (<title>), Spec MMM (<title>) — parallel
Wave 2: Spec QQQ (<title>) — depends on NNN from Wave 1
Wave 3: Spec RRR (<title>) — depends on MMM + QQQ

Permanently blocked (prerequisites outside batch):
  Spec SSS — waiting for Spec TTT (status: closed, not in batch)
```

## [mechanical] Step 4 — Wave plan display and budget check

Present the wave plan with budget estimates:

```
## Wave Execution Plan

| Wave | Specs | Dependencies | Est. Agents | Budget Check |
|------|-------|-------------|-------------|--------------|
| 1 | NNN, MMM | none | 2 | ✅ within ceiling |
| 2 | QQQ | NNN (Wave 1) | 1 | ✅ within ceiling |
| 3 | RRR | MMM + QQQ (Waves 1-2) | 1 | ✅ within ceiling |

Total: N specs across M waves
Estimated parallel agents (max at once): K
```

**Budget ceiling check per wave**: If `swarm-budget.yaml` exists:
- For each wave, compute: `wave_cost = num_agents_in_wave × estimated_per_agent_cost`
- If `wave_cost > wave_budget_ceiling`: warn and suggest splitting:
  ```
  ⚠ Wave N exceeds budget ceiling ($X.XX > $Y.YY).
  Split into sub-batches or reduce concurrency.
  ```

## [decision] Step 5 — Dry-run or confirmation

If `--dry-run` flag is set:
```
SCHEDULER DRY RUN — Wave Plan
===============================
<wave plan from Step 4>

Conflict pre-check per wave:
  Wave 1: NNN ↔ MMM — <clean | overlap in: file1, file2>
  Wave 2: QQQ — single spec, no intra-wave conflicts
```
Stop — do not execute.

If not dry-run, present:
> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `run` | Execute the wave plan |
> | **2** | `adjust` | Modify concurrency or wave assignments before running |
> | **3** | `abort` | Cancel — no specs executed |

Wait for confirmation.

## [mechanical] Step 6 — Initialize state

Initialize the scheduler state in `docs/sessions/scheduler-state.md`:
```
# Scheduler State — YYYY-MM-DD HH:MM

## Wave Plan
| Spec | Title | Wave | Status | Dependencies |
|------|-------|------|--------|-------------|
| NNN  | ...   | 1    | pending | — |
| MMM  | ...   | 1    | pending | — |
| QQQ  | ...   | 2    | pending | NNN |

## Execution Log
(appended as waves complete)
```

## [mechanical] Step 7 — Execute waves

**Wave loop** (iterate through waves sequentially):

For each Wave N (in order):

a. **Check prerequisites**: Verify all specs in this wave have their prerequisites completed from prior waves.
   - If a prerequisite **failed** in a prior wave: skip the dependent spec. Report:
     ```
     ⏭ Spec QQQ skipped — prerequisite Spec NNN failed in Wave 1.
     ```
   - If a prerequisite **succeeded**: the spec is cleared to run.
   - Independent specs in the same wave always run regardless of other specs' failures.

b. **Conflict pre-check (Spec 041)**: For each pair of specs in the wave, compare scoped files:
   - Apply the configured `conflict_resolution` strategy (halt/worktree/queue).

c. **Budget pre-check (Spec 042)**: If `swarm-budget.yaml` exists:
   - Calculate wave cost: `num_agents × estimated_per_agent_cost`
   - Check against remaining budget (ceiling minus total spent so far)
   - If would exceed ceiling: split wave into smaller sub-batches that fit within budget
   - Report budget status before launching

d. **Execute wave via /parallel**: Invoke `/parallel <NNN> <MMM> ...` with all cleared specs in this wave.
   - All specs in the wave run in parallel.
   - Wait for all agents in the wave to complete before proceeding to the next wave.

e. **Record wave results**: Update `scheduler-state.md`:
   ```
   ## Wave N — completed
   - Spec NNN: ✅ completed (elapsed: T min)
   - Spec MMM: ❌ failed (<reason>)
   - Budget spent this wave: $X.XX
   - Cumulative budget: $Y.YY / $Z.ZZ
   ```

f. **Propagate failures**: For each failed spec in this wave, mark all its dependents in subsequent waves as `skipped (prerequisite failed)`.

g. Proceed to Wave N+1.

## [mechanical] Step 8 — Final scheduler report

Present:
```
Scheduler Complete — Wave Summary
====================================
Total specs: N across M waves
Completed: NNN ✅, MMM ✅, QQQ ✅
Failed: PPP ❌ (<reason>)
Skipped (prerequisite failed): RRR (depends on PPP)
Permanently blocked: SSS (prerequisite outside batch)

Wave execution:
  Wave 1: 2/2 completed (elapsed: T min)
  Wave 2: 1/1 completed (elapsed: T min)
  Wave 3: 0/1 skipped (prerequisite failed)

Budget: $X.XX / $Y.YY (Z% used)
Session log: docs/sessions/YYYY-MM-DD-scheduler.md
```

Update `docs/sessions/scheduler-state.md` with final status.
If any specs failed, preserve their worktrees and report locations.

## [mechanical] Next action

> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `close all` | Run `/close` for each completed spec |
> | **2** | `close NNN` | Close a specific completed spec |
> | **3** | `rerun` | Re-run scheduler for failed/skipped specs |
> | **4** | `session` | Update the session log |
> | **5** | `stop` | End — review results offline |
>
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_
