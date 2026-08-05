---
name: parallel
description: "Run multiple specs in parallel using git worktrees"
workflow_stage: implementation
argument-hint: "[spec-number spec-number ...] [--batch first-last] [--dry-run]"
---

<!-- forge:paths-note (Spec 575): process-state paths in this command (docs/specs,
     docs/sessions, docs/decisions, docs/research, docs/process-kit, docs/backlog.md) are the
     CLASSIC-DEFAULT spellings, not fixed locations. When the project configures forge.paths
     (e.g. the `contained` layout), resolve each key before use — bash: `forge_path <key>`
     (source ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/config.sh, forge_config_load AGENTS.md);
     python: `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py .../runtime_config.py path <key>`. -->
# Framework: FORGE
<!-- multi-block mode: serialized — choice blocks fire at distinct mechanical steps (merge confirmation, conflict resolution, post-merge action). Each block waits for operator response before the next is presented. See docs/process-kit/implementation-patterns.md § Multi-block disambiguation rule. -->
Run multiple specs in parallel using git worktrees and isolated Claude Code agents.

If $ARGUMENTS is empty, `?`, or `help`:
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

## Choose dispatch mode

`/parallel` orchestrates worktree creation, conflict pre-flight, merge-back, and consolidation — but the **canonical dispatch mechanism** (how agents fan out into the worktrees) is **conditional on the configured autonomy level** (read from AGENTS.md, Spec 021 auto-progression config). Per ADR-451 (autonomy-progression principle) and Spec 454, substrate canonicity tracks the autonomy level:

| Autonomy level | Canonical dispatch mode |
|----------------|-------------------------|
| **L0–L2** (supervised / interactive — default operating level) | **Multi-tab** (Specs 351/352/353) |
| **L3+** (autonomous / agent-parallel) | **Native `Agent` + `isolation: "worktree"`** (requires Claude Code >= 2.1.154) |

Read the configured autonomy level from AGENTS.md first, then use the matching canonical mode. Both modes remain available at every level — only the canonical/default label is autonomy-conditional.

| Mode | When canonical | Mechanism | Status |
|------|----------------|-----------|--------|
| **Multi-tab** | Canonical at **L0–L2** | Operator opens N tabs (one per worktree), each runs `/tab <label> feature NNN` then `/implement NNN`. Tabs coordinate via the registry per Specs 351/352/353. | **Canonical at L0–L2**; available as fallback at L3+. |
| **`Agent` + `isolation: "worktree"`** | Canonical at **L3+** | One parent session spawns N `Agent` sub-agents, each with `isolation: "worktree"` and `worktree.baseRef: head` (branch from local HEAD; `fresh` branches from `origin/<default>`). Each implements its assigned spec in its isolated worktree; the parent inspects each worktree before merge. Requires Claude Code >= 2.1.154 (reinforced subagent-isolation guard). **Required permission posture**: allow Edit/Write scoped to the worktree path (e.g. `.worktrees/spec-NNN/**`) only — do NOT globally auto-allow writes or disable permission prompts. | **Canonical at L3+** (Spec 454); available as alternative at L0–L2. |
| **`EnterWorktree`** | — | Solo-session dipping — single tab walks one worktree at a time, runs `/implement`, exits. Serialized, not parallel. | **Solo-session alternative** at any level. Not a parallel-dispatch mechanism. |

**Default behavior**: Step 6 below creates the worktrees, then dispatches per the autonomy-level-canonical mode — at L0–L2 the worktrees are **operator-launched in additional Claude Code tabs** (multi-tab); at L3+ the parent session **spawns native worktree-isolated `Agent` sub-agents** routed through the same pre-flight / inspect / gate-outcome governance. `EnterWorktree` remains a solo-session alternative at any level.

See `docs/process-kit/multi-tab-quickstart.md` § Dispatch mode comparison for the canonical decision table.

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

### [mechanical] Step 2c — Consensus-Review pre-dispatch gate (Spec 590)

`Consensus-Review: true` was a prose convention: `/parallel` dispatched such specs with no check
that a `/consensus` run was ever recorded. Spec 560 was implemented and merged un-vetted under
autopilot; the retroactive consensus then surfaced a real security finding (guard-critical hook
stripping) a pre-implement vet would have caught pre-merge (SIG-560-01). This gate makes the
check mechanical. It is the `/parallel` analog of `/implement` Step 0d — same escape hatches,
same fail-closed posture.

**Scope note**: this gate keys on `Consensus-Review: true` specifically. It does NOT re-implement
`/implement` Step 0d's `BV >= 4 AND (R >= 3 OR E >= 3)` classifier — a spec that Step 0d would
classify as consensus-required still meets Step 0d when its lane agent runs `/implement`. This
gate closes the narrower hole: an explicit `Consensus-Review: true` declaration being dispatched
with nothing recorded against it.

For each spec that survived step 2 above, read its frontmatter:

1. **Trigger check** — if `Consensus-Review:` is absent, or is any value other than the literal
   `true`, this gate does not apply to that spec. Skip it silently and dispatch as today
   (Requirement 3 — zero added friction on the common path). **This is the common case.**

2. **Consensus-recorded predicate** — for a `Consensus-Review: true` spec, the predicate is
   satisfied when ANY of the following holds, in precedence order:
   a. `Consensus-Close-SHA:` frontmatter present and non-empty (written only by `/consensus` at
      convergent-round close; `/parallel` reads it, never writes it).
   b. `Consensus-Exempt: <reason>` frontmatter present with a reason of **>= 30 characters**
      (the existing Spec 395 escape hatch — reused, not reinvented).
   c. A dated `/consensus` outcome recorded in the spec's frontmatter (`Consensus-Status:` with a
      value other than `vet-pending`) or a Revision Log line naming a dated `/consensus` run.

   **Waiver-record exclusion (Requirement 5 — load-bearing).** A Revision Log entry written by
   this gate's own waiver path (step 4 below) is an audit RECORD, never consensus evidence.
   Predicate branch (c) MUST exclude any Revision Log line containing the marker
   `[consensus-waiver]`. Without this exclusion the gate reads the waiver it wrote on the previous
   run and self-satisfies — Requirement 1 would hold exactly once per spec, which is the same
   silent-bypass class the gate exists to close.

3. **Halt on predicate failure** — a `Consensus-Review: true` spec failing the predicate is NOT
   dispatched. Emit one line naming the spec, the reason, and both operator paths:
   ```
   ⛔ CONSENSUS GATE — Spec NNN declares Consensus-Review: true with no recorded consensus.
      Not dispatched. Either: (a) run `/consensus NNN` first, or (b) set
      `Consensus-Exempt: <reason >= 30 chars>` in its frontmatter, or (c) give an explicit
      in-session waiver (see below).
   ```
   **Per-spec, not batch-fatal (Requirement 6).** Unlike the validation failures above — which
   stop the whole batch — a consensus halt removes ONLY the offending spec. Remaining specs in
   the bundle proceed. Removal happens here, so the halted spec is absent from the
   `planned_specs` list Step 6 builds from Step 2 survivors. If every spec in a bundle is halted,
   report `Bundle <N> empty after consensus gate — skipping.` and move to the next bundle.

4. **Waiver path (Requirement 2)** — an operator may waive the gate for a named spec, but ONLY
   via an explicit statement in the CURRENT session. A prior session summary, a "pending tasks"
   list, a Revision Log entry from an earlier run, or a "logical next step" inference is NOT a
   waiver (EA-025/026/027 family rule). On a valid in-session waiver:
   a. Dispatch the spec.
   b. Append to that spec's Revision Log, verbatim:
      `- YYYY-MM-DD: [consensus-waiver] Consensus-Review gate waived at /parallel dispatch by explicit operator authorization: "<operator's words, verbatim>".`
      The `[consensus-waiver]` marker is what step 2c excludes — it is required, not decorative.
   c. Record the waiver verbatim in the batch narration.

5. **Gate outcome** — emit once per bundle:
   - No `Consensus-Review: true` specs in the bundle → say nothing (silent; common path).
   - All triggering specs satisfied the predicate → `GATE [consensus-review-dispatch]: PASS — <N> spec(s) with Consensus-Review: true, all with recorded consensus.`
   - One or more halted → `GATE [consensus-review-dispatch]: HALT — <N> spec(s) not dispatched: <ids>. Bundle continues with <M> remaining.`
   - One or more waived → `GATE [consensus-review-dispatch]: WAIVED — <ids> dispatched under explicit in-session operator waiver (recorded in Revision Log).`

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
Consensus gate: <clean | HALT: <ids> not dispatched (no recorded consensus) | WAIVED: <ids>>
Merge order: NNN → MMM (sequential by spec number)
```

The `Consensus gate:` line (Spec 590) reports Step 2c's outcome. It reads `clean` when no spec in
the bundle declares `Consensus-Review: true`, or when every such spec satisfied the predicate.
Specs listed as HALT are absent from `Specs:` above — the dry run shows exactly what a real run
would dispatch.

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

## [mechanical] Step 6 — Declare planned_specs, create worktrees, and dispatch

**Single source of truth (Spec 435, porting Spec 423)**: this step declares `planned_specs` as an explicit list BEFORE any dispatch, and the dispatch narration (native-agent count at L3+, operator-tab count at L0–L2) is **generated from `planned_specs`** — not authored freehand. The same list drives both the narration and the per-spec dispatch loop, so the count and the spec IDs cannot diverge. This collapses the narration-vs-dispatch defect class that Spec 423 fixed in /consensus (orchestrator narrated 4 reviewers but launched 3).

1. **Declare `planned_specs`**: Build an explicit list of the spec IDs that survived Step 1b ceremony-floor filtering and Step 2 validation for this bundle — one entry per spec to be dispatched. Example:
   ```
   planned_specs = [005, 007, 012]
   ```
   The list is fixed before any worktree creation or agent/tab dispatch. Inline-cheaper-filtered (Step 1b) and failed-validation (Step 2) specs are NOT in `planned_specs`.

2. **Create worktrees** — for each spec in `planned_specs` (in spec-number order):
   0. **(once, before the first creation) Create the run-scoped worktree allowlist
      (Spec 622)**: write `.forge/state/parallel-created-worktrees-<batch-id>.json` with
      the `preexisting` set captured in the same act — the `git worktree list` paths
      present at this moment (harness worktrees, unrelated long-lived worktrees):
      ```json
      {"batch_id": "<batch-id>", "created_at": "<ISO 8601>",
       "preexisting": ["<paths from git worktree list right now>"],
       "worktrees": [], "preserved": false}
      ```
      Allowlist-at-creation + preexisting-at-start means no snapshot-ordering dependence:
      both sets exist before any dispatch. The file is run-scoped by batch-id — a stale
      file from another batch is warned about and never merged into this run's sets.
   1. Create a branch: `spec-NNN` from the current HEAD.
   2. Create a git worktree: `git worktree add .worktrees/spec-NNN spec-NNN`
   3. Report: "Worktree created: .worktrees/spec-NNN on branch spec-NNN"
   3b. **Append the path to the allowlist (Spec 622)**: add `.worktrees/spec-NNN` (absolute
      path) to the allowlist file's `worktrees` array.
   4. **Write the batch-lane contract marker (Spec 475)** into the worktree — this artifact, not the launch prose, is what binds the lane session (ADR-451 corollary; SIG-BATCH-A/B):
      ```bash
      mkdir -p .worktrees/spec-NNN/.forge/state
      cat > .worktrees/spec-NNN/.forge/state/batch-lane.json << EOF
      {
        "batch_id": "<batch id, e.g. YYYYMMDD-HHMM>",
        "spec_id": "NNN",
        "terminal_state": "implemented",
        "forbidden": ["/close", "deferred-scope promotion", "/spec stub creation", "pick-next recommendations"],
        "return_instruction": "Lane terminal state reached. Write a mini session log to docs/sessions/parallel-NNN.md, run /tab close, and report back in the orchestrator tab. /close runs in the orchestrator after merge.",
        "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "orchestrator_session": "<orchestrator tab/session id>"
      }
      EOF
      ```
      Report: "Batch-lane contract written: .worktrees/spec-NNN/.forge/state/batch-lane.json". Lifecycle commands (`/close`, `/implement`, `/spec`) read this marker and enforce the forbidden list inside the lane; the marker dies with the worktree at merge cleanup. The forbidden list is the v1 schema — evolve additively (see docs/process-kit/parallelism-guide.md § Batch-lane contract).

3. **Emit dispatch narration generated from `planned_specs`**: the dispatched-agent count (L3+) or operator-tab count (L0–L2) and the spec IDs MUST equal the contents of `planned_specs` — do not author a count or spec ID that is not in the list. This narration is **generated from `planned_specs`** (Invariant A — Spec 435).

**Dispatch — select by configured autonomy level** (read from AGENTS.md, Spec 021):

**L0–L2 (canonical: multi-tab)**: After all worktrees are created, present the operator with the per-worktree launch instructions:

```
Worktrees created. To launch parallel agents, open one Claude Code tab per worktree:

For each worktree:
  1. Open a new Claude Code tab in the project root.
  2. cd .worktrees/spec-NNN
  3. /tab impl_NNN feature NNN
  4. /implement NNN
  5. When implementation completes, write a mini session log to
     docs/sessions/parallel-NNN.md summarizing what was done, decisions
     made, and issues encountered. Report estimated token usage.
  6. /tab close

Isolation prohibitions (Spec 622 — SIG-OVN-06; these lines are part of the dispatch
contract for every lane):
  - Do NOT create worktrees or branches beyond the one assigned to you.
  - Do NOT run any `git worktree` subcommand.
  - Do NOT run `git restore` or `git checkout --` against paths outside your assigned
    spec's file scope.

Lanes stop at `implemented` — do NOT run /close, promote deferred scope, or
create new specs in a lane. The batch-lane contract marker in each worktree
(Spec 475) enforces this; /close runs here in the orchestrator after merge.

When all tabs report "done", return to this tab and type 'all done' to proceed to merge.
```

Wait for the operator's "all done" signal. At L0–L2 `/parallel` does NOT auto-spawn sub-agents — the multi-tab pattern is operator-launched (see § Choose dispatch mode above).

**L3+ (canonical: native `Agent` + `isolation: "worktree"`)**: The parent session spawns one `Agent` sub-agent per spec, each with `isolation: "worktree"` and `worktree.baseRef: head` (branch from local HEAD; use `fresh` to branch from `origin/<default>`). **Required permission posture**: the operator's settings must allow Edit/Write scoped to the worktree path (e.g. `.worktrees/spec-NNN/**`) only — do NOT globally auto-allow writes or disable permission prompts. Requires Claude Code >= 2.1.154 (reinforced subagent-isolation guard). Each sub-agent implements ONLY its assigned spec; the parent runs the conflict pre-flight before dispatch, inspects each worktree's diff before merge, and emits `GATE [name]: PASS/FAIL` per spec — identical governance to the multi-tab path. The native `isolation: "worktree"` worktree supersedes the manual `git worktree add` in steps 1–2 above for the L3+ path — do not double-create; pass `worktree.baseRef` instead. **Batch-lane contract at L3+ (Spec 475)**: as soon as each native worktree path exists, the parent session writes the same `batch-lane.json` marker (step 2.4 above) into it before the sub-agent begins lifecycle work — sub-agents are bound by the same artifact contract as multi-tab lanes. **Allowlist append at L3+ (Spec 622)**: in the same as-soon-as-the-path-exists moment, the parent appends the native worktree path to the run's allowlist file (step 2.0/2.3b above) — the native path supersedes the manual `git worktree add`, so without this clause the append would never fire on the canonical L3+ path and every orchestrator worktree would false-positive as foreign at merge audit. **Dispatch-prompt prohibitions at L3+ (Spec 622)**: every sub-agent prompt carries the three isolation prohibitions verbatim (no worktree/branch creation beyond the assignment; no `git worktree` subcommands; no `git restore`/`git checkout --` outside the assigned spec's file scope).

**Solo-session alternative (`EnterWorktree`, any level)**: A solo operator may use `EnterWorktree` to enter each worktree one at a time, run `/implement NNN`, then `ExitWorktree`. This **serializes** execution — not parallel. Use only when the canonical mode for the level is unavailable.

Report: "Worktrees ready. Dispatch per autonomy level — L0–L2: awaiting operator multi-tab launch; L3+: native `Agent` fan-out dispatched (worktree-isolated, governance-gated)."

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

## [mechanical] Step 7b — Pre-merge reconciliation gate (Spec 435, porting Spec 423)

Before advancing to Step 8 (merge confirmation), perform reconciliation against `planned_specs`. This gate is the single mechanical check between dispatch and merge — the /parallel analog of Spec 423's pre-aggregation reconciliation gate in /consensus.

1. **Reconcile**: for each spec in `planned_specs`, verify it has either a completion result (✅ completed / ❌ failed from Step 7) OR a recorded dispatch-failure. At L3+ the accounted-for set is the agents the orchestrator spawned and monitored; at L0–L2 the operator is the dispatcher, so this gate verifies that the set reported in the "all done" signal covers `planned_specs`.

2. **If reconciliation passes** (every `planned_specs` entry is accounted-for as completed, failed, or skipped): proceed silently to Step 8.

3. **If reconciliation fails — `planned_specs` has entries with no completion result and no failure record — refuse to advance**: do NOT merge, do NOT proceed to Step 8. Emit a structured diagnostic and stop the bundle:
   ```
   ## Dispatch Reconciliation Failure (Spec 435)
   Bundle planned_specs had unaccounted-for entries.
   - planned: [list from planned_specs]
   - completed/failed: [list of spec IDs with a Step 7 result]
   - missing (no result, no failure): [list of spec IDs]

   Halting bundle before merge. Re-dispatch the missing specs (re-launch their tab/agent) or record explicit failures, then re-run /parallel.
   ```
   Operator decides next action (re-dispatch missing specs, or record them as failures and continue). No auto-retry.

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
   - If gate fails: report failure, ask whether to revert this merge or continue. Either
     way the worktree is preserved at .worktrees/spec-NNN for debugging (Spec 622 — this
     preserve branch was previously implicit).
   - If gate passes: report "Spec NNN merged and gate passed."
4. Report merge status before proceeding to the next spec.

## [mechanical] Step 9b — Merge-time overlap reconciliation gate (Spec 602)

After Step 9 has processed every spec in `planned_specs` for this bundle (all merges attempted,
skips/conflicts recorded) and before Step 10 (shared-file consolidation), run this gate. It closes
the gap where declared-file overlap between two specs in the same batch is only ever caught later,
by a human or the independent validator at `/close` — this step catches it mechanically at the
point the merge lands.

1. **Compute declared-file overlap — reuse, do not duplicate.** Use the IDENTICAL declared-file
   intersection predicate `/now` already computes at `.forge/commands/now.md` § Step 1b, point 3
   ("File-overlap surfacing"): for each pair of specs in `planned_specs` that merged successfully
   in Step 9, read each spec's `## Implementation Summary` `Changed files` list and intersect the
   declared paths. This step does NOT re-derive or restate that algorithm — `/now` Step 1b is the
   single source; here the only difference is the input set (`planned_specs` merged in this
   bundle, vs. `/now`'s implemented-but-unclosed set) and the consequence (test re-run + halt, vs.
   an advisory line).

2. **No overlap (AC3 — zero overhead on the common path)**: if no pair intersects, this step is
   silent — no gate output, no test re-run, no swarm-budget advisory. Proceed directly to Step 10.

3. **Overlap detected** — for each overlapping pair (Spec A, Spec B) sharing file(s) `F`:
   a. Re-run Spec A's own `## Test Plan` commands against the merged tree (current HEAD, after
      Step 9 has merged both A and B).
   b. Re-run Spec B's own `## Test Plan` commands against the same merged tree.
   c. **True-negative path (AC2)**: when both re-runs pass — the expected outcome whenever the
      changed line ranges within `F` are disjoint — report one pass line per pair and continue; no
      operator intervention, no choice block. The batch proceeds to the next pair, then to Step 10.
   d. **Conflict path (AC1)**: if either re-run fails, halt this bundle's finalization — mirrors the
      existing "security-gate FAIL halts the chain" behavior from Spec 498:
      ```
      ⛔ MERGE RECONCILIATION GATE — Spec <A> and Spec <B> both declare <file(s)>; re-run of
         <A|B>'s Test Plan failed against the merged tree:
         <failing command + output summary>
      Batch finalization halted (mirrors Spec 498 "security-gate FAIL halts the chain").
      Resolve the conflict in <file(s)>, then re-run from Step 9b before Step 10 proceeds.
      ```
      Do NOT proceed to Step 10 or Step 13 for this bundle. In `--batch` mode this is a mid-batch
      halt condition (see Step 1 "Mid-batch halt conditions"): report which bundles completed,
      which is in-progress, which are queued, and stop — no auto-retry.

4. **Swarm-budget advisory (Requirement 5)** — emit exactly one line, and ONLY when step 3 actually
   re-ran tests (at least one overlapping pair existed in this bundle):
   ```
   Reconciliation gate: re-ran Test Plan for <N> overlapping pair(s) — incremental cost against
   swarm ceiling (docs/sessions/swarm-budget.yaml, Spec 042). See docs/sessions/swarm-budget-state.md.
   ```
   Never emitted when step 2 (no overlap) applied — silence on the no-overlap path is the AC3
   contract, not just "no gate output" but "no advisory either."

This gate runs once per bundle, in the same per-bundle scope as Steps 2–13 (Step 1 "Bundle
execution semantics"). It must NOT redesign `/parallel`'s worktree isolation model, and it targets
only the declared-file-overlap case `/now` Step 1b already detects — not a general merge-conflict
framework.

## [mechanical] Step 9c — Worktree anti-forking audit (Spec 622)

After Step 9b and before Step 10, run the advisory audit and fold its output verbatim into
the merge summary:

```bash
bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/parallel-worktree-audit.sh <batch-id>
```
(PowerShell: `pwsh ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/parallel-worktree-audit.ps1 <batch-id>`.)

- The audit is ADVISORY ONLY — it always exits 0 and never blocks or halts the merge path.
  Output lines: `ADVISORY: foreign worktree <path> … inspect for out-of-scope changes, then
  remove with 'git worktree remove <path>'` (a dispatch-contract violation — SIG-OVN-06
  class); `attributed: <path> — declared by batch <id> (…)` (sibling-batch worktrees —
  always printed, never silently excluded); `unexplained pre-existing worktree: <path> …`
  (persistent until explained or removed); one aggregate `note:` line for worktrees outside
  /parallel's namespace; `warning:` lines for surviving sibling allowlist files.
- **Allowlist lifecycle (preservation-aware — Spec 622)**: after the audit, remove
  `.forge/state/parallel-created-worktrees-<batch-id>.json` ONLY if every worktree in its
  `worktrees` array was actually removed during merge cleanup. If ANY batch worktree was
  preserved (agent failure, operator abort, merge-conflict skip, or the gate-fail branch in
  Step 9.3), instead set `"preserved": true` in the file and leave it in place — the next
  run's audit then ATTRIBUTES the leftover worktrees to this batch instead of reporting
  unexplained foreign noise.

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
