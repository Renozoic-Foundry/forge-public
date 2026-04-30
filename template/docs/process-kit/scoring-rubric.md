<!-- Last updated: 2026-04-07 -->
# Framework: FORGE
# Prioritization Scoring Rubric

Last updated: 2026-04-07

Claude uses this rubric to assign priority scores to proposed specs. Scores are recorded in the spec frontmatter (`Priority-Score:`) and aggregated in [docs/backlog.md](../backlog.md).

---

## Formula

```
Priority Score = (BV × 3) + ((6 − E) × 2) + ((6 − R) × 2) + (SR × 1)
Maximum possible score: 40
```

Effort and Risk are inverted: lower effort and lower risk increase priority.

---

## Dimensions

### BV — Business Value (weight 3)

<!-- customize: update the BV anchor descriptions to reflect your project's core goal -->
How much does this spec move the product toward its core goal?

| Score | Anchor |
|-------|--------|
| 5 | Directly enables a primary user workflow that is currently blocked or missing |
| 4 | Completes or significantly improves an existing important workflow |
| 3 | Useful capability; meaningful but not on the critical path |
| 2 | Nice-to-have; small incremental improvement |
| 1 | Primarily internal/technical; no direct user-facing impact |

**Process integrity anchor (Spec 151)**: If a spec fixes a documented FORGE process defect, assign **BV=5** regardless of other factors.

A **process defect** is a flaw in FORGE's own methodology that produces wrong outputs when the process is followed correctly — not a feature gap, improvement request, or bug in a consumer project.

*Qualifying test*: "If a competent agent follows this command as written, will it produce incorrect results or silently skip a required gate?" → Yes = process defect → BV=5.

**Examples**:
- ✓ Qualifying — Spec 142: auto-chain in `/implement` bypassed the human-validation gate, allowing the lifecycle to advance to `closed` without human confirmation. Following the command as written triggered the defect.
- ✗ Non-qualifying — Spec 150: spec template missing a `TC` field. This is a feature gap (the field didn't exist yet), not a defect in existing process logic.

#### BV worked examples — operator-friction calibration (Spec 345)

The BV anchors above describe abstract degrees of value. The following worked examples make the abstract concrete, illustrating how to score representative spec kinds along the operator-time-saving / capability-distance heuristic.

**Worked example 1 — friction-reducer (BV=5)**: **Spec 270** (Generalized Cross-Level Sync) removed a recurring papercut that fired multiple times per session — operators previously had to manually maintain `template/` mirrors after every change to a canonical process-kit doc. Each session, that meant 1–N manual sync invocations, each one an opportunity to forget. Sync drift bugs cost real debugging time. The fix removes the papercut entirely. → BV=5 because the spec **directly enables a workflow that was previously friction-blocked at >1×/session**, even though the workflow already "worked" via the manual path.

**Worked example 2 — niche capability-add (BV=3)**: **Spec 271** (Prompt Caching Guidance for Consumer API Integrations) adds documentation that helps operators integrating Claude API calls in consumer projects calibrate cache strategy. Useful, well-scoped, but most operators won't reach for it daily — it sits in the `/spec → /implement → /close` loop only when the consumer happens to be building a Claude-API-driven app. → BV=3 because the capability is **useful but not on the critical path of the core workflow**. Compare to Spec 270 above — both are doc-only, but 270 hits the daily flow and 271 hits a niche.

**Worked example 3 — process-defect (BV=5 cross-link)**: **Spec 142** (Remove Auto-Chain from `/implement` to `/close`) closed a documented FORGE process defect — the auto-chain bypassed the human-validation gate. Per the Spec 151 process-defect anchor above, this scores BV=5 unconditionally regardless of effort or scope. The override is a **kind-discriminator the rubric already uses**: process-defects bypass the abstract BV anchors entirely because the cost of an unfixed defect is "the methodology produces wrong outputs when followed correctly" — that is always BV=5.

**Calibration-aid note**: These worked examples are **calibration aids, not new rules**. Existing scored specs are not re-scored. Future specs may deviate from the examples with rationale recorded in the spec's `Priority-Score:` HTML comment (e.g., `<!-- BV=4 — friction-reducer but only 1×/week, not 1×/session -->`). The kind-distinctions (friction-reducer vs niche capability vs process-defect) are heuristic, not taxonomic — a spec that crosses kinds keeps the higher BV anchor that fits.

### E — Effort / Complexity (weight 2, inverted)

How much AI-assisted effort does this spec require? Calibrated for context spread, iteration risk, reasoning depth, and verification cost — not human calendar time.

| Score | Anchor | AI-Effort Indicators |
|-------|--------|---------------------|
| 1 | Single file, pattern application, fast verification | Context spread: 1 file. Iteration risk: low. Reasoning: pattern application. Verification: unit test or visual check. |
| 2 | 2-5 files, clear pattern, low iteration risk | Context spread: 2-5 files. Iteration risk: low. Reasoning: straightforward. Verification: standard test suite. |
| 3 | 5-15 files or cross-subsystem, some reasoning depth | Context spread: 5-15 files. Iteration risk: moderate. Reasoning: some multi-step logic. Verification: moderate (integration tests or targeted manual). |
| 4 | High context spread, ambiguous ACs, complex reasoning | Context spread: 15+ files. Iteration risk: high (ambiguous ACs likely cause retries). Reasoning: complex chains. Verification: significant manual or cross-system testing. |
| 5 | Full codebase awareness, novel problem, expensive verification | Context spread: full codebase. Iteration risk: high (no pattern to apply). Reasoning: novel problem-solving. Verification: integration/E2E/manual, high iteration risk. |

### R — Risk / Blast Radius (weight 2, inverted)

What is the likelihood and severity of regressions, breaking changes, or data corruption if this goes wrong? At AI speed, confident-but-wrong changes propagate faster than human review can catch them.

| Score | Anchor | AI-Speed Consideration |
|-------|--------|----------------------|
| 1 | Purely additive or docs-only; no production path affected | Even a confident-but-wrong change is contained and easily reverted. |
| 2 | Isolated to one module; failure is contained and obviously visible | Low blast radius — revert is straightforward. |
| 3 | Touches shared subsystem; recoverable if it fails; no schema change | Moderate — wrong changes affect shared code; AI speed means more files touched before error is caught. |
| 4 | Touches pipeline or schema in a non-breaking but risky way | High — AI can propagate errors across many files before verification catches them. |
| 5 | Schema-breaking or pipeline-breaking change; downstream consumers affected | Critical — review gates are essential; AI speed amplifies the damage of undetected errors. |

### SR — Spec Readiness (weight 1)

How complete is the existing spec? AC precision is the primary factor — vague ACs cause expensive AI retry loops.

| Score | Anchor | Iteration Impact |
|-------|--------|-----------------|
| 1 | Concept only — no spec exists | AI will interpret freely, high iteration risk. Expect multiple failed attempts. |
| 2 | Objective + scope stub, ACs vague | Expect 2-3 implementation attempts before converging. |
| 3 | Outline + partial ACs, some ambiguity remains | Moderate retry risk — most of the spec is clear but edge cases will surface. |
| 4 | Full spec, ACs testable, minor gaps in edge cases only | Low retry risk — single pass likely with minor corrections. |
| 5 | Fully written, ACs precise and unambiguous, verification commands included | Single-pass implementation expected. |

### TC — Token Cost (advisory indicator, not scored)

Estimated token cost for implementation. Set at spec creation time by /spec.

| Indicator | Criteria |
|-----------|----------|
| `$` | 1-5 files in scope, unit test verification, SR ≥ 4 |
| `$$` | 5-15 files or integration test verification or SR = 3 |
| `$$$` | 15+ files or manual/browser/E2E verification or SR ≤ 2 |

TC is the highest applicable indicator (e.g., 3 files but manual verification → `$$`). Stored in spec frontmatter as `Token-Cost: $|$$|$$$`. TC is operator-judgment input — FORGE does not collect per-invocation cost data (Spec 316 removed the metrics framework that was documented but never wired). Calibrate against operator memory of similar past specs.

TC does not affect the priority score. It is displayed in /matrix output for sprint planning visibility and flagged when `$$$` to prompt cost review.

---

## Score calibration cadence

Quarterly (or after 3+ specs reach `implemented`): compare each completed spec's predicted BV against its actual observed impact. If 2 or more specs are systematically over- or under-predicted, update the BV anchor descriptions above. Record the calibration date in `docs/backlog.md` under `Last score calibration:`.

### E/TC calibration (Spec 158)

During /evolve F4 (score calibration), compare predicted E and TC against actual implementation experience:
- Operator-recall calibration: was TC estimate accurate vs the cost-feel of the implementation? (FORGE does not collect per-invocation cost data — see Spec 316; calibration is qualitative.)
- If session data exists: compare expected session count vs actual.
- Flag systematic E over-prediction (AI handles it easier than estimated) or under-prediction (iteration loops not anticipated).
- Update E anchor guidance when 3+ specs show consistent bias in the same direction.

---

## Worked example

**Spec 001 — Example Feature**
- BV = 4 (completes an important workflow)
- E = 2 (2-5 files, clear pattern, low iteration risk)
- R = 1 (additive only, no production path)
- SR = 3 (outline + partial ACs, some ambiguity)
- TC = $ (few files, standard tests, SR=3 bumps to $$ but file count keeps it at $)

```
Score = (4 × 3) + ((6−2) × 2) + ((6−1) × 2) + (3 × 1)
      = 12 + 8 + 10 + 3
      = 33
```
