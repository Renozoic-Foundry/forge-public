---
name: forge-init
description: "Bootstrap FORGE into a new or existing project, upgrade legacy pre-Copier projects, or create new projects from scratch"
workflow_stage: lifecycle
argument-hint: "[path] [--layout contained|classic]"
---

<!-- forge:paths-note (Spec 575): process-state paths in this command (docs/specs,
     docs/sessions, docs/decisions, docs/research, docs/process-kit, docs/backlog.md) are the
     CLASSIC-DEFAULT spellings, not fixed locations. When the project configures forge.paths
     (e.g. the `contained` layout), resolve each key before use — bash: `forge_path <key>`
     (source ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/config.sh, forge_config_load AGENTS.md);
     python: `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py .../runtime_config.py path <key>`. -->

> **(compat: prefer /forge <sub>)** — `/forge init` is the advertised form (Spec 579 single
> advertised path); this top-level alias remains for compatibility.
# Framework: FORGE
## Subcommand: init

> Bootstrap FORGE into a new or existing project, upgrade legacy pre-Copier projects, or create new projects from scratch.
>
> Accepts an optional path argument: `/forge init [path]`
> - No path → operates on the current working directory (backward-compatible)
> - Path exists → operates on that directory
> - Path does not exist → creates the directory and enters create-new mode

### [mechanical] Step 0 — Prerequisite check (Spec 143)Before any bootstrap logic, verify that required tools are available:1. Check for **Python 3.10+ (Spec 401 raised floor from 3.9)**: run `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py --version` (or directly: `python3 --version` / `python --version` / `py -3 --version`).2. Check for **Git**: run `git --version`.3. Check for **POSIX `sh` shell on PATH** (Spec 401): run `command -v sh` (POSIX) or `where sh` (Windows). On Windows: if `sh` is absent, surface this actionable message — `Windows: 'sh' not found on PATH. FORGE requires either (a) Git for Windows installed with 'Use Git and optional Unix tools from the Command Prompt' option (option 3 of the Git for Windows installer), OR (b) FORGE workflows launched from a Git Bash terminal. Re-run the Git for Windows installer and select option 3, or open Git Bash and re-run.`If all prerequisites are met: proceed silently.If any are missing:- Report what's missing and the install command for the detected platform- Ask: "Install missing prerequisites now? (yes / no)"- If yes: run the install commands, re-verify, then proceed.- If no: stop with a message listing what to install manually.Alternatively, run `bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-install.sh --check-prereqs` which handles detection, platform awareness, and interactive installation offers.Skip this step if the user passed `--skip-prereqs`.
### [mechanical] Step 0a — Resolve target path

1. Parse the remainder of `$ARGUMENTS` after `light` to extract the optional path.
   - If a path is provided: set `TARGET` to that path (resolve relative paths against CWD).
   - If no path is provided: set `TARGET` to the current working directory.

2. (The pre-4.0 TEMPLATE_SRC resolution — copier.yml clone detection and
   `.copier-answers.yml` `_src_path` — was retired with the Copier surface, Spec 558.
   The plugin runtime (`CLAUDE_PLUGIN_ROOT`) is the upstream source for scaffold and
   stoke alike.)

### [mechanical] Step 0b — Write-access gate (Spec 066)

3. Verify the workspace is writable before doing anything else:
   a. If `TARGET` exists, attempt to create a sentinel file: `<TARGET>/.forge/.write-check`
   b. If `TARGET` does not exist, verify the parent directory is writable.
   c. If creation succeeds: delete it immediately. Continue silently.
   d. If creation fails (permission denied / read-only filesystem):
      ```
      GATE [write-access]: FAIL
      The workspace at <TARGET> is read-only — FORGE cannot write files.

      Fix options:
        1. devcontainer  — add a read-write volume mount (see .devcontainer/README.md)
        2. local clone   — run /forge init from your local project clone instead
        3. delegated     — see .forge/templates/delegated-write-protocol.md to have
                           another agent apply changes on this project's behalf

      /forge init aborted.
      ```
      Stop. Do not proceed.

### [mechanical] Step 0c — Four-mode detection (Spec 072)

4. Evaluate the following checks **in order** to determine the mode:

   | Check | Mode | Description |
   |-------|------|-------------|
   | `TARGET` path does not exist | **create-new** | Fresh project creation |
   | `TARGET` has `.copier-answers.yml` | **stoke-redirect** | Classic (Copier-scaffolded) project — redirect to `/forge stoke` (v4.0.0+: its classic detection prints the `--to-plugin` converter pointer) |
   | `TARGET` has `AGENTS.md` OR `docs/specs/` OR `.claude/commands/` but NO `.copier-answers.yml` | **legacy-upgrade** | Pre-Copier FORGE/EGID project |

   In plain terms: **create-new** = there's nothing here yet, start fresh. **stoke-redirect** =
   this project was scaffolded by the old Copier-based installer, so hand off to `/forge stoke`
   instead of re-initializing it. **legacy-upgrade** = FORGE is already here but from before the
   plugin existed — upgrade it in place. **greenfield** (below) = an existing codebase with no
   FORGE files at all yet. ("EGID" = Evidence-Gated Iterative Delivery, FORGE's underlying
   methodology; see the glossary at `docs/team-guide.md#glossary` for this and every other
   FORGE-specific term.)

   **Legacy-upgrade / pre-plugin consumers (Spec 577)**: after the plugin-consumption upgrade,
   offer the full retrofit flow (`/forge retrofit` — de-vendor superseded framework files,
   reorganize to the contained layout, reconcile history). Never auto-run; the offer is a
   choice block.
   | `TARGET` exists but has none of the above markers | **greenfield** | Existing codebase, no FORGE yet |

5. Report the detected mode:
   ```
   Detected mode: <mode>
   Template source: <TEMPLATE_SRC>
   Target: <TARGET>
   ```

6. **Dirty working tree check (Spec 166)**: If mode is **legacy-upgrade** or **greenfield** (modes that modify an existing directory):
   - Run `git status --porcelain` in the target directory.
   - If output is non-empty: warn "**Uncommitted changes detected in target.** Recommend: commit or stash changes in `<TARGET>` before proceeding." Present options: **commit**, **proceed**, or **abort**.
   - If clean or mode is **create-new** or **stoke-redirect**: skip silently.

7. Dispatch to the appropriate flow below based on mode.

---

### Mode: create-new

> Target path does not exist. Create a brand-new FORGE-managed project from scratch.
> **The plugin-native scaffolder is the only path (Spec 557; the classic Copier render and its
> `--copier` flag were deleted in v4.0.0 — Spec 558).**

7. Create the target directory: `mkdir -p <TARGET>`

8. Initialize a git repo, and snapshot the (structurally empty) pre-scaffold state so Step 11
   can stage by exact path instead of `-A` (Spec 668, Spec 494 convention):
   ```bash
   # forge:spec-668-forge-init-baseline:start
   git init <TARGET>
   git -C <TARGET> status --porcelain --untracked-files=all > <TARGET>/.git/forge-init-baseline.txt
   # forge:spec-668-forge-init-baseline:end
   ```
   `create-new` mode is only entered when `<TARGET>` did not exist before this run (mode-dispatch
   precondition in Step 0c above), so the baseline is always empty in production — the snapshot
   is defense-in-depth, not a response to an observed defect: it keeps Step 11's commit scoped to
   exactly what this run created even if that precondition is ever relaxed or this block reused.

9. Generate the project skeleton into the target — plugin-native scaffold (Spec 557):
     ```bash
     ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/scaffold.py "<TARGET>" --name "<project name>" --description "<description>" --author "<author>" --owner "<owner>" --layout <contained|classic>
     ```
     **Layout choice (Spec 575)** — ask before scaffolding (greenfield AND brownfield):
     `contained` (DEFAULT + recommended): all FORGE process data lives under `.forge/project/`,
     cleanly segregated from the project's own `docs/` tree; writes the `forge.paths` block and
     `.forge/ownership.yaml`. `classic`: the pre-575 `docs/...` layout. For brownfield targets
     recommend `contained` (their `docs/` likely already belongs to the solution). Both layouts
     write the ownership manifest so the Spec 577 retrofit inventory works everywhere.
     ```bash
     # (choice already applied via --layout above)
     ```
     Writes the project-data skeleton (docs/specs/, docs/sessions/, docs/backlog.md, thin
     AGENTS.md/CLAUDE.md with the `forge.project:` runtime block) with NO copier invocation —
     executable surfaces come from the installed FORGE plugin. Non-security identity vars resolve
     at runtime via `${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/runtime_config.py`. The scaffolder aborts (exit 2, nothing
     written) if the target already contains `AGENTS.md`, `docs/specs/`, or `.copier-answers.yml`
     (overwrite guardrail).
   - If the operator passes `--copier`: explain it was removed in v4.0.0 (Spec 558) — the
     plugin-native scaffold is the only path; classic Copier projects stay supported on ≤v3.x.

10. Plant the onboarding seed file at `<TARGET>/.forge/onboarding.yaml`:
    ```yaml
    status: pending
    created: <today YYYY-MM-DD>
    template_version: "0.0.0"
    mode: create-new

    phases:
      identity: null
      features: null
      mcp_servers: null
      credentials: null
      summary: null

    features:
      nanoclaw: null
      compliance: null
      publications: null
      devcontainer: true

    mcp_servers: {}
    setup_tasks: []

    project:
      name: null
      description: null
      primary_stack: null  # valid values: language name, "deferred" (Spec 162), or null
      test_command: null
      lint_command: null
    ```

11. Create initial commit — by exact path, diffed against the Step 8 baseline, not `-A`. In this
    mode the result is every file this run created (the target was empty before Step 8), so the
    effect is deliberately whole-tree; the mechanism stays exact-path so the lint added by Spec 668
    (below) never has to allowlist this site:
    ```bash
    # forge:spec-668-forge-init-commit-block:start
    baseline="<TARGET>/.git/forge-init-baseline.txt"
    # Compared by PATH (not the full status line) so a pre-existing path that changes
    # status class between the baseline snapshot and this commit (e.g. untracked ->
    # modified) is still recognized as pre-existing and excluded.
    forge_init_existing_paths=()
    if [ -f "$baseline" ]; then
      while IFS= read -r line; do
        [ -n "$line" ] && forge_init_existing_paths+=("${line:3}")
      done < "$baseline"
    fi
    forge_init_paths=()
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      forge_init_path="${line:3}"
      forge_init_is_new=true
      for forge_init_prior in "${forge_init_existing_paths[@]}"; do
        if [ "$forge_init_path" = "$forge_init_prior" ]; then forge_init_is_new=false; break; fi
      done
      if [ "$forge_init_is_new" = true ]; then forge_init_paths+=("$forge_init_path"); fi
    done < <(git -C <TARGET> status --porcelain --untracked-files=all)
    rm -f "$baseline"
    if [ ${#forge_init_paths[@]} -gt 0 ]; then
      git -C <TARGET> add -- "${forge_init_paths[@]}"
      git -C <TARGET> commit -m "Initial FORGE project scaffold" -- "${forge_init_paths[@]}"
    fi
    # forge:spec-668-forge-init-commit-block:end
    ```

12. Print summary:
    ```
    ## /forge init — Complete (create-new)
    Target: <TARGET>
    Files created: <count>
    Git initialized: yes
    Initial commit: yes
    Onboarding seed: .forge/onboarding.yaml (status: pending)
    Onboarding: .forge/onboarding.yaml planted (status: pending)
    On first agent session, run /onboarding to customize this project.

    Next steps:
    - cd <TARGET>
    - The onboarding flow will run automatically on first agent interaction
    - Or run /onboarding to start interactive project configuration
    - Or run /now to see project state
    ```

---

### Mode: stoke-redirect

> Target already has `.copier-answers.yml` — it is Copier-managed. Redirect to `/forge stoke`.

13. Print:
    ```
    This project is already managed by Copier (.copier-answers.yml found).
    Use /forge stoke to pull upstream FORGE updates instead.
    ```
    Stop. Do not proceed with light.

---

### Mode: legacy-upgrade

> Target has FORGE-like files (AGENTS.md, docs/specs/, .claude/commands/) but no `.copier-answers.yml`. This is a pre-Copier FORGE/EGID project that needs upgrading.
>
> **Plugin-native as of v4.0.1 (Spec 635).** This mode never invokes Copier and never creates
> `.copier-answers.yml`. Its former shape — render a fresh Copier template and copy framework
> files into the target — died twice over in v4.0.0: the template was deleted (Spec 558), and
> under plugin-primary delivery framework surfaces live in the plugin cache, never in the
> consumer tree. What remains is the genuinely useful half: adopt the v4 project-data skeleton
> around the project's existing files, and merge the doctrine files with the project's own
> content preserved.

#### [mechanical] Step L1 — Install and verify the FORGE plugin

14. Framework surfaces (commands, skills, agents, libraries) come from the installed FORGE
    plugin — nothing is copied into the target tree. Verify the plugin is installed and
    registered; if not, walk the operator through the marketplace install first
    (see `docs/process-kit/single-source-generator-guide.md` and the consumer migration
    playbook). Do not proceed until `claude` registers the `forge:*` command set.

    Project-specific commands in the target's `.claude/commands/` keep their names and are
    never touched — plugin commands register under the `forge:` namespace, so file-level
    collisions cannot occur. (Un-namespaced references inside FORGE prompt text are a known
    consumer friction, tracked separately — not a conflict this mode must resolve.)

#### [mechanical] Step L2 — Scaffold the v4 reference skeleton and adopt missing pieces

15. Generate the v4 project-data reference skeleton to an empty temp directory via the
    plugin-native scaffolder (same engine as create-new Step 9; the temp dir is empty, so the
    scaffolder's overwrite guardrail cannot fire):
    ```bash
    FORGE_TMP="${TMPDIR:-${TEMP:-/tmp}}/forge-legacy-upgrade"
    rm -rf "$FORGE_TMP"
    ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/scaffold.py "$FORGE_TMP" --name "<project name>" --description "<from target's CLAUDE.md or README>" --author "<operator>" --owner "<operator>" --layout <contained|classic>
    ```
    Ask the layout question exactly as create-new Step 9 does (`contained` recommended for
    brownfield — the target's `docs/` tree already belongs to the project).

16. Walk the REFERENCE skeleton and adopt into the target only what the target lacks:
    - **Missing project-data files** (e.g. `docs/specs/README.md` scaffolding, `docs/sessions/`
      skeleton, `docs/backlog.md`, `.forge/ownership.yaml`, the `forge.paths` block): copy from
      reference to target. Report each: `Added: docs/sessions/_template.md (project-data)`
    - **Files the target already has** (its own `docs/specs/`, session logs, backlog): NEVER
      overwrite. Report each: `Kept: docs/backlog.md (project-owned)`
    - **`CLAUDE.md` / `AGENTS.md`**: route to the Section-based merge (Step L4) — the reference
      skeleton's thin doctrine files (with the `forge.project:` runtime block and the Spec 640
      managed authorization-core block) are the "template side" of that merge.
    - **`.gitignore`**: append reference entries the target lacks; never remove project entries.

#### [mechanical] Step L3 — Obsolete file detection

17. Check the target for known-obsolete pre-Copier files (static mapping — inlined here since
    Spec 635; the manifest that used to carry it is not part of the scaffolded skeleton). For
    each obsolete file that exists in the target:

    ```
    Obsolete files detected (replaced in current FORGE):
      .claude/commands/egid.md → replaced by forge.md
      .claude/commands/confirm.md → replaced by delegation guardrails in AGENTS.md
      .claude/commands/status.md → replaced by now.md
      ...
    Remove these files? (yes / no / pick individually)
    ```

    If yes: delete the obsolete files. If pick individually: prompt for each. If no: leave them.

#### [decision] Step L4 — Section-based merge for CLAUDE.md and AGENTS.md

18. The merge strategy parses both the project file and the template file by `##` headings and classifies each section.

    **CLAUDE.md section classification:**

    | Section heading pattern | Classification | Action |
    |------------------------|---------------|--------|
    | `Two hard rules` | framework | Take template |
    | `Spec gate` | framework | Take template |
    | `Change lanes` | framework | Take template |
    | `Spec lifecycle` | framework | Take template |
    | `Evidence gates` (generic) | framework | Take template |
    | `Operating loops` | framework | Take template |
    | `Context-aware file reading` | framework | Take template |
    | `Model tiering` | framework | Take template |
    | `Prompt caching` | framework | Take template |
    | `Pre-implementation checklist` | framework | Take template |
    | `Post-implementation checklist` | framework | Take template |
    | `Bash Safety Patterns` | framework | Take template |
    | `Compliance profile rules` | framework | Take template |
    | `Detailed process docs` | framework | Take template |
    | `Evidence gate.*enforcement` | project | Preserve |
    | `Handoff validation.*enforcement` | project | Preserve |
    | `Changelog gate.*enforcement` | project | Preserve |
    | `Deployment sync gate.*enforcement` | project | Preserve |
    | `Post-gate failure rule` | project | Preserve |
    | `Session continuity` | project | Preserve |
    | `Parallel agent strategy` | project | Preserve |
    | `Claude Code environment notes` | project | Preserve |
    | `Content standards` | shared | Take template |
    | `Communication style` | shared | Take template |
    | `Code review` | shared | Take template |
    | `Architecture quick-ref` | project | Preserve |
    | `Key commands` | project | Preserve |
    | `Core constraints` | project | Preserve |
    | Unknown heading | project | Preserve (conservative) |

    **AGENTS.md section classification:**

    | Section heading pattern | Classification | Action |
    |------------------------|---------------|--------|
    | `Agent Identity` | framework | Take template |
    | `Capabilities` | framework | Take template |
    | `Bounded Autonomy` | framework | Take template |
    | `Delegation Contract` | framework | Take template |
    | `Signal Capture` | framework | Take template |
    | `Evidence Gates` (table) | framework | Take template |
    | `Workflow Map` | framework | Take template |
    | `Autonomy Levels` | framework | Take template (new in FORGE) |
    | `Budget Ceilings` | framework | Take template (new in FORGE) |
    | `Agent Role Separation` | framework | Take template (new in FORGE) |
    | `Runtime Configuration` | framework | Take template (new in FORGE) |
    | `NanoClaw Integration` | framework | Take template (new — onboarding decides if kept) |
    | `Repo Conventions` | framework | Take template |
    | `Known pitfalls` | project | Preserve entirely |
    | `Changelog gate` | project | Preserve |
    | `Deployment sync gate` | project | Preserve |
    | `Roadmap maintenance` | project | Preserve |
    | `Documentation sync gate` | project | Preserve |
    | `Backlog gate` | project | Preserve |
    | `Delegation.*Guardrails` | project | Preserve |
    | `Housekeeping` | project | Preserve |
    | `Module structure` | project | Preserve |
    | `Feature folder` | project | Preserve |
    | `Upstream Sync` | project | Preserve |
    | `Git Conventions` | project | Preserve |
    | `Appendix.*Project-specific` | project | Preserve |
    | Unknown heading | project | Preserve (conservative) |

19. After classification, assemble the merged file:
    - Framework sections: use template version
    - Project sections: use project version, inserted after the last framework section that preceded them in the original file
    - New framework sections (in template but not in project): add in template order
    - Present a summary before writing:
      ```
      ## CLAUDE.md merge plan
      Framework sections updated: <count>
      Project sections preserved: <count>
      New sections added: <count>
      Sections removed: 0

      Confirm merge? (yes / show details / abort)
      ```
    - If confirmed: write the merged file. If abort: skip the merge for that file.

#### [mechanical] Step L5 — No management marker (deliberate)

20. Do NOT create `.copier-answers.yml` — that file is the Copier-management marker, and
    planting it would misroute this project to stoke-redirect classic detection on any future
    `/forge init` run. Plugin-primary projects need no marker: the installed plugin IS the
    framework linkage, and `/forge stoke` (content-merge engine, Specs 559/591) handles future
    project-data updates without one.

#### [mechanical] Step L6 — Plant onboarding seed

21. Create `<TARGET>/.forge/onboarding.yaml`:
    ```yaml
    status: pending
    created: <today YYYY-MM-DD>
    template_version: "0.0.0"
    mode: legacy-upgrade

    features:
      nanoclaw: null
      compliance: null
      publications: null
      devcontainer: true

    mcp_servers: {}
    setup_tasks: []

    project:
      name: null
      description: null
      primary_stack: null  # valid values: language name, "deferred" (Spec 162), or null
      test_command: null
      lint_command: null
    ```

#### [mechanical] Step L7 — Cleanup and report

22. Clean up the temp directory: `rm -rf "$FORGE_TMP"`

23. Print summary:
    ```
    ## /forge init — Complete (legacy-upgrade)
    Target: <TARGET>
    Plugin: forge (registered — framework surfaces come from the plugin cache)
    Project-data files adopted: <count>
    Project files preserved: <count>
    Doctrine files merged: <count> (CLAUDE.md, AGENTS.md)
    Obsolete files removed: <count>
    Onboarding seed: .forge/onboarding.yaml (status: pending)
    On first agent session, run /onboarding to customize this project.

    Next steps:
    - Review merged CLAUDE.md and AGENTS.md
    - The onboarding flow will run automatically on first agent interaction
    - Or run /onboarding to start interactive project configuration
    - Future project-data updates: /forge stoke (content-merge engine); plugin updates
      arrive via the marketplace
    ```

---

### Mode: greenfield

> Existing directory with no FORGE markers. Run the original greenfield/brownfield PRD interview flow.

#### [mechanical] Detection (greenfield vs brownfield)

24. Check the target directory for existing project markers:
    - `CLAUDE.md` exists → **brownfield**
    - `docs/specs/` exists → **brownfield**
    - `.claude/commands/` exists → **brownfield**
    - None of the above → **greenfield**

25. Report:
    - Greenfield: "No existing process kit detected. Starting greenfield bootstrap with PRD interview."
    - Brownfield: "Existing project detected. Running brownfield injection (existing files will NOT be overwritten)."

#### [decision] Greenfield PRD Interview

26. **(Greenfield only)** Ask the following questions one at a time. Wait for each answer before proceeding.
    a. "What is the project name? (used for CLAUDE.md header and file references)"
    b. "Describe the project in 1–2 sentences. (used for CLAUDE.md opening paragraph)"
    c. "What is the git remote URL? (type `none` if not yet created)"
    d. **Defer-to-AI pattern** for language/framework:
       ```
       Do you have a preferred language/framework, or should I recommend one
       based on the project requirements?
       1. I have a preference (tell me what you'd like)
       2. Recommend for me (I'll suggest the best fit after hearing your goals)
       ```
       - If **1**: ask "What language/framework? (e.g., Python, TypeScript + React, Go)"
       - If **2**: defer the recommendation — record `primary_stack: null` for now. After
         questions e and f are answered, propose a stack with brief rationale based on the
         project description, features, and constraints. Ask: "Accept this recommendation?
         (yes to accept, or type your preferred stack to override)"
    e. "What are the 2–3 most important features or goals for the initial version?"
    f. "Are there any hard constraints? (e.g., must run offline, no external APIs, specific OS support)"
    g. **(If stack was deferred in step d)**: Based on the project description, features, and
       constraints from answers b/e/f, recommend a primary stack:
       ```
       ## Stack Recommendation
       Based on your project requirements, I recommend: <stack>

       Rationale: <2-3 sentences explaining why this stack fits the stated requirements>

       Accept this recommendation? (yes to accept, or type your preferred stack to override)
       ```
       Record the accepted or overridden value as `primary_stack`.
    h. **Defer-to-AI pattern** for test and lint commands:
       ```
       Do you have preferred test and lint tools, or should I choose the standard
       ones for <primary_stack>?
       1. I have preferences (tell me what you'd like)
       2. Use the defaults for <primary_stack>
       ```
       - If **1**: ask for test command, then lint command
       - If **2**: set `test_command` and `lint_command` to the conventional defaults for the
         chosen stack (e.g., Python → `pytest -q` / `ruff check .`, TypeScript → `npm test` / `eslint src/`).
         Report: "Using defaults: test=`<cmd>`, lint=`<cmd>`"

27. **(Spec 141 — Forward-write to onboarding.yaml)** After all answers are collected, update
    `<TARGET>/.forge/onboarding.yaml` with the PRD interview answers before proceeding:
    ```yaml
    project:
      name: <answer a>
      description: <answer b>
      primary_stack: <answer d/g>
      test_command: <answer h, null if 'none'>
      lint_command: <answer h, null if 'none'>
    ```
    If all identity fields (name, description, primary_stack) are non-null, also set:
    ```yaml
    phases:
      identity: complete
      features: null
      mcp_servers: null
      credentials: null
      summary: null
    ```
    This prevents `/onboarding` from re-asking these questions.

28. After forward-write, proceed to **Create Structure**.

#### [mechanical] Brownfield Inventory

29. **(Brownfield only)** List which process kit files already exist. For each file in the bootstrap manifest, check if it exists in the target project.

29. Report: "The following files already exist and will be SKIPPED: `<list>`. The following files will be CREATED: `<list>`." Proceed to **Create Structure**, skipping existing files.

#### [mechanical] Create Structure

30. Create the directory structure (skip directories that already exist):
    ```
    docs/specs/
    docs/sessions/
    docs/process-kit/
    docs/decisions/
    .claude/commands/
    ```

31. **Copy process kit files** from the bootstrap manifest. For each file:
    - If the file already exists in the target: **skip** (brownfield safety).
    - If the file is new: create it from the corresponding template in `docs/process-kit/`.
    - Substitute template variables:
      - `{{PROJECT_NAME}}` → project name from interview or existing project
      - `{{PROJECT_DESCRIPTION}}` → description from interview
      - `{{REPO_URL}}` → git remote URL
      - `{{PRIMARY_STACK}}` → language/framework
      - `{{DATE}}` → today's date (YYYY-MM-DD)

    Files to create:
    a. **CLAUDE.md** — Generate from PRD interview answers (greenfield) or create minimal stub (brownfield).
    b. **docs/specs/_template.md** — Copy from `docs/process-kit/spec-template.md`
    c. **docs/specs/README.md** — Copy from `docs/process-kit/spec-index-template.md`
    d. **docs/specs/CHANGELOG.md** — Create with initial entry
    e. **docs/sessions/_template.md** — Copy session log template
    f. **docs/sessions/scratchpad.md** — Create empty scratchpad with header
    g. **docs/sessions/error-log.md** — Create with header
    h. **docs/sessions/insights-log.md** — Create with header
    i. **docs/process-kit/scoring-rubric.md** — Copy scoring rubric
    j. **docs/process-kit/human-validation-runbook.md** — Copy validation runbook
    k. **docs/process-kit/checklists.md** — Copy checklists
    l. **docs/backlog.md** — Create with header, empty ranked tables, and scoring formula
    m. **.claude/commands/** — For each FORGE command file:
       - If the file does not exist in the target: copy it.
       - If the file exists and contains `# Framework: FORGE` in the first 5 lines: overwrite (FORGE-owned).
       - If the file exists and does NOT contain `# Framework: FORGE`: **conflict** — the user
         has a project-specific command with the same name. Collect for conflict interview.
       After copying non-conflicting commands, run the **Command Name Conflict Resolution**
       interview (same as Step L2b in legacy-upgrade mode) for any conflicts found.

32. **Create .gitignore** if it does not exist. Include standard exclusions:
    ```
    tmp/
    *.pyc
    __pycache__/
    .venv/
    node_modules/
    dist/
    build/
    .env
    *.log
    docs/compliance/standards/*.pdf
    ```
    If `.gitignore` exists, check if `tmp/` is listed. If not, suggest adding it.

33. **Create initial session log**: Create `docs/sessions/YYYY-MM-DD-001.md` from the session template. Populate summary: "Bootstrapped project process kit via /forge init."

#### [mechanical] Report (Spec 147 — vision-first greenfield)

34. Print:
    ```
    ## /forge init — Complete
    Mode: greenfield | brownfield
    Files created: <count>
    Files skipped: <count> (existing)
    CLAUDE.md: created | skipped
    .gitignore: created | updated | skipped
    Session log: docs/sessions/YYYY-MM-DD-001.md

    Next steps (greenfield):
    - Review CLAUDE.md and customize as needed
    - Run /interview to build a Project Requirements Document (PRD)
      The interview captures your vision, personas, pillars, and success
      metrics — then offers to save the result as docs/process-kit/prd.md.
    - After the PRD: make architecture decisions (/decision), break the
      roadmap into specs (/spec), then /implement.

    Next steps (brownfield):
    - Review CLAUDE.md and customize as needed
    - Run /now to see project state
    - Run /spec to create your first spec when ready
    ```

---

## [mechanical] Next action

After light completes:
- **(Greenfield)**: "Next: run `/interview` to define your project vision and build a PRD."
- **(Brownfield)**: "Next: run `/now` to see your project state."


## [decision] Brownfield/greenfield close-out — bounded /reconcile offer (Spec 577 R4)

After scaffolding into an EXISTING repo (brownfield) — and after onboarding is seeded — end with:

```
Seed the spec corpus from this repo's git history? /reconcile drafts retroactive stub specs
for large change clusters and memory notes for small ones (purely additive; stubs never
auto-advance).
```
> **Choose** — type a number or keyword:
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **1** | 1 | `last-90-days` | Recent history is highest-signal; bounded stub volume | /reconcile bounded to commits since 90 days ago |
> | **2** | — | `last-200-commits` | Commit-count bound for repos with bursty history | /reconcile bounded to the last 200 commits |
> | **3** | — | `full-history` | Complete corpus; large repos may draft many stubs | /reconcile over the full history |
> | **4** | 2 | `later` | Not ready to triage stubs now; marker keeps it un-forgettable | Plant the reconcile-pending marker — /now surfaces it until run or dismissed |
> | **5** | — | `skip` | History seeding not wanted | No reconcile, no marker |

On `later`: write `.forge/state/reconcile-pending.json` (`{"planted":"init","options":[...]}`).
On a scope choice: run /reconcile with that bound (its thresholds/doctrine unchanged).
Recommended ordering: init → /onboarding → /reconcile (classification benefits from onboarding's
stack/test-command answers) — say so when the operator picks a scope before onboarding ran.
