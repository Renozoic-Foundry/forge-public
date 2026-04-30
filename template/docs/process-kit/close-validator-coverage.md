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

## Lane-gate sentinel (Reqs 9–11) — single canonical source

This is the **canonical text** of the lane-gate sentinel region. The block below is byte-identical to the fenced `# >>> spec-344 lane-gate` / `# <<< spec-344 lane-gate` regions inside:

- `.forge/commands/implement.md` Step 2a
- `.claude/commands/implement.md` Step 2a
- `template/.forge/commands/implement.md` Step 2a
- `template/.claude/commands/implement.md` Step 2a
- `.forge/commands/close.md` Step 2 addendum
- `.claude/commands/close.md` Step 2 addendum
- `template/.forge/commands/close.md` Step 2 addendum
- `template/.claude/commands/close.md` Step 2 addendum
- `.forge/commands/revise.md` Step 2c
- `.claude/commands/revise.md` Step 2c
- `template/.forge/commands/revise.md` Step 2c
- `template/.claude/commands/revise.md` Step 2c

**12 mirror locations total.** AC 17 requires `md5sum` byte-identity across all 12 (CRLF normalized). Adding/removing/editing this sentinel requires updating the canonical source here AND re-syncing all 12 mirrors. Use `scripts/spec-344-sync-sentinels.sh` (authored at /implement) to atomically substitute all 12 from this canonical source.

### Canonical sentinel block (do not edit without re-syncing 12 mirrors)

```
# >>> spec-344 lane-gate
LANE-GATE: Spec 089 Approved-SHA mechanism is Lane B only. Read these conditions in order:

1. **Read `Change-Lane:` from the spec's frontmatter.** Possible values: `hotfix`, `small-change`, `standard-feature`, `process-only`, `Lane-B`, missing, or unrecognized.

2. **Read `docs/compliance/profile.yaml`.** If the file is absent: this is a Lane A FORGE-internal project — skip Spec 089's behavior for this Step entirely. No SHA computed, no `Approved-SHA:` written or verified or cleared, no `GATE [spec-integrity]` line, no override prompt. Proceed silently to the next Step.

3. **If `docs/compliance/profile.yaml` is present:** the project declares Lane B usage. Now apply the predicate:
   - If `Change-Lane:` is `Lane-B`: PROCEED with Spec 089's existing behavior verbatim. Compute/verify/clear the SHA per the existing logic.
   - If `Change-Lane:` is `hotfix`, `small-change`, `standard-feature`, or `process-only`: SKIP Spec 089's behavior. No GATE line, no prompt. Proceed silently.
   - If `Change-Lane:` is missing or any other value (e.g., a typo like `Lane_B`): STOP. Do not proceed. Emit `GATE [spec-integrity]: FAIL — Change-Lane missing or unrecognized ('<value>') under a Lane B compliance profile. Set Change-Lane explicitly before proceeding.` HALT. Do not invoke the SHA logic. Do not transition status. Do not proceed to subsequent steps.

This block is load-bearing prose — Claude reads it as instructions and follows the predicate. The fail-closed branch ("STOP. Do not proceed.") is imperative; do not soften the phrasing.

See: docs/process-kit/close-validator-coverage.md § Lane-gate sentinel — canonical source.
# <<< spec-344 lane-gate
```

---

## Spec 035 ↔ Spec 344 cross-edit invariant (CISO concern, /implement directive 3)

**Warning to future maintainers**: edits to the recognized Lane B token (currently hardcoded as `Lane-B` per /revise 2026-04-29 round-2-on-new-scope, was previously `forge.lanes.b_token:` configurable but cut as premature optimization) require simultaneous re-sync of all 12 mirrored sentinel regions. A maintainer who edits the recognized-set in `docs/compliance/profile.yaml` (Spec 035 schema) without re-syncing the sentinel regions could silently push legitimate Lane B specs into the fail-closed branch (and vice versa).

**Mitigation today (doc-only)**: this cross-edit warning is documented here. Any change to the recognized Lane B token requires:
1. Update the canonical sentinel block above.
2. Run `scripts/spec-344-sync-sentinels.sh` to propagate to all 12 mirrors.
3. Verify byte-identity via `md5sum` (AC 17 manual check).
4. Update `docs/compliance/profile.yaml` schema (Spec 035) if the recognized-set definition changed.

**Future hardening**: Spec 367 (CI parity gate for spec-integrity sentinel regions) promotes this to an automated CI assertion — token-set coherence between `profile.yaml` and the canonical recognized-set across the 12 sentinel regions, plus automated md5sum byte-parity. Spec 367 must follow Spec 344 /implement.

---

## Spec 367 CI parity gate

`scripts/validate-spec-integrity-sentinels.sh` (and PowerShell sibling
`.ps1`) runs two independent checks on every commit that touches any of the
16 sentinel-bearing files, the canonical coverage doc, or
`docs/compliance/profile.yaml`. The combined pre-commit hook installed by
`.forge/bin/install-pre-commit-hook.sh` invokes them automatically.

### Check 1 — `--sentinel-parity` (md5 byte-identity)

For each sentinel region kind, extract the body bytes between the `>>>` and
`<<<` markers, strip CR characters (so CRLF and LF mirrors compare equal), and
compute md5. Assert:

- All 12 lane-gate mirrors equal the canonical block in this doc.
- All 4 guards mirrors (close.md only) equal each other.

`FAIL` names every divergent file with its hash and the canonical hash.

### Check 2 — `--token-set-coherence`

Extracts the recognized Lane B token-set (currently `hotfix`, `small-change`,
`standard-feature`, `process-only`, `Lane-B`) from each of:

- the canonical sentinel block in this doc (the line beginning `Possible
  values:`),
- each of the 12 lane-gate sentinel mirrors,
- `docs/compliance/profile.yaml` `forge.lanes:` schema (only when the file is
  present — Lane A repos have no profile and this source is skipped).

Compares pairwise. On mismatch the report distinguishes:

- **silent-allow risk** — a source has an *extra* token (the lane-gate would
  permit a value the canonical set does not authorize).
- **silent-DoS risk** — a source is *missing* a token (legitimate specs would
  be pushed into the fail-closed branch of the lane gate).

This catches the convergent CTO+CISO+DA+COO concern raised at /consensus 344
round-2: byte-parity hashes the sentinel contents but does not detect a
maintainer who edits `profile.yaml`'s recognized-set without re-syncing the
12 sentinel regions, or who edits the canonical doc's recognized-set without
re-syncing the mirrors.

### Doc-warning + CI-gate relationship (Spec 344 /implement directive 3)

The cross-edit invariant warning above (§ Spec 035 ↔ Spec 344 cross-edit
invariant) is the **read-time human reminder**. The Spec 367 CI gate is the
**commit-time automated enforcement**. Both intentionally remain in place —
the doc warning surfaces the constraint when a maintainer is editing, the
gate catches the case where the warning was missed.

### When the gate fires

The pre-commit hook invokes the validator only when the staged file set
includes one of:

- `.forge/commands/{implement,close,revise}.md`
- `.claude/commands/{implement,close,revise}.md`
- `template/.forge/commands/{implement,close,revise}.md`
- `template/.claude/commands/{implement,close,revise}.md`
- `docs/process-kit/close-validator-coverage.md`
- `docs/compliance/profile.yaml`

Other commits skip the validator (no overhead). When the validator does fire
it runs both checks and exits non-zero on any failure.

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
