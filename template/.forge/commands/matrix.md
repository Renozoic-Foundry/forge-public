---
name: matrix
description: "Update and present the prioritization matrix"
model_tier: haiku
workflow_stage: planning
---

# Framework: FORGE
Update and present the prioritization matrix.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /matrix — Update and present the full prioritization matrix.
  Usage: /matrix
  No arguments accepted.
  Behavior: Reads backlog and rubric, verifies score arithmetic, detects manual
    overrides vs errors, syncs spec frontmatter, detects status discrepancies,
    re-scores promoted specs, evaluates strategic fit (Spec 110), checks review
    velocity for cognitive debt (Spec 128), recommends sprint bundles, presents
    ranked tables, writes corrections on confirmation.
  See: docs/backlog.md, docs/process-kit/scoring-rubric.md
  ```
  Stop — do not execute any further steps.

---

1. Read docs/backlog.md.
2. Read docs/process-kit/scoring-rubric.md.
3a. **Input range validation (Spec 148)**: Before computing scores, validate that each BV, E, R, SR value in every backlog row is an integer between 1 and 5 inclusive. If any value is outside this range, flag it as an input error: "[dimension] must be 1-5 (got [value]) in Spec NNN". Report all input errors before proceeding to arithmetic checks. Do not compute scores for rows with invalid inputs.
3. **Score integrity check**: For every row in the backlog, recompute the total from BV/E/R/SR using the formula in `docs/process-kit/scoring-rubric.md`. Report any mismatches:
   - If the BV/E/R/SR values match between spec frontmatter and backlog but the total is wrong → **arithmetic error**: auto-correct the total immediately (no human confirmation needed). Report what was corrected: "Auto-corrected Spec NNN: listed=X, computed=Y (BV=a E=b R=c SR=d)."
   - If the BV/E/R/SR values differ between spec frontmatter and backlog → **manual override detected** (flag for human review — may indicate a formula revision need). Do NOT auto-correct these.
4. **Frontmatter sync**: For each draft/approved spec in the backlog, read the spec file's `Priority-Score:` frontmatter and compare BV/E/R/SR values against the backlog row. Report discrepancies as a separate section before rankings.
5. **Status sync check (Spec 028 — authoritative source enforcement)**: The spec file `Status:` field is the single authoritative source of truth for spec status. For each spec in docs/specs/README.md:
   a. Read the spec file's `Status:` frontmatter field.
   b. Compare to README.md index row status.
   c. Compare to backlog table status.
   d. If discrepancy found: report as:
      ```
      STATUS DRIFT — Spec NNN:
        Spec file (authoritative): implemented
        README.md: draft          ← needs update
        backlog.md: in-progress   ← needs update
      ```
   e. On confirmation (step 9), auto-correct README.md and backlog.md to match spec file.
   - Do NOT auto-correct spec file — it is authoritative. If spec file and README/backlog disagree, spec file wins.
   - If drift is found: flag as a process defect: "STATUS DRIFT detected — derived views are out of sync with spec files."
6. Re-score any spec whose status changed to `draft` (SR likely increased — recalculate and note the delta).
7. **Dependency analysis** (Spec 087): For each non-closed spec, read its `Dependencies:` frontmatter field (comma-separated spec IDs) or the `Depends` column in the backlog table. Classify each spec:
   - **Blocked**: has a dependency on a spec that is NOT `closed`. List which dependency is unmet.
   - **Ready**: all dependencies are `closed` (or no dependencies). Can be implemented now.
   - **Parallel-safe batch**: ready specs whose `Implementation Summary → Changed files` lists have no overlapping paths. These can be implemented simultaneously in parallel worktrees.

   Present a dependency summary before the ranked tables:
   ```
   ## Dependency status
   Blocked: Spec NNN (waiting on NNN), ...
   Ready: Spec NNN, NNN, NNN
   Parallel batch: Specs NNN + NNN (no shared files)
   ```
   If no specs have dependencies defined, skip this section silently.

8. **Strategic fit evaluation** (Spec 110):
   a. Read the project's CLAUDE.md — extract the project description and mission statement (the first paragraph or "## What this project is" section).
   b. Read AGENTS.md — check for `forge.strategic_scope` config under `## Project Context`. If present, use it as the strategic scope definition. If absent, infer scope from CLAUDE.md's project description.
   c. **The strategic fit test**: For each draft spec, ask: "Does this spec's objective directly improve the project's core workflow loop as described in CLAUDE.md / `forge.strategic_scope`?" If the spec builds runtime infrastructure, a separate product, or features that belong in another tool <!-- module:nanoclaw -->(e.g., NanoClaw, an MCP server, an IDE extension)<!-- /module:nanoclaw -->, it fails the test.
   d. Classify each draft spec:
      - `on-mission` — directly improves the core workflow (spec lifecycle, gates, evidence, process enforcement)
      - `borderline` — useful but expands scope beyond the core loop (may be worth keeping with scope adjustment)
      - `scope-creep` — building a different product or feature that belongs elsewhere
   e. Present a Strategic Fit table:
      ```
      ## Strategic Fit Review
      | Spec | Title | Classification | Rationale |
      |------|-------|----------------|-----------|
      | NNN  | ...   | on-mission     | Improves gate integrity via ... |
<!-- module:nanoclaw -->
      | NNN  | ...   | scope-creep    | Builds runtime scheduler — belongs in NanoClaw |
<!-- /module:nanoclaw -->
      ```
   f. For each `scope-creep` spec, recommend a disposition:
      - `deprecate` — not worth doing in any project (rare)
<!-- module:nanoclaw -->
      - `defer-to-<project>` — belongs in a specific other project (e.g., `defer-to-nanoclaw`, `defer-to-mcp-server`)
<!-- /module:nanoclaw -->
      - `reclassify` — scope can be narrowed to fit (explain how)
   g. **Human confirmation gate**: Present dispositions and ask for confirmation before applying. The operator can:
      - Confirm all dispositions
      - Override individual classifications (e.g., "keep 094 as draft — I want it here")
      - Skip the strategic fit review entirely ("skip fit")
   h. On confirmation: update each scope-creep spec's status to `deprecated (scope-creep → <disposition>)` in the spec file, README.md, and backlog.md. Add a revision log entry: `YYYY-MM-DD: Deprecated via /matrix strategic fit review — <rationale>.`

   If `forge.strategic_scope` is absent from AGENTS.md and CLAUDE.md has no clear mission statement, skip this step with a note: "Strategic fit review skipped — no `forge.strategic_scope` config or CLAUDE.md mission statement found. Add `forge.strategic_scope` to AGENTS.md to enable."

9. **Review Velocity Check** (Spec 128 — cognitive debt guardrail, recalibrated by Spec 158):
   a. Read AGENTS.md — extract `forge.review_velocity.threshold` (default: 0.6) and `forge.review_velocity.window` (default: 5).
   b. Identify specs closed in the last N sessions (where N = `window`). Read each session log in `docs/sessions/` sorted by date descending, collecting spec IDs mentioned as closed.
   c. For each closed spec, read its `## Evidence` section. A spec has "human review evidence" if its Evidence section contains non-placeholder content (not just `(pending implementation)` or empty bullets).
   d. Compute: `debt_ratio = specs_without_evidence / total_closed_specs`.
   e. If `debt_ratio > threshold`, emit a warning section:
      ```
      ## Review Velocity — COGNITIVE DEBT WARNING

      N of M recently closed specs lack human review evidence.
      Specs without evidence: NNN, NNN, NNN
      Threshold: X% (configured in AGENTS.md forge.review_velocity.threshold)

      Evidence presence is what matters — closure speed is not a concern.
      Closing 5+ specs in one session is normal for AI-assisted work.
      ```
   f. If `debt_ratio <= threshold` or no specs were closed in the window, emit:
      ```
      ## Review Velocity
      Review velocity OK — N of M recently closed specs have human review evidence.
      ```
   g. **Token cost overrun check** (Spec 158): For each closed spec with a `Token-Cost:` estimate in frontmatter, check if actual token cost data exists in `.forge/metrics/command-costs.yaml`. If actual significantly exceeds estimate (e.g., `$` estimate but actual tokens > $$ threshold), flag: "Spec NNN: TC estimate was $ but actual cost was $$$ — consider whether ACs were insufficiently precise (SR too low) or scope was underestimated."
   h. This check is **advisory only** — it MUST NOT block any `/close` or `/implement` operations.

10. Present the full ranked backlog in two tables (process improvement + application/infrastructure), sorted by score descending within each table. Include a `Depends` column showing dependency spec IDs (or "—") for non-closed specs. Include a `TC` column showing the Token-Cost indicator (`$`, `$$`, `$$$`, or `?` if not set) for non-closed specs. Exclude deprecated specs from the ranked tables (show them in a separate "Deprecated" section below).

11. **Sprint lane planning** (Spec 156, replaces effort-tier bundles):
   From on-mission, **ready** (not blocked) draft specs, construct a dependency-chain sprint plan:

   a. **Identify dependency chains**: Trace all dependency sequences in the backlog (Spec A → B → C where each depends on the previous). Use the `Depends` column from Step 7 and spec frontmatter `Depends:` fields.

   b. **Identify the critical path**: Find the longest dependency chain by cumulative E score. Label it explicitly in the output.

   c. **Group into thematic lanes**: Group remaining ready specs (not on the critical path) into thematic bundles based on functional area. Infer theme from spec titles, scope sections, and file overlap analysis (from `Implementation Summary → Changed files`). Name lanes descriptively (e.g., "Lane 1: Scoring & Calibration", "Lane 2: Session Automation") — not by effort tier.

   d. **Assign to sprints**: Place specs into sprints respecting dependency ordering:
      - A spec with `Depends: NNN` where NNN is in Sprint 1 must be in Sprint 2 or later.
      - Within a sprint, specs in different lanes have no dependency conflicts and no file overlap — they can execute concurrently.
      - Within a lane, specs may be sequential (dependency chain) or parallel (independent, no file overlap).

   e. **File-scope isolation check**: For specs assigned to the same sprint in different lanes, read each spec's `Implementation Summary → Changed files` and check for overlapping paths. If overlap is detected, flag it: "File overlap between Spec NNN and NNN on <path> — cannot run in parallel. Move one to a later sprint or sequential lane."

   f. **Token cost flagging** (Spec 158): For any spec with `Token-Cost: $$$` in its frontmatter, add a note: "High token cost — consider whether a cheaper approach exists before implementing."

   g. **Output the sprint table**:
   ```
   ## Sprint Plan

   **Critical path**: Spec NNN → NNN → NNN (cumulative E=N)

   | Sprint | Lane | Specs | TC | Notes |
   |--------|------|-------|----|-------|
   | 1 | Lane 1: <theme> | NNN | $ | Critical path start |
   | 1 | Lane 2: <theme> | NNN, NNN | $$, $ | `/parallel NNN NNN` |
   | 2 | Lane 1: <theme> | NNN | $$ | Needs NNN from Sprint 1 |
   | 2 | Lane 2: <theme> | NNN | $$$ | High token cost |

   ### Deferred
   | Spec | Title | Blocked by | Reason |
   |------|-------|-----------|--------|
   | NNN | ... | NNN | Dependency not yet closed |

   ### Future
   | Spec | Title | Score | Reason |
   |------|-------|-------|--------|
   | NNN | ... | NN | Low priority, no clear sprint assignment |
   ```

   h. For lanes containing 2+ independent specs (no dependencies between them, no file overlap), suggest a `/parallel` command: "`/parallel NNN NNN`".

   i. The operator can select a sprint to begin. Report: "Selected Sprint N. Starting with Spec NNN — run `/implement NNN` or `/parallel NNN NNN` for parallel lanes."

### Step 11b — Review Router (Spec 159)

After generating the sprint plan (Step 11) but before presenting highlights (Step 12), run the review router on the sprint plan:

a. Select perspectives: **COO** (always — process efficiency of sprint sequencing) + **CTO** (always — architectural coherence of lane groupings). Add **CFO** if any $$$ specs are in the plan.
b. Display selection rationale.
c. Run selected perspectives on the sprint plan as a whole — focus on lane assignments, sequencing decisions, and parallel groupings.
d. Present the Review Brief after the sprint table.
e. BLOCK is advisory — the operator decides whether to adjust the plan.

12. Highlight:
   - The top-ranked spec not yet `approved` (recommend it as next to approve)
   - Any spec that moved rank since the last update
   - Any `proposed` spec that is now blocked or unblocked by a recently completed spec
   - **Blocked specs** that cannot be implemented until their dependencies close
13. Ask for confirmation, then:
   - Write status corrections and manual-override resolutions to docs/backlog.md (arithmetic score errors were already auto-corrected in step 3 — manual overrides require human decision here)
   - Write strategic fit dispositions (if confirmed in step 8g)
   - Update the `Last updated:` field to today's date

## [mechanical] Next action
After corrections are written, present a context-aware next action:
- If rank order changed: "Next: review the new top-ranked spec — run `/implement next` to pick it up."
- If status discrepancies were found: "Next: resolve the status discrepancies above, then run `/implement next`."
- If a sprint was selected: "Next: implement Sprint N — run `/implement NNN` to start, or `/parallel NNN NNN` for parallel lanes."
- If no changes needed: "Backlog is current. Next: run `/implement next` to continue building."
