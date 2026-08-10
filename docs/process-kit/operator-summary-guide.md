<!-- Last updated: 2026-06-24 -->
# Framework: FORGE
# Operator-summary guide — the four-part summary (Spec 497)

`/close` and `/now` present operator-facing summaries in a single **four-part** shape,
designed for minimal cognitive load: the operator should see *what happened*, *what they
still need to judge*, *why it matters*, and *what to do next* — in that order, lean by
default. This guide is the canonical format reference; the command bodies cite it.

The format is **lean by default** and honors `forge.output.verbosity` (Spec 225): `lean`
shows the four sections tersely; `verbose` (or an explicit operator request) expands the
per-item detail. Both modes always carry the same four labeled sections — verbosity changes
depth, never structure.

## The four parts

### 1. Accomplished & machine-verified
What shipped, plus the checks a machine already confirmed (gate outcomes). One headline line
("<what shipped> — N gates PASS") followed by the machine-verified ticks. Medium-confidence
items are flagged inline ("(medium confidence — override if concerned)"). This is the
"you don't need to re-check these" section.

### 2. Needs human validation
A **bullet checklist** — each row a single thing the human can verify and tick. This is the
canonical "Needs Your Review" set: human-judgment items (UX, external content, physical-logic
checks, irreversible actions, LOW-confidence checks) rendered as ticks, not prose paragraphs.
If nothing needs human judgment, say so explicitly ("Nothing requires human judgment — all
ACs machine-verified.") rather than omitting the section.

### 3. Why it matters
One or two lines linking the deliverable to the spec's `## Objective` — and to the PRD,
security posture, or compliance obligation when the scope touches them. This is the
**value-link**: it answers "why was this worth doing," and it is the part the close-time
structural check verifies is present (Spec 497 AC3). A summary that lists what changed but
never says why is incomplete.

### 4. Recommended next actions
When a decision is open: **≥2 options, each with explicit pros and cons, then a named
recommendation** (Spec 497 AC4). When no decision is open, this collapses to the single
highest-value next step. The point is to make the operator's decision cheap — the options
and trade-offs are laid out, and FORGE states which one it recommends and why, without
removing the operator's choice.

## Worked example (lean, `/close`)

```
## Review Brief — Spec 497

### 1. Accomplished & machine-verified
Implement-time telemetry capture + four-part summaries + 30-day acceptance rate shipped — 9 gates PASS.
- [x] Tests — test-spec-497 PASS (7/7 ACs)
- [x] Lint — validate-bash.sh clean
- [x] Single-source parity — forge-parity.sh --check clean

### 2. Needs human validation
- [ ] **[UX]** /close + /now four-part output reads cleanly on a real spec — Expected: four labeled sections, value-link present; Actual: see this brief; AI assessment: structure is mechanical, prose quality is human judgment.
- [ ] **[Scope]** 3 files beyond the declared changed-files (acceptance_rate.py, token_usage.py, schema) — confirm acceptable.

### 3. Why it matters
Closes Spec 258 AC#5 (acceptance-rate read side, open since May) and moves capture to
implement-time so /close becomes batched human sign-off over on-disk evidence — the
operator's 2026-06-22 minimal-cognitive-load ask.

### 4. Recommended next actions
- Option A — /close 497 now. Pros: ships the value; queue stays drained. Cons: review the scope delta first.
- Option B — inspect the 3 scope-delta files, then close. Pros: full confidence. Cons: a few minutes.
- **Recommendation**: Option A after a glance at Part 2 — the delta is substrate logic the spec frames as "living in the substrate."
```

## When NOT to use it

The four-part shape is for operator-facing *summaries* at `/close` and `/now`. It does not
replace gate-outcome lines (`GATE [...]: PASS/FAIL`), choice blocks, or error/abort messages —
those keep their own formats and are never suppressed by verbosity (Spec 225).

See also: `docs/process-kit/output-verbosity-guide.md` (lean/verbose rules),
`docs/process-kit/gate-categories.md` (machine-verifiable vs human-judgment classification),
`docs/process-kit/positive-signal-taxonomy.md` (the wins-to-keep capture bucket).
