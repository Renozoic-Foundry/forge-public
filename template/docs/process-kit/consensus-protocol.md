# Consensus Protocol

`/consensus` is FORGE's structured multi-role review primitive. This doc is the canonical reference for the convention — when consensus runs, how rounds cap, how its outputs feed `/implement`'s gates, and how the protocol composes with adjacent mechanisms (DA review, integrity hashing, Lane B audit).

## When consensus runs

There are two distinct consensus arcs:

| Arc | Trigger | Captures | Tracked via |
|-----|---------|----------|-------------|
| **Proposal-level consensus** | `/evolve` or `/spec` creation surfaces a candidate idea | *Intent* — does this idea belong on the roadmap? | session-log notes; no spec frontmatter yet |
| **Final-draft consensus** | Populated spec body, before `/implement` | *Quality* — is this spec text correct, complete, internally consistent? | `Consensus-Close-SHA:` (Spec 389), gated at `/implement` Step 0d (Spec 395) |

Both are needed. Proposal-level consensus catches "should we?" issues. Final-draft consensus catches spec-text-specificity issues — internal contradictions, brittle algorithms, parser-implementability bugs, missing edge cases — that proposal-level review structurally cannot see, because the spec text didn't exist yet.

The 2026-05-03 audit (Spec 395 trigger) found that of 31 open drafts only 7 had been through a final-draft arc; running `/consensus` on the remaining 7 surfaced concrete spec-text concerns in every one. See [final-draft-consensus-guide.md](final-draft-consensus-guide.md) for worked examples.

## Default-on classification (Spec 395)

A draft is `consensus-required` (final-draft) when ALL hold:

- `Status:` = `draft`
- `Change-Lane:` ∈ {`standard-feature`, `small-change`}
- `BV ≥ 4 AND (R ≥ 3 OR E ≥ 3)` — high-value AND non-trivial

Exemptions:

- `Change-Lane:` = `hotfix` (urgency exemption)
- `Consensus-Exempt: <reason ≥ 30 chars>` (operator-set escape valve)
- Trivial-doc fast-path: `Consensus-Exempt: trivial-doc — <30+ char justification>` AND lane = `small-change` (operator-attested; verified at `/close` not at `/implement`)

Lane B (`docs/compliance/profile.yaml` present) adds a counter-sign rule for high-stakes range — see [lane-b-audit-conventions.md](lane-b-audit-conventions.md).

## Round cap and extension (Spec 301; Spec 395 Req 4)

Default round cap is 3. Rounds 4-5 are gated by the round-3 extension prompt:

```
Round 3 reached — extend? (R=<n>; does this spec span ≥ 3 distinct subsystems
where concerns differ per subsystem? [y/N])
```

Extension is allowed when ANY hold:

- `R ≥ 4`
- Operator answers `y` (operator-declarative subsystem count ≥ 3)

Otherwise the operator must select Accept / Revise / Defer. The maximum is round 5; rounds 6+ are not supported (the spec needs `/revise`).

**Why operator-declarative**: a prior draft used `awk` path-prefix counting, which conflated unrelated directories and broke on root-level files. Operators know subsystem boundaries better than path heuristics do.

When the round number exceeds 2, `Consensus-Close-SHA` is **not written** (Spec 389 Step 4c) — rounds 3+ indicate unresolved divergence, so a fresh DA pass is warranted at `/implement`.

## Posture asymmetry — fail-closed enforcement vs fail-soft optimization

`/implement` has two consensus-related gates with deliberately different failure postures. The asymmetry is load-bearing — confusing one for the other produces the wrong incident response.

| Gate | Spec | Posture | Purpose | When it fires |
|------|------|---------|---------|---------------|
| Step 0d (Final-Draft Consensus Gate) | 395 | **fail-closed** (ENFORCEMENT) | Prevent `/implement` on un-vetted specs | Spec is `consensus-required`, no SHA, no exemption → HALT |
| Step 2b.0 (Encoded-DA Verification) | 389 | **fail-soft** (OPTIMIZATION) | Skip a redundant DA subagent spawn | `DA-Encoded-Via:` present but verification fails → fall through to fresh DA |

The principle: **optimizers fail soft, enforcers fail closed**.

- An enforcer's job is to prevent a bad outcome (an un-vetted spec entering implementation). The safe default is to halt and ask the operator.
- An optimizer's job is to skip redundant work when conditions are met. The safe default is to do the work the optimization would have skipped.

Confusing the two produces concrete incidents:
- A fail-soft enforcer silently lets un-vetted specs through (defeats the gate).
- A fail-closed optimizer halts on benign drift (defeats the optimization).

This asymmetry is documented in both gates' implementation steps and in [final-draft-consensus-guide.md](final-draft-consensus-guide.md) § Posture asymmetry.

## Activity log fields (Spec 395 Req 3)

`/implement` Step 0d emits a `consensus-gate-check` event to `docs/sessions/activity-log.jsonl` (the canonical activity-log path established by Spec 134; Spec 052 immutability sealing reads from this file) for every spec it processes:

**Lane A** (no compliance profile): `timestamp, event_type, spec_id, decision (PASS|FAIL|SKIP), gate_path, agent_id, consensus_status`.

`gate_path` values: `SHA`, `exempt`, `exempt-trivial-doc`, `skip-not-qualifying`, `skip-hotfix`, `missing`.

`consensus_status` is `vet-pending` when frontmatter contains `Consensus-Status: vet-pending`, `absent` otherwise.

**Lane B** (`docs/compliance/profile.yaml` present): Lane A fields + `operator_identity`, `spec_file_sha` (sha256 of spec file), and the applicable provenance (`consensus_close_sha` OR `consensus_exempt_reason` + `reviewed_by_identity`). See [lane-b-audit-conventions.md](lane-b-audit-conventions.md).

## Provisional-Until and sunset review (Spec 395 Req 9)

The Step 0d gate ships PROVISIONAL for 90 days post-Spec-395 close. The spec records `Provisional-Until: <close + 90 days>` in its frontmatter; `/now` surfaces a sunset reminder starting D-7. At sunset, `/evolve` presents trigger-rate, drift recurrence, and operator-friction data; the operator picks one of:

1. Make the gate permanent
2. Tighten the qualifying rule
3. Loosen to advisory-only (warn-not-block)
4. Remove the gate (backfill alone proved sufficient)

The decision is recorded as a follow-up spec.

## Backfill (vet-pending status)

Drafts that pre-date Spec 395 may be marked `Consensus-Status: vet-pending`. The convention is **prompt-not-block at all phases**:

- Pre-SLA (within 30 days of Spec 395 close): silent
- Post-SLA: `/now` and `/matrix` surface a one-line advisory: `N drafts vet-pending past <date> SLA — vet-now-or-set-Consensus-Exempt at /implement`
- At `/implement`: Step 0d fires only if `Consensus-Close-SHA` AND `Consensus-Exempt` are both absent

vet-pending drafts pass Step 0d IFF the operator explicitly sets `Consensus-Exempt: <reason ≥ 30 chars>` (the existing escape). No auto-block at any point.

## Cross-references

- [final-draft-consensus-guide.md](final-draft-consensus-guide.md) — worked examples, R2 prompt structure, when to opt out
- [lane-b-audit-conventions.md](lane-b-audit-conventions.md) — Lane B counter-sign and audit-fields
- [devils-advocate-checklist.md](devils-advocate-checklist.md) — DA-Encoded-Via convention (Spec 389)
- Spec 258 — `Consensus-Review: true | auto` field (this convention is additive)
- Spec 301 — original 3-round cap
- Spec 389 — `Consensus-Close-SHA` mechanism (consumed by Step 0d)
- Spec 395 — this convention's spec
