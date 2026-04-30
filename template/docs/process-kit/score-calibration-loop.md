# Score Calibration Loop

This document describes the predicted-vs-observed audit loop that grounds FORGE's `/evolve` F4 anchor revisions in measurement, not memory. It is the canonical reference for the proxy semantics and the time-blindness mitigation principle introduced by Spec 368.

## Time-blindness mitigation

**Principle**: Claude does not compute durations from session memory. All time-derived proxies are computed in shell from git commit timestamps and must be reproducible by re-running the shell command on the same repo state.

The shared helper at `.forge/lib/score-audit.sh` (PowerShell parity at `.forge/lib/score-audit.ps1`) emits shell-derived timestamps via `date -u +%FT%TZ` (bash) or `[DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")` (PowerShell), and computes all duration values in shell arithmetic. The helper file carries this principle as a top-of-file comment, anchoring the rule in code where it cannot be silently bypassed.

LLMs (Claude included) are unreliable on duration, calendar effort, and cross-session memory of historical patterns. Leaving calibration as model-self-reported recall is the weakest evidence layer in FORGE. By deriving proxies from artifacts the model cannot fudge — git timestamps, session JSON sidecars, `/revise` invocation count, validator/DA pass-fail history — calibration becomes auditable.

## Audit log

The audit log lives at `.forge/state/score-audit.jsonl`, append-only, one JSON object per line. The path is overridable via the `SCORE_AUDIT_FILE` environment variable (used by fixtures to isolate test data).

Each record has `schema_version: 1` and one of two `kind` values:

- `predicted` — written at `/spec` and at `/revise` when scores change. Contains the predicted BV/E/R/SR/TC, lane, `kind_tag`, `revise_round`, and `predicted_by` (`operator` or `claude`).
- `observed` — written at `/close` after the status transition. Contains shell-derived `wallclock_days`, `session_count`, `revise_rounds`, `validator_outcome`, `da_outcome`, `tc_overrun_derived`, `kind_tag`, and `creation_ts_source` (`git-log` or `frontmatter`).

The helper writes records via a single `>>` redirection of a string short enough to fit in `PIPE_BUF` (4096 bytes per POSIX) so concurrent appends from `/parallel` worktrees are safe. The 4000-byte ceiling triggers a `WARN: record exceeds atomic-append bound; truncating discretionary fields` warning and truncates `kind_tag` to its bare value.

The `kind_tag` enumeration (operator may override at `/spec`):

- `instrumentation` — adds telemetry, audit logs, drift detectors
- `doc` — process-kit / README / runbook updates
- `command-edit` — slash-command surface changes (no new file)
- `linter` — validation gates, drift checks
- `template-sync` — template / own-copy parity work
- `process-defect` — fixes a flaw in FORGE's own process
- `feature` — new user-facing capability
- `hotfix` — critical correction
- `other` — fallback

`/evolve` F4 cross-tabs by `lane × kind_tag` so bias-by-kind surfaces from day one rather than waiting for a follow-up spec.

## Proxy mapping

Bias detection compares the predicted score band against the observed proxy. All bands are direction-only — they identify over- or under-prediction trends, not magnitudes.

### E (Effort) observed proxy

E is the dimension where calibration matters most. The proxy uses `wallclock_days` and `session_count`:

| Predicted E | Predicted band | Observed proxy hits when... |
|-------------|---------------|-----------------------------|
| E=1         | wallclock < 1d AND session_count == 1 | Both predicates hold |
| E=3         | wallclock ∈ [1, 3]d OR session_count ∈ [2, 3] | Either holds |
| E=5         | wallclock > 5d OR session_count > 4 | Either holds |

Bias triggers:

- **E over-prediction** — predicted E≥4 but observed `wallclock_days < 1` AND `session_count <= 1`. AI handled it easier than estimated.
- **E under-prediction** — predicted E≤2 but observed `wallclock_days > 3` OR `session_count > 3`. Iteration loops not anticipated.

### SR (Spec Readiness) observed proxy

SR uses `revise_rounds` and `validator_outcome`:

- SR=5 prediction with `revise_rounds == 0` AND `validator_outcome == PASS` is a calibration **HIT**.
- SR≥4 prediction with `revise_rounds >= 2` OR `validator_outcome ∈ {FAIL, PARTIAL}` is a HIGH-confidence **MISS** (over-prediction).

### R (Risk) observed proxy

`R` is harder to ground because R-failures are rare. Documented signals:

- post-close incidents
- `/revise` triggered by harness failure
- close→revert pattern

These feed into the bias report as **advisory only** — sample size is too small to threshold reliably.

### BV (Business Value) observed proxy

**Explicitly NOT auto-derived.** BV calibration remains qualitative per the existing rubric. Future calibration would require a feedback loop on whether the value materialized — out of scope here.

### TC (Token Cost) observed proxy

TC uses `tc_overrun_derived`, a boolean computed by the helper from the same proxy mapping:

| Predicted TC | Predicted band                  |
|--------------|----------------------------------|
| `$`          | wallclock < 1 AND session_count == 1 |
| `$$`         | wallclock ∈ [1, 5] OR session_count ∈ [2, 4] |
| `$$$`        | wallclock > 5 OR session_count > 4 |

`tc_overrun_derived = true` iff observed exceeds the predicted band by at least one tier in either dimension. No operator prompt at `/close` for this field.

## Bias report at /evolve F4

The `/evolve` F4 step invokes `bash .forge/lib/score-audit.sh bias-report <mode>` (or the PowerShell parity). The helper:

1. Reads predicted/observed pairs grouped by `(lane, kind_tag)`.
2. For each cell, counts same-direction deviations per dimension (E, SR).
3. Triggers an anchor-revision advisory when **N≥3** specs in the same dimension+lane+kind_tag cell show same-direction deviation.
4. Suffixes every advisory with the literal `(direction-only; magnitude not measured)`.
5. Annotates each advisory `(based on N=<count> closed specs since first record)`.
6. In **lean** mode (Spec 225), suppresses sub-threshold cells. In **verbose** mode, renders them as `insufficient data (N=<count>)`.

Example output:

```
E over-prediction in lane=standard-feature kind_tag=command-edit (based on N=4 closed specs since first record) (direction-only; magnitude not measured)
SR over-prediction in lane=hotfix kind_tag=process-defect (based on N=3 closed specs since first record) (direction-only; magnitude not measured)
```

The CEfO sub-agent (Spec 158) consumes this report alongside the operator-recall pass at Step 6b. The CEfO prompt instructs: "report direction only; do not assert magnitude."

## Adjacent instrumentation streams

`.forge/state/` is the canonical FORGE instrumentation directory. Spec 368 establishes the schema authority for `score-audit.jsonl`. Adjacent specs SHALL extend the existing record schema under additive keys; they SHALL NOT create parallel `.jsonl` files.

Known adjacent stream:

- **Spec 247 — Operator Effort Attribution** (draft). When implemented, Spec 247 extends the existing record schema with additive keys (e.g. `operator_messages`, `agent_output_lines`, `leverage_ratio`). Spec 247's eventual `/implement` is therefore expected to depend on Spec 368 (schema base) — not run in parallel as a sibling.

Future instrumentation specs touching `.forge/state/` MUST:

- Bump `schema_version` if breaking, or add additive keys without bump if forward-compatible.
- Document the new keys in this file's section above (extending the table of known streams).
- Reuse `.forge/lib/score-audit.sh` as the writer; do NOT introduce parallel writers.

## Storage and tamper-evidence

The audit log is append-only **by convention, not by enforcement**. An adversarial agent could rewrite history. Spec 333's drift-evidence pattern would be the precedent if hardening becomes warranted.

In FORGE's own repo, `.forge/state/score-audit.jsonl` is committed to git so calibration history is reviewable. Consumer projects (template-bootstrapped) get the file path under `.gitignore` by default; operators may opt in by removing the exclusion. The template ships `.forge/state/.gitkeep` with a one-line README explaining the file's purpose.

## What the calibration loop does NOT do

- It does not change the scoring formula, anchors, or weights.
- It does not introduce per-invocation token-cost telemetry (Spec 316 honesty constraint preserved).
- It does not block any lifecycle command on audit-log success — the audit log is advisory.
- It does not surface real-time calibration deltas in `/now` or `/matrix` (those remain operator-judgment surfaces).
- It does not enforce that operators act on the advisories. This is an evidence-presentation spec, not a behavior-change spec.

The proxy mapping itself becomes load-bearing without ever being calibrated against ground truth. Mitigation: every advisory carries the mandatory `(direction-only; magnitude not measured)` suffix; `score-calibration-loop.md` carries the time-blindness principle as the in-band guardrail. Long-term re-calibration of the proxy mapping would require a future spec once N is large.
