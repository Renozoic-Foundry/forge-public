---
name: session
description: "Create or update the session log"
model_tier: haiku
workflow_stage: session
---
# Framework: FORGE
# Model-Tier: haiku
Create or update the session log for this session.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /session — Create or update today's session log; mine chat for errors and insights.
  Usage: /session
  No arguments accepted.
  Creates: docs/sessions/YYYY-MM-DD-NNN.md + .json sidecar
  Behavior: Populates summary, decisions, pain points, spec triggers, process
    improvements. Mines conversation for EA/CI entries. Reviews scratchpad.
    Generates a JSON handoff sidecar for machine-parseable context transfer.
  See: docs/sessions/_template.md, .forge/templates/session-handoff-schema.json, docs/process-kit/context-anchoring-guide.md, CLAUDE.md (two hard rules)
  ```
  Stop — do not execute any further steps.

---

1. Check docs/sessions/ for a log file dated today (YYYY-MM-DD-NNN.md where NNN is today's session number). If none exists, create one from docs/sessions/_template.md.

### [mechanical] Step 1b — Read accumulated entries (Spec 131)

Before mining the conversation, read any structured entries already appended to the session log by `/implement` and `/close` (these commands now append incremental "spec started" and "spec closed" entries during execution). Collect:
- Specs started (with timestamps)
- Specs closed (with gate outcomes and signal counts)
- Any other structured entries

Present these accumulated entries to the human:
```
## Accumulated session data (auto-logged)
The following entries were captured automatically during this session:
- <HH:MM> Spec NNN started (via /implement)
- <HH:MM> Spec NNN closed — 5 PASS, 0 FAIL (via /close)
...
```

Use these accumulated entries as the foundation for the session log — synthesize them into the Summary and other sections rather than starting from a blank template.

### [mechanical] Step 1c — Auto-draft synthesis (Spec 157)

Generate a **complete draft session log** with all sections pre-populated from accumulated entries and conversation context:

a. **Summary**: Synthesize from accumulated entries — what was started, what was completed, what was deferred. 2-3 sentences.
b. **Decisions made**: Extract from spec implementations, /close outcomes, and explicit conversation decisions. Each entry self-contained and searchable.
c. **Process pain points**: Infer from error patterns, retries, manual workarounds, and conversation friction. Be specific.
d. **Spec triggers**: Extract from conversation context and scratchpad items — new specs that must exist before the next session.
e. **Process improvement items**: Extract from conversation context — changes needed to CLAUDE.md, checklists, runbook, or workflow docs.

Present the complete draft to the operator:
```
## Draft Session Log
<full draft with all sections populated>

Review this draft. You can:
- **approve** — write to disk as-is
- **edit** — tell me what to change, then approve
- **regenerate** — start the draft from scratch
```

**Human confirmation required** before writing the session log to disk. Do not write without approval.

2. If the operator requests edits, apply them and re-present. If the operator approves, write the session log. If no accumulated entries exist, fall back to manual population — review the conversation and populate:
   - **Summary**: 2–3 sentences covering goal, what was completed, what is deferred
   - **Decisions made**: every concrete choice about code, schema, process, or architecture made this session — each entry self-contained and searchable
   - **Process pain points**: anything that caused friction, confusion, or required a workaround — be specific
   - **Spec triggers**: any new specs that must exist before the next implementation session
   - **Process improvement items**: any changes needed to CLAUDE.md, checklists, runbook, or workflow docs — each must become a spec before being implemented
3. Check the `Last evolve loop review:` field — if it's blank or > 30 days ago, add a note flagging that section F of the human validation runbook should be run.
4. **Auto-extract errors and insights** (Spec 157). Scan accumulated entries and the full conversation for:
   - Any error, bug, or unexpected behavior found or discussed — even if fixed inline
   - Any correction the user made to Claude's behavior, assumptions, or output
   - Any process recommendation or new constraint that emerged from discussion
   - Any decision that changes how the workflow operates going forward

   For each finding, generate a **draft EA/CI entry** with recommended classification:
   ```
   ### EA-NNN: <title> (DRAFT)
   - Found via: <source>
   - Error: <what went wrong>
   - Root cause: <why>
   - Prevention: <recommendation>
   - Spec: <NNN or "no spec needed">

   ### CI-NNN: <title> (DRAFT)
   - Source: <source>
   - Insight: <what was surfaced>
   - Action: <recommendation>
   ```

   Get the next sequential ID from `docs/sessions/error-log.md` and `docs/sessions/insights-log.md` respectively.

   Present all draft entries together for human confirmation:
   ```
   ## Draft EA/CI Entries
   <all draft entries>

   Confirm each: **yes** (append to logs) | **edit** (modify then append) | **drop** (discard)
   ```

   **Human confirmation required** for each entry before appending to the session log's Error autopsies / Chat insights sections AND to the persistent log files.
5. **Scratchpad auto-triage** (Spec 157). Read docs/sessions/scratchpad.md (if it exists). For each open (unchecked) note, present a **recommended action** based on content analysis:

   | Pattern | Recommended Action |
   |---------|-------------------|
   | Tagged `[evolve]` with clear scope | "Convert to spec" |
   | Contains `→ Converted to Spec NNN` but still unchecked | "Mark resolved" |
   | Older than 30 days with no activity | "Defer or drop" |
   | Unclear scope or ambiguous | "Discuss" |

   Present all items together with recommendations:
   ```
   ## Scratchpad Triage
   | # | Note (summary) | Age | Recommendation |
   |---|---------------|-----|---------------|
   | 1 | <note> | N days | Convert to spec |
   | 2 | <note> | N days | Mark resolved |
   | 3 | <note> | N days | Defer or drop |

   For each: **yes** (accept recommendation) | **no** (keep as-is) | **skip** (defer to next session)
   ```

   Operator confirms or overrides each recommendation. On "Convert to spec": run `/spec` workflow inline. On "Mark resolved": mark `[x]` with resolution note. On "Defer or drop": mark `[x]` with "Dropped" or leave open.
5b. **Knowledge consolidation check**: If this session touched 3+ specs or the conversation surfaced significant cross-cutting insights, note: "Consider running `/synthesize` to consolidate session knowledge into a refined reference document."
6. **Release multi-tab claims**: Read `docs/sessions/registry.md` (if it exists). If any row with Status = `active` matches this session (by date and context), update its Status to `closed`. Report: "Tab claim released: <label>." If no registry or no matching row, skip silently.
7. **Generate JSON handoff sidecar** (Spec 119): After the markdown session log is complete, generate a machine-parseable JSON sidecar file alongside it. The sidecar filename matches the session log but with a `.json` extension (e.g., `docs/sessions/2026-03-27-001.json` alongside `docs/sessions/2026-03-27-001.md`).
   - The JSON must conform to the schema at `.forge/templates/session-handoff-schema.json`.
   - Extract from the session log: `session_id` (from filename), `date`, `summary`, `decisions[]`, `specs_touched[]`, `gate_outcomes[]`, `open_items[]` (spec triggers, pain points, process improvements), `next_actions[]`, `error_autopsies[]`, `chat_insights[]`.
   - If no items exist for an array field, write an empty array `[]`.
   - Report: "JSON handoff sidecar written: `docs/sessions/YYYY-MM-DD-NNN.json`."
8. Report the session log file path and a one-line summary of any open action items.

## [mechanical] Next action
Present a context-aware next-action menu based on current state:

> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `/close NNN` | Validate and close an implemented spec (if any exist) |
> | **2** | `/implement next` | Pick up the highest-ranked spec |
> | **3** | `/now` | Review project state (for the next session) |
> | **4** | `stop` | Session complete |
>
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_

Include only the options that apply: show `/close NNN` only if implemented specs exist; show `/implement next` only if draft specs exist in the backlog.
