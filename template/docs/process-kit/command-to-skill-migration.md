# Command-to-Skill Migration Runbook (Spec 461)

This runbook defines how FORGE migrates descriptive commands into Claude Code **skills**
(`SKILL.md` under `.claude/skills/<name>/`), the four-category partition that governs which
commands migrate and how each migrated skill behaves, the description-quality checklist that
gates auto-invocation, the **batched** graduation procedure for Category B, the
explicit-only-forever list (Category C) with rationale, and an honest statement of which
skills auto-fire from day 1.

> **Last verified:** 2026-06-15 (Spec 461 implementation).

## Activation model (why this matters)

A **slash command** requires the operator to type `/name` — an explicit gesture: predictable,
but it loses every utterance where the operator described the intent without remembering the
command name. A **skill** with `disable-model-invocation: false` is invoked autonomously by
the model when prompt context matches the skill's `description:` — zero recall cost, but every
false-fire is a behavior change the operator did not ask for. A skill with
`disable-model-invocation: true` is invocable only on explicit naming (the dual-surface period).

A skill's `description:` is the **only** signal Claude Code uses to decide whether to
auto-invoke it. A loose description fires on unintended prompts; a tight description never
fires when it should. That asymmetry is the load-bearing risk this runbook manages.

## Honest status note (Spec 461)

**Categories A skills (3) auto-fire from day 1; Categories B and C (10) do not auto-fire.**

This supersedes the pre-R1 framing ("no skill is auto-invocable at first ship"). The three
Category A skills — `dependency-audit`, `brainstorm`, `note` — ship with
`disable-model-invocation: false` and MAY fire autonomously on prompts matching their
descriptions. This is a new behavior consumers should expect; it is not a regression. The
remaining 10 skills (Categories B + C) exist but do not auto-fire — they are invocable only by
explicit naming until (Category B) a batched graduation spec flips them, or (Category C) never.

## The four-category partition

The migration partition is the load-bearing decision. The partition heuristic: a skill belongs
to **Category A** if and only if (i) the model can reliably infer the operator's intent from
prompt context with low false-positive risk AND (ii) a false-fire is recoverable in seconds with
no destructive state mutation AND (iii) the recall-cost savings is high. Otherwise it goes to
**B** (medium false-fire risk; may graduate after observed-explicit-invocation evidence) or
**C** (false-fire blast radius high enough that graduation is never appropriate).

### Category A — Real auto-invocable skills (3, ship with `disable-model-invocation: false`)

| Skill | Why auto-invocation is worth it on day 1 | Description positive example | Description negative example |
|---|---|---|---|
| `dependency-audit` | Operators rarely remember to invoke this until after a breakage; auto-fire on dependency-change context catches the gap | "package.json updated to bump react to 19.0" | "let's add a comment explaining the react usage" |
| `brainstorm` | High recall-cost — operators want spec-opportunity surfacing but rarely think to type `/brainstorm`; auto-fire on roadmap/next-step prompts is high-leverage | "what should we work on next?" | "what does this function do?" |
| `note` | Lowest false-fire blast radius (creates scratchpad entry deletable in seconds); high recall value (operators forget to record context) | "remember this for the next checkpoint" | "remember to bring milk tomorrow" |

The positive/negative example pairs above are embedded as YAML comments above the `description:`
field in each Category A `SKILL.md` so future reviewers can replay the vetted intent.

### Category B — Dual-surface explicit-only (7, ship with `disable-model-invocation: true`)

These skills carry medium false-fire risk OR uncertain recall-cost value. Graduate via the
**single batched follow-up spec** when ≥3 of them have accumulated explicit-invocation evidence
+ cleared the description-quality checklist.

| Skill | Why explicit-only at first ship | Graduation trigger |
|---|---|---|
| `explore` | Fires on "research X" prompts but also on benign curiosity questions — false-fire risk medium | ≥3 explicit invocations + description-quality pass |
| `synthesize` | Mode-flag-rich (`--postmortem`, `--topic`, etc.); auto-fire mis-picks the wrong mode | ≥3 + description distinguishes mode-selection signals |
| `insights` | Fires on "what are we learning" — could fire on tutorial questions | ≥3 + description anchored to project-process-data context |
| `interview` | Socratic gesture — operators want it deliberately, not as a surprise | ≥3 + description excludes generic question-asking |
| `trace` | Fires on "where is REQ-X" — could fire on debugging questions | ≥3 + description anchored to spec-traceability context |
| `matrix` | Display-mostly; operators type `/matrix` deliberately | ≥3 + description excludes generic prioritization questions |
| `evolve` | Process-quality concern surface — could fire on generic "how can we improve" | ≥3 + description anchored to FORGE process-quality signals |

### Category C — Explicit-only-forever (3, ship with `disable-model-invocation: true`; CISO tripwire enforced)

These skills have high false-fire blast radius. Graduation is NEVER appropriate. The CISO
tripwire fixture (`test-spec-461-invocation-policy.{sh,ps1}`, AC3c) asserts these MUST remain
`true` — a future `/revise` that flips any of these to `false` FAILs the fixture.

| Skill | Why never auto-invocable |
|---|---|
| `consensus` | Spawns N role subagents on each invocation; non-trivial token + time cost per false-fire |
| `decision` | Creates a tracked ADR artifact; false-fire pollutes the architectural decision record |
| `revise` | Mutates an existing spec; false-fire corrupts prior agreements / consensus closure |

### Category D — Keep as command (16, no change)

| Command | Rationale (why this MUST remain operator-explicit) |
|---|---|
| `spec` | Creates a tracked artifact under `docs/specs/` |
| `implement` | Mutates code under an active SHA-bound contract |
| `close` | Terminal lifecycle gate; evidence-bound |
| `forge` | Unified lifecycle dispatcher — meta-command, operator-only |
| `forge-init` | Bootstraps the framework; one-shot, operator-only |
| `forge-stoke` | Resumes from compaction; explicit operator gesture |
| `onboarding` | Configures the project; explicit operator gesture |
| `session` | Closes the session log — terminal, operator-only |
| `configure` | Mutates configuration; explicit operator approval required |
| `tab` | Initializes/closes a multi-tab session — session-boundary, operator-explicit |
| `parallel` | Dispatches multi-spec parallel execution — high-blast-radius |
| `scheduler` | Multi-agent scheduler — high-blast-radius |
| `now` | Status display — operators type `/now` deliberately; mis-fire would create noise on every prompt |
| `test` | Runs the test suite — operator-explicit |
| `nanoclaw` | Manages the NanoClaw container — operator-explicit infrastructure gesture |
| `configure-nanoclaw` | Mutates NanoClaw hardware key enrollment — operator-explicit |

## Description-quality checklist (Category B graduation gate)

For Category A skills the description was vetted at spec-time (positive/negative example pairs in
the Partition table above, embedded in each `SKILL.md`). For **Category B graduation** (the single
batched follow-up spec), apply this checklist per skill:

1. The `description:` names the **intent class**, not the command name. Operator review: the
   description reads as a behavior the model would recognize even if the operator had never heard
   of FORGE.
2. The `description:` includes at least one **positive example** (a prompt phrasing the skill
   SHOULD fire on). Recorded as a YAML comment in `SKILL.md`.
3. The `description:` includes at least one **negative example** (a similar prompt phrasing the
   skill should NOT fire on). The negative example is the load-bearing half — it forces the
   description-writer to think about the false-fire surface.
4. The skill has been invoked **explicitly** ≥3 times (in explicit-only mode) with no operator
   complaint that the body misbehaved.
5. The operator records the graduation decision in the batched follow-up spec's Revision Log,
   including the SHA of each `SKILL.md` at graduation time.
6. **Rollback clause**: if a graduated skill mis-fires in production, the operator MAY revert it
   to `disable-model-invocation: true` in a single-line `/revise` to the batched graduation spec.
   The CISO tripwire does NOT block this rollback (it only blocks Category C `false`-flips).

## Batched graduation procedure (Category B — single follow-up spec)

Category B does **not** graduate one skill per spec. Graduation is a **single batched follow-up
spec** covering whichever Category B skills are ready at the time:

1. Trigger: ≥3 of the 7 Category B skills have accumulated explicit-invocation evidence and clear
   the description-quality checklist above.
2. Open ONE follow-up spec listing the ready skills. For each, flip
   `disable-model-invocation: true → false` and record the SHA of the `SKILL.md` at graduation.
3. The follow-up spec re-runs the body-equivalence fixture (AC4) and the invocation-policy fixture
   (the Category B set under test moves from the "must be true" bucket to "now false"); Category C
   stays under the tripwire unchanged.
4. Skills not yet ready remain `true` and wait for the next batched graduation spec. There is no
   per-skill ceremony.

## Explicit-only-forever list (Category C — rationale + amendment rule)

The Category C set is `consensus`, `decision`, `revise` (rationale in the Category C table above).
The CISO tripwire fixture mechanically enforces it. Amendment rules:

- **Adding** to the explicit-only-forever list is routine: update this runbook's Category C table
  and the `CAT_C` array in `test-spec-461-invocation-policy.{sh,ps1}`, then `/revise`.
- **Removing** from the list requires a separate Lane-B-style spec because the CISO tripwire must
  be updated deliberately — a removal weakens a safety property and must not ride along on an
  unrelated change.

## Dual-surface coexistence

This migration is **additive**. The 13 corresponding command files at
`template/.claude/commands/` are NOT deleted or modified — both the command surface and the skill
surface coexist. AC4 body-equivalence guarantees that whichever surface answers a `/<name>`
invocation, the body — and therefore the behavior — is identical. The 16 Category D commands are
untouched (byte-identical to baseline, AC5).

<!-- forge:maintainer-detail:start -->
## Verification

```bash
bash .forge/bin/tests/test-spec-461-skill-presence.sh       # ACs 1, 2, 5
bash .forge/bin/tests/test-spec-461-invocation-policy.sh    # AC3 (CISO tripwire + AC3c drift)
bash .forge/bin/tests/test-spec-461-body-equivalence.sh     # AC4 (+ injected-drift sub-case)
grep -c "disable-model-invocation: false" template/.claude/skills/*/SKILL.md  # expect 3 (Cat A)
grep -c "disable-model-invocation: true"  template/.claude/skills/*/SKILL.md  # expect 10 (Cat B + C)
```
<!-- forge:maintainer-detail:end -->

## Helper invocations in skill/command bodies (Spec 538)

Since skills are generated verbatim from the canonical command body (`.forge/commands/<name>.md`
via `forge-sync-skills.sh`), any `.forge/bin/*` or `.forge/lib/*` helper invocation authored into
a command body ships into the skill body too — including to plugin-only consumers with no
vendored `.forge/` tree. Author every such invocation with the
`${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/...` idiom (resolves from the plugin root when installed as
a plugin, falls back to project-relative for classic vendored consumers). See
`docs/process-kit/single-source-generator-guide.md#plugin-root-relative-helper-resolution-in-commandsskills-spec-538`
for the full convention, the PowerShell equivalent, and documented exclusions (project-scoped
data paths, FORGE's own self-referential authoring paths, and destination-report/naming-template
prose that never resolves to a helper being invoked).

## Plugin namespacing (forward note)

Plugin packaging (`.claude-plugin/plugin.json`) is **not** introduced by Spec 461. Spec 463 adds
plugin namespacing **additively** via the plugin manifest, without renaming `SKILL.md` frontmatter
or churning through these 13 files.
