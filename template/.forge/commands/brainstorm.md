---
name: brainstorm
description: "Discover spec opportunities from signals and roadmap"
model_tier: haiku
workflow_stage: planning
---
# Framework: FORGE
# Model-Tier: haiku
Generate spec recommendations by analyzing project knowledge sources.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /brainstorm — Generate spec recommendations from roadmap, signals, and scratchpad.
  Usage: /brainstorm [focus area]
  Arguments: focus area (optional) — e.g. "Phase 2", "messaging", "process improvement"
  Behavior:
    - Reads roadmap, signals, scratchpad, and backlog
    - Identifies gaps: unmet roadmap prerequisites, recurring signal patterns, open scratchpad items
    - Presents numbered recommendations with titles, sources, and score estimates
    - Offers to create selected recommendations as specs via /spec
  Sources analyzed:
    - docs/roadmap.md — unmet phase prerequisites
    - docs/sessions/signals.md — recurring patterns (2+ entries)
    - docs/sessions/scratchpad.md — open items not yet converted to specs
    - docs/backlog.md — gaps in coverage
  See: docs/roadmap.md, docs/process-kit/scoring-rubric.md
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Step 1 — Gather sources
Read the following files (skip silently if any do not exist):
<!-- parallel: all four reads are independent -->
- `docs/roadmap.md`
- `docs/sessions/signals.md`
- `docs/sessions/scratchpad.md`
- `docs/backlog.md`
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

**Empty-signal check:** Before presenting recommendations, check: does `docs/backlog.md` have zero draft specs AND `docs/sessions/signals.md` have zero entries AND `docs/sessions/scratchpad.md` have zero open items? If all three are empty (new project with no history to mine), prepend this note to the output:

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
