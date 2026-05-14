# Final-Draft Consensus Guide

This guide complements [consensus-protocol.md](consensus-protocol.md) with worked examples and operational guidance. It is the operator-facing companion to the convention codified by Spec 395.

## Why final-draft consensus catches different bugs

Proposal-level `/consensus` (run at `/evolve` or `/spec` creation) reviews the *intent* of a spec — does this idea belong on the roadmap, are we solving the right problem, are the rough trade-offs acceptable. Final-draft consensus reviews the populated spec text — internal consistency, parser-implementability, contradictions between sections, algorithm correctness.

These are different review tasks. A spec can pass proposal-level consensus cleanly (the idea is good) and then surface multiple concrete bugs at final-draft consensus (the spec text is broken). The reverse is also true: a spec with rock-solid prose may have poor strategic value.

Both arcs are needed. Spec 395's trigger was an audit (2026-05-03) that found 14 active drafts had received only proposal-level consensus or none at all; running `/consensus` on them surfaced concrete concerns in every case.

## Worked example: Spec 395's own /consensus R1 (2026-05-09)

Spec 395 is itself a convention codification. By Req 6 it must dogfood the convention — its own final-draft must go through `/consensus` before `/implement`. Round 1 produced 1 approve / 4 concern, with these concrete spec-text bugs surfaced:

| # | Reviewer | Bug | Type | What proposal-level consensus would have missed |
|---|----------|-----|------|-------------------------------------------------|
| 1 | DA | Req 1 lane set ⊃ Req 2 exemption set inconsistently — process-only was excluded by Req 1 but had a Req 2 exemption branch (unreachable code). | internal contradiction | Yes — the bug only exists once both Reqs are populated with specific lane lists |
| 2 | DA | Trivial-doc fast-path's runtime LOC verifier was brittle: globs, mirror-multiplier annotations like `+3 mirrors`, and new-files-don't-exist-yet at gate time biased the parser toward false-pass. | parser-implementability | Yes — this is a property of the actual algorithm specified in Req 2, not the high-level idea |
| 3 | DA | Req 5 said vet-pending was advisory-only; Backfill section said "blocked from /implement until vetted or exempted". Direct contradiction. | section-vs-section contradiction | Yes — both sections existed in the proposal but the contradiction only surfaces once both are populated |
| 4 | DA | Req 4's awk-based subsystem-detection (`{split($0, parts, "/"); print parts[1]"/"parts[2]}`) was algorithmically broken — conflated unrelated paths, miscounted sibling dirs, broke on root-level files. | algorithm correctness | Yes — the algorithm only existed in the populated spec |
| 5 | MT | Permanent gate without baseline drift data — framing concern. | framing | Possibly caught at proposal stage, but the *commitment level* (permanent vs provisional) is a final-draft choice |
| 6 | CTO | Step 0d (this spec) is fail-closed; Step 2b.0 (Spec 389) is fail-soft. The asymmetry was undocumented and load-bearing. | posture inconsistency | Yes — the asymmetry only becomes visible once both specs' implementation steps are written |
| 7 | CISO | Composition risk: Consensus-Exempt + vet-pending + Spec 052 sealing creates an audit-laundering path on Lane B. | composition / cross-spec | Possibly caught at proposal stage, but the specific 3-spec composition only surfaces with full text |
| 8 | COO | vet-pending advisory string ergonomics — the original was unclear about whether to vet or to exempt at `/implement`. | UX / ergonomics | No — this is genuinely a final-draft polish issue |

`/revise` applied 7 concrete fixes, R2 reached 5/5 aligned-approve, and `Consensus-Close-SHA` was written.

**Headline observation**: 4 of the 8 R1 findings are *spec-text-specificity* issues that proposal-level review structurally cannot catch — the relevant artifact (the populated text) doesn't exist yet at proposal stage. This is the value proposition Spec 395 codifies.

## Worked examples: Specs 388-394 (today's vetting arc)

The same session that revised Spec 395 also ran final-draft `/consensus` on the other open drafts identified in the 2026-05-03 audit (388, 389, 392, 394). Every R1 surfaced concrete concerns. A condensed list:

- **Spec 388** (`/spec` adjacency scan + fold-via-/revise option) — DA: scan-window heuristic was specified in characters but referenced "first 200 lines" elsewhere. Internal unit mismatch.
- **Spec 389** (DA-Encoded-Via convention) — DA: SHA reachability check used `git log <SHA>..HEAD` which silently returns empty for unreachable SHAs; should use `git cat-file -e <SHA>^{commit}` for explicit failure.
- **Spec 392** (`/explore` Step 2 topic-overlap pre-check) — DA: topic-overlap algorithm threshold was specified as a percentage but applied to raw match count.
- **Spec 394** (placeholder — extend with concrete bug when documented) — see session log for the specific finding.

Each of these is a final-draft-only bug. None could have been caught at proposal stage.

## R2 prompt structure (CI-334 from 2026-05-09)

When R1 produces concerns and `/revise` applies fixes, the R2 prompt format affects convergence speed. Two patterns observed:

| Pattern | Behavior | Outcome |
|---------|----------|---------|
| Open-ended R2: "here's the revised spec; vote" | Roles re-litigate from scratch; sometimes raise *new* concerns unrelated to R1; mild divergence persists into R3+ | Slower convergence |
| **Structured R2: "you said X in R1; we did Y; vote on Y"** — each role's R2 prompt cites their R1 vote + concern, the operator's reframe or applied fix, and asks them to verify resolution | Roles produce calibrated re-votes that engage with the specific concern rather than re-litigating | Faster convergence — both 389 R2 and 395 R2 reached 5/5 aligned-approve in one round |

**Recommended R2 prompt skeleton** for each role:

```
In R1 you raised: <concern verbatim>.
Reframe / fix applied: <revision summary>.
Does this resolve your concern? (vote: approve | concern | reject; if concern, name what is still missing)
```

The structure forces the role to verify a specific resolution rather than re-evaluate the whole spec. New concerns may still surface, but they are surfaced as such (`new finding, not related to R1 X`) and can be triaged separately.

## Posture asymmetry — fail-closed vs fail-soft

`/implement` has two consensus-related gates with deliberately different failure postures:

- **Step 0d** (Final-Draft Consensus Gate, Spec 395) is **fail-closed** — an enforcer.
- **Step 2b.0** (Encoded-DA Verification, Spec 389) is **fail-soft** — an optimizer.

The principle is **optimizers fail soft, enforcers fail closed**. Both phrases appear here intentionally — they are the canonical names for the two postures.

Why the asymmetry is load-bearing:

- Step 0d's job is to prevent `/implement` on un-vetted specs. If the gate were fail-soft, an un-vetted spec would slip through silently — defeating the gate's purpose. The safe default for an enforcer is HALT.
- Step 2b.0's job is to skip a redundant DA subagent spawn when consensus has already covered DA's checklist. If the gate were fail-closed, a benign verification failure (e.g., the Consensus-Close-SHA exists but a small drift was detected) would block `/implement` entirely — defeating the optimization. The safe default for an optimizer is fall through to the un-optimized path.

If you find yourself implementing a new gate, ask: *what does failure mean here?* If failure means "let something dangerous through," it's an enforcer (fail-closed). If failure means "do the un-optimized thing," it's an optimizer (fail-soft). Don't mix the two postures; document which one each gate is.

## When to opt out (Consensus-Exempt patterns)

`Consensus-Exempt: <reason ≥ 30 chars>` is the operator's escape valve. Use it when:

- The spec is genuinely outside the consensus-required class but the classification rule mis-fires (rare; file a Spec 395 sunset signal).
- The spec is hotfix-adjacent — codebase regression block urgent fix, but the lane is technically `small-change` rather than `hotfix`. Reason should name the urgency anchor.
- Trivial-doc fast-path: `Consensus-Exempt: trivial-doc — <30+ char justification>`. Lane must be `small-change`. Verified retroactively at `/close` — if the actual diff exceeded ≤2 files OR >30 LOC, `/close` Step 7 emits CONDITIONAL_PASS. No `/implement`-time block.

What an exemption reason should NOT be: "I don't have time for consensus." The convention exists to prevent rushed un-vetted specs from entering implementation. If you're skipping consensus because you're rushed, that's the strongest signal that consensus would catch something.

## Lane B addendum (compliance profiles)

When `docs/compliance/profile.yaml` is present, the `Consensus-Exempt` escape valve is INSUFFICIENT on its own for high-stakes specs (BV ≥ 4 AND R ≥ 3). The exemption frontmatter must take the form:

```
- Consensus-Exempt: <reason ≥ 30 chars> [reviewed-by: <second-operator-identity>]
```

The `[reviewed-by: ...]` token is a forensic anchor. It prevents an audit-laundering composition: Consensus-Exempt + vet-pending status + Spec 052 sealing could otherwise let an under-vetted high-stakes spec carry the full audit weight of a properly-reviewed one. The counter-sign records both `operator_identity` and `reviewed_by_identity` in the activity log; Spec 052 immutability sealing then anchors both signatures.

Lane A (no compliance profile present) does not require counter-sign — the single 30-char operator-authored reason remains the trust root.

See [lane-b-audit-conventions.md](lane-b-audit-conventions.md) for the full Lane B fields list.

## Cross-references

- [consensus-protocol.md](consensus-protocol.md) — the convention reference
- [lane-b-audit-conventions.md](lane-b-audit-conventions.md) — Lane B fields and counter-sign rule
- [devils-advocate-checklist.md](devils-advocate-checklist.md) — DA-Encoded-Via and the optimizer side of the asymmetry
- Spec 258 — `Consensus-Review:` field
- Spec 301 — round cap
- Spec 389 — Consensus-Close-SHA
- Spec 395 — this convention
