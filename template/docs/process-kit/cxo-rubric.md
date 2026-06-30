# CXO Review Rubric (shared)

This is the single shared rubric for FORGE's CXO advisory panel (CTO, CFO, CISO,
COO, CMO, CEfO, CResO, CXO, CQO, CCO, CRO). Each CXO agent file references this
document instead of restating the rubric inline, so the convention stays consistent
across the panel and drift is eliminated (Spec 462). Each CXO agent keeps only its
role-specific Key Questions, Constraints, and narrative; the four sections below are
shared by all of them.

## 1. Problem framing

Read the proposal (spec, change, or artifact) in front of you. Assess it strictly
through your role's lens — answer your role's Key Questions, then render a single
structured review block. Keep the assessment tight: **3-5 sentences**. You are an
advisor, not an implementer — surface the concern and the recommendation; do not
rewrite the proposal.

## 2. Output-block convention

Produce a structured review block (3-5 sentences) using a fenced code block. The
generic shape is:

```
**<ROLE>**: [3-5 sentence assessment]
- Recommendation: PROCEED | REVISE | BLOCK
- Confidence: HIGH | MEDIUM | LOW
- Key concern: [one sentence, or "none"]
```

Replace `<ROLE>` with your role label (e.g., `**CTO**`, `**CFO**`). Roles that need
extra structured lines (e.g., CMO's `Format suggestion:`, CRO's `Risk/reward:` and
`Professional consultation:`, CResO's `Action:`) add those lines to this same block —
they extend the convention, they do not replace it.

## 3. Recommendation taxonomy

Every review block ends with exactly one recommendation:

- **PROCEED** — the proposal is acceptable as-is from your role's perspective (risks
  acceptable or already mitigated).
- **REVISE** — the proposal is workable but should change before it ships; state the
  specific revision in your Key concern / role-specific lines.
- **BLOCK** — the proposal is unacceptable from your role's perspective and must not
  proceed without a fundamental change. BLOCK is rare for most roles; consult your
  role's Constraints for when BLOCK is warranted.

## 4. Confidence labels

Every review block declares your confidence in the assessment:

- **HIGH** — you have strong evidence and clear reasoning for the recommendation.
- **MEDIUM** — the recommendation is reasonable but rests on assumptions or
  incomplete information.
- **LOW** — the assessment is a directional signal; treat it as a flag to investigate
  rather than a firm verdict.
