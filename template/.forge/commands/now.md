---
name: now
description: "Review current project state and suggest next action"
workflow_stage: session
---

# Framework: FORGE
# Model-Tier: haiku
<!-- multi-block mode: serialized — choice blocks fire at distinct mechanical steps (validation queue at Step 1, exit gate at Step 13). They do not co-present in the same agent message. See docs/process-kit/implementation-patterns.md § Multi-block disambiguation rule. -->

**Output verbosity (Spec 225)**: At the start of execution, read `forge.output.verbosity` from `AGENTS.md` (default: `lean`). In **lean** mode, suppress non-actionable diagnostic output (passing-gate confirmations, KPI tables, calibration deltas, MCP pin status, deprecation scans, signal-by-signal pattern dumps, root-cause groupings, deferred-scope aging when none aged, score-rubric details when unchanged) — write the full content to its file artifact (session log, `pattern-analysis.md`, etc.) and emit a one-line pointer in chat (or omit entirely if purely informational). In **verbose** mode, emit full detail as before. **Never suppressed in either mode**: choice blocks, FAILed gates, push-confirmation prompts, Review Brief "Needs Your Review" items, operator-input prompts, error/abort messages. See `docs/process-kit/output-verbosity-guide.md` for the full rules and worked examples.

Review the current project state and tell me what should happen next.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /now — Review project state and recommend the next action.
  Usage: /now
  No arguments accepted.
  Reads: docs/backlog.md, docs/sessions/ (latest log + JSON sidecar), CLAUDE.md, docs/specs/README.md
  Reports: validation queue, active work, next recommended spec, evolve loop status, blockers.
          Also: count of drafts past `valid-until:` (Spec 363) — silent on zero.
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

g. **Methodology resolution** (Spec 187): Read `forge.methodology` from AGENTS.md (default: `none`).
   Use the methodology value to adapt terminology in this command's output:
   - `scrum`: "Daily standup" headers, "Sprint backlog" for next spec, "Definition of Done" for validation
   - `safe`: "Iteration sync" headers, "PI backlog" for next spec, "Iteration demo" for validation
   - `kanban`: "Board review" headers, "Pull queue" for next spec, "Done column" for validation
   - `devops`: "Status check" headers, "Pipeline queue" for next spec, "Release validation" for validation
   - `safety-critical`: "Safety status review" headers, "Hazard log" for next spec, "V&V gate" for validation
   - `none` (default): "Project status" headers, standard FORGE terminology
   Store as `methodology_label` for use in output sections below.

Present a **Session Brief** section before the main output:
```
## <methodology_label.header> — "Last time on [project]"

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

## [mechanical] Step 0c — /configure first-use nudge (Spec 286)

Read `.forge/onboarding.yaml` if it exists. If the file is missing, unreadable, or unparseable: skip this step silently (do not block `/now` execution).

If the file parses and `status: complete` AND `configure_nudge_shown` is `false` or absent:
- Extract at least one defaulted setting value from the parsed yaml (prefer `project.primary_stack`; fall back to `features.devcontainer` or the literal `autonomy=L1` + `agents=Claude Code` pair if stack is null/deferred).
- Emit a single one-line nudge immediately after the Session Brief (or at the top of output if the Session Brief was skipped):
  ```
  Defaults applied: stack=<primary_stack or "deferred">, autonomy=L1, agents=Claude Code. Adjust any setting via `/configure`.
  ```
- After emitting the line, set `configure_nudge_shown: true` in `.forge/onboarding.yaml` (preserve all other keys and formatting; add the key under the `status:` line if absent). Write the file.

If `status` is not `complete` OR `configure_nudge_shown: true`: skip this step silently.

Do not add any further prompts, choice blocks, or follow-up interaction — this is a one-line advisory only. The nudge must never appear again after the first emission (dismissal persists via the flag).

If `.forge/onboarding.yaml` lacks the `configure_nudge_shown` key entirely (pre-existing projects), treat that as "not shown" — the nudge will appear once on the next `/now`, then dismiss.

## [mechanical] Step 0d — MCP integrity probe (Spec 284)

Persistent fail-closed visibility for the hash-verified MCP server lockfiles. Runs on every `/now` invocation — if any probe fails, the advisory re-appears until resolved (not one-shot).

Read `.mcp.json` (project root). If absent: skip this step silently (consumer project has no MCP config yet). If present but has no `mcpServers` entries: skip silently.

For each MCP server referenced in `.mcp.json`:

1. **context7 probe** (if `mcpServers.context7` exists):
   - Check `.mcp-lock/npm/package-lock.json` exists → if missing: emit `⚠ MCP integrity: context7 lockfile missing at .mcp-lock/npm/package-lock.json — server will fail-closed on activation. Restore via /forge stoke or remove server from .mcp.json.`
   - Check `npm` is on PATH (shell `command -v npm`) → if missing: emit `⚠ MCP integrity: npm not installed — context7 server will fail-closed. Install npm ≥ 7 or remove server from .mcp.json.`
   - If both checks pass: no line emitted (silent pass).

2. **fetch probe** (if `mcpServers.fetch` exists):
   - Check `.mcp-lock/python/requirements.lock` exists → if missing: emit `⚠ MCP integrity: fetch lockfile missing at .mcp-lock/python/requirements.lock — server will fail-closed on activation.`
   - Check `pip` (or `python -m pip`) is on PATH → if missing: emit `⚠ MCP integrity: pip not installed — fetch server will fail-closed. Install Python ≥ 3.10 with pip ≥ 22.3 or remove server.`
   - If both checks pass: no line emitted.

3. **Staleness probe** (only runs if `.mcp-lock/` is present AND `docs/process-kit/mcp-pinning-policy.md` exists):
   - Read `Last verified:` from the top of `docs/process-kit/mcp-pinning-policy.md`. Compute days since that date.
   - For `context7`: threshold = 60 days. If age > threshold: emit `MCP pin stale: @upstash/context7-mcp verified <N> days ago (threshold 60). Bump-verification checklist: docs/process-kit/mcp-pinning-policy.md.`
   - For `mcp-server-fetch`: threshold = 365 days. If age > threshold: emit similar one-line advisory.
   - If all pins fresh: silent.

4. **Generic tooling check** (even when lockfiles present and PATH-tools available): if `npm --version` reports < 7, or `pip --version` reports < 22.3, emit `⚠ MCP integrity: <tool> version <v> is below minimum — MCP server will fail-closed. Upgrade to <min>+.`

If any probe in steps 1–4 emits an advisory, include a trailing line: `Run /configure and choose MCP servers (#8) to disable servers without lockfiles, or see docs/process-kit/mcp-pinning-policy.md.`

This step is silent on clean pass. It is NOT dismissible by a flag — the advisory surfaces on every `/now` run until the underlying condition is fixed (that is the persistent fail-closed design).

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
     > | # | Rank | Action | Rationale | What happens |
     > |---|------|--------|-----------|--------------|
     > | **1** | 2 | `review NNN` | Inspect first; reduces accidental approvals | Display full validation checklist from human-validation-runbook.md |
     > | **2** | 1 | `close NNN` | Closure path; default after operator review | Run /close NNN to validate and close the spec |
     > | **3** | — | `skip` | Defer validation; pick up other work | Defer validation — continue to backlog recommendations |
     ```
     If user selects "review NNN":

     **Part 1 — Spec-specific checklist** (Spec 232): Read the spec file (`docs/specs/NNN-*.md`) and generate a targeted validation checklist:

     a. **From Acceptance Criteria**: For each AC in the spec, create a numbered validation item:
        ```
        ## Spec-Specific Validation — Spec NNN

        ### Acceptance Criteria
        1. [ ] AC1: "<AC text>" — Verify: <concrete check instruction based on the AC>
        2. [ ] AC2: "<AC text>" — Verify: <concrete check instruction>
        ...
        ```

     b. **From Test Plan**: For each test plan item, create a verification step:
        ```
        ### Test Plan Verification
        1. [ ] <test plan item> — Run/check: <how to verify>
        ...
        ```

     c. **From Implementation Summary**: List changed files for visual inspection:
        ```
        ### Changed Files (visual inspection)
        - [ ] `<file path>` — spot-check changes
        ...
        ```

     **Part 2 — Generic runbook sections**: Then read `docs/process-kit/human-validation-runbook.md`, identify applicable sections (A–G) based on the spec's changes, and display the Quick Check list for each applicable section under a `### General Checks` heading.

     **Footer**: End with: "Run `/close NNN` when validation is complete."
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
8. **Active tabs check (Spec 352)**: Glob `.forge/state/active-tab-*.json` (Spec 353 marker primitive). For each marker file, parse the JSON and read `last_command_at`. Classify:
   - **active**: `last_command_at` within 30 minutes of now.
   - **stale**: `last_command_at` older than 30 minutes.
   - **malformed/unreadable**: treat as not-active (skip the file; do not error).

   Emit a single one-line surface based on the counts:
   - If active count `N == 0`: emit nothing (suppress line — single-tab/solo sessions see zero noise, regardless of stale count).
   - If `N >= 1` and stale count `M == 0`: emit `Tabs: N active`.
   - If `N >= 1` and `M >= 1`: emit `Tabs: N active, M stale (run /tab close to clean stale)`.

   This surface is read-only — `/now` does not modify, delete, or prompt against marker files. The visibility nudge drives `/tab init` adoption without imposing per-command friction.
8b. **Runbook staleness check** (Spec 107): Read all `.md` files in `docs/process-kit/`. For each file, look for a `<!-- Last updated: YYYY-MM-DD -->` comment. If the date is more than 30 days ago (or the comment is missing), flag the runbook as potentially stale:
   ```
   ## Stale runbooks
   The following runbooks have not been updated in 30+ days:
   - docs/process-kit/<filename>.md — last updated: <date> (<N> days ago)
   ```
   If all runbooks are current, skip silently.

8d. **Aging drafts count surface (Spec 363)**: Read every `docs/specs/[0-9][0-9][0-9]-*.md` file with `Status: draft` in frontmatter. Parse the `valid-until: YYYY-MM-DD` field, if present. Count drafts whose `valid-until:` is **populated AND past today**. Drafts lacking `valid-until:` (pre-backfill state, missing field, or commented-out) are silent — not counted, not warned.
   - If count `N >= 1`: emit one line `Aging drafts: N past validity — run /matrix to triage via strategic-fit flow.`
   - If count `N == 0` (zero populated-and-expired) OR no drafts have `valid-until:` populated yet: emit nothing.
   This surface is read-only and additive. `/now` does not modify any spec frontmatter. Renewal happens via `/revise NNN` (refreshes `valid-until:`) or operator direct edit. Triage of expired drafts happens via `/matrix` Step 8 strategic-fit flow.

8c. **Process-kit external-source freshness check** (Spec 278): Read `forge.process_kit.freshness_threshold_days` from AGENTS.md (default: **180** if absent or unset). Scan `.md` files under `docs/process-kit/` AND `template/docs/process-kit/` for a `<!-- Last verified: YYYY-MM-DD against <source-url> -->` marker within the first 10 lines.
   - For each file carrying the marker: compare the date to today. If the date is older than the threshold, flag the guide as stale.
   - Files without the marker are skipped silently (not every guide needs one — the convention applies only to guides that cite external authorities; see `docs/process-kit/runbook.md` § Process-Kit Doc Freshness Convention).
   - If any flagged: report
     ```
     ## Stale process-kit guides
     The following guides cite external authorities but have not been re-verified in <threshold>+ days:
     - <path> — last verified: <date> (<N> days ago) against <source-url>
     ```
     Include a trailing hint: "Revalidate by reading `docs/process-kit/runbook.md` § Process-Kit Doc Freshness Convention."
   - If none flagged, skip silently.
   - This is advisory only — it does not block subsequent commands.

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

Then report:
- **Validation queue**: specs at `implemented` awaiting `/close` (from step 1) — this is the top priority
- **Active work**: any open spec triggers or process improvement items from the last session log that haven't been converted to specs yet
- **Agent activity** (Spec 134): If `docs/sessions/activity-log.jsonl` exists and has entries, read it and summarize events since the last operator session log. Group by agent_id. For each agent: list specs started, specs closed, gates failed, errors. If no activity log or empty, skip silently.
- **Next recommended spec**: the highest-ranked backlog item with status `draft` or `approved` that is ready to implement — state its spec ID, file path, score, and the first implementation step. Only recommend new implementation if the validation queue is empty or the user has deferred validation.
- **Evolve loop check**: state the date of the last evolve loop review (from the most recent session log's `Last evolve loop review:` field) and flag if it's overdue (> 30 days)
- **Active tabs**: any other Claude Code tabs with active claims (from step 8) — warn about potential conflicts
- **Blockers**: anything that must be resolved before the next spec can start

If no outstanding items exist and the backlog is current, recommend the single highest-value next action and explain the rationale using the scoring rubric.

## [mechanical] Step 0e — Release-eligible + deprecation surfacing (Spec 291)

Surface two release-policy signals so they cannot decay silently between tag
cuts (see `docs/process-kit/release-policy.md`).

### Release-eligible count

Read `docs/sessions/signals.md`. Count entries matching `^### SIG-[0-9]+-RE`
(emitted by `/close` Step 3d). If the file is missing, count is 0.

- If count is 0: skip silently.
- If count is ≥ 1: emit a single one-line advisory:
  ```
  N release-eligible spec(s) pending tag cut. See docs/process-kit/v1.0.0-to-next-audit.md to audit before running scripts/cut-release.sh.
  ```

### Deprecation warnings

Scan two surfaces for machine-readable deprecation markers (per
release-policy.md § Deprecation policy):

1. **Surface 1 — `copier.yml`**: parse for top-level variables carrying
   `deprecated: true`. Emit one line per match:
   ```
   ⚠ Deprecated copier variable: <name> (deprecated_in: <ver>, removed_in: <ver>) — see release-policy.md.
   ```

2. **Surface 2 — slash command files**: scan `.claude/commands/*.md` for files
   whose YAML frontmatter (between `---` markers at the top) or first 10 lines
   contain `deprecated: true`. Emit one line per match:
   ```
   ⚠ Deprecated command: /<name> (deprecated_in: <ver>, removed_in: <ver>) — see release-policy.md.
   ```

If `copier.yml` is absent (consumer projects without the template's `copier.yml`):
skip Surface 1 silently. If `.claude/commands/` is absent: skip Surface 2 silently.

These advisories are read-only and non-blocking. They surface twice — once at
`/now` (for daily visibility) and again at `/evolve` (during periodic review).



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

## [mechanical] Step 13 — Context-aware choice block (Spec 131; convention v2.0 per Spec 320)

<!-- safety-rule: session-data — if today's session log has unsynthesized spec activity AND ## Summary is unpopulated, /session is inserted at rank 1 and stop is downgraded to —. See docs/process-kit/implementation-patterns.md § Session-data safety rule. -->

At the end of every `/now` invocation, present a numbered choice block based on current context. Build the options dynamically using the v2.0 convention (Rank + Rationale columns; ≤80 char rationale; `—` for unranked):

```
> **Choose** — type a number or keyword:
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
```

Always include these options (numbered dynamically based on which apply). Default ranks (override per session-data safety rule):

1. **If implemented specs exist**: `close NNN` — rank `1`, rationale "Closure first; clears the validation queue" — Run `/close NNN` to validate and close
2. **If draft/approved specs exist in backlog**: `implement` — rank `1` if no validation queue else `2`, rationale "Top-of-backlog ready; clean transition" — Run `/implement next` for the top-ranked spec. Read the top-ranked spec file (`docs/specs/NNN-*.md`) and append its objective as a sub-line: "_<first sentence from the spec's ## Objective section>_"
3. **If session log is stale** (from Step 11): `session` — rank `1` if safety rule fires (see above) else `2`, rationale "Synthesize before next work" — Run `/session` to update the session log
4. **If evolve loop is overdue** (from Step 12): `evolve` — rank `2`, rationale "Process review; cumulative signal threshold crossed" — Run `/evolve` for process review
5. **If backlog is empty or has no draft specs**: `brainstorm` — rank `2`, rationale "Discover next work when backlog is dry" — Run `/brainstorm` to discover new spec opportunities
6. **If evolve loop is overdue OR knowledge consolidation may help** (Spec 328): `synthesize --postmortem` — rank `—`, rationale "Consolidate accumulated knowledge into a refined reference doc" — Run `/synthesize --postmortem` (default mode hint; operator can pick `--decisions`, `--topic <theme>`, `--architecture`, or `--all` instead)
7. **Always**: `stop` — rank `—` (always unranked; session-data safety rule may further downgrade), rationale "No action needed right now" — End the /now invocation

**Session-data safety rule (Spec 320 Req 4)**: Before emitting the choice block, evaluate today's session log per the positive "populated Summary" definition (heading present + ≥1 non-placeholder body line). If the rule fires (unsynthesized spec activity AND Summary unpopulated): **insert `session` at rank 1**, downgrade `stop` to `—`. The dynamic options above are the *normal* presentation; when the rule fires, prepend a `session` row at rank 1.

Present only the options that apply to the current context. Number them sequentially starting from 1. Each option carries an explicit Rank cell (`1`, `2`, …, or `—`) and a Rationale cell ≤80 chars (use `—` if it would echo the Action label).

After the choice block, include the footer:
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_


## [mechanical] Tab-lane awareness directive (Spec 351)

Before emitting any next-action choice block in this command, consult the active-tab marker (Spec 353 primitive):

1. Read `.forge/state/active-tab-*.json` (primary). If present, extract `lane`. If `last_command_at` > 30 minutes ago, treat marker as **stale**.
2. If no marker, fall back to `docs/sessions/registry.md` rows with `Status = active` for the current session. Use the row's `Lane` column.
3. If neither yields an active lane: emit the choice block as today. No preamble, no filtering, no annotation. **Skip the rest of this directive.**
4. If an active lane is detected: emit the one-line preamble (`Tab lane: <lane>. Options below filtered to lane scope.` / `... Cross-lane options annotated.` / `... (stale ~Nm)...`) and apply the filter/annotate decision rules from `docs/process-kit/tab-lane-awareness-guide.md` § Per-lane decision rules.
5. Filtered rows are struck through with rank `—` (not silently dropped) so the operator can override by typing the keyword directly.

The guide is the single source of truth for which rows filter vs annotate per lane. This directive is intentionally short — the central guide encodes the rules so every emitter stays consistent.

