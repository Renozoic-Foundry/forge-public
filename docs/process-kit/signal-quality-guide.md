# Signal Quality Guide (Spec 267)

This guide governs how the three Spec 267 classification fields (`Root-cause category`, `Wrong assumption`, `Evidence-gate coverage`) are populated on Error Autopsy (EA), Chat Insight (CI), and Signal (SIG) entries. The fields are inferred by the agent at `/session` Step 4 and `/close` Step 6, then operator-confirmed before persistence.

The classification is the pivot that lets `/evolve` group signals by *underlying mechanism* rather than by surface-level wording. Without it, pattern analysis groups "things that look similar" — with it, pattern analysis groups "things that broke for the same reason," which is what determines the right prevention strategy.

---

## Root-cause taxonomy (5 categories)

The five categories align with the taxonomy in [docs/articles/debugging-in-forge.md § What Actually Triggers a Signal](../articles/debugging-in-forge.md), extended with `process-defect` (anchored by Spec 151) and `other` (a deliberate safety valve, not a default).

### 1. `spec-expectation-gap`

The spec said one thing; the operator (or reality) expected another. The acceptance criteria, scope, or stated assumptions of the spec didn't capture the full picture. The implementation may be technically correct against the written spec, but it is misaligned with what was actually wanted or possible.

**Prevention strategy**: tighten future specs — sharper ACs, primary-source verification of preconditions, the Devil's Advocate gate. Improving the spec is the *only* way to prevent this class.

### 2. `model-knowledge-gap`

The agent didn't know how the tool, platform, or operational environment actually behaves. The implementation looks confident and the agent had no reason to doubt it; reality contradicted the model's prior. These are not bugs in the spec — no AC could have prevented them — they are gaps in what the agent knows about the world.

**Prevention strategy**: capture the learned behavior as an institutional pattern (CI entry) so future sessions inherit it. Linters and ACs cannot prevent this — only durable institutional memory can.

### 3. `implementation-error`

The agent (or operator) just made a mistake. Typo, copy-paste artifact, arithmetic error, hallucinated detail, missed copy of a file in a multi-mirror set. The spec was right, the model knew the domain, and the failure was a slip during execution. These are the most preventable through mechanical checks — they have no conceptual difficulty.

**Prevention strategy**: mechanical validation — syntax checks, formula verification, automated linting, pre-commit hooks, mirror-parity asserts. Build a guardrail; don't rely on attention.

### 4. `process-defect`

The FORGE process itself permitted, encouraged, or failed to catch the failure. The spec was clear, the model knew the domain, the implementation was attentive — but the workflow didn't have a checkpoint where this class of failure could be intercepted. Either no gate exists, or an existing gate is mis-scoped, mis-tuned, or bypassable.

**Prevention strategy**: file a process-only spec that adds, broadens, or tightens the gate. Anchored by Spec 151 (Methodology-Fixing Score Weight) — process defects auto-rank at the top of the backlog because they otherwise produce recurring failures at scale.

### 5. `other`

Genuinely unclear. The failure doesn't cleanly fit any of the four categories above, or it sits at an intersection where the dominant category is contested. **`other` is a safety valve, not a default.** When in doubt, pick the closest category and note the ambiguity in the entry text — `other` should be the last resort, used when forcing a category would produce false signal.

`/evolve` flags a high `other`-rate (>40% of signals since last review) as a signal-quality regression — habitual `other` defeats the purpose of categorization.

---

## Field rubrics (1-line each)

| Field | Rubric |
|-------|--------|
| **Root-cause category** | Pick the category whose *prevention strategy* you would actually pursue. Don't pick by surface wording. |
| **Wrong assumption** | The single false belief that, if held correctly, would have averted the failure. Empty when no specific belief was wrong (e.g., positive-outcome insights). |
| **Evidence-gate coverage** | Did an existing FORGE gate (DA, completeness, test-execution, dependency-audit, two-stage-review, consensus, etc.) catch this, miss this, or no gate applies? Default to `no-applicable-gate` when uncertain (safe default — `missed-by-existing-gate` is a stronger claim that demands you name the gate). |

The operator confirms each field per existing flow. Empty/`other` is acceptable when categorization is genuinely unclear; the goal is to prompt the agent's best inference, not to block drafting.

---

## Worked examples (2 per category)

### `spec-expectation-gap`

**EA-050 — Spec 235 DA FAIL: missing `--fix` flag** (caught by DA gate before code was written)
- **Root-cause category**: `spec-expectation-gap`
- **Wrong assumption**: "`validate-readme-stats.sh` has a `--fix` flag that will write corrections back to README.md."
- **Evidence-gate coverage**: `caught-by-existing-gate` — DA review reading the spec validated the assumption against the actual script and rejected the spec before implementation.

**EA-051 — Specless implementation under launch urgency**
- **Root-cause category**: `spec-expectation-gap`
- **Wrong assumption**: "Launch urgency implies authorization to skip the spec gate for small fixes."
- **Evidence-gate coverage**: `missed-by-existing-gate` — specless-commit-guard. The guard existed but didn't trigger because the agent committed via batch path that bypassed the regex.

### `model-knowledge-gap`

**EA-005 — `set -euo pipefail` rejected as "invalid option"**
- **Root-cause category**: `model-knowledge-gap`
- **Wrong assumption**: "PowerShell-authored bash scripts will execute under bash without modification."
- **Evidence-gate coverage**: `no-applicable-gate` — no FORGE gate verifies CRLF/LF normalization on script files; the failure surfaced at runtime.

**EA-035 — `compose-modules.sh` sed delimiter collision on macOS**
- **Root-cause category**: `model-knowledge-gap`
- **Wrong assumption**: "GNU sed and BSD sed accept the same delimiter behavior; `/` works as a delimiter even when the pattern contains `/`."
- **Evidence-gate coverage**: `no-applicable-gate` — `validate-bash.sh --portability` did not exist at the time; the failure motivated adding portability checks.

### `implementation-error`

**EA-040 — `local` keyword in top-level loop**
- **Root-cause category**: `implementation-error`
- **Wrong assumption**: empty (this was a copy-paste slip, not a belief).
- **Evidence-gate coverage**: `missed-by-existing-gate` — `bash -n` syntax check would have caught this; was not yet wired into validate-bash.sh at the time of EA-040.

**EA-049 — All 11 brainstormed specs scored incorrectly**
- **Root-cause category**: `implementation-error`
- **Wrong assumption**: empty (mental arithmetic errors, not a belief).
- **Evidence-gate coverage**: `missed-by-existing-gate` — score-verification gate (later filed as Spec 236) didn't exist; rapid batch creation amplified per-spec arithmetic slips into a systemic miscalculation.

### `process-defect`

**EA-053 — Commit guard regex false positive on compound commands**
- **Root-cause category**: `process-defect`
- **Wrong assumption**: "Word-boundary regex `\bgit\b.*\bcommit\b` matches only true `git commit` invocations."
- **Evidence-gate coverage**: `caught-by-existing-gate` — the gate fired (correctly, by its own rules) but mis-scoped its match. The defect is in gate tuning, not in the absence of the gate.

**EA-054 — Parallel agent content duplication**
- **Root-cause category**: `process-defect`
- **Wrong assumption**: "Isolated subagents writing into separate worktrees will not produce duplicated section headers when their changes merge back."
- **Evidence-gate coverage**: `no-applicable-gate` — no de-duplication awareness exists in the parallel-merge flow; subagents append blindly. A new gate (mirror-parity + section-uniqueness check at parallel-merge time) is the prevention.

### `other`

**EA-058 — Git host rejects ed25519 SSH keys**
- **Root-cause category**: `other` — sits between `model-knowledge-gap` (agent didn't know the host's key-format restriction) and `spec-expectation-gap` (the host README's instruction was the artifact). The dominant category depends on whether one views the README as a spec or as derived knowledge.
- **Wrong assumption**: "Modern ed25519 keys are accepted by all major Git hosting providers."
- **Evidence-gate coverage**: `no-applicable-gate` — no gate exists to verify hosting-provider key-format compatibility before publishing instructions.

**EA-059 — Docx orphan character from partial find-replace**
- **Root-cause category**: `other` — operator-side manual edit error in a Word document; not an agent failure mode and not a FORGE process defect (the document was being hand-edited outside the workflow).
- **Wrong assumption**: empty.
- **Evidence-gate coverage**: `no-applicable-gate` — manual `.docx` edits sit outside FORGE's gate surface entirely.

---

## How `/evolve` uses these fields

Spec 267 extends `/evolve` Step 8a with two outputs that depend directly on the three fields:

- **Root-cause Category Grouping** (Spec 267 Requirement 5) — every signal is bucketed by `Root-cause category`, surfacing whether recent failures cluster in spec quality, model knowledge, attentive execution, or process defects. If the `other` bucket exceeds 40% of recent signals, an advisory fires recommending re-calibration against this guide.
- **Gate-Coverage Gaps** (Spec 267 Requirement 5) — `missed-by-existing-gate` signals are clustered by the named gate. A cluster qualifies as a gap when ≥3 signals name the same gate OR ≥50% of a pattern cluster is `missed-by-existing-gate`. Each qualifying gap surfaces as a candidate for spec-level gate improvement.

See [`.claude/commands/evolve.md`](../../.claude/commands/evolve.md) Step 8a (h) and (i) for the exact output formats.

---

## Backward compatibility

Pre-Spec-267 EA/CI/SIG entries (EA-001..EA-059, CI-001..CI-157 as of 2026-04-16) do not carry the three fields. Pattern analysis treats them as `Root-cause category: other`, `Wrong assumption: <empty>`, `Evidence-gate coverage: no-applicable-gate`. Retroactive backfill is the operator's choice and is not a gate. New entries adopt the new fields; old entries remain authoritative as written.
