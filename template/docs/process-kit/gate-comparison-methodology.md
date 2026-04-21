---
title: Gate Comparison Methodology
scope: forge-internal
spec: 277
phase: 1
---

# Gate Comparison Methodology (Spec 277, Phase 1)

This document describes the shadow-mode instrumentation that captures review-gate signals from three independent code reviewers — Claude Code's built-in `/ultrareview`, FORGE Validator Stage 2 (Code Quality), and the DA role-registry review — during `/close` runs that match narrow trigger criteria. The data is captured silently, persisted locally, and consumed by a follow-up spec (Phase 2) that decides whether `/ultrareview` should **replace**, **augment**, or **be dropped** relative to what `/close` already runs.

## Why shadow mode

Adding a new user-visible review gate before we have evidence it provides unique value would (a) extend the Review Brief with potentially redundant findings, (b) increase `/close` wall-clock time for every qualifying spec, and (c) bake in a decision (keep `/ultrareview`) that we have no evidence supports. Shadow mode collects the data needed for the keep/replace/drop decision without any of those costs on the operator's visible close experience.

## Trigger criteria

`/close` invokes the shadow `/ultrareview` pass only when **all** of these hold:

- One of:
  - `Consensus-Review: true` in the spec front-matter, OR
  - `BV >= 4` AND scope touches external interfaces / API / CLI contracts, OR
  - `R >= 4` (high risk — from Priority-Score)
- `Change-Lane:` is NOT `hotfix` and NOT `process-only`.
- `--skip-ultrareview` flag is absent from `$ARGUMENTS`.
- The spec has a committed diff since it transitioned to `in-progress` (i.e., there is code to review).

The trigger criteria deliberately mirror the Spec 258 consensus triggers — narrow by design to protect baseline `/close` cost. The seeded-bug corpus (see below) covers the "did we miss a defect?" axis independently of live close volume.

## Captured metrics (per gate, per qualifying close)

Each of the three gates runs inside a shared instrumentation wrapper that records:

| Field | Description |
|---|---|
| `gate` | `"ultrareview-shadow"`, `"validator-stage2"`, or `"da"` |
| `spec_id` | Spec number (three-digit) |
| `timestamp` | ISO 8601 UTC of invocation start |
| `duration_s` | Wall-clock seconds from invocation to completion (monotonic) |
| `tokens` | Token usage reported by the sub-agent harness (0 if unreported) |
| `severity_counts` | `{"critical": N, "warning": N, "info": N}` from parsed JSON |
| `raw_output` | Verbatim text output from the sub-agent |
| `skipped` | `true` if the gate did not run (skip reason below) |
| `skip_reason` | `"hotfix"`, `"process-only"`, `"operator-skip"`, `"not-triggered"`, `"no-diff"`, `"ultrareview-error: <error>"`, or `"role-registry-absent"` |

The wrapper is observationally transparent — it never modifies the sub-agent's return value or downstream flow.

## Persistence layout

For every qualifying close (and every skipped-with-reason close), `/close` writes three files under `.forge/state/gate-comparison/<spec-id>/`:

```
.forge/state/gate-comparison/
  NNN/
    ultrareview.json       # shadow /ultrareview capture
    validator-stage2.json  # Validator Stage 2 capture
    da.json                # DA role-registry review capture
```

The parent `.forge/state/gate-comparison/` directory is gitignored in the template. Validator-Stage2 and DA files are written even when the `/ultrareview` shadow is skipped — they are the always-run comparators.

## Session sidecar schema

`.forge/templates/session-handoff-schema.json` is extended to accept:

- A `gate_outcomes[]` entry with `gate: "ultrareview-shadow"`, including `duration_s`, `severity_counts`, `skipped`, `skip_reason`, `comparison_dir`.
- `duration_s` and `tokens` fields added to the existing validator and DA gate entries.

Fields are optional / additive. Consumers that ignore unknown fields continue to work (non-breaking).

## Seeded-bug corpus (offline)

`scripts/gate-comparison-corpus.sh <historical-spec-id>` applies a library of seed defects to a historical spec's diff and runs each of the three gates against each seeded diff. The defect library lives in `scripts/gate-comparison-defects/` and ships with at least five categories:

| Patch | Defect category |
|---|---|
| `null-deref.patch` | Null / undefined pointer dereference |
| `missing-error-handling.patch` | Missing error / exception handling |
| `hardcoded-secret.patch` | Hardcoded credential or secret |
| `off-by-one.patch` | Off-by-one boundary error |
| `unused-import.patch` | Unused / incorrect import |

The runner writes a per-gate / per-defect detection matrix to `docs/digests/gate-comparison-seeded-<YYYY-MM-DD>.md` for analyst review.

## Phase 2 decision criteria

Phase 2 runs once both of these are satisfied:

1. At least **10 qualifying closes** have shadow data in `.forge/state/gate-comparison/` (or 30 calendar days have passed since Spec 277 closed, whichever comes first).
2. The seeded-bug corpus has been run against the current `/ultrareview`, Validator Stage 2, and DA reviewer configurations.

Phase 2's decision matrix (proposal — Phase 2 may refine):

| Observation | Recommended outcome |
|---|---|
| `/ultrareview` detection rate >= Validator Stage 2 AND unique-finding rate >= 20% of its total findings | **Replace** Validator Stage 2 with `/ultrareview` |
| Detection rate comparable, unique-finding rate < 20% | **Drop** `/ultrareview` — redundant |
| Detection rate lower than Stage 2 but high-severity unique findings present | **Augment** — narrow gate for high-R specs only |
| False-positive rate > 40% on seeded corpus | **Drop** regardless of detection rate |
| Wall-clock cost > 3x Validator Stage 2 with no detection advantage | **Drop** — cost disproportionate |

## Phase 2 readiness surface

`/now` reports a one-line prompt when the readiness threshold is reached:

```
Spec 277 Phase 2 ready — write follow-up spec to consume shadow data.
```

Trigger: `.forge/state/gate-comparison/` contains data for >= 10 qualifying closes OR >= 30 calendar days have elapsed since Spec 277 closed. The prompt is informational (never blocks `/now`).

## Operator-facing opt-out

Any qualifying close can be run with `/close NNN --skip-ultrareview` to bypass the shadow invocation. The skip is recorded in `ultrareview.json` as `{skipped: true, skip_reason: "operator-skip"}`. Validator Stage 2 and the DA review still run — they are baseline gates independent of the shadow comparison.

## What this methodology does NOT do (Phase 1)

- Does **not** display `/ultrareview` findings in the Review Brief, stdout, or session log.
- Does **not** block `/close` based on `/ultrareview` output under any circumstance.
- Does **not** modify Validator Stage 2 or DA role-registry review behavior — the wrapper is observationally transparent.
- Does **not** introduce new spec front-matter fields.
- Does **not** ship `/ultrareview` integration at `/implement` time.

All of the above are Phase 2 decisions, informed by the data captured here.
