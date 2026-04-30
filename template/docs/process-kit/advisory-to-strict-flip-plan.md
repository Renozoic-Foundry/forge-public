<!-- Last updated: 2026-04-28 -->
# Framework: FORGE
# Advisory→Strict Flip Plan — Specs 327 + 330

This document defines the criteria, mechanics, monitoring, ownership, and reversibility protocol for flipping the FORGE foundation gates from `mode: advisory` to `mode: strict`. Filed per Spec 332 to prevent both gates from becoming permanent advisory zombies (CTO key risk at /consensus 330; CISO mode-default concern).

The flip itself is a one-line YAML edit to `AGENTS.md`. This document defines **when** that edit happens.

## Background

Two FORGE gates currently ship in `advisory` mode:

| Gate | Spec | Script | Default mode | Purpose |
|------|------|--------|--------------|---------|
| Authorization-rule lint | 327 | `scripts/validate-authorization-rules.sh` | advisory | Verify command bodies require operator confirmation before authorization-required actions (`git push`, `gh pr create`, `rm -rf`, etc.) |
| AGENTS.md prose↔YAML drift | 330 | `scripts/validate-agents-md-drift.sh` | advisory | Verify the operator-readable prose in `AGENTS.md` stays in sync with the structured YAML block consumed by Gate 327 |

A gate that ships advisory and stays advisory forever is functionally equivalent to no gate. This plan makes the flip predictable, owner-attributed, and reversible.

## Criteria — Spec 327 strict flip

**Mandatory criteria (all must hold):**

1. **Triage closed**: Spec 326 (auth-rule audit triage) is at `Status: closed`. Spec 326 dispositions every advisory-mode violation as either whitelisted (with reason), fixed, or accepted.
2. **Mechanical clean**: `bash scripts/validate-authorization-rules.sh --mode=strict; echo $?` returns `0` against the current command surface.
3. **Stability window**: at least **5 consecutive sessions** (default M=5; operator may tune) of `/implement` runs across multiple specs with zero new strict-mode violations introduced. Verified by running the linter in `--mode=strict` at each /close — exit 0 across the window.

**Subjective criterion (operator decides):**

4. **Operator judgment**: The owner (see § Owner) judges the post-baseline-clean state stable enough that the cost of a false-positive flip-back is acceptable.

The mechanical criteria are necessary but not sufficient. The subjective layer is intentional — it preserves operator agency and prevents premature flips driven solely by mechanical signals.

## Criteria — Spec 330 strict flip

**Mandatory criteria (all must hold):**

1. **Spec closed**: Spec 330 is at `Status: closed`. (Satisfied by /close 330 on 2026-04-26.)
2. **Mechanical clean**: `bash scripts/validate-agents-md-drift.sh --mode=strict; echo $?` returns `0` against the current `AGENTS.md`.
3. **Alias-map audit complete**: `scripts/agents-md-action-aliases.yaml` `ignore_prose:` and `ignore_block:` lists have each entry annotated with a removal-rationale comment (per Spec 330 AC 9a) — no silent escape hatches.
4. **Triage decision tree available** (recommended, not blocking): Spec 334 (process-kit page on prose↔block model + triage decision tree) is at `Status: closed`. This is the COO-consensus disposition from /close 330: "sequencing 334 before 332's flip" (CHANGELOG 2026-04-26). Spec 334 hardens operator decision-making at the flip moment by documenting the decision tree operators consult before flipping. Treated as a **soft prerequisite** here — recommended but not strictly blocking.

**Subjective criterion (operator decides):**

5. **Operator judgment**: Same shape as Spec 327 criterion 4.

The Spec 330 criteria are stricter on the alias-map audit (criterion 3) because the drift detector is a **foundation gate for Gate 327** — the prose↔block sync underpins the authorization model itself. Per CISO consensus at /consensus 330: "advisory default carries forward the Spec 327 known weakness for an integrity check that is itself a foundation of the authorization model."

## Mechanics

### Flip event

The flip itself is a YAML-block edit to `AGENTS.md`. For Spec 327:

```diff
 forge.security.gates.authorization_rule_lint:
   enabled: true
-  mode: advisory
+  mode: strict
```

For Spec 330: the same single-line edit on the drift detector's mode field (same YAML block).

### Flip workflow

1. **Pre-flip dry run**: in a feature branch, the operator runs the relevant linter in `--mode=strict` against the current command surface. Confirms exit 0.
2. **Flip PR**: a dedicated PR titled `Flip Spec 327 to strict` (or `Flip Spec 330 to strict`) with the one-line YAML edit.
3. **CI check**: the flip PR's CI run includes the linter in strict mode against the merged-state surface. Merge gated on exit 0.
4. **Merge**: standard FORGE close path. Single small commit with a descriptive message and a SIG entry recording the flip event.
5. **Post-flip session log**: the next `/session` synthesis after the flip records the event.

### Flip is independent per gate

Spec 327 and Spec 330 flip independently. Either can flip first; both ultimately should reach strict. **Spec 330 flipping first is the recommended order** because the prose↔block sync underpins Gate 327's correctness — flipping 330 first locks in the foundation, then 327 builds on it.

## Monitoring (post-flip)

For the **first 5 `/implement` runs** after a flip (default M=5; operator may tune):

1. The linter runs in strict mode at /close as part of Step 7c (Gate 327) or Step 7d (Gate 330).
2. If a violation is surfaced, the /close output explicitly notes "you can flip this gate back to advisory by reverting the YAML edit — see `docs/process-kit/advisory-to-strict-flip-plan.md` § Reversibility."
3. The operator decides at each violation whether to (a) fix the violation forward, (b) whitelist with reason, or (c) flip the gate back to advisory and capture a SIG entry recording the failure mode.

`/evolve` cycles count any flip-back event as a high-severity signal.

## Owner

**Spec 327 flip**: project owner (same as Spec 327 Approver).

**Spec 330 flip**: project owner (same).

The owner exercises subjective judgment when the mandatory criteria are met. There is no automated trigger — the flip is intentionally a deliberate human act.

## Reversibility

A flip is reversible. If post-flip monitoring surfaces a regression that cannot be fixed forward within one session, the operator may roll back:

1. **Revert PR**: a one-line revert of the `mode: strict` → `mode: advisory` edit, titled `Revert: Flip Spec NNN to strict` with rationale in the PR body.
2. **SIG entry**: append a SIG entry to `docs/sessions/signals.md` capturing what failed. Use the standard SIG schema (see `docs/sessions/signals.md` lines 6-21 + `docs/process-kit/signal-quality-guide.md`):
   - `Type: [process]`
   - `Impact: high` (a flip-back is significant)
   - `Observation: <what surfaced post-flip>`
   - `Root-cause category: <spec-expectation-gap | model-knowledge-gap | implementation-error | process-defect | other>`
   - `Wrong assumption: <what we believed about flip-readiness that turned out to be false>`
   - `Evidence-gate coverage: <which gate did/didn't catch the regression>`
   - `Recommendation: <what to change before the next flip attempt>`
3. **Re-flip**: the operator may attempt another flip later, after addressing the SIG-captured gap and re-satisfying the criteria.

A flip-back is a normal operational event, not a failure of the gate. The advisory-mode default exists precisely to make this reversible.

## Related specs

- **Spec 327** — Authorization-rule lint gate (initial gate; ships advisory).
- **Spec 330** — AGENTS.md prose↔YAML drift detector (foundation gate; ships advisory).
- **Spec 326** — Auth-rule audit triage (mandatory criterion 1 for Spec 327 flip).
- **Spec 332** — This planning spec (filed at /consensus 330 follow-up to prevent advisory-zombie failure mode).
- **Spec 334** — Process-kit page on prose↔block model + triage decision tree (recommended soft prerequisite for Spec 330 flip per COO consensus disposition).
- **Spec 331** — `forge:<x>:start/end` shared parser library (CTO + MT compositional debt; tangentially related — the linters consume the sentinel block parsed via this pattern).
- **Spec 333** — Drift detector evidence persistence (CISO request for audit-trail artifact; tangentially related).

## Current observed baseline (plan-filing time, 2026-04-28)

For traceability, the strict-mode dry-run results captured at /implement 332:

| Gate | Command | Mode | Exit | Note |
|------|---------|------|------|------|
| Spec 327 | `bash scripts/validate-authorization-rules.sh --mode=strict` | strict | 0 | 122 command files clean across 7 actions |
| Spec 330 | `bash scripts/validate-agents-md-drift.sh --mode=strict` | strict | 0 | 7 actions in prose, 7 in block, 0 drift |

Both gates would pass in strict mode today. The mandatory criteria above remain the gating contract — operator subjective judgment is the final layer before the flip.
