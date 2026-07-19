# Close Adoption Gate — Operator Guide

> Spec 402 — closes the **build-without-adopt** failure mode: a spec ships new
> machinery (a frontmatter field, a generated-artifact path, a config block, or an
> annotation format) and records closure as "code merged," but no operator or
> process actually uses it. The gate fires at `/close` (Step 2g+) and FAILs when a
> declared artifact/format/field/config has zero consumers and no explicit
> follow-up adoption spec.

## Why this gate exists

`/evolve` loop 18 (Proposal P1) generalized five build-without-adopt signals
(SIG-036-01, SIG-036-02, SIG-187-01, SIG-134-01, SIG-258-01). In each case the
originating spec shipped machinery that the spec itself did not exercise:

- A generated-artifact path (`docs/compliance/traceability-*.md`) that no command reads.
- A config block (`forge.dispatch_rules`) shipped `enabled: false` with no trigger criteria.
- A frontmatter field declared in `_template.md` that no spec populates.

Closure recorded "merged," not "behavior changed." Operators and auditors read the
declaration, assume it is live, and build on a false floor.

Spec 387's safety-property gate (Step 2g) covers the safety-property *subset* of
this pattern. Spec 402 extends the same forcing function to the broader
artifact/format/config superset.

## Relationship to Spec 387

| | Spec 387 (Step 2g) | Spec 402 (Step 2g+) |
|---|---|---|
| Scope | Safety properties (correctness/security/concurrency) | Any new artifact path, frontmatter field, or config block |
| Detection | Diff matches `.forge/safety-config-paths.yaml` registry | Spec-body scan of Scope / Requirements / Acceptance Criteria |
| Adoption evidence | `## Safety Enforcement` section (code path + negative-path test) | ≥1 consumer in the repo; originating spec body counts |
| Escape hatch | `Safety-Override:` (≥50-char reason) OR `# UNENFORCED — see Spec NNN` | `Follow-up adoption spec: NNN` |

Step 2g+ does **not** re-check safety properties — Step 2g owns those. The two gates
run back-to-back at `/close`.

## What the gate detects

The driver `adoption_gate_check` (in `.forge/lib/close-adoption-gate.{sh,ps1}`)
scans the spec's `## Scope`, `## Requirements`, and `## Acceptance Criteria`
sections for three declaration classes:

1. **New frontmatter fields** — `Capitalized-Hyphenated:` tokens that are not
   already known FORGE frontmatter fields (the known-field allow-list mirrors
   `_template.md` plus the lifecycle fields written by commands).
2. **Generated-artifact paths** — backticked output globs ending in a doc/data
   extension, e.g. `` `docs/compliance/traceability-*.md` ``.
3. **Config-block keys** — dotted keys under `forge.` or `multi_agent.`, e.g.
   `forge.dispatch_rules`.

## The adoption check

For each detected declaration, the gate greps the repo for ≥1 consumer:

- **Originating-spec-as-consumer**: a frontmatter field populated in the spec's own
  frontmatter counts; a path or config key referenced by any consuming file counts.
- The gate library, its tests, and this guide are excluded from the consumer count
  (they name the tokens definitionally, not as adoption).

If every declaration has ≥1 consumer → **PASS**. If any declaration has zero
consumers AND no follow-up field → **FAIL** (exit 2).

## The escape hatch — `Follow-up adoption spec: NNN`

When adoption is intentionally deferred to a named successor, add to the spec
frontmatter:

```
- Follow-up adoption spec: 600
```

The referenced spec (`600`) must exist in `docs/specs/`. A valid follow-up field
defers the gate entirely — Spec 600 owns adoption. A follow-up field pointing at a
non-existent spec does **not** defer (it FAILs like an unadopted declaration), so
the escape hatch cannot be used to launder a dangling reference.

## Worked example 1 — frontmatter field, FAIL then PASS

A spec adds a `Demo-Field:` declaration in its Requirements but never populates it.

```
GATE [close-adoption]: FAIL — 1 declaration(s) shipped without a consumer: Demo-Field
Remediation: (a) exercise the declaration (the originating spec body counts —
populate the field/path/config in this spec or a consuming file), or (b) add
`Follow-up adoption spec: NNN` to the spec frontmatter naming the successor.
```

Add the field to the spec's own frontmatter (`- Demo-Field: <value>`) and re-run:

```
GATE [close-adoption]: PASS — all 1 declaration(s) have ≥1 consumer.
```

## Worked example 2 — generated-artifact path with no reader (SIG-036-02)

A spec declares it will emit `` `docs/compliance/traceability-*.md` `` but no command
or process reads the path.

```
GATE [close-adoption]: FAIL — 1 declaration(s) shipped without a consumer: docs/compliance/traceability-*.md
```

Disposition: either wire a command to read the path (then the command file is the
consumer), or add `Follow-up adoption spec: NNN` naming the spec that ships the reader.

## Worked example 3 — config block shipped disabled (SIG-187-01)

A spec adds `forge.dispatch_rules` `enabled: false` with no documented trigger
criteria and nothing reading the block.

```
GATE [close-adoption]: FAIL — 1 declaration(s) shipped without a consumer: forge.dispatch_rules
```

Disposition: reference the block from a command (`/implement` reading
`forge.dispatch_rules.enabled` is the consumer), or defer via follow-up spec.

## Worked example 4 — deferred adoption (PASS)

A spec adds a `Demo-Field:` declaration but adoption is owned by Spec 950:

```
- Follow-up adoption spec: 950
```

```
GATE [close-adoption]: PASS — adoption deferred via Follow-up adoption spec.
```

## Retroactive scope — what the gate does NOT do

The gate runs at `/close` time only. It never re-evaluates already-closed specs, so
historical specs that predate the convention are not flagged. The one-time backfill
audit of specs that *would* have failed is an informational, non-blocking `/evolve`
pass (Spec 402 AC8) — captured to a markdown report for operator review, not a gate.

<!-- forge:maintainer-detail:start -->
## File map

- `.forge/lib/close-adoption-gate.sh` + `.ps1` — detection + adoption-check + gate driver
- `.claude/commands/close.md` / `.forge/commands/close.md` Step 2g+ — gate invocation
- `template/.forge/lib/close-adoption-gate.{sh,ps1}` — template mirrors
- `template/.claude/commands/close.md` / `template/.forge/commands/close.md` Step 2g+ — template mirrors
- `.forge/bin/tests/test-spec-402-adoption-gate.{sh,ps1}` — fixtures (ACs 1-7)
<!-- forge:maintainer-detail:end -->

## Cross-references

- Spec 387 — safety-property gate (the safety subset; Step 2g)
- `docs/process-kit/gate-categories.md` — this gate is machine-verifiable
- `docs/process-kit/safety-property-gate-guide.md` — the prior-art gate this one generalizes
