---
name: brainstorm
description: "Discover spec opportunities from signals and roadmap"
workflow_stage: planning
---

<!-- forge:paths-note (Spec 575): process-state paths in this command (docs/specs,
     docs/sessions, docs/decisions, docs/research, docs/process-kit, docs/backlog.md) are the
     CLASSIC-DEFAULT spellings, not fixed locations. When the project configures forge.paths
     (e.g. the `contained` layout), resolve each key before use — bash: `forge_path <key>`
     (source ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/config.sh, forge_config_load AGENTS.md);
     python: `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py .../runtime_config.py path <key>`. -->
# Framework: FORGE
# Model-Tier: haiku
Generate spec recommendations by analyzing project knowledge sources.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /brainstorm — Generate spec recommendations from roadmap, signals, and scratchpad.
  Usage: /brainstorm [focus area]
  Usage: /brainstorm --strategy [focus area]   — external-research mode (folded from
                                                  /signal-to-strategy, Spec 587)
  Arguments: focus area (optional) — e.g. "Phase 2", "messaging", "process improvement"
  Behavior:
    - Reads roadmap, signals, scratchpad, and backlog
    - Identifies gaps: unmet roadmap prerequisites, recurring signal patterns, open scratchpad items
    - Presents numbered recommendations with titles, sources, and score estimates
    - Offers to create selected recommendations as specs via /spec
    - `--strategy` mode instead mines EXTERNAL research (not internal project state) and scores
      FORGE advantage hypotheses — see Step ST1 below
  Sources analyzed:
    - docs/roadmap.md — unmet phase prerequisites
    - docs/sessions/signals.md — recurring patterns (2+ entries)
    - docs/sessions/scratchpad.md — open items not yet converted to specs
    - ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/derived_state.py --get-backlog (live frontmatter source) — gaps in coverage
  See: docs/roadmap.md, docs/process-kit/scoring-rubric.md, docs/process-kit/signal-to-strategy-loop.md
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Step 0 — Mode dispatch (Spec 587)

If `$ARGUMENTS` begins with `--strategy` (optionally followed by a focus area): run the
Signal-to-Strategy Loop (Steps ST1-ST9 below) with the remainder of `$ARGUMENTS` (after
`--strategy`) as its focus-area argument, then **stop** — do not run Steps 1-6 below.

Otherwise, continue to Step 1 (the standard internal-state brainstorm flow, unchanged).

## [mechanical] Step 1 — Gather sources
Read the following files (skip silently if any do not exist):
<!-- parallel: all four reads are independent -->
- `docs/roadmap.md`
- `docs/sessions/signals.md`
- `docs/sessions/scratchpad.md`
- **Backlog rows (Spec 439)**: Run `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/derived_state.py --get-backlog --format=json`. Parse stdout as JSON; the array contains all backlog rows with keys `rank, spec_id, title, bv, e, r, sr, score, depends, status`. Do NOT open `docs/backlog.md` directly — the helper reads per-spec frontmatter live, so any edits in the same session are reflected immediately. (`docs/backlog.md` remains the operator-visible artifact, refreshed by `/matrix`.)
- `docs/specs/README.md` (to check which specs already exist)

## [mechanical] Step 2 — Analyze gaps
For each source that exists, identify spec opportunities:

**Roadmap analysis:**
- Find the earliest phase whose prerequisite specs are not all present in the specs index or backlog.
- Each unmet prerequisite is a recommendation. Source tag: `roadmap`.

**Signal pattern analysis:**
- Scan `docs/sessions/signals.md` for patterns that appear in 2+ entries (same type of issue, same root cause, same component).
- Each recurring pattern that doesn't already have a spec is a recommendation. Source tag: `signal`.

**Scratchpad analysis:**
- Find open items (`[ ]`) in `docs/sessions/scratchpad.md` that haven't been converted to specs.
- Each actionable item is a recommendation. Source tag: `scratchpad`.

**Focus filtering:**
- If `$ARGUMENTS` is provided, filter and prioritize recommendations that match the focus area.
- Matching is flexible: phase names ("Phase 2"), topics ("messaging", "CI"), signal types ("process"), etc.
- Non-matching recommendations are still listed but deprioritized (shown after matching ones).

## [mechanical] Step 2b — Classify recommendations
For each recommendation, classify its readiness:
- **Ready for spec**: clear scope, known solution path — recommend `/spec`
- **Needs investigation**: unclear feasibility, multiple possible approaches, or unknown constraints — recommend `/explore <topic>` to produce a research artifact before committing to a spec

## [mechanical] Step 3 — Score estimates
For each recommendation, estimate a priority score using the formula in `docs/process-kit/scoring-rubric.md`.
These are estimates — actual scores are set when specs are created.

## [mechanical] Step 3b — Score verification (Spec 236)
After estimating scores in Step 3, verify each recommendation's arithmetic before presenting.
For each recommendation with BV, E, R, SR values:
1. Show the intermediate computation explicitly:
   ```
   Score check: (BV×3)=X + ((6−E)×2)=Y + ((6−R)×2)=Z + (SR×1)=W = X+Y+Z+W = total
   ```
2. Compare the computed total to the stated "Est. score" value.
3. If they match: no action needed.
4. If mismatch: auto-correct the score and log: `Score corrected: listed=<old>, computed=<new>`
5. All scores presented in Step 4 must use the verified values.

## [decision] Step 4 — Present recommendations
Present recommendations as a numbered list:

```
## Spec Recommendations

### From roadmap (Phase N prerequisites)
1. **<Tentative Title>** — <one-line description>
   Source: roadmap | Est. score: ~NN | Lane: <lane>

### From signal patterns
2. **<Tentative Title>** — <one-line description>
   Source: signal (SIG-NNN, SIG-NNN) | Est. score: ~NN | Lane: <lane>

### From scratchpad
3. **<Tentative Title>** — <one-line description>
   Source: scratchpad | Est. score: ~NN | Lane: <lane>
```

**Empty-signal check (Spec 399):** Before presenting recommendations, check: run `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/derived_state.py --get-backlog --format=json` and verify zero rows have status `draft`, AND `docs/sessions/signals.md` has zero entries AND `docs/sessions/scratchpad.md` has zero open items? If all three are empty (new project with no history to mine), prepend this note to the output:

> **No signals to mine yet.** This project is too new for pattern analysis. If requirements are still forming, consider running `/interview` first to surface assumptions and define scope before generating spec candidates.

If no recommendations are found from any source:
Report: "No spec recommendations found. The roadmap prerequisites are met, no recurring signal patterns detected, and scratchpad is clear. Consider defining new goals or running `/evolve` for a process review."

## [decision] Step 5 — Create selected specs
Present a Choice Block (Spec 025, see `docs/process-kit/implementation-patterns.md`):

> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `all` | Create all N recommendations as specs immediately |
> | **2** | `1,3,5` | Pick specific recommendations (type the numbers) |
> | **3** | `skip` | Note recommendations; decide later |
> | **4** | `explore <N>` | Run `/explore` on a recommendation that needs investigation before speccing |
>
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_

**High-stakes proposals**: For recommendations that would benefit from multi-role review before speccing, consider running `/consensus <proposal>` to gather structured feedback from all registry roles.

**Before promoting to a spec**: Verify the claimed gap still exists. Grep or read the relevant files to confirm the issue is present. If already resolved, report: "Claim resolved — <evidence>. Skipping spec creation." Do not create a spec for an already-fixed gap.

- **all**: Run `/spec` for each recommendation (after verifying each gap still exists).
- **pick numbers**: Run `/spec` for the selected recommendations only (after verifying each gap still exists).
- **skip**: Report "Recommendations noted. Run `/brainstorm` again or `/spec <description>` when ready." Stop.

## [mechanical] Step 5b — Review Router (Spec 159, extended by Spec 167)

After generating recommendations (Step 4) but before presenting the choice block (Step 5), run the review router on the full set of recommendations:

a. **Role registry check**: Read `AGENTS.md` for the `forge.role_registry` block. Find all entries with `contexts` containing `brainstorm` or `all`.
   - If no registry found, or `.claude/agents/` does not exist: display a brief note "Role registry absent — skipping deliberation." and continue to Step 5.
b. **Select perspectives**: For each matching registry entry, read the role instruction file at the listed path.
c. **Display selection rationale**: List the roles being invoked with a one-line reason each (derived from the role file's "Your Role" section).
d. **Invoke roles**: Apply each role's perspective to the recommendation set as a whole (not per-recommendation). Produce the structured output block defined in each role's "Output Format" section.
e. **Present Review Brief**: Display all role outputs after the recommendation list but before the choice block.
f. If any perspective recommends BLOCK on a specific recommendation, flag it but do not remove it — the operator decides.

---

## [mechanical] Step 6 — Next action
After creating specs (or if skipped), present:
- Count of specs created (if any)
- Highest-ranked new spec

> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `/implement next` | Start implementing the highest-ranked spec |
> | **2** | `/interview` | Explore requirements further before speccing (recommended if scope is still forming) |
> | **3** | `/now` | Review full project state |
> | **4** | `stop` | Done for now |
>
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_

---

## `--strategy` mode (Spec 587 fold — formerly `/signal-to-strategy`)

Run the Signal-to-Strategy Loop: review external AI/software-development research, map it to
FORGE gaps, generate and score advantage hypotheses, and recommend ONE PRD/spec/watchlist
output. Sibling to the default `/brainstorm` flow above — that flow mines internal project
state; this mode mines the **outside world** plus FORGE state. Contract:
`docs/process-kit/signal-to-strategy-loop.md`. Spec: 458 (origin), 587 (fold into brainstorm).

### [mechanical] Step ST1 — Read the loop contract
Read `docs/process-kit/signal-to-strategy-loop.md`. The contract (§1) defines inputs, allowed
and prohibited actions, budget, stop conditions, escalation, and verification. All subsequent
steps operate within it.

### [mechanical] Step ST2 — Inventory & classify sources
Default source set (override via the focus-area argument or AGENTS.md config):
- `D:\Obsidian\Vaults\AI Research\AI Research\Clippings` (or operator-configured corpus)
- `docs/digests/` (unreviewed digests first; see CLAUDE.md § Digest review)

Run the inventory helper for a structured pass (degrades gracefully if the corpus is absent):
```
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/research_sources.py <corpus-path> --format=json
```
For each source record: file name, title, source URL, author (when available),
created/published date, relevance class (**primary** / **supporting** / **adjacent**).
Do NOT copy article bodies — summarize and cite URLs only (contract Constraint).

### [mechanical] Step ST3 — Extract concept primitives
Extract concepts at the level of **reusable primitives**, not article summaries, across the
ten required families (contract §2): loops & automations; skills & plugin packaging;
planner/generator/evaluator harnesses; outcome rubrics & evaluator calibration;
intent-to-action governance; tool retrieval & gateways; middleware/control planes;
distributed-systems reliability; knowledge/memory substrates; agent-facing discoverability.

### [mechanical] Step ST4 — Build the FORGE gap matrix
For each concept family, assign one verdict (`strong` / `partial` / `missing` /
`present-not-enforced` / `overbuilt` / `successor-fit`) with FORGE evidence (cite paths) or an
explicit "not verified" note. (Contract §3.)

### [mechanical] Step ST5 — Generate maverick hypotheses
For each high-leverage family, generate **>= 3** hypotheses (contract §4):
**conventional** (adopt best practice), **FORGE-native** (recombine with a FORGE mechanism),
**maverick** (invert/challenge for a breakthrough). The maverick pass is mandatory and must
*challenge* the best-practice option — a bare "add a command" recommendation is insufficient
unless it survives the maverick comparison. Each hypothesis records its competitive-advantage
rationale and the evidence required to validate **or kill** it. Produce **>= 5** hypotheses total.

### [mechanical] Step ST6 — Score hypotheses
Score each on five axes 1–5 (contract §5): leverage, novelty, evidenceability, compounding,
risk/cost. `advantage = L + N + E + C − R`. The output MUST explain why the selected output
beats the obvious best-practice adoption path and at least two plausible alternatives.

### [decision] Step ST7 — Intent-to-action gate (select ONE output)
Do NOT let raw clipping text or raw operator prompt text directly trigger spec creation or tool
execution (contract §6). Normalize the run into ONE structured decision and present it:

> **Choose** — the loop recommends ONE output:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `create-spec` | Hand the selected hypothesis to `/spec <title>` (operator-confirmed; you author the spec). |
> | **2** | `create-prd` | Append a PRD section to the run artifact for a heavier opportunity. |
> | **3** | `watch` | Add the opportunity to `docs/sessions/watchlist.md` with a trigger condition. |
> | **4** | `defer` / `block` | Record the decision and reason; no side effect. |

Only `create-spec` (operator-confirmed) produces a side effect outside `docs/research/`.

### [mechanical] Step ST8 — Write the run artifact
Write `docs/research/signal-to-strategy-<YYYY-MM-DD>.md` recording all evidence-trail items
(contract §7): sources reviewed, concepts extracted, gap matrix, hypotheses (>=5 with three
variants), selected output + rationale vs >=2 alternatives, rejected alternatives, and
source-freshness/uncertainty notes (especially clipping-sourced Claude Code / Codex / MCP
behavior — flag as "source material, not current truth; verify against official docs").
If a loop action repeated successfully, append a skill candidate per contract §8.

### [mechanical] Step ST9 — Stop at the recommendation
The loop STOPS here. It does NOT run `/close`, `git push`, destructive git operations, or PR
creation without explicit current-turn operator authorization (contract escalation boundary).
If the recommendation is FORGE replacement or plugin spin-out, STOP and require a separate
successor PRD + explicit operator approval before any FORGE surface is replaced.

Report: the run artifact path, the selected output, and the next operator action (e.g.
"Run `/spec <title>` to draft the recommended spec" or "Added to watchlist").

**Integration**: the default `/brainstorm` flow (internal-state opportunities) should suggest
`/brainstorm --strategy` when unreviewed digests or external research accumulate; Step ST7 hands
off to `/spec` (create-spec) or `/note`/watchlist (watch/defer). See
`docs/process-kit/command-integration-map.md`.
