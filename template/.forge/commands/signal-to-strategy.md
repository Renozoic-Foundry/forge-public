---
name: signal-to-strategy
description: "Turn external research signals into scored FORGE advantage hypotheses"
workflow_stage: planning
---
# Framework: FORGE
# Model-Tier: sonnet
Run the Signal-to-Strategy Loop: review external AI/software-development research, map it to
FORGE gaps, generate and score advantage hypotheses, and recommend ONE PRD/spec/watchlist
output. Sibling to `/brainstorm` — `/brainstorm` mines internal project state; this command
mines the **outside world** plus FORGE state.

Contract: `docs/process-kit/signal-to-strategy-loop.md`. Spec: 458.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /signal-to-strategy — Convert external research signals into scored FORGE advantage hypotheses.
  Usage: /signal-to-strategy [focus area]
  Arguments: focus area (optional) — e.g. "loops", "skills", "tool gateways".
  Behavior:
    - Inventories + classifies configured research sources (relevance: primary/supporting/adjacent)
    - Extracts reusable concept primitives across the 10 required concept families
    - Builds a FORGE coverage/gap matrix with evidence
    - Generates >=5 advantage hypotheses, each with conventional / FORGE-native / maverick variants
    - Scores hypotheses (leverage, novelty, evidenceability, compounding, risk/cost)
    - Recommends ONE output via the intent-to-action gate: PRD, /spec draft, or watchlist item
    - Writes a dated run artifact to docs/research/signal-to-strategy-<YYYY-MM-DD>.md
  Boundaries:
    - Never auto-creates specs from raw clipping text (intent-to-action gate)
    - Never runs /close, git push, destructive git, or PR creation without explicit authorization
    - Summarizes + cites source URLs; never copies article bodies
  See: docs/process-kit/signal-to-strategy-loop.md, ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/research_sources.py
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Step 1 — Read the loop contract
Read `docs/process-kit/signal-to-strategy-loop.md`. The contract (§1) defines inputs, allowed
and prohibited actions, budget, stop conditions, escalation, and verification. All subsequent
steps operate within it.

## [mechanical] Step 2 — Inventory & classify sources
Default source set (override via $ARGUMENTS or AGENTS.md config):
- `D:\Obsidian\Vaults\AI Research\AI Research\Clippings` (or operator-configured corpus)
- `docs/digests/` (unreviewed digests first; see CLAUDE.md § Digest review)

Run the inventory helper for a structured pass (degrades gracefully if the corpus is absent):
```
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/research_sources.py <corpus-path> --format=json
```
For each source record: file name, title, source URL, author (when available),
created/published date, relevance class (**primary** / **supporting** / **adjacent**).
Do NOT copy article bodies — summarize and cite URLs only (contract Constraint).

## [mechanical] Step 3 — Extract concept primitives
Extract concepts at the level of **reusable primitives**, not article summaries, across the
ten required families (contract §2): loops & automations; skills & plugin packaging;
planner/generator/evaluator harnesses; outcome rubrics & evaluator calibration;
intent-to-action governance; tool retrieval & gateways; middleware/control planes;
distributed-systems reliability; knowledge/memory substrates; agent-facing discoverability.

## [mechanical] Step 4 — Build the FORGE gap matrix
For each concept family, assign one verdict (`strong` / `partial` / `missing` /
`present-not-enforced` / `overbuilt` / `successor-fit`) with FORGE evidence (cite paths) or an
explicit "not verified" note. (Contract §3.)

## [mechanical] Step 5 — Generate maverick hypotheses
For each high-leverage family, generate **>= 3** hypotheses (contract §4):
**conventional** (adopt best practice), **FORGE-native** (recombine with a FORGE mechanism),
**maverick** (invert/challenge for a breakthrough). The maverick pass is mandatory and must
*challenge* the best-practice option — a bare "add a command" recommendation is insufficient
unless it survives the maverick comparison. Each hypothesis records its competitive-advantage
rationale and the evidence required to validate **or kill** it. Produce **>= 5** hypotheses total.

## [mechanical] Step 6 — Score hypotheses
Score each on five axes 1–5 (contract §5): leverage, novelty, evidenceability, compounding,
risk/cost. `advantage = L + N + E + C − R`. The output MUST explain why the selected output
beats the obvious best-practice adoption path and at least two plausible alternatives.

## [decision] Step 7 — Intent-to-action gate (select ONE output)
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

## [mechanical] Step 8 — Write the run artifact
Write `docs/research/signal-to-strategy-<YYYY-MM-DD>.md` recording all evidence-trail items
(contract §7): sources reviewed, concepts extracted, gap matrix, hypotheses (>=5 with three
variants), selected output + rationale vs >=2 alternatives, rejected alternatives, and
source-freshness/uncertainty notes (especially clipping-sourced Claude Code / Codex / MCP
behavior — flag as "source material, not current truth; verify against official docs").
If a loop action repeated successfully, append a skill candidate per contract §8.

## [mechanical] Step 9 — Stop at the recommendation
The loop STOPS here. It does NOT run `/close`, `git push`, destructive git operations, or PR
creation without explicit current-turn operator authorization (contract escalation boundary).
If the recommendation is FORGE replacement or plugin spin-out, STOP and require a separate
successor PRD + explicit operator approval before any FORGE surface is replaced.

Report: the run artifact path, the selected output, and the next operator action (e.g.
"Run `/spec <title>` to draft the recommended spec" or "Added to watchlist").

---

**Integration**: `/brainstorm` (internal-state opportunities) should suggest
`/signal-to-strategy` when unreviewed digests or external research accumulate; this command's
Step 7 hands off to `/spec` (create-spec) or `/note`/watchlist (watch/defer). See
`docs/process-kit/command-integration-map.md`.
