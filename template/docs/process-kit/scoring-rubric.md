<!-- Last updated: 2026-04-06 -->
# Framework: FORGE
# Prioritization Scoring Rubric

Last updated: 2026-04-06

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

TC is the highest applicable indicator (e.g., 3 files but manual verification → `$$`). Stored in spec frontmatter as `Token-Cost: $|$$|$$$`. When historical cost data exists in `.forge/metrics/command-costs.yaml`, use it to calibrate estimates for similar specs.

TC does not affect the priority score. It is displayed in /matrix output for sprint planning visibility and flagged when `$$$` to prompt cost review.

---

## Score calibration cadence

Quarterly (or after 3+ specs reach `implemented`): compare each completed spec's predicted BV against its actual observed impact. If 2 or more specs are systematically over- or under-predicted, update the BV anchor descriptions above. Record the calibration date in `docs/backlog.md` under `Last score calibration:`.

### E/TC calibration (Spec 158)

During /evolve F4 (score calibration), compare predicted E and TC against actual implementation metrics:
- If token cost data exists in `.forge/metrics/`: compare TC estimate vs actual tokens consumed.
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
