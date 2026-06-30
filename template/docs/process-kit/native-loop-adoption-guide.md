# Native-Loop Adoption Guide (Spec 464)

How FORGE's lifecycle commands adopt three native Claude Code primitives — `/loop dynamic`,
`/goal`, and `ScheduleWakeup` — *inside* the command bodies so they self-pace and self-terminate
instead of relying on operator re-invocation. This is the **inside-command** sibling to Spec 459
(scheduled routines that fire from *outside* the lifecycle).

`Last verified: 2026-06-15`

> Honesty note: every loop this spec adds is **session-bounded** (see § Session-bounded vs
> reboot-surviving). Nothing here introduces a custom scheduler, daemon, or background service —
> native primitives only (ADR-359 native-over-custom).

## Which primitive where

| Command | Flag / site | Primitive | Invocation site | What it does |
|---------|-------------|-----------|-----------------|--------------|
| `/now`  | `--watch`   | `/loop dynamic` (+ native `ScheduleWakeup` scheduling) | command entry, after the help block | re-runs `/now` at model-paced delays until a state change or `/loop end` |
| `/implement` | `--goal-mode` | `/goal` | command entry, after Gate Outcome Format | wraps the implementation pass in an evidence-derived exit condition; hard cap 20 turns or `--abort` |
| `/evolve` | exit (gated) | `ScheduleWakeup` | command exit | schedules a `/evolve --auto` signal-check heartbeat (`forge.evolve.rewake_interval_days`); admission is **signal-based**, not calendar (Spec 500 / ADR-500) |

## Cache-window guidance

Anthropic prompt-cache TTL is ~5 minutes. `/loop dynamic` (used by `/now --watch`) should prefer
delays that respect this window where the workload allows — a wake that lands inside the cache TTL
reuses cached static context cheaply, while a wake far outside it pays full re-read cost. The model
picks each delay; this is documentation, not enforcement. Lower bound is
`forge.now.watch_default_min_delay` (default `60` s); upper bound is `3600` s.

## Session-bounded vs reboot-surviving

`/loop dynamic` and `ScheduleWakeup` live **only inside an active Claude Code session**. They do not
survive session close or machine reboot. Operators needing reboot-surviving recurrence use the
Routines API / `/schedule` (Spec 459), which fires from outside via `CronCreate`. This is a deliberate
scope boundary: 464 self-paces *within* a session; 459 owns durable, cross-session scheduling.

## Relationship to Spec 459

- **459 fires from outside** the lifecycle: `CronCreate` / `/schedule` routines invoke `/consensus`,
  `/evolve --scan`, `/brainstorm` on a cron schedule that survives reboot.
- **464 fires from inside** lifecycle commands: `/now --watch`, `/implement --goal-mode`, and the
  `/evolve` rewake loop within an active session.
- They compose: a 459 routine can fire `/evolve`, and that `/evolve` invocation then schedules its
  own next heartbeat per 464. Both invocations hit the same **signal-based admission** check (Spec 500
  Step 0-cd): explicit invocations always run; `--auto` heartbeats run only when a signal threshold is
  crossed — so a quiet period self-skips and there is no double-evolve / churn risk. (The ADR-046
  cool-down now governs *applied* self-modification at the apply surface, not review admission — Spec 500 / ADR-500.)

## Operator opt-out paths

- `forge.evolve.scheduled_rewake: false` — disables the `/evolve` ScheduleWakeup heartbeat entirely.
  Signal-based admission (Spec 500 Step 0-cd) still governs any manual `/evolve --auto`; behavior is
  identical to a manually invoked `/evolve`.
- `/loop end` — terminates an active `/now --watch` loop.
- `/implement --abort` — short-circuits a `--goal-mode` run immediately and prints the structured
  failure summary.

## Per-Lane required-gate list for /goal evaluation

`/implement --goal-mode`'s third exit signal (R5(iii)) reads the **filesystem gate-emissions log** at
`tmp/evidence/SPEC-NNN-YYYYMMDD/gate-emissions.log`. `/implement` appends a `GATE [<name>]: PASS`
line to this log as it emits each gate; the goal evaluator confirms all required gates for the spec's
`Change-Lane` are present **in the log file** (not the transcript — the log is the only injection-safe
source). Required gates per Change-Lane:

| Change-Lane | Required `GATE [...]: PASS` emissions |
|-------------|----------------------------------------|
| `hotfix` | `GATE [completeness]`, `GATE [delivery]` |
| `small-change` | `GATE [completeness]`, `GATE [delivery]` |
| `standard-feature` | `GATE [completeness]`, `GATE [delivery]`, `GATE [template-sync]` |
| `process-only` | `GATE [completeness]`, `GATE [delivery]` |

(The list is grounded in FORGE's current gate convention; extend it as new lanes/gates ship. The log
path and write timing are the convention `/implement --goal-mode` relies on — write each gate line at
the moment the gate is emitted, before the next step.)

## Per-primitive claude-code-version pin matrix

Verified against Claude Code documentation at /implement Step 0 (2026-06-15). The spec halts with
`GATE [primitive-version-pin]: FAIL — <primitive> not present in Claude Code <version>` on a mismatch.

| Primitive | Minimum verified version | Notes |
|-----------|--------------------------|-------|
| `/loop dynamic` | `2.1.72` | recurring task; omit interval → model self-paces (1 min – 1 hour) |
| `/goal` | `2.1.139` | autonomous run-until-condition; **requires ≥ 2.1.139** (above the spec's `>= 2.1.133` header pin — see note) |
| `ScheduleWakeup` | not a documented native primitive as of 2026-06-15 | the documented scheduled-task tools are `CronCreate` / `CronList` / `CronDelete` (used by `/loop` under the hood); `ScheduleWakeup` is referenced as the model-paced re-invocation mechanism — treat the underlying scheduling as native `/loop dynamic` re-invocation. If `ScheduleWakeup` is unavailable in the host runtime, the `/evolve` heartbeat degrades to no-op and `/now`'s signal-based recommendation surfaces the review instead (safe default; Spec 500 R7). |

> Version-pin finding (recorded at /implement Step 0, AC14): the spec's frontmatter pins
> `claude-code-version: ">= 2.1.133"`, but `/goal` requires `>= 2.1.139`. Operators on a runtime below
> `2.1.139` MUST NOT rely on `/implement --goal-mode`; the single-pass `/implement` path is unaffected.
> `ScheduleWakeup` is not a documented primitive — the `/evolve` heartbeat is best-effort, and
> signal-based admission (Spec 500 Step 0-cd) is the authoritative control over whether a review runs
> regardless of how `/evolve --auto` was invoked.

## 20-turn cap failure runbook

When `/implement --goal-mode` hits the 20-turn hard cap without the evidence-derived exit condition
satisfied, it prints the structured failure summary and exits non-zero. Operators:

1. **Re-engage manually** — drop out of `--goal-mode` and finish the remaining ACs interactively. The
   failure summary lists exactly which of the three evidence signals (validator exit code, spec
   `Status: closed`, gate-emission log) are still unmet and which gates are missing.
2. **Consider whether the ACs were under-specified** — a cap-fire often means the spec's acceptance
   criteria did not pin down a verifiable exit. Tighten the spec rather than the loop.
3. **Do NOT bump the cap.** The 20-turn cap is a hard safety bound (operator-chosen; revisit only when
   insights data accumulates — it is not derived from empirical run data). It is non-configurable by
   design (ADR-451 — autonomy advances only as fast as gates are machine-enforced).

## Audit-scope note for /now --watch

`/now --watch` creates a **persistent filesystem-survey loop** that is visible in operator transcripts.
Consumers should be aware that at **each wake** the loop reads:

- `.forge/state/` — derived/cool-down/checkpoint state,
- `docs/specs/` — spec frontmatter and statuses,
- `docs/digests/` — unreviewed external-research digests.

Nothing is written by the survey itself beyond the normal `/now` snapshot. The loop terminates on any
user prompt, a detected state change, or explicit `/loop end`. There is no network access and no
data leaves the session; the privacy surface is the transcript record of repeated filesystem reads.

## First-run notice prose for /evolve --auto heartbeat (retired by Spec 500)

The Spec 464 first-run cool-down notice is **retired** — there is no calendar cool-down on review
admission anymore (Spec 500 / ADR-500). A scheduled `/evolve --auto` heartbeat that finds no
accumulated signals now self-skips with the Step 0-cd admission line and reschedules:

```
GATE [evolve-admission]: SKIP — auto; no accumulation — skipped (nothing crossed since <date>; signals N/<t>, scratchpad N/<t>, EA N/<t>, deferred N/<t>, velocity N/<t>).
```

The companion status cue printed by `/now --watch` at arming and each wake:

```
[watch armed] next check in ~Xs; /loop end to terminate
```
