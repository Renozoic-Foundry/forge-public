---
name: synthesize
description: "Synthesize accumulated project artifacts into refined documents"
model_tier: sonnet
workflow_stage: session
---
# Framework: FORGE
# Model-Tier: sonnet
Synthesize accumulated FORGE artifacts into a refined, actionable document.

If $ARGUMENTS is `?` or `help`:
  Print a usage block with the following information then stop — do not execute any further steps:
  - Command: /synthesize — Knowledge synthesis command (FORGE Spec 106).
  - Usage: /synthesize <mode> [options]
  - Modes (exactly one required):
    - --postmortem: Generate incident/sprint postmortem from recent session logs
    - --topic <query>: Summarize all artifacts related to a topic
    - --decisions [--since YYYY-MM-DD]: Compile decision log from session logs
    - --architecture: Draft architecture overview from ADRs, specs, and agent config
  - Options:
    - --sessions N: Number of recent sessions to include (postmortem only, default 5)
    - --since YYYY-MM-DD: Limit to artifacts on or after this date (decisions mode)
  - Output: docs/synthesis/YYYY-MM-DD-<mode>.md
  - Each output includes a Sources section listing every artifact that contributed.
  - Reference: docs/specs/106-knowledge-synthesis-command.md

---

Parse $ARGUMENTS:
- Detect the mode flag: `--postmortem`, `--topic`, `--decisions`, `--architecture`.
- If no mode flag is present, print the help text above and stop.
- If `--postmortem`: set `MODE=postmortem`. Parse optional `--sessions N` (default 5).
- If `--topic`: set `MODE=topic`. The next argument is `QUERY` (required — if missing, print help and stop).
- If `--decisions`: set `MODE=decisions`. Parse optional `--since YYYY-MM-DD`.
- If `--architecture`: set `MODE=architecture`.

Set `TODAY` = current date in YYYY-MM-DD format.
Set `OUTPUT_DIR` = `docs/synthesis`.
Set `OUTPUT_FILE` = `docs/synthesis/{TODAY}-{MODE}.md` (for topic mode: `docs/synthesis/{TODAY}-topic-{QUERY}.md` with spaces replaced by hyphens).

---

## [mechanical] Step 1 — Ensure output directory

If `docs/synthesis/` does not exist, create it.

---

## Mode A — Postmortem (`--postmortem`)

### [mechanical] Step A1 — Gather session logs

Read all `.md` files in `docs/sessions/` excluding `_template.md`, `signals.md`, `error-log.md`, `insights-log.md`, `scratchpad.md`, `context-snapshot.md`, and `registry.md`.

Sort by filename date prefix (newest first). Take the most recent N files (where N = `--sessions` value, default 5).

From each session log, extract:
- **Session ID**: from the filename
- **Summary**: the objective or summary section
- **Pain points / blockers**: lines under "Pain points", "Blockers", or "Process improvement items"
- **Decisions made**: items in any "Decisions" section
- **Error autopsies referenced**: any EA-NNN references
- **Specs worked on**: any spec IDs mentioned

Track each file path in `SOURCES` list.

### [mechanical] Step A2 — Read error-log.md

Read `docs/sessions/error-log.md`. Extract EA-NNN entries referenced in the gathered session logs.
If file does not exist: skip silently.
Add to `SOURCES` if read.

### [mechanical] Step A3 — Read signals.md

Read `docs/sessions/signals.md`. Extract SIG-NNN entries from the date range covered by the gathered sessions.
If file does not exist: skip silently.
Add to `SOURCES` if read.

### [decision] Step A4 — Generate postmortem

Write a structured postmortem document to `OUTPUT_FILE` with these sections:

1. **Title**: "Postmortem — {TODAY}" with a generated-by note showing N sessions analyzed
2. **Period Covered**: date of oldest session to date of newest session
3. **Executive Summary**: 2-3 sentence summary of key accomplishments, recurring problems, and overall trajectory
4. **Key Accomplishments**: bulleted list of specs completed, features delivered, process improvements made
5. **Recurring Problems**: bulleted list of pain points or blockers appearing in 2+ sessions, with session references
6. **Error Patterns**: summary of error autopsies grouped by root cause; if none, state "No error autopsies recorded in this period."
7. **Decisions Made**: chronological list with date and context for each
8. **Signals & Observations**: notable signals grouped by type
9. **Recommendations**: 3-5 actionable recommendations based on patterns observed
10. **Sources**: bulleted list of every file path that contributed

---

## Mode B — Topic Summary (`--topic <query>`)

### [mechanical] Step B1 — Search artifacts

Search the following directories for files containing `QUERY` (case-insensitive):
- `docs/specs/` — spec files
- `docs/sessions/` — session logs
- `docs/decisions/` — ADR files
- `docs/sessions/signals.md` — signal entries
- `docs/sessions/error-log.md` — error autopsies
- `docs/sessions/insights-log.md` — chat insights
- `docs/sessions/scratchpad.md` — open notes
- `AGENTS.md` — agent configuration

For each match, record the file path and the matching section/context (the paragraph or list item containing the match, plus surrounding context).

Track each file path in `SOURCES` list.

If no matches found: write a brief note to `OUTPUT_FILE` stating "No artifacts found matching the query." and stop.

### [decision] Step B2 — Generate topic summary

Read the matching sections from each file (read the relevant portions, not entire files when they are large).

Write a structured topic summary document to `OUTPUT_FILE` with these sections:

1. **Title**: "Topic Summary: {QUERY}" with a generated-by note and list of artifact types searched
2. **Overview**: 2-3 sentence synthesis of what the project artifacts say about this topic
3. **Spec Coverage**: list of specs referencing this topic, with status and one-line relevance summary
4. **Decisions & Rationale**: decisions from session logs and ADRs in chronological order
5. **Signals & Observations**: relevant signals, error autopsies, and insights
6. **Open Items**: scratchpad notes, unresolved questions, or draft specs related to this topic
7. **Synthesis**: coherent narrative connecting findings — what has been decided, what remains open, trajectory
8. **Sources**: bulleted list of every file path that contributed

---

## Mode C — Decision Log (`--decisions`)

### [mechanical] Step C1 — Gather session logs

Read all `.md` files in `docs/sessions/` excluding `_template.md`, `signals.md`, `error-log.md`, `insights-log.md`, `scratchpad.md`, `context-snapshot.md`, and `registry.md`.

If `--since YYYY-MM-DD` is set: only include files whose date prefix >= that date.

Sort by filename date prefix (oldest first — chronological order).

From each session log, extract content under "Decisions made" or "Decisions" sections.

Track each file path in `SOURCES` list.

### [mechanical] Step C2 — Read ADRs

Read all `.md` files in `docs/decisions/` (if the directory exists).
Extract the decision title, status, date, and context from each ADR.
If directory does not exist or is empty: skip silently.
Add each file to `SOURCES` if read.

### [decision] Step C3 — Generate decision log

Write a structured decision log document to `OUTPUT_FILE` with these sections:

1. **Title**: "Decision Log" with a generated-by note and period covered
2. **Summary**: count of decisions extracted from N session logs and M ADRs
3. **Chronological Decision Log**: for each session date, list each decision with its text, surrounding context, and spec ID if referenced
4. **ADR Decisions**: list each ADR with title, status, date, and one-line summary; if none, state "No ADRs found."
5. **Decision Themes**: group decisions by theme/area (e.g., Architecture, Process, Tooling) and summarize trajectory
6. **Sources**: bulleted list of every file path that contributed

---

## Mode D — Architecture Overview (`--architecture`)

### [mechanical] Step D1 — Read ADRs

Read all `.md` files in `docs/decisions/` (if the directory exists).
If directory does not exist or is empty: note "No ADRs found" and continue.
Add each file to `SOURCES` if read.

### [mechanical] Step D2 — Read closed specs

Read `docs/specs/README.md` to identify closed specs.
For each closed spec, read its "Implementation Summary" section (the `## Implementation Summary` block).
If no closed specs exist: note "No closed specs found" and continue.
Add each file to `SOURCES` if read.

### [mechanical] Step D3 — Read agent config

Read `AGENTS.md` if it exists. Extract the architecture-relevant sections (capabilities, tools, coordination patterns).
If file does not exist: skip silently.
Add to `SOURCES` if read.

### [mechanical] Step D4 — Read CLAUDE.md

Read `CLAUDE.md`. Extract the "Architecture quick-ref" section and any structural information.
Add to `SOURCES`.

### [decision] Step D5 — Generate architecture overview

Write a structured architecture overview document to `OUTPUT_FILE` with these sections:

1. **Title**: "Architecture Overview" with a generated-by note and a disclaimer to verify against source artifacts
2. **System Overview**: high-level description based on CLAUDE.md, AGENTS.md, and closed specs
3. **Key Components**: list of major components/modules with one-line descriptions
4. **Architectural Decisions**: summary of ADRs and rationale; if none, state "No ADRs recorded. Architectural decisions are embedded in spec files and session logs."
5. **Evolution History**: how architecture evolved based on closed specs, chronologically ordered
6. **Current State**: what the architecture looks like now based on most recent closed specs and AGENTS.md
7. **Known Gaps & Open Questions**: gaps from draft/in-progress specs, scratchpad notes, or missing ADRs
8. **Sources**: bulleted list of every file path that contributed

---

## [mechanical] Step 2 — Confirm output

After writing the output file, print:

    Synthesis complete: {OUTPUT_FILE}
    Mode: {MODE}
    Sources: {count} artifacts consulted

## [mechanical] Step 3 — Next action

Present a context-aware next action:
- If postmortem: "Next: review the postmortem and share with your team. Run `/note` to capture any follow-up items."
- If topic: "Next: review the topic summary. Run `/spec` if any open items need formal tracking."
- If decisions: "Next: review the decision log for consistency. Run `/evolve` if decision patterns suggest process improvements."
- If architecture: "Next: review the architecture overview for accuracy. Run `/note` to flag any corrections needed."
