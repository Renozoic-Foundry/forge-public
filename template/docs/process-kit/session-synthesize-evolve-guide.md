# Session / Synthesize / Evolve — Canonical Timing Guide

Anchor: `session-synthesize-evolve-guide`

Canonical guidance for when to run `/session`, `/synthesize`, and `/evolve`. Three commands, three different purposes, three different cadences. If you are unsure which one to run, start here.

Last updated: 2026-04-23 (Spec 309).

---

## Canonical comparison table

| Command | What it does (1 sentence) | Trigger conditions | Automation class | Expected cadence | Preconditions |
|---------|---------------------------|--------------------|------------------|------------------|---------------|
| `/session` | Creates or updates today's session log, mines the conversation for errors and insights, auto-triages the scratchpad, and emits a JSON handoff sidecar. | **Auto-prompted by `/now` Step 11** when any of: (a) >2h since the session log was last modified, (b) no session log exists for today, or (c) 3+ specs closed since the last session log update. Also one of FORGE's two hard rules: every session ends with a session log. | Auto-prompted (manual to execute — `/now` surfaces the recommendation; the operator runs it). Never runs unattended. | Once per working session, at minimum at end-of-session. Multiple times per day is fine when sessions are long. | An active working session with at least some activity (implementations, closes, decisions, or conversation worth capturing). No prerequisites on other artifacts. |
| `/synthesize` | Synthesizes accumulated artifacts (sessions, ADRs, specs, signals) into a refined narrative document — postmortem, topic summary, decision log, or architecture overview. | **Manually invoked** when the operator needs a consolidated read of accumulated knowledge. Recommended as a secondary hint by `/session` Step 5b (3+ specs touched in one session OR cross-cutting insights surfaced) and by `/evolve` Step 8.f (10+ signals or 3+ recurring themes in pattern analysis). Not directly surfaced by `/now`. | Manual-only. Never auto-prompted by `/now`, never runs unattended. | On-demand. Typical cadence: monthly postmortem, ad hoc topic summaries, quarterly architecture refresh, decision log before major reviews. | Requires an explicit mode flag (`--postmortem`, `--topic <query>`, `--decisions`, `--architecture`). Needs accumulated source material (session logs, ADRs, closed specs, signals) to synthesize from. Output directory `docs/synthesis/` is created on demand. |
| `/evolve` | Runs the KCS evolve loop review — AC drift check, signal pattern analysis, score calibration, spec proposal generation, and process improvement review. | **Auto-prompted by `/now` Step 12** when any signal-based threshold is crossed (defaults, composable — ANY fires the recommendation): 15 unreviewed signals, 4 open `[evolve]` scratchpad notes, 3 new error autopsies, 5 deferred-scope items, or 5 specs closed since the last review. Also a 30-day fallback time trigger if `Last evolve review` is stale/blank. Fast-path mode also fires automatically after each spec reaches `implemented` (via `/close`). `--auto` mode consults `docs/sessions/evolve-config.yaml` for its own trigger semantics. | Auto-prompted (manual to execute by default). Optional `--auto` mode runs unattended per config but still requires human approval for action items. | Fast path F1+F4 per spec close. Full F1-F4 monthly or when any signal threshold trips. Escalated (bold top-of-`/now` banner) after 2+ consecutive `/now` invocations flag it without action. | No active evolve loop already in progress (checked via `docs/sessions/context-snapshot.md` — the evolve-loop state marker blocks concurrent runs and also blocks `/implement`, `/spec`, `/close` during the loop). Access to `docs/sessions/signals.md`, `docs/backlog.md`, and the session-log history for the review period. |

---

## Reading guide for solo developers

Use this section to answer the three "when do I run X?" questions in under 60 seconds.

### When do I run `/session`?

- **At the end of every working session.** This is non-negotiable — one of FORGE's two hard rules is "every session ends with a session log."
- **When `/now` tells you to.** If `/now` says "Session log is stale" or "N accumulated entries since last update," run `/session` now, not later.
- **If you have been coding for 2+ hours without a log update.** Drafting a log at the 2-hour mark captures fresher context than waiting until fatigue hits.
- **After closing 3+ specs in a row.** `/now` will prompt you; `/session` auto-draft synthesizes the accumulated `/close` entries.

You never need to pass arguments. `/session` handles the rest.

### When do I run `/synthesize`?

- **When you need a narrative for an audience.** Sharing progress with a team? Preparing a retrospective? Writing up an architecture brief? `/synthesize` produces the shareable document.
- **When `/session` or `/evolve` suggests it.** `/session` recommends synthesis after 3+ specs touched or cross-cutting insights. `/evolve` recommends it after 10+ signals or 3+ recurring patterns.
- **On a regular cadence:** monthly postmortem (`/synthesize --postmortem`), quarterly architecture overview (`/synthesize --architecture`), ad hoc topic summaries (`/synthesize --topic <query>`).
- **Before a major review or decision.** Generate a decision log (`/synthesize --decisions --since <date>`) to see every decision in one place.

`/synthesize` is **not** a status-update command. Use `/session` for "what happened today" and `/synthesize` for "what happened this quarter, narrated."

### When do I run `/evolve`?

- **When `/now` says "Evolve loop recommended."** This is the primary trigger. Do not ignore it — the escalation banner appears after 2 unheeded prompts.
- **After closing a spec**, `/close` routes into `/evolve --spec NNN` fast-path automatically (F1+F4 only — AC drift check and backlog update).
- **Monthly**, whether or not a trigger fires, run `/evolve --full` for the complete F1-F4 review (AC drift, KPIs, score calibration, signal patterns, regret rate).
- **When the signals pile up.** 15+ unreviewed signals is the signal-count default. 4+ open `[evolve]` scratchpad notes is the scratchpad default. Either indicates process debt accumulating.

`/evolve` is a process-review command. Running it mid-session blocks `/implement`, `/spec`, and `/close` until the loop exits — schedule it for a natural break point.

---

## Rationale

### Why three commands, not one?

Each command operates on a different timescale and produces a different artifact class:

- `/session` operates on **today's session**. Produces a timestamped session log (`docs/sessions/YYYY-MM-DD-NNN.md`) + JSON sidecar. It's the write-back path for context anchoring.
- `/synthesize` operates on **a span of accumulated sessions**. Produces a narrative document (`docs/synthesis/YYYY-MM-DD-<mode>.md`) — the summarized read-back path for humans and future AI sessions.
- `/evolve` operates on **the process itself**. Produces updates to the backlog, score calibration adjustments, new spec proposals, and signal pattern analysis — it is the KCS (Knowledge-Centered Service) evolve loop that keeps the framework self-correcting.

Merging any two of these would produce a command with unclear scope and conflicting cadence. `/session` needs to be quick and habit-forming (haiku tier). `/synthesize` needs rich cross-artifact reasoning (sonnet tier, on-demand). `/evolve` needs structured pattern detection and gate logic (sonnet tier, gated).

### Why automation classes differ

- `/session` is **auto-prompted**: the habit must form. `/now` Step 11 is the nag mechanism. But execution remains manual because a session log is a human-signed record of the day.
- `/synthesize` is **manual-only**: it is a report-generation command, and reports should be produced when a human needs one, not on a schedule. Auto-generating synthesis reports nobody reads wastes tokens and noise.
- `/evolve` is **auto-prompted with optional auto-run**: process review has a real cost (several signal reads + KPI analysis + human attention), so it should not run every session. But letting it lapse is dangerous — hence the signal-threshold prompts and the escalation banner. `--auto` mode exists for operators who want cron-style runs with human approval at the action-taking step.

### Why `/synthesize` has no `/now` trigger

`/now` surfaces **work you should do**. `/session` is work (a habit gate). `/evolve` is work (a process gate). `/synthesize` is a tool you reach for when you have a need — it is not itself a gate or a habit. Recommending `/synthesize` from `/now` would add noise without improving outcomes. `/session` and `/evolve` surface `/synthesize` as a secondary hint exactly where the signal (3+ specs touched, 10+ accumulated signals) arises naturally.

### Why trigger thresholds are what they are

The Step 11 thresholds (2h, no log today, 3+ specs) are empirical — they minimize false positives on short sessions while catching the "I got deep into implementation and forgot" failure mode.

The Step 12 thresholds (15 signals / 4 scratchpad notes / 3 EAs / 5 deferred items / 5 specs / 30 days) come from Spec 193's composable-trigger design: ANY threshold fires, and the 30-day fallback ensures the loop never lapses entirely. Operators who find a specific threshold too chatty can override in `docs/sessions/evolve-config.yaml`.

### Relationship to FORGE's two hard rules

From `CLAUDE.md`:

> 1. Every change has a matching spec. No implementation without one.
> 2. Every session ends with a session log. No exceptions.

Rule 2 is enforced by `/session`. `/synthesize` and `/evolve` are not session-closure gates — they are distinct artifacts. Do not substitute `/synthesize` or `/evolve` for `/session` at end-of-session. Run `/session` first, then `/evolve` if prompted, then `/synthesize` if you need a narrative.

---

## Audit notes (Spec 309 Requirement 4)

Cross-reference audit performed during Spec 309 implementation:

- **`/now` Step 11 (session staleness)** — documented above matches the actual code in `.claude/commands/now.md`. No drift.
- **`/now` Step 12 (evolve loop triggers)** — documented above matches the actual code. Thresholds listed are the defaults; `docs/sessions/evolve-config.yaml` may override.
- **`/synthesize` has no direct `/now` trigger** — confirmed. It is surfaced only as a secondary hint from `/session` Step 5b and `/evolve` Step 8.f. This is intentional (see Rationale above), not a defect. No follow-up spec required.
- **`/evolve` fast-path auto-fire via `/close`** — `/close` routes into `/evolve --spec NNN` automatically on implemented-spec closure. Documented above.

No discrepancies requiring a follow-up spec were found. If a future audit reveals drift between `/now` and this guide, update this document and the corresponding `/now` step in the same spec.

---

## See also

- `CLAUDE.md` — the two hard rules and the role mapping table
- `.claude/commands/session.md` — `/session` implementation
- `.claude/commands/synthesize.md` — `/synthesize` implementation
- `.claude/commands/evolve.md` — `/evolve` implementation
- `.claude/commands/now.md` — Steps 11-12 (staleness and evolve-trigger detection)
- `docs/process-kit/context-anchoring-guide.md` — why session logs exist
- `docs/process-kit/human-validation-runbook.md` — section F covers the evolve loop runbook
- `docs/sessions/evolve-config.yaml` — evolve-loop trigger mode and thresholds
