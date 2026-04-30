---
name: session
description: "Create or update the session log"
workflow_stage: session
---
# Framework: FORGE
# Model-Tier: haiku

**Output verbosity (Spec 225)**: At the start of execution, read `forge.output.verbosity` from `AGENTS.md` (default: `lean`). In **lean** mode, suppress non-actionable diagnostic output (passing-gate confirmations, KPI tables, calibration deltas, MCP pin status, deprecation scans, signal-by-signal pattern dumps, root-cause groupings, deferred-scope aging when none aged, score-rubric details when unchanged) — write the full content to its file artifact (session log, `pattern-analysis.md`, etc.) and emit a one-line pointer in chat (or omit entirely if purely informational). In **verbose** mode, emit full detail as before. **Never suppressed in either mode**: choice blocks, FAILed gates, push-confirmation prompts, Review Brief "Needs Your Review" items, operator-input prompts, error/abort messages. See `docs/process-kit/output-verbosity-guide.md` for the full rules and worked examples.

Create or update the session log for this session.

> Timing guidance: see [session-synthesize-evolve-guide](../../docs/process-kit/session-synthesize-evolve-guide.md) for the canonical comparison of `/session` vs `/synthesize` vs `/evolve` — triggers, cadence, automation class.

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

### [mechanical] Step 0 — Necessity Preview (Spec 355)

Before doing any mutating work, decide whether running `/session` will produce value. Reduces wasted operator effort on no-op runs (experienced operators run `/session` defensively even when nothing has changed; this step gives them an explicit go/skip decision).

**`--force` override**: If the invocation arguments contain `--force`, skip this step entirely and proceed directly to Step 1. The operator's `--force` is absolute.

Otherwise, perform two quick counts (no file writes, no synthesis):

1. **Entries count**: open today's session log (`docs/sessions/YYYY-MM-DD-NNN.md`). Find the timestamp of the most recent `## Summary` update — typically the last "Last updated" or the last full re-synthesis marker, falling back to file mtime if no marker is present. Count structured entries (sections appended by `/implement`, `/close`, `/note`, etc. — `###`-level headings or structured entry markers like `### Spec NNN — started`, `### Spec NNN — closed`) added AFTER that timestamp.

2. **EA/CI candidate count**: do a *quick* scan of recent conversation for unrecorded Errors/Anomalies (EA) or Corrections/Insights (CI) — this is heuristic, not a full mining pass. Look for:
   - Operator corrections (e.g., "no, that's wrong", "actually, do X instead")
   - Implementation friction (e.g., "this approach didn't work", "had to revert")
   - Surprising outcomes (e.g., "didn't expect that", "that's interesting")
   - Architectural insights (e.g., "this means we should…", "pattern: …")
   Count distinct candidates. Do NOT classify or draft full SIG entries — that happens in Step 6 if we proceed.

**Output**:

- **Skip path** — if both counts are zero AND `--force` is not present:
  ```
  Nothing new since <HH:MM> — skipping. Run /session --force to override.
  ```
  Stop. Exit without writing files. Do not proceed to Step 1.

- **Proceed path** — if entries count > 0 OR EA/CI candidates exist (OR `--force` is present, but in that case Step 0 was already bypassed above):
  ```
  N entries, M EA candidates, K open [evolve] items — proceeding with draft.
  ```
  (K is the open `[evolve]` scratchpad count — read from `docs/sessions/scratchpad.md` if present; 0 if absent.)
  Continue to Step 1.

**Constraints**:
- MUST NOT cache the necessity result across invocations (recompute every time — ensures freshness).
- MUST NOT extend this skip path to `/now` Step 11 staleness prompts (different semantics, orthogonal concern).
- MUST NOT modify any files during Step 0 (read-only check).

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
4. **Auto-extract errors and insights** (Spec 157, extended by Spec 267). Scan accumulated entries and the full conversation for:
   - Any error, bug, or unexpected behavior found or discussed — even if fixed inline
   - Any correction the user made to Claude's behavior, assumptions, or output
   - Any process recommendation or new constraint that emerged from discussion
   - Any decision that changes how the workflow operates going forward

   For each finding, **infer the three Spec 267 classification fields from the conversation** before drafting the entry:
   - **Root-cause category**: pick one of `spec-expectation-gap`, `model-knowledge-gap`, `implementation-error`, `process-defect`, `other`. Use `other` when categorization is genuinely unclear — do not guess. See `docs/process-kit/signal-quality-guide.md` for the taxonomy and worked examples.
   - **Wrong assumption** (optional): the specific belief held before the bug surfaced, now known to be false. Empty string if the error wasn't an assumption failure.
   - **Evidence-gate coverage**: pick one of `caught-by-existing-gate`, `missed-by-existing-gate`, `no-applicable-gate`. If `missed-by-existing-gate`, name the gate that should have caught it.

   Then generate a **draft EA/CI entry** with recommended classification and the three new fields:
   ```
   ### EA-NNN: <title> (DRAFT)
   - Found via: <source>
   - Error: <what went wrong>
   - Root cause: <why>
   - Root-cause category: <spec-expectation-gap|model-knowledge-gap|implementation-error|process-defect|other>
   - Wrong assumption: <the specific false belief, or empty>
   - Evidence-gate coverage: <caught-by-existing-gate|missed-by-existing-gate|no-applicable-gate> [— gate name if missed]
   - Prevention: <recommendation>
   - Spec: <NNN or "no spec needed">

   ### CI-NNN: <title> (DRAFT)
   - Source: <source>
   - Insight: <what was surfaced>
   - Root-cause category: <spec-expectation-gap|model-knowledge-gap|implementation-error|process-defect|other>
   - Wrong assumption: <the specific false belief, or empty>
   - Evidence-gate coverage: <caught-by-existing-gate|missed-by-existing-gate|no-applicable-gate> [— gate name if missed]
   - Action: <recommendation>
   ```

   Get the next sequential ID from `docs/sessions/error-log.md` and `docs/sessions/insights-log.md` respectively.

   Present all draft entries together — including the three classification fields — for human confirmation:
   ```
   ## Draft EA/CI Entries
   <all draft entries — show Root-cause category, Wrong assumption, and Evidence-gate coverage alongside the existing fields>

   Confirm each: **yes** (append to logs) | **edit** (modify then append) | **drop** (discard)
   ```

   **Human confirmation required** for each entry before appending to the session log's Error autopsies / Chat insights sections AND to the persistent log files. Absence/empty values for the three new fields are acceptable (treated as `other` / empty / `no-applicable-gate` downstream) — the goal is to prompt the agent's best inference, not block drafting.
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
5b. **Knowledge consolidation check**: If this session touched 3+ specs or the conversation surfaced significant cross-cutting insights, note: "Consider running `/synthesize <mode>` to consolidate session knowledge into a refined reference document." Mode hint (Spec 328): if a single dominant theme emerges (one spec/concept mentioned 3+× more than others), suggest `/synthesize --topic <theme>`; otherwise default to `/synthesize --postmortem` for general consolidation. Operator can override at invocation.
6. **Multi-tab claim status (Spec 353)**: Read `docs/sessions/registry.md` (if it exists). If any row with Status = `active` matches this session (by `.forge/state/active-tab-*.json` marker's `registry_row_pointer`, or by date and context if no marker exists), surface it as **informational output only**: "You are in tab '<label>' (lane: <lane>, started: <time>)." Do **NOT** mutate the registry — tab close is now an explicit action via `/tab close`. Operators frequently run `/session` mid-flow (mid-chat checkpoints, post-/close updates), and auto-releasing the claim would silently drop their tab claim out from under them. If no registry or no matching row, skip silently. *(Behavior change from pre-Spec-353: `/session` no longer auto-closes the registry row — see CHANGELOG.)*
7. **Generate JSON handoff sidecar** (Spec 119): After the markdown session log is complete, generate a machine-parseable JSON sidecar file alongside it. The sidecar filename matches the session log but with a `.json` extension (e.g., `docs/sessions/2026-03-27-001.json` alongside `docs/sessions/2026-03-27-001.md`).
   - The JSON must conform to the schema at `.forge/templates/session-handoff-schema.json`.
   - Extract from the session log: `session_id` (from filename), `date`, `summary`, `decisions[]`, `specs_touched[]`, `gate_outcomes[]`, `open_items[]` (spec triggers, pain points, process improvements), `next_actions[]`, `error_autopsies[]`, `chat_insights[]`.
   - If no items exist for an array field, write an empty array `[]`.
   - Report: "JSON handoff sidecar written: `docs/sessions/YYYY-MM-DD-NNN.json`."
8. Report the session log file path and a one-line summary of any open action items.

## [mechanical] Next action
Present a context-aware next-action menu based on current state:

<!-- safety-rule: session-data — /session is itself the synthesis path; this exit block fires AFTER Summary is populated, so the rule typically does not fire here. Keep stop ranked normally. See docs/process-kit/implementation-patterns.md § Session-data safety rule. -->

> **Choose** — type a number or keyword:
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **1** | 1 | `/close NNN` | Drain validation queue if implemented specs exist | Validate and close an implemented spec (if any exist) |
> | **2** | 2 | `/implement next` | Resume solve loop with top-of-backlog | Pick up the highest-ranked spec |
> | **3** | — | `/now` | Stage for next session if stopping here | Review project state (for the next session) |
> | **4** | — | `stop` | Session complete; Summary is now populated | Session complete |
>
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_

Include only the options that apply: show `/close NNN` only if implemented specs exist; show `/implement next` only if draft specs exist in the backlog.
