# Close Validator Coverage — Spec 344

_Documents the three /close-side guards (Reqs 1–3) that close the validator-approval-window gap surfaced by /close 318, AND the lane-gate sentinel (Reqs 9–11) that restricts Spec 089's Approved-SHA mechanism to Lane B specs only._

## The /close 318 incident (motivation for Reqs 1–8)

At /close 318, the validator subagent approved the spec text **T**. After validator approval, a SIG-311-P1 → SIG-CLOSE-01 cleanup was applied to the spec file producing **T'**, and the cleanup was never re-validated. The Approved-SHA gate (Spec 089) fires on edits between /implement and /close, but does NOT fire on edits applied **during /close itself**.

This created a silent edit window: any /close-side mutation of Scope/Requirements/Acceptance Criteria/Test Plan would slip through the validator's coverage. The fix is structural — three /close-side guards that close the window:

1. **Diff re-validation at Step 3** (Req 1) — covers the *pre-Step-3 window* (edits between Approved-SHA verification and Step 3 start)
2. **Step 3 scoped-section restriction** (Req 2) — refuses any Step 3 edit to Scope/Requirements/AC/Test Plan
3. **Approved-SHA re-verify post-Step-3** (Req 3) — covers the *during-Step-3 window* (edits applied by Step 3 itself)

The two SHA-anchored guards (Req 1 + Req 3) MUST NOT be merged. Guard 1 anchors on the pre-edit SHA; Guard 3 anchors on the post-Step-3 SHA. Merging them would drop the post-Step-3 hash anchor that the Spec 089 extension requires.

## Guard 1 — Diff re-validation at Step 3 (Req 1)

**Trigger**: at start of `/close` Step 3 (status transition).

**Logic**: compare the spec file's current bytes against the bytes that were Approved-SHA-verified at Step 2. If non-empty diff:
- Invoke validator on the **full spec file** (matches Step 2d behavior — full ACs).
- Validator FAIL → block status transition with documented error.
- Validator PASS → proceed.

**Scope clarification (DA F2 disposition)**: the diff-check compares **spec-file bytes only**, not the broader working tree. Most /close edits are to README/backlog/CHANGELOG/session log — none of those touch the spec file. Validator re-run only fires when the spec file itself changed between Step 2 verification and Step 3 start, which should be rare (and is exactly the /close 318 incident class).

## Guard 2 — Step 3 scoped-section restriction (Req 2)

**Trigger**: any Edit/Write tool call during /close Step 3 that targets the spec file.

**Logic**: parse the spec file's headings; identify `## Scope`, `## Requirements`, `## Acceptance Criteria`, `## Test Plan`. Any edit whose changed lines fall inside one of these sections MUST be refused with the documented "use /revise — these sections are off-limits at /close" error.

**Permitted Step 3 edits**: frontmatter (excluding `Status:`), `## Implementation Summary`, `## Revision Log`, the spec's `## Evidence` block, and any closure-logging block.

**Off-limits headings (canonical list)**:
- `## Scope`
- `## Requirements`
- `## Acceptance Criteria`
- `## Test Plan`

This list is the single canonical source. It is referenced by the guard logic in all 4 mirrors of `/close.md`. Adding or removing a heading from this list requires updating the canonical source here AND re-syncing the 4 mirror copies of the guard sentinel region.

## Guard 3 — Approved-SHA re-verify post-Step-3 (Req 3)

**Trigger**: after /close Step 3 completes.

**Logic**: recompute the spec-file SHA-256 (per the Spec 089 four-section extraction). Verify against the recorded `Approved-SHA:`. If Step 3 made any non-scoped edits (which it may legitimately do — e.g., add `Closed: YYYY-MM-DD`, append Revision Log entries), the re-verify accounts for those by recomputing the SHA over the four protected sections (Scope, Requirements, AC, Test Plan) — those sections weren't allowed to change per Guard 2, so the recomputed hash MUST match the stored hash.

**Mismatch handling**: HALT with `GATE [spec-integrity]: FAIL — Step 3 modified protected sections (post-Step-3 hash mismatch).` Operator must investigate the Step 3 edit that touched a protected section and fix the path that allowed it.

**Lane-gate scoping (Req 11 footnote)**: Guard 3 only fires when an `Approved-SHA:` field exists in the spec frontmatter. Under the lane-gate (Reqs 9–11), only Lane B specs carry the field — so Guard 3 effectively no-ops on Lane A specs. This is the natural consequence of the lane gate, not a separate change.

---

---

### Recovery

When the gate fails, the canonical sentinel block in this doc is the source
of truth. Re-sync the mirrors:

```bash
bash scripts/spec-344-sync-sentinels.sh
bash scripts/validate-spec-integrity-sentinels.sh
git add -u
```

If the canonical block is itself wrong (rare — usually catches the *other*
direction), edit it here, then re-sync as above. Token-set drift between
`profile.yaml` and the canonical doc requires updating one side to match the
other; the choice is a recognized-set policy decision, not an automation
question.

### Run locally

```bash
# Both checks (default):
bash scripts/validate-spec-integrity-sentinels.sh

# Only one:
bash scripts/validate-spec-integrity-sentinels.sh --sentinel-parity
bash scripts/validate-spec-integrity-sentinels.sh --token-set-coherence

# With evidence artifact (Spec 333 pattern):
bash scripts/validate-spec-integrity-sentinels.sh --evidence-dir tmp/evidence/SPEC-367/

# PowerShell sibling:
pwsh scripts/validate-spec-integrity-sentinels.ps1 -SentinelParity -TokenSetCoherence
```

The acceptance suite at `tests/spec-367-acceptance.sh` exercises the 6
fixtures named in Spec 367 Test Plan item 3 (clean-pass parity, one-byte
divergence, CRLF tolerance, clean-pass tokens, sentinel-region token drift,
coverage-doc-only token drift).

---

## Threat coverage handoff (Lane A)

When Spec 344 ships, Lane A specs no longer carry the Approved-SHA gate. The threat originally covered (post-approval edit detection) now relies on:

- **Spec 003** (parallel worktree execution) — boundary isolation prevents cross-spec edits during parallel runs.
- **Spec 145** (PreToolUse edit-gate hook) — blocks Edit/Write tool calls on spec files outside the active /implement spec's `files_in_scope`.
- **Guards 1+2** (this spec) — diff re-validation + scoped-section restriction at /close.

These three together provide functionally equivalent coverage on Lane A without the per-spec hash management overhead that Spec 089 imposes. Lane B retains the hash gate verbatim (audit-chain compliance unchanged).

## Spec 548 — validator execution-evidence enforcement (post-check + redaction)

**Could-not-check handling (Spec 618)**: the Stage-1 scanner pre-check
(`validator-pipeline.sh prepare` → `flagged-acs.json`) is three-state. When
`section_found:false`, the spec has no recognized acceptance-criteria heading — the scan
read NO ACs, so the empty `flagged_acs` means nothing. `prepare` emits an operator-visible
warning, `/close` Step 2d treats Stage 1 as could-not-check (never "no browser-verb ACs"),
and `/close` Step 2b2 emits a blocking `GATE [browser-evidence]: COULD-NOT-CHECK` outcome
with the standard `--accept-deferred-acs`/`--force` override paths. Only
`section_found:true` lets an empty `flagged_acs` mean a clean spec (Stage-1 no-op).

Two mechanical layers harden validator independence at /close Step 2d (fallback path):

1. **Spec-copy redaction** (`spec_redact.py`): the validator receives a copy with
   implementer-authored proof sections (`## Evidence`, `## Disposition Record`,
   `## Devil's Advocate Findings`) stripped — the evidence-blind rule no longer depends on
   prompt compliance (SIG-532-04/535-02 showed ~2/3 same-day lapse rates on prompt-only
   enforcement).
2. **Execution-evidence post-check** (`validator_evidence_postcheck.py`): any AC the shared
   scanner (`ac-pattern-scanner.sh <spec> runnable` — the Spec 550 matcher infrastructure,
   the ONLY command-detection source) flags as naming a runnable command must carry execution
   evidence (exit code / output excerpt, tolerated variants documented in
   `EVIDENCE_PATTERNS`) in its criterion result. A PASS without it — or a PASS citing the
   implementer Evidence section — downgrades to `GATE [validator]: FAIL`, naming the AC and
   the missing element (one-shot retry contract).

**Enforcement ceiling (honest)**: the post-check verifies evidence **presence, not
truthfulness** — a validator could fabricate a plausible exit code without executing
anything. It is a lint-level speed bump against drift, NOT a hard trust boundary.
Evidence-to-tool-call trace binding is the named follow-up (watchlist: "Full validator
isolation"). At L3/L4 the whole layer is **designed-not-enforced** until the
managed-settings trust root lands (ADR-453 §6.1) — same ceiling as Spec 498's push gate.

## What is NOT handled by these guards

- **Genuine post-close corrections** (typos, broken links, signal-ID drift caught later) are a separate problem. /close-time edits and post-close edits are different windows. If you hit a post-close correction case, file a follow-up spec for the optional **Pattern A errata-file mechanism** (deferred follow-up, not a launch requirement of Spec 344).

- **Pattern B (numbered revision specs / Supersedes-chain in Lane A)** — recorded as deferred follow-up. Adopt only if Lane A ever requires Lane B-style audit-trail discipline.

## References

- Spec 089 — Spec Integrity SHA Signatures (now Lane B only)
- Spec 052 — Lane B precedent (audit-chain anchor)
- Spec 035 — Compliance profile schema
- Spec 145 — PreToolUse edit-gate hook
- Spec 003 — Parallel worktree execution
- Spec 342 — Approved-SHA whitespace tolerance (deprecated as superseded)
- Spec 358 — Signature-gates Lane B only (deprecated; scope absorbed here)
- Spec 367 — CI parity gate for spec-integrity sentinel regions (follows Spec 344)

## Batch dispatch (Spec 582)

Batch mode dispatches ONE read-only validator per spec, concurrently (waves of
`forge.roles.implementer.max_parallel`, Spec 042 swarm ceiling overall). Independence is the
point: no shared conversational context between validators (field evidence: independently
surfaced dead code, an unedited AC, a superseded write path, and a committed gate deletion that
document review missed). The orchestrator-global role lock (`active-role.json`, batch-shaped
`spec: "<first>-<last> (batch)"`) blocks orchestrator writes for the whole dispatch window —
same Spec 100 hook, no schema change. Every report passes the Spec 548 evidence post-check
individually; the dispatch prompt injects the evidence listing + excerpts + exit-code contract
up front so first-pass reports satisfy it.

## Spec 620 — repro-provenance gate (Step 2b7)

`/close` Step 2b7 byte-verifies the spec's `## Reproduction Commands` block against runs
captured via `forge run <spec-id> -- <command…>` — string comparison only (the settled
provenance-not-execution model; see `docs/process-kit/repro-provenance-guide.md`). Three
per-line outcomes: `verified` / `broken` (the only close-blocker; `--repro-accept "<reason>"`
downgrades with the reason recorded verbatim) / `unverifiable` (labelled attestation, one
per-spec reason, standing auto-reason on non-interactive runs). The gate text ships in all
four canonical `/close` mirrors (the same 4-mirror list Guard-family checks use); the
comparator (`repro_provenance.py`) is structurally subprocess-free with git resolution
isolated in `repro_gitsha.py` behind a hex-shape injection guard.
