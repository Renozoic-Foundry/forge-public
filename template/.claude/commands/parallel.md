---
name: parallel
description: "Run multiple specs in parallel using git worktrees"
workflow_stage: implementation
---
# Framework: FORGE
<!-- multi-block mode: serialized — choice blocks fire at distinct mechanical steps (merge confirmation, conflict resolution, post-merge action). Each block waits for operator response before the next is presented. See docs/process-kit/implementation-patterns.md § Multi-block disambiguation rule. -->
Run multiple specs in parallel using git worktrees and isolated Claude Code agents.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /parallel — Execute 2+ independent specs in parallel via git worktrees.
  Usage:
    /parallel <spec-number> <spec-number> [spec-number ...] [--dry-run]
    /parallel --batch '<bundle1>' '<bundle2>' [...] [--dry-run]
  Arguments:
    spec-numbers (required, 2+) — e.g. /parallel 005 007 012
    --batch (optional) — execute multiple bundles sequentially. Each bundle is a
      single-quoted string of space-separated spec IDs. Example:
      /parallel --batch '005 007' '012 014'
      Bundles run in argument order; per-bundle conflict pre-flight, swarm budget,
      and Step 13 close-all all fire per bundle. Spec 362 introduced this mode.
    --dry-run (optional) — show planned worktrees and conflict scan without executing
  Cross-platform quoting (`--batch` mode):
    bash / Git Bash: use single-quoted strings as shown.
    PowerShell: also use single-quoted strings, OR pass the stop-parsing token
      `--%` before the bundle args to bypass PowerShell's argument transformation.
    /parallel does NOT silently rewrite quoting — operators are responsible for
      using shell-compatible quoting.
  Behavior:
    - Validates all specs are draft or approved status
    - Scans spec scopes for file overlap and warns if detected
    - Creates spec-NNN branches in isolated git worktrees
    - Launches Claude Code agents in each worktree
    - Waits for all agents to complete
    - Requires human confirmation before merge phase
    - Sequential merge-back in spec-number order
    - Runs harness gate after each merge (if applicable)
    - Consolidates mini session logs into single session log
    - Preserves failed worktrees for debugging
  See: docs/specs/003-parallel-worktree-execution.md, docs/process-kit/long-running-task-patterns.md, docs/process-kit/implementation-patterns.md
  ```
  Stop — do not execute any further steps.

---

## When NOT to use /parallel

`/parallel` has a fixed ceremony floor — worktree creation, branch management, agent spawn, mini-session-log per agent, sequential merge-back, and shared-file consolidation. That floor only pays back when the implementation work itself is substantial enough to justify isolation. For trivial-edit specs the ceremony cost exceeds the work, and inline execution in the main session is faster and cheaper.

Run inline (skip `/parallel`) if ANY of the following is true:
- Total LOC delta across the candidate specs is ≤ ~50 lines (rough operator estimate, not a hard count).
- Any candidate spec is doc-only (no source-code changes at all).
- Candidate specs share a file or adjacent sections (merge surface > divergence surface).
- Operator estimates implementation time < 30 minutes per spec.

Concrete evidence: `docs/sessions/signals.md` SIG-CLOSE-01 (2026-04-24) documents a `/parallel 310 311` invocation on two small-change specs where the worktree + agent + merge ceremony substantially exceeded the implementation cost; bailing out to inline saved an estimated ~30% of tool calls and a full round of merge/consolidation.

If in doubt, run inline first — /parallel can always be invoked later.

## [mechanical] Step 0z — Lane-mismatch warning (Spec 353)

If `.forge/state/active-tab-*.json` marker exists for this session, read its `lane` field.

This command's natural lane (per `docs/process-kit/multi-tab-quickstart.md` § Lane choice):

| Command | Lane |
|---------|------|
| /parallel | feature |
| /spec | feature OR process-only (depending on spec subject) |
| /scheduler | feature |
| /forge stoke | process-only |

If `marker.lane` does not match this command's natural lane, emit a one-line warning: `⚠ Action targets <expected> lane; active tab is '<marker.lane>'. Continue?` Soft-gate only — do not refuse. Operator decides whether the mismatch matters.

Skip silently if no marker exists.

## [mechanical] Step 1 — Parse arguments

Parse $ARGUMENTS to extract spec numbers, batch bundles, and flags.

**Single-bundle mode (default, backward compatible)**:
- Extract all numeric tokens as spec IDs (zero-pad to 3 digits).
- Detect `--dry-run` flag if present.
- If fewer than 2 spec numbers provided: stop and report: "At least 2 spec numbers are required. Usage: /parallel 005 007 [012 ...]"
- Set `BUNDLES = [<single bundle of all parsed spec IDs>]`.

**Multi-bundle batch mode (Spec 362, `--batch` flag detected)**:
- Detect the `--batch` flag. All subsequent single-quoted arguments are bundle strings.
- Each bundle string is a space-separated list of spec IDs (numeric tokens, zero-padded to 3 digits).
- A bundle MAY contain a single spec ID (single-spec bundle is acceptable in `--batch` mode — execution is the same as `/parallel A B` minus the 2-spec floor; the floor is a single-bundle-mode constraint, not a multi-bundle constraint).
- Set `BUNDLES = [<bundle 1>, <bundle 2>, ...]` in argument order.
- If `BUNDLES` is empty after parsing (operator typed `/parallel --batch` with no bundle args): stop and report: "No bundles specified. Usage: /parallel --batch 'NNN NNN' 'MMM MMM'"
- Cross-platform quoting per the help text — `/parallel` does not silently transform input.

**Bundle execution semantics (both modes)**:
- The remainder of this command (Steps 2–13) operates on a single bundle. In single-bundle mode the loop iterates exactly once. In `--batch` mode the loop iterates over `BUNDLES` in argument order, running Steps 2–13 per bundle.
- Step 0z (lane-mismatch warning) fires ONCE at invocation, BEFORE the bundle loop — not per bundle (per Spec 362 AC 13). The lane is defined at command invocation, not per-bundle.
- Step 13 close-all choice block fires ONCE PER BUNDLE inside the loop — operators in an N-bundle batch see N close-all prompts, preserving per-bundle authorization granularity (Spec 362 AC 10).
- Mid-batch halt conditions: swarm budget exhaust, conflict-halt under `conflict_resolution: halt`, operator interrupt, OR context compaction between bundles. On halt, report which bundles completed, which is in-progress (if any), which are queued — and exit without further bundle execution. Operators must re-enter `/matrix` to re-issue an `execute-all` choice; there is no `--resume` flag (Spec 362 Constraint).

## [mechanical] Step 1b — Ceremony-floor pre-flight (Spec 362)

Before each bundle's agent dispatch, evaluate every spec in the bundle against the "When NOT to use /parallel" rule (see top of this file). Filter specs matching ANY of:
- LOC ≤ ~50 — sum the approximate LOC across files listed in the spec's `## Implementation Summary` `Changed files` list (rough heuristic, not a hard count).
- Doc-only paths — every listed path matches `docs/`, `*.md`, or `README*` (no source-code paths).
- `Token-Cost: $` in frontmatter AND no other heavyweight indicator (e.g., `Consensus-Review: true`, `R >= 3`, `E >= 3`).

For each filtered spec, report: `inline-cheaper — <spec-id> skipped from this batch (<reason>); run inline.` Then proceed with the unfiltered specs.

**Placeholder fallback (Spec 362 Req 4)**: If a draft spec's `## Implementation Summary` `Changed files` list contains the literal `<path>` placeholder OR the section is missing entirely, `/parallel` does NOT filter that spec — placeholder content cannot be evaluated, and operator-included specs are trusted by default.

**Empty bundle**: If a bundle becomes empty after filtering (every spec was filtered as inline-cheaper), `/parallel` skips that bundle entirely and proceeds to the next. Report: `Bundle <N> empty after ceremony-floor filter — skipping.`

This filter lives in `/parallel`, not in `/matrix` — `/matrix` does not need to learn LOC heuristics.

## [mechanical] Step 2 — Validate specs

For each spec number:
1. Read `docs/specs/NNN-*.md`.
2. Check status:
   - `draft` or `approved` → eligible. Record the spec title, scope (files listed in Scope section), and change lane.
   - `in-progress` → stop and report: "Spec NNN is already in-progress. Complete it first or use /implement."
   - `implemented`, `closed`, `deprecated` → stop and report: "Spec NNN is `<status>` and cannot be implemented."
3. Collect the list of files mentioned in each spec's "Scope" and "Requirements" sections for conflict detection.

If any spec fails validation, stop and report all failures at once — do not proceed with a partial set.

## [mechanical] Step 3 — Pre-flight conflict scan (Spec 041)

Load conflict resolution config from `docs/sessions/scheduler-config.yaml` (skip if absent — use default: `conflict_resolution: worktree`).

**Orchestrator-only boundary check (Spec 237):** Before scanning for inter-spec conflicts, check each spec's Implementation Summary for orchestrator-only files (see `docs/process-kit/parallelism-guide.md` § Write-Permission Boundaries):
- Orchestrator-only files: `docs/backlog.md`, `docs/specs/README.md`, `docs/specs/CHANGELOG.md`, `docs/sessions/*.md`, `docs/sessions/signals.md`, `docs/sessions/scratchpad.md`, `CLAUDE.md`
- If any spec's Implementation Summary lists orchestrator-only files:
  ```
  ⚠ ORCHESTRATOR-ONLY FILES IN SCOPE — Spec NNN lists files that are orchestrator-managed during /parallel:
  - <file list>
  These files will NOT be modified by the agent. The orchestrator handles post-merge updates.
  ```
  Remove these files from the agent's `files_in_scope` before dispatching. The agent's `/implement` will skip these; the orchestrator updates them in the post-merge pass (Step 9+).

Compare the file scopes across all specs:
1. For each pair of specs, compute the intersection of their scoped files (excluding orchestrator-only files already removed above).
2. Record file ownership in `docs/sessions/agent-file-registry.md` (create if absent):
   ```
   # Agent File Registry — YYYY-MM-DD HH:MM
   | File | Claimed by | Spec |
   |------|-----------|------|
   | path/to/file.md | Spec NNN agent | NNN |
   ```
   This registry enables real-time conflict queries during execution (step 7).
3. If any overlap is found, apply the configured `conflict_resolution` strategy:
   - **`worktree`** (default): report the overlap and continue — worktree isolation means conflicts surface at merge time where they can be resolved interactively:
     ```
     ⚠ FILE OVERLAP DETECTED (resolution: worktree — merge-time conflict expected):
     - Spec NNN and Spec MMM both touch: <file1>, <file2>
     - Both will proceed in isolated worktrees; resolve conflicts during merge (step 9).
     ```
   - **`halt`**: stop and report — do not run the lower-priority spec in this batch:
     ```
     ⛔ FILE OVERLAP DETECTED (resolution: halt):
     - Spec NNN and Spec MMM both touch: <file1>, <file2>
     - Spec MMM removed from this batch. Re-queue or run separately after Spec NNN.
     ```
     Remove the conflicting lower-priority spec(s); continue with remaining.
   - **`queue`**: remove lower-priority spec from this batch and note it should run after:
     ```
     ⚠ FILE OVERLAP DETECTED (resolution: queue):
     - Spec MMM queued to run after Spec NNN (ordering dependency on shared files).
     ```
4. If `conflict_resolution=worktree` and overlap exists: ask confirmation before continuing:
   "Overlapping files detected. Worktrees will isolate execution; merge conflicts expected in step 9. Proceed? (yes/no)"
   - If `no`: stop.
   - If `yes` or `--dry-run`: continue.

If no overlap is found, report: "Pre-flight conflict scan: clean — no file overlap detected."

## [decision] Step 4 — Dry-run report (if --dry-run)

If `--dry-run` flag is set, report the execution plan and stop:
```
DRY RUN — Parallel Execution Plan
==================================
Specs: NNN (<title>), MMM (<title>)
Branches: spec-NNN, spec-MMM
Worktree paths: .worktrees/spec-NNN, .worktrees/spec-MMM
Conflict scan: <clean | overlapping files listed>
Merge order: NNN → MMM (sequential by spec number)
```
Stop — do not execute.

## [mechanical] Step 5 — Inline-approve draft specs

For each spec with status `draft`:
1. Validate completeness (objective, scope, ACs, test plan filled; change lane selected).
2. If complete:
   a. Update `Status: in-progress` in the spec file.
   b. Add a dated revision entry: `YYYY-MM-DD: Approved inline via /parallel. Status → in-progress.`
   c. Update the spec's row in `docs/specs/README.md` to `in-progress`.
   d. Add a CHANGELOG entry: `- YYYY-MM-DD: Spec NNN approved inline via /parallel.`
3. If incomplete: stop and report what is missing. Do not proceed with partial approvals.

## [mechanical] Step 5b — Swarm budget pre-flight (Spec 042)
Read `docs/sessions/swarm-budget.yaml` (skip silently if absent — no budget enforcement).

If config exists:
a. Calculate per-agent allocation: `per_agent_usd = swarm_ceiling_usd / N` (N = number of specs being run in parallel).
b. Report:
   ```
   Swarm Budget Pre-flight
   =======================
   Swarm ceiling: $X.XX USD / K tokens
   Agents: N
   Per-agent allocation: $Y.YY USD
   Alert thresholds: 50% ($A.AA), 80% ($B.BB), 90% ($C.CC)
   Notification: <log-only | nanoclaw>
   ```
c. If swarm_ceiling_usd is 0 or unset: skip enforcement, report "No swarm budget ceiling configured."
d. Initialize `docs/sessions/swarm-budget-state.md` with: start time, N agents, per-agent allocation, swarm ceiling, thresholds.

## [mechanical] Step 6 — Create worktrees and launch agents

For each spec (in spec-number order):
1. Create a branch: `spec-NNN` from the current HEAD.
2. Create a git worktree: `git worktree add .worktrees/spec-NNN spec-NNN`
3. Report: "Worktree created: .worktrees/spec-NNN on branch spec-NNN"

Then, for each worktree, launch a Claude Code agent:
- Use the `EnterWorktree` tool to spawn an isolated agent in each worktree.
- Each agent receives the instruction: "Run /implement NNN in this worktree. When complete, write a mini session log to docs/sessions/parallel-NNN.md summarizing what was done, decisions made, and any issues encountered. Report your estimated token usage (input + output) in the mini session log."
- All agents run in parallel — do not wait for one to finish before starting the next.

Report: "Launched <N> parallel agents. Waiting for all to complete..."

## [decision] Step 7 — Wait, budget tracking, and completion

Monitor all agents until completion. As each agent finishes:
- Report: "Agent for Spec NNN: <completed | failed>"
- If failed: report the error context and note: "Worktree preserved at .worktrees/spec-NNN for debugging."

**Budget tracking (Spec 042 — if swarm-budget.yaml exists)**:
- As agents report token usage in their mini session logs, aggregate total spend:
  `estimated_cost_usd = (total_input_tokens / 1M × cost_per_1m_input_usd) + (total_output_tokens / 1M × cost_per_1m_output_usd)`
- At each threshold crossing (50%, 80%, 90%, 100%):
  - If `notify_via=nanoclaw`: send alert via `mcp__nanoclaw__send_message`:
    ```
    ⚠️ FORGE Swarm Budget Alert — <threshold>% reached
    Swarm: $X.XX / $Y.YY (N agents, elapsed: T min)
    Per-agent: Spec NNN=$A.AA, Spec MMM=$B.BB
    Action: <info | wrap up | HALTING ALL AGENTS>
    ```
  - If `notify_via=log-only`: append to `docs/sessions/swarm-budget-state.md`.
- At 100% ceiling: halt all remaining agents. Set `halt_reason: budget_ceiling_reached` in state file. Report halt to human.

Once all agents have finished (or halted), present the summary:
```
Parallel Execution Results
===========================
Spec NNN — <title>: ✅ completed | ❌ failed (<reason>)
Spec MMM — <title>: ✅ completed | ❌ failed (<reason>)

Completed: X/Y specs
Failed worktrees preserved: .worktrees/spec-NNN (if any)
```

If all specs failed, stop and report. Do not proceed to merge.

## [decision] Step 8 — Human confirmation before merge

Present:
```
Ready to merge. Order: NNN → MMM (by spec number).
Failed specs will be skipped.
```

> **Choose** — type a number or keyword:
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **1** | 1 | `merge` | Default after agents complete; sequential is safe | Begin sequential merge (NNN → MMM) |
> | **2** | 2 | `inspect` | Review diff before committing to merge | List changed files per worktree before deciding |
> | **3** | — | `abort` | Use only if agents went off-track | Abort — worktrees preserved for manual handling |

If `inspect`: for each completed worktree, run `git diff --stat spec-NNN..main` (or equivalent) and display the changed files. Then re-present the choice block (without the inspect option).

Wait for human confirmation. Do not auto-proceed.

## [mechanical] Step 9 — Sequential merge-back

For each completed spec (in spec-number order):
1. Merge: `git merge spec-NNN --no-ff -m "Merge Spec NNN — <title> (parallel execution)"`
2. If merge conflict:
   - Report the conflicting files.
   - Present:
     > **Merge conflict in Spec NNN** — type a number:
     > | # | Rank | Action | Rationale | What happens |
     > |---|------|--------|-----------|--------------|
     > | **1** | 1 | `resolve` | Direct path; conflict is real and needs operator | Pause for manual conflict resolution, then continue |
     > | **2** | — | `skip` | Defer this spec; keep batch moving | Skip this spec — preserve worktree, continue to next |
   - If `skip`: skip this spec, preserve worktree, continue to next.
   - If `resolve`: pause for human resolution, then continue.
3. If merge succeeds and a test command is configured:
   - Run the harness gate (test + lint).
   - If gate fails: report failure, ask whether to revert this merge or continue.
   - If gate passes: report "Spec NNN merged and gate passed."
4. Report merge status before proceeding to the next spec.

## [mechanical] Step 10 — Shared-file consolidation

After all merges complete, check for shared files that may need manual consolidation:
- `README.md` — verify no duplicate or conflicting sections
- `docs/specs/CHANGELOG.md` — ensure entries are in chronological order
- `docs/backlog.md` — verify consistency
- `docs/sessions/signals.md` — merge any duplicate signal entries

Report any files that need manual review.

## [mechanical] Step 11 — Session log consolidation

1. Read each mini session log from `docs/sessions/parallel-NNN.md`.
2. Create or update today's session log (`docs/sessions/YYYY-MM-DD-NNN.md`):
   - Combine summaries from all parallel agents.
   - Merge decisions, pain points, and spec triggers.
   - Note which specs were executed in parallel.
   - Record any merge conflicts or consolidation issues.
3. Delete the mini session logs after consolidation.

## [mechanical] Step 12 — Cleanup

For each successfully merged spec:
1. Remove the worktree: `git worktree remove .worktrees/spec-NNN`
2. Delete the branch: `git branch -d spec-NNN`

For failed specs:
- Preserve the worktree and branch.
- Report: "Failed worktrees preserved for debugging: .worktrees/spec-NNN"

## [mechanical] Step 13 — Final report

Present:
```
Parallel Execution Complete
=============================
Merged: Spec NNN, Spec MMM
Failed/Skipped: Spec PPP (if any)
Session log: docs/sessions/YYYY-MM-DD-NNN.md
Preserved worktrees: .worktrees/spec-PPP (if any)
```

For each successfully merged spec, read the spec file and extract the first sentence of the `## Objective` section.

<!-- safety-rule: session-data — if today's session log has unsynthesized spec activity AND ## Summary is unpopulated, /session ranks 1 and stop is downgraded to —. See docs/process-kit/implementation-patterns.md § Session-data safety rule. -->

> **Choose** — type a number or keyword:
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **1** | 1 | `close all` | Drains all merged specs to closed status | Run `/close` for each merged spec sequentially |
> | **2** | 2 | `close NNN` | Selective close; finish one at a time | Close a specific merged spec (type spec number). _<objective>_ |
> | **3** | — | `implement next` | Skip close; resumes solve loop | Skip close — start next implementation |
> | **4** | 2 | `session` | Synthesize the parallel arc; especially if multi-spec | Run `/session` to update the session log |
> | **5** | — | `stop` | Downgraded if today's session log has unsynthesized entries | End session — review deliverables offline |
>
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_
