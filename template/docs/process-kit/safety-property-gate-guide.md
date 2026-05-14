# Safety Property Gate — Operator Guide

> Spec 387 — closes the build-without-dogfood failure mode for safety-property declarations
> in FORGE configuration. This guide explains what the gate does, when it fires, the registry
> file, the override path, the threshold-to-action mappings, and worked examples.

## Why this gate exists

The 2026-05-03 audit (SIG-036-01 and four siblings) found that 4 of 5 reviewed closed specs
shipped machinery that the originating spec itself did not adopt. The most consequential case:
`multi_agent.atomic_checkout: true` was declared in `template/AGENTS.md.jinja`, the schema and
storage shipped, but no command implements the concurrent-claim detection logic. Operators
(and auditors) read AGENTS.md, see `atomic_checkout: true`, and assume the property holds —
when in fact two agents can race a claim with zero detection. The classic false-assurance
attack surface: believed-safe + actually-unsafe.

The gate adds a `/close`-time forcing-function prompt that catches new instances at the moment
they are introduced, plus a quarterly `/evolve` sweep that catches dormancy in already-closed
specs, plus a one-time backfill audit (30-day SLA) over pre-existing safety-schema declarations.

## The three components

1. **Component A** — `/close`-time prompt, scope-filtered via `.forge/safety-config-paths.yaml`.
   When the spec's diff includes new entries in registered config files, /close asks
   "Does this introduce a safety property?" Yes-answers gate the close on a `## Safety
   Enforcement` body section listing enforcement code path + negative-path test, with an
   explicit `# UNENFORCED — see Spec NNN` annotation when enforcement is deferred.

2. **Component B** — Quarterly `/evolve` sweep that verifies enforcement persistence and runs
   a wide-net grep over non-registered files. Runs on the existing `/evolve` cadence —
   no new schedule. Gated by 90-day dormancy threshold (skips if last sweep <90 days).

3. **Component C** — One-time backfill audit (`scripts/safety-backfill-audit.sh`) with a
   30-day SLA hard-failure rule (no operator discretion at the boundary).

## The registry file

`.forge/safety-config-paths.yaml` lists the paths whose new entries trigger Component A's
prompt. Initial pattern set (per Spec 387 R1a):

```yaml
patterns:
  - AGENTS.md
  - CLAUDE.md
  - .forge/onboarding.yaml
  - .mcp.json
  - .forge/safety-config-paths.yaml
  - template/AGENTS.md.jinja
  - template/CLAUDE.md.jinja
  - "template/**/*.yaml"
```

Two key properties:

- **Self-monitoring**: the registry file is itself in the registry (entry 5). Any modification
  to the registry triggers Component A's prompt — adding/removing patterns gets the same
  scrutiny as adding/removing safety properties.
- **Bootstrap fallback**: the first-time addition of `.forge/safety-config-paths.yaml` to a
  project (or its deletion) is detected by a hardcoded fallback in `/close.md` that runs
  independently of registry contents. This handles the chicken-and-egg case.

## The prompt flow at /close

After the validator subagent step and before the close-completion step:

1. Detection: `git diff <baseline>..HEAD --name-only` is matched against registered patterns.
2. If no match AND no bootstrap-fallback trigger: silent skip.
3. If `Safety-Override:` frontmatter present: validate (≥50 chars, non-trivial), log to
   activity-log.jsonl, skip the prompt, proceed.
4. Otherwise emit verbatim:

   ```
   This spec touched <N> file(s) matching the safety-config registry: <paths>.
   Does this introduce a safety property — a behavior the system relies on for correctness, security, or concurrency?
   [y/N]
   ```

5. **No** (default): logs `safety-prompt-no` event, proceeds.
6. **Yes**: gate-checks the spec body for a `## Safety Enforcement` section with three lines:
   - `Enforcement code path: <file>::<symbol>`
   - `Negative-path test: <file>::<test-name>`
   - `Validates ...` (≥10 chars description)

   Missing or invalid → `/close` exits with code 2 + the canonical R2e message. Operator must
   either add the section, or set `Safety-Override:` frontmatter.

## The override path

`Safety-Override:` is for the case where the diff matched the registry but the operator
asserts the change is not a safety property (e.g., a documentation-only edit to AGENTS.md).
The override has guardrails:

- **≥50 characters** (after whitespace trim) — forces actual reasoning, not "wip" or "ok".
- **Trivial-string regex reject** — case-insensitive match against `wip|ok|later|fix|tbd|n/a|na|none|pass|done` is rejected.
- **Audit logged** — every accepted override appends one record to `activity-log.jsonl`:
  ```json
  {"event_type":"safety-override","spec":"NNN","paths":[...],"reason":"...","timestamp":"..."}
  ```

Frequent overrides (>2/quarter) trigger a /evolve warning per the threshold mappings below.

## The UNENFORCED deferral path

When a safety property is declared but enforcement is deferred to a later spec, the schema
field in the affected config file must be either ABSENT or followed by:

```
some_safety_property: true   # UNENFORCED — see Spec 134
```

The corresponding Spec NNN must exist in `docs/specs/` with status `draft`, `in-progress`,
`implemented`, or `closed`. Status `draft` is allowed at /close-time but flagged at the next
quarterly sweep (R5c).

The `## Safety Enforcement` section in the originating spec uses placeholders:

```
Enforcement code path: src/concurrent.sh::<placeholder>
Negative-path test: tests/test-concurrent.sh::<deferred to Spec 134>
Validates that two simultaneous claim attempts are not both granted.
```

## Threshold-to-action mappings

The quarterly `/evolve` sweep emits a 7-metric record and cross-checks against five thresholds.
When a threshold is crossed, /evolve emits a warning. **The mappings are the action surface —
metrics without paired action thresholds are themselves a build-without-dogfood instance**
(per CI-307).

| Metric | Threshold | Action |
|---|---|---|
| `no_rate` | >0.5 over rolling 4-quarter window | Warning: "Registry over-firing — consider tightening pattern set or operator habituation review" |
| `overrides_used` | >2 in current quarter | Warning: "Override frequency above threshold — pattern audit recommended" |
| `dormant_found` | >0 | Per-item disposition prompt for the operator (delete declaration, annotate UNENFORCED with new spec, or file follow-up enforcement spec) |
| `wide_net_flagged` | >0 | Warning: "New safety-named tokens outside registry — consider expanding `.forge/safety-config-paths.yaml`" |
| `yes_answers / specs_prompted` | <0.05 over 4-quarter window | Warning: "Prompt firing without yields — recheck registry coverage" |

## The 7-metric record schema

`.forge/state/safety-sweep.jsonl` is append-only — one record per sweep:

```json
{
  "timestamp": "2026-05-03T22:50:00Z",
  "specs_prompted": 10,
  "yes_answers": 2,
  "no_rate": 0.800,
  "deferred_with_unenforced": 1,
  "overrides_used": 3,
  "dormant_found": 2,
  "wide_net_flagged": 1
}
```

All five threshold rows above operate against this schema. The schema is canonical and frozen
at spec time per round-5 CTO amendment.

## Worked example 1 — yes-path with shipped enforcement (atomic_checkout)

A spec adds `multi_agent.atomic_checkout: true` to `template/AGENTS.md.jinja`. The diff
matches the registry. /close prompts:

```
This spec touched 1 file(s) matching the safety-config registry: template/AGENTS.md.jinja.
Does this introduce a safety property — a behavior the system relies on for correctness, security, or concurrency?
[y/N] y
```

The spec body must contain:

```markdown
## Safety Enforcement

Enforcement code path: .forge/lib/atomic-claim.sh::acquire_spec_claim
Negative-path test: .forge/bin/tests/test-atomic-claim-race.sh::test_two_agents_one_spec
Validates that two simultaneous claim attempts on the same spec produce exactly one success and one failure with retry.
```

If all three lines resolve (file exists, symbol in file, test name in test file): /close
proceeds. The Spec 365 immutability mechanism does NOT cover the Safety Enforcement section
(R2f), so a later /revise correcting the code path won't trigger a SHA recompute cascade.

## Worked example 2 — no-path (Consensus-Review is not a safety property)

A spec adds `Consensus-Review: true` to a different spec's frontmatter via `template/docs/specs/_template.md`. The diff matches `template/**/*.yaml` (if YAML) or no
pattern (if markdown). If the diff matches:

```
[y/N] n
```

Logged as `safety-prompt-no`, /close proceeds. No safety property — `Consensus-Review`
governs review process, not behavior the system relies on for correctness.

## Worked example 3 — hypothetical deferred case

A spec adds a new schema field `multi_agent.require_confirmation_at: critical` to AGENTS.md
but enforcement is deferred to a separately scheduled implementer spec, Spec 600.

In `template/AGENTS.md.jinja`:

```yaml
multi_agent:
  require_confirmation_at: critical   # UNENFORCED — see Spec 600
```

In the originating spec's body:

```markdown
## Safety Enforcement

Enforcement code path: .forge/lib/confirmation-gate.sh::<placeholder>
Negative-path test: .forge/bin/tests/test-confirm-gate.sh::<deferred to Spec 600>
Validates that critical-tier actions require explicit confirmation before execution.
```

/close proceeds (Spec 600 must exist with valid status). At the next quarterly /evolve sweep,
if Spec 600 is still `draft` (not progressed), the `dormant_found` count increments and the
operator gets a per-item disposition prompt.

## Worked example 4 — retroactive annotation (pre-convention enforcement)

A backfill audit dry-run flags a safety-schema declaration as MISSING enforcement evidence
(e.g., `multi_agent.atomic_checkout: true` in `AGENTS.md` and `template/AGENTS.md.jinja`).
Verification reveals the enforcement DOES exist — at `.claude/commands/implement.md`'s
"Atomic spec checkout and activity log" step (shipped by Spec 134 R3a) — but the originating
spec closed before the `## Safety Enforcement` section convention existed (Spec 387 post-dates it).

The right disposition is **retroactive annotation**, not duplicate enforcement: ship a small
spec (Spec 396 was the canonical first instance) that adds a `## Safety Enforcement` section
to the closed originating spec, paired with a newly-authored negative-path test fixture.
Status of the originating spec remains `closed` — this is documentation of existing
enforcement, not new requirements.

The added section in Spec 134:

```markdown
## Safety Enforcement

Enforcement code path: AGENTS.md::atomic_checkout
Enforcement code path: template/AGENTS.md.jinja::atomic_checkout
Enforcement code path: .claude/commands/implement.md::Atomic spec checkout
Negative-path test: scripts/tests/test-spec-134-atomic-claim-race.sh::test_two_agents_one_spec
Validates that two sequenced claim attempts via the activity-log read-then-append pattern are detected — the second attempt finds the prior unfinished spec-started event and aborts ...
```

**Symbol resolution rule** (canonical for retroactive annotations): "symbol" in
`Enforcement code path: <file>::<symbol>` is interpreted as a function or test-block name
in code files (shell, Python, etc.) OR a section-heading text in markdown command files
(such as `.claude/commands/*.md`, where the "code" is operator-readable instructions, not
callable functions). The resolution rule for both forms: **literal grep against the file
MUST return ≥1 match** (`grep -F '<symbol>' <file>`). The `Validates`-prefixed prose line
should be **bounded to what the existing enforcement actually guarantees** — overclaiming
is a defect class (e.g., do not assert "absolute concurrent-safety" when the underlying
pattern is read-then-append with a check-then-append race window).

Why two enforcement-code-path lines for the declaration files (`AGENTS.md`,
`template/AGENTS.md.jinja`) on top of the canonical implementation pointer? The Spec 387
backfill audit greps each spec body for `Enforcement code path: <declaration-file>::` to
classify the hit as enforced. The audit is **symbol-blind by design at first ship** — only
the file-prefix is verified, not the symbol referent. Pairing each declaration-file location
with the implementation pointer is what flips the audit from list (ii) → list (i). The
audit's symbol-resolution gap is filed as a separate small-change spec (Spec 396 Out-of-scope
follow-up); until that lands, the declaration-file pairing pattern is the convention.

When to use retroactive annotation vs ship-enforcement:

- **Retroactive annotation**: enforcement code path **already exists** in the codebase, just
  not annotated. Cheapest disposition (~30 min per case). Spec 396 is the pattern.
- **Ship enforcement**: declaration is real but no code-path enforces it. Costs whatever
  the implementation costs.
- **Delete the declaration**: turns out not to be a safety property at all (workflow config,
  documentation marker, etc.). Spec 397's `require_confirmation_at` ignore-list is the parallel
  pattern for the "false-positive class" disposition.

## Worked example 5 — audit ignore-list (workflow-config false-positive)

A backfill audit dry-run flags a token as MISSING enforcement evidence (e.g.,
`require_confirmation_at` in AGENTS.md). The token syntactically matches the audit's prefix
regex `(atomic|enforce|require|validate|guard|prevent|reject)_[a-zA-Z_]+`, but verification
reveals it is **not actually a safety property** — it is an autonomy-level chain-control
config (AGENTS.md:415–436). The `require_X` framing is workflow, not safety: L2 lists
confirm-points; L3/L4 use empty list.

The right disposition is **audit ignore-list entry**: register the token in
`.forge/safety-config-ignore.yaml` with an explicit `reason:` field. The audit's filter step
(Spec 397 R3) reads the yaml and moves matching hits from list (ii) "MISSING" into a new
list (iii) "Ignored declarations (operator-curated)" — preserving audit visibility while
suppressing /close-time SLA pressure.

Example entry:

```yaml
version: 1
ignore:
  - token: require_confirmation_at
    reason: "Autonomy-level chain-control config (AGENTS.md:415-436); the require_X framing is workflow, not safety. L2 lists confirm-points; L3/L4 use empty list."
    added: 2026-05-04
    spec: 397
```

`--check-only` mode (used by /close Step 2g.5 SLA gate) is silent on list (iii), so workflow-
config false positives no longer block /close. Each entry requires explicit operator judgment
recorded in the `reason:` field — the audit cannot self-discriminate which `require_X` /
`validate_X` keys are safety properties.

### Disposition decision tree (false-positive class)

When the audit flags a token, decide between three patterns:

| Pattern | When | Cost | Canonical spec |
|---------|------|------|---------------|
| **Audit ignore-list** | Token is workflow-config / not a safety property at all (the regex match is incidental) | Cheapest (~10 min — yaml entry + reason) | Spec 397 |
| **Retroactive annotation** | Token IS a safety property AND code-path enforcement already exists, but originating spec pre-dates the `## Safety Enforcement` convention | ~30 min per case (annotate closed spec + add negative-path test) | Spec 396 |
| **Ship enforcement** | Token IS a safety property AND no code-path enforces it (real gap) | Whatever the implementation costs | per case |

The first question to ask: **is this token actually a safety property?** If no → ignore-list.
If yes → check whether enforcement already exists (annotate) vs needs to be built (ship).
Per-token operator judgment is required; the audit surfaces candidates, the operator decides
the disposition.

## 1-quarter verification plan (AC17)

Per the round-5 COO amendment, the first-quarter post-implement checklist is the on-the-ground
test of whether the gate is doing its job. Run this 90 days after Spec 387 closes:

1. **Sample 10 closed specs** from the post-Spec-387 timeframe. Confirm Component A's prompt
   fired iff the diff touched a registered path. Expected: 100% true-positive (every prompt
   matched a registered-path diff) and 100% true-negative (no prompt fired on diffs that
   didn't touch registered paths).
2. **Override ratio**: `overrides_used / specs_prompted < 0.30`. Higher overrides = either
   the registry is too aggressive or operators are gaming the gate. Either way, file a follow-up.
3. **Sweep action triggers**: at least one of the 5 R5g sweep metrics triggered an action by
   end of Q1. If zero metrics triggered any action over the entire quarter, file a follow-up
   spec to either retire components (the metrics aren't earning their keep) or tune thresholds
   (the action thresholds are too lax).

The verification plan is itself a build-without-dogfood guard for the gate. If Spec 387 ships
metrics that nobody acts on for 90 days, that's the same failure mode the spec exists to
prevent — and the gate gets retired or recalibrated, not preserved as a dead artifact.

## Backfill audit

Run once at /implement completion, then again at any /close that hits the 30-day SLA marker:

```bash
scripts/safety-backfill-audit.sh           # full report + 30-day SLA marker
scripts/safety-backfill-audit.sh --dry-run # full report, no marker change
scripts/safety-backfill-audit.sh --check-only  # quiet mode for /close gate
```

PowerShell parity: `scripts/safety-backfill-audit.ps1 [-DryRun] [-CheckOnly]`.

## Disposition decision tree

When a safety-named declaration lacks enforcement evidence:

- **Ship enforcement**: add a `## Safety Enforcement` section in some spec referencing the
  declaration's file+symbol. Best path when the property is real and you're committed to it.
- **Annotate `# UNENFORCED — see Spec NNN`**: when enforcement is deferred to a known follow-up
  spec. Spec NNN must exist with status `in-progress` or `implemented` (per R3c at sweep-time).
- **Delete the declaration**: when the property turns out not to be needed, or it's not a
  safety property after all. Cleanest path for false starts.

## Cross-references

- Spec 365 immutability — `## Safety Enforcement` and `Safety-Override:` are excluded from
  the Approved-SHA hash input (R2f, R4d). Code-path corrections via `/revise` do not trigger
  Spec 365 recompute.
- Spec 134, 187 — explicit cases in the backfill audit.
- Spec 349 — behavioral-AC fixture convention; every behavioral AC paired with a fixture.
- CI-307 (insights-log) — telemetry-without-action-thresholds is itself build-without-adopt;
  R5g threshold-to-action mappings address this directly.

## File map

- `.forge/safety-config-paths.yaml` — registry (data, not code)
- `.forge/lib/safety-config.sh` + `.ps1` — path-match + override-validation + section-validation helpers
- `.claude/commands/close.md` Step 2g — Component A
- `.claude/commands/evolve.md` Step S — Component B
- `scripts/safety-backfill-audit.sh` + `.ps1` — Component C
- `.forge/state/safety-backfill-deadline.txt` — 30-day SLA marker (set by audit, checked at /close)
- `.forge/state/safety-sweep.jsonl` — quarterly metric history (append-only)
- `.forge/state/safety-config-paths-prior.yaml` — prior-quarter snapshot (registry-curation drift check)
