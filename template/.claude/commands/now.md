---
name: now
description: "Review current project state and suggest next action"
model_tier: haiku
workflow_stage: session
---

# Framework: FORGE
# Model-Tier: haiku
Review the current project state and tell me what should happen next.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /now — Review project state and recommend the next action.
  Usage: /now
  No arguments accepted.
  Reads: docs/backlog.md, docs/sessions/ (latest log + JSON sidecar), CLAUDE.md, docs/specs/README.md
  Reports: validation queue, active work, next recommended spec, evolve loop status, blockers.
  Prefers JSON handoff sidecars for structured context; falls back to markdown parsing.
  See: CLAUDE.md (operating loop, spec lifecycle), docs/backlog.md
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Step 0 — Snapshot freshness check (Spec 091)
Read `docs/sessions/context-snapshot.md`. Check the `Generated:` timestamp.
- If generated within the last 10 minutes AND no `## Active implementation` section shows a step change: use snapshot data directly for steps 1-8. Report: "Using recent context snapshot (generated <time>)." Skip to step 9 (write updated snapshot with refreshed timestamp).
- If stale (>10 minutes), missing, or an active implementation is in progress: proceed with full file reads (steps 1-8) and write a fresh snapshot.

## [mechanical] Step 0b — Session Brief (Spec 105)
Check `forge.context.session_briefing` in AGENTS.md (default: `true` if absent).
If `false`: skip this step entirely.

If `true` (or absent):
a. **JSON sidecar check** (Spec 119): Before reading markdown session logs, check if `.json` sidecar files exist alongside the 3 most recent session logs. For each session log `docs/sessions/YYYY-MM-DD-NNN.md`, look for `docs/sessions/YYYY-MM-DD-NNN.json`.
   - If a JSON sidecar exists: parse it directly for `summary`, `decisions`, `specs_touched`, `open_items`, `next_actions`, `error_autopsies`, and `chat_insights`. This is faster and more structured than parsing markdown.
   - If no JSON sidecar exists: fall back to reading the markdown session log as before.
   - Report which method was used: "Loaded session context from JSON sidecar" or "Parsed session context from markdown (no JSON sidecar)."
b. Read the 3 most recent session logs from `docs/sessions/` (by filename date, excluding `_template.md`, `context-snapshot.md`, `scratchpad.md`, `signals.md`, `registry.md`, `error-log.md`, `insights-log.md`).
   - If no session logs exist: skip this step (new project — first session).
   - For logs without a JSON sidecar: extract from markdown: **Summary** section content, **Decisions made** entries, unresolved **Process pain points**, unchecked **Process improvement items**.
c. Read `docs/sessions/signals.md` — extract signal entries from the last 7 days (by section date header).
d. Read `docs/sessions/scratchpad.md` — list items NOT marked `[resolved]` or checked off.
e. Read `docs/sessions/context-snapshot.md` — check for specs listed as in-progress or active that have not been closed (stale > 24h from session log date).

f. **Session identity check** (Spec 133): Resolve the current operator identity using this fallback chain:
   1. Check `docs/sessions/context-snapshot.md` for a `## Session identity` section — use the name stored there.
   2. If not found: check `.copier-answers.yml` for `default_owner` — use that value.
   3. If not found: use literal "operator".
   Display: "Session identity: **<resolved name>**. Confirm or type a new name."
   - If the user confirms (or does not object): proceed with the resolved name.
   - If the user provides a different name: use that name instead.
   Store the confirmed identity in the context snapshot under `## Session identity` (written in Step 9).

Present a **Session Brief** section before the main output:
```
## Session Brief — "Last time on [project]"

**Recent sessions** (last 3):
- <date>: <1-line summary from each session>

**Open decisions/blockers**:
- <unresolved pain points or open process items from recent logs>

**Recent signals** (last 7 days):
- <signal IDs and 1-line summaries>

**Unresolved scratchpad**:
- <open items from scratchpad>

**Stale work**:
- <any in-progress specs not closed within 24h, or "none">
```

Constraints:
- Keep the entire brief to ≤15 lines (summarize aggressively — one line per session, one line per signal)
- If a section has no items, omit that section entirely (don't show empty headers)
- Read only the Summary and Pain Points sections from session logs (not the full files) to minimize token cost

---

1. **Validation queue (priority check)**: Read docs/specs/README.md and scan for any specs with status `implemented` (not yet `closed`). For each one found, list it as needing human validation.
   - If any `implemented` specs exist, present them as the **priority recommended action**:
     ```
     ## Validation queue
     The following specs are implemented but not yet validated by a human:
     - Spec NNN — <title>: <objective>
     ```
     For each implemented spec, read its spec file (`docs/specs/NNN-*.md`) and extract the first sentence of the `## Objective` section. Include it as `<objective>` in the listing above.
     Then offer a choice for each implemented spec:
     ```
     > **Choose** — type a number or keyword:
     > | # | Action | What happens |
     > |---|--------|--------------|
     > | **1** | `review NNN` | Display full validation checklist from human-validation-runbook.md |
     > | **2** | `close NNN` | Run /close NNN to validate and close the spec |
     > | **3** | `skip` | Defer validation — continue to backlog recommendations |
     ```
     If user selects "review": read `docs/process-kit/human-validation-runbook.md`, identify applicable sections (A–G) based on the spec's changes, and display the full Quick Check list for each applicable section. After displaying, remind: "Run `/close NNN` when validation is complete."
   - This takes priority over recommending new implementation work.

<!-- parallel: steps 2-5 are independent reads — run them simultaneously -->
2. Read docs/backlog.md and identify the highest-ranked spec with status `draft` or `approved`.
3. Read docs/sessions/ and find the most recent session log. Check its "Spec triggers" and "Process improvement items" sections for any open items (unchecked boxes).
4. Read CLAUDE.md post-implementation checklist and identify any items that appear outstanding based on recent session context.
5. Check docs/specs/README.md for any spec listed as `draft` that has been sitting without movement.
6. **Session log auto-create**: Check `docs/sessions/` for a log file matching today's date. If none exists, create a stub from `docs/sessions/_template.md` with today's date and the next session number (scan existing files to determine NNN). Report: "Created session log: `docs/sessions/YYYY-MM-DD-NNN.md`."
7. **Scratchpad review**: Read `docs/sessions/scratchpad.md` for any open notes — list all unresolved items grouped by tag (`[validate]`, `[session]`, `[evolve]`, untagged).
7b. **Pending explorations**: Scan `docs/research/` for files matching `explore-*.md`. For each file, check the `Status:` field. If any have `Status: proposed`, report:
   ```
   **Pending explorations**: N proposed research artifact(s) in docs/research/
   - explore-<topic>.md (proposed, <date>)
   ```
   If no proposed explorations exist or the directory is absent, skip silently.
8. **Active tabs check**: Read `docs/sessions/registry.md` (if it exists). Report any rows with Status = `active`, listing their tab label, lane, claimed spec(s), and start time. Flag any stale claims (last active > 30 minutes ago). If no registry or no active rows, skip silently.
8b. **Runbook staleness check** (Spec 107): Read all `.md` files in `docs/process-kit/`. For each file, look for a `<!-- Last updated: YYYY-MM-DD -->` comment. If the date is more than 30 days ago (or the comment is missing), flag the runbook as potentially stale:
   ```
   ## Stale runbooks
   The following runbooks have not been updated in 30+ days:
   - docs/process-kit/<filename>.md — last updated: <date> (<N> days ago)
   ```
   If all runbooks are current, skip silently.

9. **Write context snapshot**: After gathering all data above, write `docs/sessions/context-snapshot.md` (gitignored) with the following structured sections. This snapshot is used by subsequent commands for display-only lookups, reducing redundant file reads.
   ```
   # Session Context Snapshot
   Generated: YYYY-MM-DD HH:MM

   ## Validation queue
   <list of implemented specs or "empty">

   ## Next recommended spec
   <spec ID, title, score, lane, or "none">

   ## Open scratchpad notes
   <count and summary, or "none">

   ## Active tabs
   <registry summary or "none">

   ## Last session log
   <file path>

   ## Evolve loop status
   <last review date, overdue flag>

   ## Session identity
   <confirmed operator name from Step 0b.f>
   ```

10. **Current session cost** (Spec 085 — skip if `forge.model_router.mode` is `static` or `.forge/metrics/command-costs.yaml` does not exist):
   Read `.forge/metrics/command-costs.yaml`. Filter entries to today. Summarize: total commands, total estimated cost, tier distribution. Include in the context snapshot under `## Session Cost`.

Then report:
- **Validation queue**: specs at `implemented` awaiting `/close` (from step 1) — this is the top priority
- **Active work**: any open spec triggers or process improvement items from the last session log that haven't been converted to specs yet
- **Agent activity** (Spec 134): If `docs/sessions/activity-log.jsonl` exists and has entries, read it and summarize events since the last operator session log. Group by agent_id. For each agent: list specs started, specs closed, gates failed, errors. If no activity log or empty, skip silently.
- **Next recommended spec**: the highest-ranked backlog item with status `draft` or `approved` that is ready to implement — state its spec ID, file path, score, and the first implementation step. Only recommend new implementation if the validation queue is empty or the user has deferred validation.
- **Evolve loop check**: state the date of the last evolve loop review (from the most recent session log's `Last evolve loop review:` field) and flag if it's overdue (> 30 days)
- **Active tabs**: any other Claude Code tabs with active claims (from step 8) — warn about potential conflicts
- **Blockers**: anything that must be resolved before the next spec can start

If no outstanding items exist and the backlog is current, recommend the single highest-value next action and explain the rationale using the scoring rubric.

## [mechanical] Step 11 — Session log staleness detection (Spec 131, enhanced by Spec 157)

Check `docs/sessions/` for the most recent session log. Compare its date to the current time:
- If >2 hours since the session log was last modified (or no log exists for today): flag as stale.
- If 3+ specs have been closed since the last session log update (check CHANGELOG.md for close entries after the log date): flag as stale.
- **Spec 157 enhancement**: If stale AND accumulated entries exist (structured entries appended by /implement and /close in today's session log), offer "Draft session log?" as a choice block option that triggers `/session` auto-draft directly — not just "run `/session`":
  ```
  Session log is stale with N accumulated entries.
  → **Draft session log?** — `/session` will generate a pre-populated draft for your review.
  ```
- If stale but no accumulated entries: fall back to "Session log is stale — run `/session` to update."

## [mechanical] Step 12 — Evolve loop trigger detection (Spec 131, enhanced by Specs 157, 193)

Check signal-based triggers for the evolve loop. Read `docs/sessions/evolve-config.yaml` if it exists for threshold overrides; otherwise use defaults below.

**Signal-based triggers** (composable — ANY threshold crossed fires the recommendation):
1. **Unreviewed signals**: Count entries in `docs/sessions/signals.md` added after the last evolve review date. Default threshold: **15**.
2. **Open scratchpad notes**: Count unchecked `[evolve]` (or `[outer-loop]`) items in `docs/sessions/scratchpad.md`. Default threshold: **4**.
3. **Error autopsies**: Count error autopsy entries in session logs since last evolve review. Default threshold: **3**.
4. **Deferred scope items**: Count "Out of scope" items across closed specs since last review that were dispositioned as "deferred" (not "dropped"). Default threshold: **5**.
5. **Spec velocity**: Count specs closed since last evolve review (from CHANGELOG.md). Default threshold: **5**.

**Fallback time trigger**: If the last evolve review date is >30 days ago or blank, also flag as overdue (backward-compatible safety net).

Read the most recent session log's `Last evolve review:` field (or `Last evolve loop review:` for backward compat).

- If any threshold is crossed: report which triggers fired:
  ```
  Evolve loop recommended — <N> trigger(s) crossed:
  - Unreviewed signals: <count>/<threshold>
  - Spec velocity: <count>/<threshold>
  ```
  Add to the choice block: "Evolve loop triggered — run `/evolve`."
- If no thresholds crossed: skip silently.
- **Spec 157 escalation**: Track how many consecutive `/now` invocations have flagged the evolve loop (check context-snapshot.md for a `## Evolve loop overdue count` field). If flagged 2+ times without action:
  - Escalate visibility: present the warning in **bold at the top of /now output**, not just in the choice block:
    ```
    **EVOLVE LOOP OVERDUE** — last review: <date> (<N> days ago). Flagged <M> times without action.
    Run `/evolve --full` to address.
    ```
  - Update the overdue count in context-snapshot.md.

## [mechanical] Step 13 — Context-aware choice block (Spec 131)

At the end of every `/now` invocation, present a numbered choice block based on current context. Build the options dynamically:

```
> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
```

Always include these options (numbered dynamically based on which apply):

1. **If implemented specs exist**: `close NNN` — Run `/close NNN` to validate and close
2. **If draft/approved specs exist in backlog**: `implement` — Run `/implement next` for the top-ranked spec. Read the top-ranked spec file (`docs/specs/NNN-*.md`) and append its objective as a sub-line: "_<first sentence from the spec's ## Objective section>_"
3. **If session log is stale** (from Step 11): `session` — Run `/session` to update the session log
4. **If evolve loop is overdue** (from Step 12): `evolve` — Run `/evolve` for process review
5. **If backlog is empty or has no draft specs**: `brainstorm` — Run `/brainstorm` to discover new spec opportunities
6. **Always**: `stop` — No action needed right now

Present only the options that apply to the current context. Number them sequentially starting from 1.

After the choice block, include the footer:
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_
