# Devil's Advocate Gate Checklist

Last updated: 2026-03-13

This checklist is used by the Devil's Advocate role (or the agent in DA mode) to stress-test a spec before implementation begins. Every spec at L2+ autonomy must pass this gate. At L0–L1 it is recommended but optional.

**Instructions:** Review the spec and check each item. Any "No" or "Unclear" answer must be resolved before the spec advances to implementation. Record findings in the spec's Revision Log.

---

## 1. Logic and Completeness

- [ ] **Objective clarity**: Can you state the spec's goal in one sentence without ambiguity?
- [ ] **Scope boundaries**: Are in-scope and out-of-scope items explicitly listed?
- [ ] **Acceptance criteria testability**: Can each AC be verified with a concrete test or observation?
- [ ] **Missing ACs**: Are there obvious behaviors or edge cases the ACs do not cover?
- [ ] **Contradictions**: Do any ACs contradict each other or conflict with existing specs?
- [ ] **Assumptions**: Are all assumptions stated? Are any unstated assumptions risky?

**Challenge prompt:** "What is the simplest scenario that would satisfy all ACs but still produce a wrong or incomplete result?"

---

## 2. Security and Secrets

- [ ] **Credential exposure**: Could the implementation introduce secrets, API keys, or tokens into version control?
- [ ] **Input validation**: Does the spec account for untrusted or malformed input?
- [ ] **Permission boundaries**: Does the implementation stay within the agent's granted autonomy?
- [ ] **Data exposure**: Could the change leak sensitive data in logs, outputs, or error messages?
- [ ] **Dependency risk**: Do any new dependencies have known vulnerabilities or excessive permissions?

**Challenge prompt:** "If a hostile actor controlled the input to this feature, what could they achieve?"

---

## 3. Scope and Blast Radius

- [ ] **File scope**: Are all files to be modified explicitly listed in the spec?
- [ ] **Unintended side effects**: Could changes to shared modules, utilities, or configs affect unrelated features?
- [ ] **Rollback feasibility**: Can this change be fully reverted with a single `git revert`?
- [ ] **Breaking changes**: Does the change alter any public API, schema, CLI interface, or output format?
- [ ] **Cross-spec interference**: Could this spec's changes conflict with any in-progress or planned specs?

**Challenge prompt:** "What is the worst thing that happens if this change has a bug and goes unnoticed for a week?"

---

## 4. Financial and Resource Exposure

- [ ] **Budget alignment**: Is the estimated effort (tokens, cost, time) within the lane's budget ceiling?
- [ ] **External API costs**: Does the implementation call paid APIs? Are costs bounded?
- [ ] **Runaway risk**: Could a loop, retry, or recursive call cause unbounded resource consumption?
- [ ] **Storage growth**: Does the change create files or data that grow without bound?

**Challenge prompt:** "If the agent ran this implementation 100 times by mistake, what would the cost be?"

---

## 5. Test Coverage

- [ ] **Happy path covered**: Does the test plan cover the primary success scenario?
- [ ] **Edge cases covered**: Are boundary conditions, empty inputs, and error paths tested?
- [ ] **Regression risk**: Are existing tests still valid after this change?
- [ ] **Manual validation needed**: Are there aspects that cannot be automatically tested? If so, are they in the human validation runbook?
- [ ] **Test isolation**: Do tests depend on external state (network, filesystem, time) that could cause flakiness?

**Challenge prompt:** "What test would catch a subtle regression introduced by this change?"

---

## 6. Blast Radius Assessment

Rate the overall blast radius and record it in the spec:

| Rating | Criteria | Action |
|--------|----------|--------|
| **Low** | Changes isolated to one module/file, no shared dependencies, full test coverage | Proceed normally |
| **Medium** | Changes touch shared code or config, partial test coverage, affects 2–3 features | Add targeted tests for adjacent features; human spot-check recommended |
| **High** | Changes to core interfaces, schemas, or infrastructure; broad downstream impact | Mandatory human review before implementation; consider splitting spec |

**Blast radius for this spec:** [ Low / Medium / High ] (circle one)

---

## Outcome

- [ ] **PASS** — All items checked, no unresolved concerns. Spec may proceed to implementation.
- [ ] **CONDITIONAL PASS** — Minor concerns noted below; may proceed if addressed during implementation.
- [ ] **FAIL** — Blocking concerns identified. Spec must be revised before implementation.

**Concerns and recommendations:**

> (Record any findings, suggested revisions, or risk mitigations here.)

**Reviewed by:** (agent role or human name)
**Date:** YYYY-MM-DD

---

## Handling CONDITIONAL_PASS findings (Spec 324)

When the DA gate returns **CONDITIONAL_PASS**, the spec has warning-class findings (and zero critical findings). Operators have two paths to clear the gate: (a) `/revise` the spec, or (b) disposition the findings inline in the spec body. Both are legitimate. This section documents when to use which, and how to author the inline path correctly. The pattern is rooted in Spec 294 (round-3 DA: 8 findings, 0 critical, 4 warning, 4 info — all warnings resolved inline without forcing a 4th `/revise` cycle; signal SIG-294-03 captured the ergonomics win).

### Decision rule by severity

- **Critical** → **`/revise`** required. Critical-severity findings are **NOT eligible for inline disposition**. If a critical finding appears in a dispositions table, the wrong gate decision was recorded — re-run `/revise` instead of dispositioning. Critical findings indicate a structural defect in the spec (wrong scope, conflicting requirements, missing AC class) that the implementer cannot correct without rewriting the spec.
- **Warning** with a clear implementation resolution → **inline dispositions table**. Warnings are testability/specificity issues that the implementer can fix while implementing — tightening an AC, spelling out a path, calibrating a threshold. The dispositions table records the finding + the fix applied.
- **Info** → **spec Evidence note** OR absorb silently. Info findings are observations that don't block implementation — minor consistency issues, missing-anchor notes, optional improvements. If acted upon, record in `## Evidence` at /implement; otherwise no action required.

### When to escalate to /revise anyway

Even with all-warning findings, escalate to `/revise` when:

- **Volume threshold (provisional)**: more than 5 warnings in a single DA pass. Calibrated against Spec 294 only (4 warnings, all inline-resolved); revisit after 3-5 more CONDITIONAL_PASS specs to confirm the threshold. The threshold is a heuristic for "this many concerns probably means the spec needs structural rework, not surface tightening."
- **AC mutation rule**: any disposition that **adds, removes, or rewrites an existing AC** requires `/revise`. AC tightening (replacing vague-AC text with concrete grep predicates, adding required columns, spelling out command paths) **does NOT** — that is the documented pattern. The bright line: are you changing what the AC verifies, or how precisely it verifies it? Latter → inline; former → /revise.

### Dispositions table format

Place the dispositions table in a `## Devil's Advocate Findings` section of the spec body. Required columns:

| Column | Content |
|--------|---------|
| `#` | Finding number (1-based, matching the DA agent's finding order) |
| `Severity` | `critical` / `warning` / `info` (critical should never appear here per the decision rule) |
| `Domain` | Which DA domain raised it (Logic and Completeness, Security and Secrets, Scope and Blast Radius, Financial and Resource Exposure, Test Coverage, Blast Radius Assessment) |
| `Finding` | The DA agent's verbatim finding text (or one-paragraph summary preserving the technical content) |
| `Disposition` | `Applied: <what was changed>` OR `Deferred: <reason + future trigger>` OR `Acknowledged: <reason for no action>` |

Each disposition must name the specific change (which AC was tightened, which Scope bullet was added, which file path was spelled out). "Accepted" or "Acknowledged" without a concrete resolution is insufficient — that fails Requirement 4 (traceability).

### Worked example — Spec 324 (this very spec)

Spec 324's own DA Pass 1 returned CONDITIONAL_PASS with 7 findings (4 warning + 3 info). Per the pattern this section documents, those findings were dispositioned inline rather than triggering /revise. The actual table is in `docs/specs/324-da-conditional-pass-dispositions-documentation.md` § Devil's Advocate Findings — readers can grep for `Spec 324` or `SIG-294-03` to trace the precedent. Excerpt of the format (3 of 7 rows):

| # | Severity | Domain | Finding | Disposition |
|---|----------|--------|---------|-------------|
| 1 | warning | Logic & Completeness | Req 3 says 5 columns; AC3 said "at least 4 columns" — internal inconsistency weakens traceability. | Applied: tightened AC3 to require 5 columns including `#` finding-number column. |
| 2 | warning | Logic & Completeness | AC2 ("documents critical/warning/info decision rule in explicit prose") was the only AC without a grep predicate. | Applied: replaced AC2 with three concrete grep predicates mapping critical → /revise, warning → inline disposition, info → Evidence note. |
| 4 | warning | Scope & Blast Radius | AC6 invoked `forge-sync-cross-level.sh --check` as bare command; script lives at `.forge/bin/`, not on PATH. | Applied: spelled out as `bash .forge/bin/forge-sync-cross-level.sh --check`. |

(All 7 dispositions follow the same format. None mutate existing ACs in violation of the AC mutation rule — every change either tightens an AC's testability or spells out path/syntax. AC 7 was added new, which the rule permits.)

### Operator checklist for inline disposition

1. **Verify zero critical findings** — re-read DA output. If critical present: STOP and run `/revise`.
2. **Count warnings** — if >5: STOP and run `/revise` (provisional threshold).
3. **Classify each disposition** — for each warning, determine whether the fix mutates an existing AC's verification target (→ /revise) or tightens its precision (→ inline OK).
4. **Author the table** in `## Devil's Advocate Findings` of the spec body with all 5 columns.
5. **Apply the fixes** during implementation (modifying the spec body's Scope/Requirements/AC text where dispositioned).
6. **Recompute Approved-SHA** — refer to `## Spec integrity signature` in `/implement` Step 2a; re-hash Scope + Requirements + ACs + Test Plan after disposition edits land.
7. **Add Revision Log entry** noting the inline-disposition pass and SHA recomputation.
8. **Continue with implementation** — the spec is now ready, no /revise loop needed.

### Anti-patterns to avoid

- ❌ **Critical findings in the dispositions table.** This indicates the gate decision was wrong, not a disposition opportunity. Re-run /revise.
- ❌ **"Accepted" or "Acknowledged" without concrete resolution.** Fails the traceability requirement. Each disposition must name what changed (or document why no change is the right call, with a re-evaluation trigger).
- ❌ **Disposition that rewrites an existing AC's verification target.** That is structural revision. /revise.
- ❌ **Skipping the SHA recomputation.** The spec body changed; the integrity hash must reflect that or `/close` will fail Step 2 spec-integrity verification.

### Reference

- Pattern origin: Spec 294 round-3 DA (signal SIG-294-03, see `docs/sessions/signals.md`).
- Documentation spec: Spec 324 (this section's source spec; the spec itself uses the pattern recursively).
- Step 2b in `/implement`: the gate that produces CONDITIONAL_PASS and supports the inline-disposition path.

---

## DA-Encoded-Via convention (Spec 389)

When a spec's design phase already absorbed DA-class concerns through `/consensus` rounds 1+2 (e.g., the round-1 DA participant raised a concern, the round-2 reframe addressed it, and the convergent round closed at aligned-approve ≥ 4/5), the `/implement` Step 2b fresh-DA subagent spawn becomes redundant. Spec 389 formalizes this with two opt-in frontmatter fields and a verification step.

### When to use

The convention applies when **all** of the following hold:

- The spec has been through `/consensus` rounds 1 and/or 2 (NOT round 3+).
- The latest convergent round closed with **aligned-approve** ≥ 4/5 (per Spec 301 vote-tally semantics).
- DA was a participant in those rounds and DA's concerns were absorbed into the spec text via reframes or amendments.
- Implementation has not yet started — the encoding is invalidated by any commit touching files in the spec's `## Implementation Summary` after the convergent round closes.

If any condition fails, do NOT add `DA-Encoded-Via:` — let `/implement` Step 2b spawn a fresh DA subagent via the normal path.

### Frontmatter fields

Two fields work together:

- **`DA-Encoded-Via: consensus-round-N`** — written by the operator or spec author when the conditions above hold. `N ∈ {1, 2}`. Round 3+ values fail validation at `/implement`.
- **`Consensus-Close-SHA: <40-char-git-sha>`** — written automatically by `/consensus` Step 4c at convergent-round close. `/implement` reads this; it MUST NOT be hand-edited or written by `/implement` itself.

After successful encoded-DA verification, `/implement` adds a third field:

- **`DA-Verification: consensus-round-N (SHA <8-char-prefix> + drift-clean)`** — annotation recording that the encoded path verified cleanly without a fresh subagent spawn.

### What `/consensus` does (Step 4c)

When invoked on a spec topic with `--round N`:

1. Skip silently if topic is ADR or freeform (mechanism is spec-only).
2. Skip silently if `--round` not provided (avoids fragile Consensus-Record parsing — operator opts in explicitly).
3. Skip silently if `N > 2`.
4. Skip silently unless Step 4 divergence signal is `Aligned-approve` with ≥ 4 approve votes.
5. Skip silently on operator-decision exit at the 3-round cap (Step 4b).
6. Otherwise: write `Consensus-Close-SHA: $(git rev-parse HEAD)` to spec frontmatter and report it.

### What `/implement` does (Step 2b.0)

When `DA-Encoded-Via:` is present in spec frontmatter:

1. **Value validation** — exact match `consensus-round-1` or `consensus-round-2`.
2. **SHA presence** — `Consensus-Close-SHA:` populated.
3. **SHA format** — 40-char lowercase hex.
4. **Reachability** — `git cat-file -e <SHA>^{commit}` succeeds. Catches rebased/force-pushed SHAs.
5. **Drift check** — `git log <SHA>..HEAD --name-only -- <Implementation-Summary-files>` returns empty. Implementation-Summary paths are passed as **git pathspecs**, not shell globs (operators may use git-pathspec patterns like `tests/fixtures/389/*.md`).

All-PASS → skip subagent spawn, record `DA-Verification` annotation, proceed.
Any-FAIL → log the failure mode and fall through to fresh DA subagent (existing path). The encoding does not "fail closed" by halting — it falls back to the safe default.

When `DA-Encoded-Via:` is absent → fast-path no-op, normal Step 2b flow runs unchanged. Pre-389 specs see no behavioral change.

### Failure modes (operator-visible diagnostics)

| Failure | Message | Resolution |
|---------|---------|------------|
| Value not in {round-1, round-2} | `DA-Encoded-Via must be consensus-round-1 or consensus-round-2 (got: <value>)` | Set to a valid round, OR remove the field to fall back to fresh DA |
| Missing SHA | `Consensus-Close-SHA required when DA-Encoded-Via is set` | Re-run `/consensus --round N`, OR remove `DA-Encoded-Via:` |
| Bad SHA format | `Consensus-Close-SHA must be 40-char hex (got: <value>)` | Re-run `/consensus --round N` to refresh |
| Unreachable SHA | `Consensus-Close-SHA <prefix> not reachable from HEAD (rebased or force-pushed?)` | Re-run `/consensus --round N` on the current branch |
| Drift detected | `drift detected: <files>` | Re-run `/consensus --round N` to refresh, OR remove `DA-Encoded-Via:` and accept fresh DA |

### Trust model

The encoding relies on operator integrity. A malicious or careless operator could hand-edit `Consensus-Close-SHA` to point at a side-branch commit with no diff to Implementation-Summary files, bypassing the drift check. This is a documented trust gap — not a security vulnerability, since the FORGE process trusts the operator to author specs honestly. A future enhancement could HMAC the SHA via Spec 89's integrity mechanism (out of scope for Spec 389).

### Anti-patterns to avoid

- ❌ Adding `DA-Encoded-Via:` to a spec that did NOT go through `/consensus` rounds 1+2.
- ❌ Adding `DA-Encoded-Via: consensus-round-3` (or higher) — round 3+ implies unresolved divergence.
- ❌ Hand-editing `Consensus-Close-SHA:` to silence a drift-check failure.
- ❌ Running `/implement` immediately after `/consensus --round N` when the spec's Implementation-Summary files have been touched in the interim. The drift check will catch this, but it wastes a verifier pass — fix the file scope first.

### Reference (Spec 389)

- Specs 385 + 386 (precedent): inline DA-Decision: PASS with consensus-rationale annotation, before Spec 389 formalized the convention.
- Spec 389 docs: `docs/specs/389-da-encoded-via-consensus.md`.
- `/consensus` Step 4c — SHA writer.
- `/implement` Step 2b.0 — encoded-DA verifier (this section's mechanical counterpart).
- Trust-model rationale: `forge` operates on operator-authored specs; the encoding extends but does not change that trust boundary.
