# Implementation and Testing in FORGE

How to move a spec from `draft` to `implemented` efficiently — the working rhythm between
`/spec` and `/close`. This guide covers the seven practices that make implementation fast
*and* evidence-clean. (New to FORGE? Start with [Getting Started](getting-started.md).)

## Contents

1. [Pick the right change lane](#1-pick-the-right-change-lane)
2. [Make acceptance criteria executable](#2-make-acceptance-criteria-executable)
3. [Fast feedback: `/test <path>` per vertical slice](#3-fast-feedback-test-path-per-vertical-slice)
4. [The delivery gate: full tests and lint](#4-the-delivery-gate-full-tests-and-lint)
5. [Live-smoke: when mocks aren't enough](#5-live-smoke-when-mocks-arent-enough)
6. [Targeted human validation](#6-targeted-human-validation)
7. [Checkpoints, resume, and parallel work](#7-checkpoints-resume-and-parallel-work)

## 1. Pick the right change lane

The lane sets the ceremony level — review rigor, budget ceiling, and gate requirements:

| Lane | Use when | Ceremony |
|------|----------|----------|
| `hotfix` | Critical fix, needed now, inside an already-open spec's scope | Minimal — DA gate may be skipped |
| `small-change` | Low-risk tweak, few files | Light |
| `standard-feature` | New command, new capability, cross-cutting change | Full gates |
| `process-only` | Docs/tracking changes only | Light |

Match ceremony to scale: a trivial edit does not deserve a `standard-feature` pipeline, and a
cross-cutting change should not sneak through as a `small-change`. The lane is declared in spec
frontmatter and verified at `/implement`.

## 2. Make acceptance criteria executable

The single highest-leverage habit: write each AC so a command can prove it.

- **Weak**: "The quick reference should be up to date."
- **Executable**: "`grep -cE '/(retro|harvest)\b' docs/QUICK-REFERENCE.md` returns 0."

Executable ACs eliminate validation-gate debates, let the validator re-run evidence fresh, and
survive context loss between sessions. Avoid vague terms ("should", "reasonable", "as needed") —
`/implement` scans for them and will prompt you to rewrite. Include negative-path ACs for gates
and validators: "seeding X makes check Y FAIL (then revert)".

## 3. Fast feedback: `/test <path>` per vertical slice

Implement in vertical slices — one requirement end-to-end at a time — and run the *narrow* test
after each slice:

```
/test tests/test_resolver.py     # one file's tests, seconds
```

`/test` with a path runs just that target with evidence capture; without arguments it runs the
full configured suite. The rhythm: slice → targeted test → next slice. Don't pay for the full
suite on every edit — that's what the delivery gate is for.

## 4. The delivery gate: full tests and lint

The `in-progress → implemented` transition requires ALL of: every AC satisfied, the full
configured test suite green, lint clean, and docs updated — verified by evidence (command output,
grep results, structural checks), not claims. `/implement` runs this as its post-implementation
checklist and emits structured `GATE [...]: PASS/FAIL` outcomes. A FAIL is a hard stop with a
named remediation, not a warning.

Your project's test and lint commands come from onboarding (`/configure` changes them later).

## 5. Live-smoke: when mocks aren't enough

Synthetic fixtures can pass while the real thing breaks. When a spec's Test Plan names a live
step — "smoke test", "live dry-run", "against the live repo", "production data sample" —
`/implement` Step 6e detects it and asks you to execute it for real (or explicitly defer to
`/close`, which then blocks until the evidence exists).

Rule of thumb: any spec that changes tooling, sync/release pipelines, generators, or consumer
delivery should run its real command against a scratch or live target at least once before close.
Fixtures verify logic; live-smoke verifies the world.

## 6. Targeted human validation

The human-validation runbook (`docs/process-kit/human-validation-runbook.md`) is sectioned
deliberately — run only the sections the spec names in its "Human validation steps" line, not the
whole checklist. A docs-only spec might need section A alone; a runtime change might need A + C.
The spec author declares the sections; `/close` presents exactly those for review.

## 7. Checkpoints, resume, and parallel work

- **Checkpoints**: `/implement` writes a checkpoint after each major step. If a run is
  interrupted, re-running `/implement NNN` detects it and offers to resume from the last
  completed step instead of restarting.
- **Parallel work**: `/parallel NNN NNN` runs multiple specs simultaneously in isolated git
  worktrees — use it only when the specs' `Changed files` lists are disjoint. `/implement next`
  surfaces a parallel-batch suggestion when adjacent backlog items qualify. Overlapping scopes
  serialize; shared state (git index, registries) is the hazard.
- **Multi-tab sessions**: `/tab` claims a spec per tab so two sessions never implement the same
  spec; commits stage explicit paths only.

---

*See also: [Getting Started](getting-started.md) · [Command reference](command-reference.md) ·
[FAQ](faq.md) · [Team Guide](team-guide.md)*
