---
name: insights
description: "Mine FORGE process data for cross-session insights"
workflow_stage: session
---
# Framework: FORGE
# Model-Tier: haiku
Mine all FORGE process data to produce a cross-session, project-scoped insights report.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /insights — Project-scoped insights engine (FORGE Spec 049).
  Usage: /insights [--errors] [--friction] [--signals] [--velocity] [--since YYYY-MM-DD]

  Arguments:
    (none)              Full analysis across all dimensions
    --errors            Error pattern analysis only
    --friction          Process friction analysis only
    --signals           Signal cluster analysis only
    --velocity          Spec velocity analysis only
    --since YYYY-MM-DD  Limit analysis to sessions on or after this date

  Data sources:
    docs/sessions/*.md        Session logs (decisions, pain points, spec triggers)
    docs/sessions/signals.md  Retrospective signals (SIG-NNN entries)
    docs/sessions/error-log.md   Error autopsies (EA-NNN)
    docs/sessions/insights-log.md  Chat insights (CI-NNN)
    docs/sessions/scratchpad.md  Open notes
    docs/backlog.md           Spec velocity and aging

  Output: Structured markdown report, rendered inline.
  Each finding includes: occurrence count, source references, severity, recommended action.
  Findings already tracked in backlog or scratchpad are flagged "already tracked."
  See: docs/specs/049-project-insights-engine.md
  ```
  Stop — do not execute any further steps.

---

Parse $ARGUMENTS:
- Set `MODE` = `full` (default), or one of: `errors`, `friction`, `signals`, `velocity` if the matching flag is present.
- Set `SINCE` = the date string after `--since` if provided, else empty.
- If `--errors` → MODE=errors. If `--friction` → MODE=friction. If `--signals` → MODE=signals. If `--velocity` → MODE=velocity.

If `docs/sessions/` does not exist or contains no `.md` files other than `_template.md`:
  Report: "No session data found. Run `/session` to create your first session log."
  Stop.

---

<!-- parallel: steps 1-6 are independent reads — run them simultaneously -->

## [mechanical] Step 1 — Read session logs

Read all `.md` files in `docs/sessions/` excluding `_template.md`, `signals.md`, `error-log.md`, `insights-log.md`, `scratchpad.md`, `context-snapshot.md`, and `registry.md`.

If `SINCE` is set: only include session files whose date prefix (YYYY-MM-DD in filename) is >= SINCE.

From each session log, extract:
- **Pain points / friction items**: lines under "Pain points", "Blockers", or "Process improvement items" sections
- **Spec triggers**: items listed as spec triggers (unchecked or noted)
- **Decisions**: items in any "Decisions" section
- **Date**: from the filename (YYYY-MM-DD)

## [mechanical] Step 2 — Read error-log.md

Read `docs/sessions/error-log.md`.
Extract each EA-NNN entry: ID, title, root cause category, affected component, date (if present).
If file does not exist: skip silently.

## [mechanical] Step 3 — Read insights-log.md

Read `docs/sessions/insights-log.md`.
Extract each CI-NNN entry: ID, title, category, date (if present).
If file does not exist: skip silently.

## [mechanical] Step 4 — Read signals.md

Read `docs/sessions/signals.md`.
Extract each SIG-NNN entry: ID, type (error/insight/decision/feedback), summary, action.
If file does not exist: skip silently.

## [mechanical] Step 5 — Read scratchpad.md

Read `docs/sessions/scratchpad.md`.
Extract all open notes: their tag (`[spec-trigger]`, `[validate]`, `[evolve]`, untagged), content, and age (date added if present).
If file does not exist: skip silently.

## [mechanical] Step 6 — Read backlog.md

Read `docs/backlog.md`.
Extract:
- All specs with their status, score, and `Last updated` date (from the backlog header fields or row data)
- The `Last evolve loop review:` date
- Any stalled specs: status = `draft` or `in-progress` with no movement in > 14 days

---

## [mechanical] Step 7 — Load existing tracking context

Read `docs/specs/README.md`. Collect all spec IDs and their titles for cross-referencing.
Build a set: `TRACKED` = all spec titles/descriptions visible in backlog.md + scratchpad.md open notes.
This is used in Step 8 to avoid recommending what's already tracked.

---

## [mechanical] Step 8 — Analyze

Perform only the dimensions included in MODE (or all if MODE=full):

### A — Error patterns (skip if MODE != full and MODE != errors)

Group EA-NNN entries by root cause category or affected component.
For each group with 2+ entries:
- Pattern name: inferred common theme (e.g., "shell script path/encoding issues")
- Occurrences: list of EA-NNN IDs
- Severity: `isolated` (1 occurrence) | `recurring` (2–3) | `systemic` (4+)
- Check if this pattern is already tracked in `TRACKED` — if yes, flag "already tracked in Spec NNN"
- Recommended action: `/spec` (if not tracked) or "tracked in Spec NNN" (if tracked)

### B — Process friction (skip if MODE != full and MODE != friction)

Scan all extracted pain points and friction items from session logs.
Group identical or semantically similar items (e.g., same tool/command appearing in multiple sessions).
For each group with 2+ occurrences:
- Friction label: the recurring pain point (e.g., "heredoc quoting failure")
- Occurrences: list of session file references (YYYY-MM-DD-NNN.md)
- Severity: `isolated` | `recurring` | `systemic`
- Check against `TRACKED`
- Recommended action: `/spec` (if not tracked), `/revise` (if an existing spec needs updating), or "tracked in Spec NNN"

### C — Signal clusters (skip if MODE != full and MODE != signals)

From signals.md SIG-NNN entries, group by type and common theme.
For each cluster with 2+ signals:
- Cluster label: inferred theme
- Members: SIG-NNN list
- Predominant type: error | insight | decision | feedback
- Check against `TRACKED`
- Recommended action: `/spec`, `/evolve`, or "tracked in Spec NNN"

### D — Spec velocity (skip if MODE != full and MODE != velocity)

From backlog.md data:
- List specs stalled at `draft` for > 14 days (flag as stale)
- List specs stalled at `in-progress` for > 7 days (flag as blocked)
- Compute approximate lead time for recently `closed` specs if date data is available
- Flag if the evolve loop review is overdue (> 30 days since `Last evolve loop review:`)

### E — Improvement debt (always included unless MODE is a single dimension other than full)

From scratchpad.md open notes:
- Flag notes tagged `[spec-trigger]` that have not been converted to specs — these are improvement debt
- Flag notes aged > 14 days (stale scratchpad items)
- Check each against `TRACKED`
- Recommended action: `/spec` (if not tracked) or "tracked in Spec NNN"

---

## [decision] Step 9 — Render report

Render the following structured markdown report:

```
# FORGE Insights Report
Generated: YYYY-MM-DD
Sessions analyzed: N  |  Date range: YYYY-MM-DD → YYYY-MM-DD
Findings: N error patterns, N friction clusters, N signal clusters, N velocity flags, N improvement debt items

---

## Error Patterns
(omit section if MODE excludes this dimension or no findings)

### [severity] <Pattern Name>
- **Occurrences (N):** EA-NNN, EA-NNN, ...
- **Severity:** systemic | recurring | isolated
- **Tracking:** already tracked in Spec NNN | ⚠ not tracked
- **Recommended action:** /spec "<suggested title>" | tracked in Spec NNN — no action needed

---

## Process Friction
(omit section if MODE excludes this dimension or no findings)

### [severity] <Friction Label>
- **Occurrences (N):** session YYYY-MM-DD-NNN.md, ...
- **Severity:** systemic | recurring | isolated
- **Tracking:** already tracked in Spec NNN | ⚠ not tracked
- **Recommended action:** /spec "<suggested title>" | /revise NNN | tracked in Spec NNN

---

## Signal Clusters
(omit section if MODE excludes this dimension or no findings)

### <Cluster Label> (N signals, type: error|insight|decision|feedback)
- **Members:** SIG-NNN, SIG-NNN, ...
- **Tracking:** already tracked in Spec NNN | ⚠ not tracked
- **Recommended action:** /spec "<suggested title>" | /evolve | tracked in Spec NNN

---

## Spec Velocity
(omit section if MODE excludes this dimension or no findings)

- Stalled drafts (>14 days): Spec NNN — <title> (stalled N days)
- Blocked in-progress (>7 days): Spec NNN — <title>
- Evolve loop: last review YYYY-MM-DD — [current | ⚠ overdue by N days]

---

## Improvement Debt
(omit section if MODE != full or no findings)

- [spec-trigger] "<note summary>" — added YYYY-MM-DD — ⚠ not converted to spec
- [stale] "<note summary>" — added YYYY-MM-DD — stale (N days)

---

## Summary
<N> findings across <N> sessions. <N> already tracked. <N> new recommendations.
Top recommendation: <single highest-priority actionable item>
```

If a section has no findings, omit it entirely (do not print empty sections).
If no findings at all: report "No patterns detected across the analyzed data. Project process looks clean."

---

## [mechanical] Step 10 — Next action

Present a context-aware next action:
- If untracked error patterns or friction clusters found: "Next: run `/spec <suggested title>` to create a spec for the top untracked finding."
- If stalled specs found: "Next: run `/implement next` to resume the highest-ranked stalled spec, or `/now` to review blockers."
- If improvement debt found: "Next: run `/spec <note summary>` to convert the oldest untracked scratchpad trigger to a spec."
- If evolve loop is overdue: "Next: run `/evolve` — last review was N days ago."
- If no actionable findings: "Next: continue current work. Run `/now` for project state."
