# Consensus Protocol

`/consensus` is FORGE's structured multi-role review primitive. This doc is the canonical reference for the convention — when consensus runs, how rounds cap, how its outputs feed `/implement`'s gates, and how the protocol composes with adjacent mechanisms (DA review, integrity hashing, Lane B audit).

## When consensus runs

There are two distinct consensus arcs:

| Arc | Trigger | Captures | Tracked via |
|-----|---------|----------|-------------|
| **Proposal-level consensus** | `/evolve` or `/spec` creation surfaces a candidate idea | *Intent* — does this idea belong on the roadmap? | session-log notes; no spec frontmatter yet |
| **Final-draft consensus** | Populated spec body, before `/implement` | *Quality* — is this spec text correct, complete, internally consistent? | `Consensus-Close-SHA:` (Spec 389), gated at `/implement` Step 0d (Spec 395) |

Both are needed. Proposal-level consensus catches "should we?" issues. Final-draft consensus catches spec-text-specificity issues — internal contradictions, brittle algorithms, parser-implementability bugs, missing edge cases — that proposal-level review structurally cannot see, because the spec text didn't exist yet.

The 2026-05-03 audit (Spec 395 trigger) found that of 31 open drafts only 7 had been through a final-draft arc; running `/consensus` on the remaining 7 surfaced concrete spec-text concerns in every one. See `final-draft-consensus-guide.md` for worked examples.

## Default-on classification (Spec 395)

A draft is `consensus-required` (final-draft) when ALL hold:

- `Status:` = `draft`
- `Change-Lane:` ∈ {`standard-feature`, `small-change`}
- `BV ≥ 4 AND (R ≥ 3 OR E ≥ 3)` — high-value AND non-trivial

Exemptions:

- `Change-Lane:` = `hotfix` (urgency exemption)
- `Consensus-Exempt: <reason ≥ 30 chars>` (operator-set escape valve)
- Trivial-doc fast-path: `Consensus-Exempt: trivial-doc — <30+ char justification>` AND lane = `small-change` (operator-attested; verified at `/close` not at `/implement`)

Lane B (`docs/compliance/profile.yaml` present) adds a counter-sign rule for high-stakes range — see `lane-b-audit-conventions.md`.

## Review-depth proportionality (Spec 666)

Classification above decides **whether** a draft is reviewed. This section decides **how deeply**.
It never reduces coverage: every spec that classifies as `consensus-required` still gets reviewed.
What changes is the instrument.

### The three depths

| Depth | Roster | Select when |
|-------|--------|-------------|
| **Full round** | all five roles (`/consensus`, 5 agents × N rounds) | `R >= 3`, **or** the spec introduces a novel mechanism, **or** its scope is security-bearing |
| **Single-reviewer DA pass** | Devil's Advocate alone | `R <= 2` and the spec's defect class is *duplicate-infrastructure* (the same capability being built twice) or *silently-lost* (something that disappears between source and artifact without an error) |
| **Read-through** | no agents; the reviewer reads the spec | `R <= 2`, the change is an enumerated set of mechanical edits, and no new mechanism is introduced |

**Escalation overrides the tier, always.** Two conditions promote any spec to a full round no matter
which depth its inputs select:

- **A REFRAME outcome.** If any reviewer at any depth returns a Maverick-Thinker-class reframe — the
  spec is solving the wrong problem, or a materially simpler shape exists — the review escalates to
  a full round before the spec advances. Proportionality must never be able to talk itself out of
  the escalation path; on 2026-08-06 that path is what stopped a sprint run mid-flight.
- **Security-bearing scope.** Authorization boundaries, credential or secret handling, the push
  guard, signing and verification, permission surfaces. These take a full round at any `R`.

### Who selects the depth

The reviewer selects, never the author. The inputs are mechanical and already on the spec — the
`R` value in `Priority-Score:` frontmatter and the defect class — so the party being reviewed does
not get to choose the depth of its own review. **A spec cannot declare its own tier**: there is no
frontmatter field for it, and adding one would invert the gate. Where one operator is both author
and reviewer, the selection is still made from the frontmatter inputs, in the reviewer role, and
recorded with the round.

### Evidence base (2026-08-06, N=9 enumerated — provisional)

The three depths were run against a single corpus in one session, which is where the rule's
selection criteria came from:

| Depth | Agents spawned | Specs | Yield |
|---|---|---|---|
| Full 5-role round | 15 | 3 (632, 636, 655) | all aligned-concern; one REFRAME; the heredoc trap |
| Single DA pass | 4 | 4 (644, 648, 652, 653) | the sprint's sharpest finding (644's central claim was false) |
| Read-through, no agents | 0 | 2 (646, 654) | 654 cleared outright; 646's cross-spec overlap found |

Every one of the nine returned findings, so depth reduction is not a coverage argument — it is a
cost argument. The single-reviewer passes cost roughly a quarter of a full round and produced
comparable findings, because the Devil's Advocate lens independently covered the
duplicate-infrastructure ground nominally assigned to the CTO. That was measured, not assumed: the
CTO lens was the original recommendation and was changed mid-session on the evidence.

> **Provisional — one session, N=9, not a calibration set.** This rule is described from a single
> day's corpus and evaluated against that same corpus, so the retrospective below is a consistency
> check, not validation. Treat the thresholds as a starting convention, not a measured boundary.
> Revisit once at least three independent sessions have applied it, and record disagreements when
> they happen. (Spec 666's prose says "eight specs"; the table it carried enumerates nine spec IDs.
> The enumeration is the authority here — the count is recorded as nine rather than silently
> reconciled to eight.)

**Retrospective application** (Spec 666 AC2 — the rule re-derived for each spec, compared against
the depth actually used): 9 of 9 agree. `632` (R=3, and security-bearing: the push guard) → full;
`636` (R=4) → full; `655` (R=4) → full; `644`, `648`, `652`, `653` (all R=2, duplicate-infrastructure
or silently-lost) → single DA; `646`, `654` (R=2, enumerated mechanical edits, no new mechanism) →
read-through. Two calls were close and are recorded as such: **644** reads as enumerated-mechanical
on its face (add the missing guides) and would have gone to read-through on `R` alone — the
silently-lost class is what routed it to a DA pass, and the DA is what found its central claim
false, so the class dimension is load-bearing rather than decorative. **653** builds a new
acceptance-gate suite, which one could fairly read as a novel mechanism and escalate to a full
round; it is scored as agreeing because gate scripts are existing FORGE infrastructure and its
defect class is silently-lost, but this is the boundary the rule is least sure of.

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

## Universal review-evidence marker — Consensus-Rounds (Spec 623)

Spec 395 requires review evidence at `/implement` Step 0d; Spec 389 seals a
`Consensus-Close-SHA` only on convergent rounds ≤ 2. Composed, a 3+-round review — the
most-reviewed spec in the corpus — used to look UN-reviewed to the gate (the inversion a
consumer hit with 15 role assessments on record). `/consensus` Step 4c+ now writes
`Consensus-Rounds: <N>` at every completed round, convergent or not, and Step 0d runs a
single evidence-presence check: SHA, exemption, or a cross-checked rounds marker.

- **Cross-check anchor**: the Spec 258 `consensus_reviews[]` records in
  `docs/sessions/*.json` — the max parseable round for the spec across ALL records and ALL
  sidecar files must be ≥ the marker (checker:
  `.forge/lib/consensus-evidence-check.sh <spec-file>`).
- **Round-field format contract**: the `round` field SHOULD be an integer 1–5. The checker
  parses standalone integers bounded 1–9 and takes the max — prose values like
  `"1-2 (in-workflow)"` parse to 2; unrelated large digits (999, timestamps) never inflate
  the parse. A record with no parseable round contributes presence but no depth.
- **Write ordering (load-bearing)**: the sidecar record for round N is flushed BEFORE the
  frontmatter marker. An interrupted run leaves record ≥ marker, never the reverse — so a
  marker exceeding the record is tamper-evidence, not crash residue.
- **Three outcomes**: recorded ≥ N → PASS; recorded < N → hard FAIL (inflated claim); no
  record / unparseable rounds / malformed marker / absent checker → COULD-NOT-CHECK, routed
  to the Spec 395 exemption/operator-adjudication path (never a silent pass, never the
  forgery FAIL).
- **Honesty limit (named deliberately)**: both artifacts are agent-writable in single-agent
  mode. Two-artifact agreement catches accidental drift and staleness and makes casual
  forgery leave evidence in two places — but it is NOT cryptographic and adds little
  resistance against a single actor deliberately coordinating both writes. Cryptographic
  anchoring of consensus evidence belongs to the trust-root/signing arc (ADR-453 §6.1
  class), not this mechanism.

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

This asymmetry is documented in both gates' implementation steps and in `final-draft-consensus-guide.md` § Posture asymmetry.

## Activity log fields (Spec 395 Req 3)

`/implement` Step 0d emits a `consensus-gate-check` event to `docs/sessions/activity-log.jsonl` (the canonical activity-log path established by Spec 134; Spec 052 immutability sealing reads from this file) for every spec it processes:

**Lane A** (no compliance profile): `timestamp, event_type, spec_id, decision (PASS|FAIL|SKIP), gate_path, agent_id, consensus_status`.

`gate_path` values: `SHA`, `exempt`, `exempt-trivial-doc`, `skip-not-qualifying`, `skip-hotfix`, `missing`.

`consensus_status` is `vet-pending` when frontmatter contains `Consensus-Status: vet-pending`, `absent` otherwise.

**Lane B** (`docs/compliance/profile.yaml` present): Lane A fields + `operator_identity`, `spec_file_sha` (sha256 of spec file), and the applicable provenance (`consensus_close_sha` OR `consensus_exempt_reason` + `reviewed_by_identity`). See `lane-b-audit-conventions.md`.

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

- `final-draft-consensus-guide.md` — worked examples, R2 prompt structure, when to opt out
- `lane-b-audit-conventions.md` — Lane B counter-sign and audit-fields
- [devils-advocate-checklist.md](devils-advocate-checklist.md) — DA-Encoded-Via convention (Spec 389)
- Spec 258 — `Consensus-Review: true | auto` field (this convention is additive)
- Spec 301 — original 3-round cap
- Spec 389 — `Consensus-Close-SHA` mechanism (consumed by Step 0d)
- Spec 395 — this convention's spec
- Spec 666 — review-depth proportionality (the tier rule above)
