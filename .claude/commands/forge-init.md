# Framework: FORGE
## Subcommand: init

> Bootstrap FORGE into a new or existing project, upgrade legacy pre-Copier projects, or create new projects from scratch.
>
> Accepts an optional path argument: `/forge init [path]`
> - No path → operates on the current working directory (backward-compatible)
> - Path exists → operates on that directory
> - Path does not exist → creates the directory and enters create-new mode

### [mechanical] Step 0 — Prerequisite check (Spec 143)Before any bootstrap logic, verify that required tools are available:1. Check for **Python 3.10+ (Spec 401 raised floor from 3.9)**: run `.forge/bin/forge-py --version` (or directly: `python3 --version` / `python --version` / `py -3 --version`).2. Check for **Git**: run `git --version`.3. Check for **Copier 9.0+**: run `python -m copier --version`.4. Check for **POSIX `sh` shell on PATH** (Spec 401): run `command -v sh` (POSIX) or `where sh` (Windows). On Windows: if `sh` is absent, surface this actionable message — `Windows: 'sh' not found on PATH. FORGE requires either (a) Git for Windows installed with 'Use Git and optional Unix tools from the Command Prompt' option (option 3 of the Git for Windows installer), OR (b) FORGE workflows launched from a Git Bash terminal. Re-run the Git for Windows installer and select option 3, or open Git Bash and re-run.`If all prerequisites are met: proceed silently.If any are missing:- Report what's missing and the install command for the detected platform- Ask: "Install missing prerequisites now? (yes / no)"- If yes: run the install commands, re-verify, then proceed.- If no: stop with a message listing what to install manually.Alternatively, run `bash .forge/bin/forge-install.sh --check-prereqs` which handles detection, platform awareness, and interactive installation offers.Skip this step if the user passed `--skip-prereqs`.
### [mechanical] Step 0a — Resolve target path

1. Parse the remainder of `$ARGUMENTS` after `light` to extract the optional path.
   - If a path is provided: set `TARGET` to that path (resolve relative paths against CWD).
   - If no path is provided: set `TARGET` to the current working directory.

2. Detect the FORGE template source:
   - If the current repo root contains `copier.yml`: local FORGE clone detected. Prompt for the bootstrap source:
     ```
     Bootstrap source — determines where /forge stoke pulls future updates:
     1. gh:Renozoic-Foundry/forge-public  ← recommended (public GitHub — works on any machine)
     2. <current directory path>  ← local path (only works on this machine)

     Choose (1 or 2, default: 1):
     ```
     Set `TEMPLATE_SRC` to the chosen value. **Note**: if the user is a FORGE developer working from a local clone and wants local stoke behavior, they should choose option 2.
   - Else if `TARGET` has `.copier-answers.yml` with `_src_path`: use that as `TEMPLATE_SRC`.
   - Else: ask the human for the path to the FORGE repo.

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
   | `TARGET` has `.copier-answers.yml` | **stoke-redirect** | Already Copier-managed — redirect to `/forge stoke` |
   | `TARGET` has `AGENTS.md` OR `docs/specs/` OR `.claude/commands/` but NO `.copier-answers.yml` | **legacy-upgrade** | Pre-Copier FORGE/EGID project |
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

7. Create the target directory: `mkdir -p <TARGET>`

8. Initialize a git repo: `git init <TARGET>`

9. Generate the full FORGE template into the target:
   ```bash
   python -m copier copy "<TEMPLATE_SRC>" "<TARGET>" --defaults --trust
   ```

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

11. Create initial commit:
    ```bash
    cd <TARGET> && git add -A && git commit -m "Initial FORGE project scaffold"
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

#### [mechanical] Step L1 — Generate fresh template

14. Generate a fresh FORGE template to a temp directory:
    ```bash
    FORGE_TMP="${TMPDIR:-${TEMP:-/tmp}}/forge-legacy-upgrade"
    rm -rf "$FORGE_TMP"
    python -m copier copy "<TEMPLATE_SRC>" "$FORGE_TMP" --defaults --trust
    ```

15. Read `.forge/update-manifest.yaml` from the fresh template to classify files.

#### [mechanical] Step L2 — Process files by classification

16. Walk the fresh template directory and classify each file against the manifest:

    **Framework files** (paths matching `framework.paths` in manifest — always overwrite):
    - **Exception: `.claude/commands/` conflict check** — Before overwriting any command file,
      check if the target file already exists AND is not a FORGE command (i.e., it was created
      by the user for project-specific functionality). Detection: read the first 5 lines of the
      existing file — if it does NOT contain `# Framework: FORGE`, it is a project-specific
      command. For each conflict found, collect it for the conflict interview (Step L2b below).
    - For non-conflicting framework files: copy from temp to target, creating directories as needed.
    - Overwrite existing FORGE-owned files (files that contain `# Framework: FORGE` header).
    - Report each: `Updated: .forge/lib/logging.sh (framework)`

    **Project files** (paths matching `project.paths` in manifest — never touch):
    - Skip entirely, do not copy, do not modify.
    - Report each: `Skipped: docs/specs/001-my-spec.md (project-owned)`

    **Merge files** (paths matching `merge.paths` in manifest — intelligent merge):
    - For `CLAUDE.md` and `AGENTS.md`: execute the **Section-based merge** (Step L3 below).
    - For `.gitignore`: append new entries from template that don't exist in project.
    - For `.mcp.json`: merge server lists (add new servers, keep existing project servers).
    - For other merge files: present side-by-side diff and ask human to choose.

    **New files** (exist in template but not in target, not matching any project path pattern):
    - Copy from temp to target.
    - Report each: `Added: .forge/bin/forge-status.ps1 (new)`

#### [decision] Step L2b — Command name conflict resolution

16b. If any `.claude/commands/` conflicts were detected in Step L2 (existing project-specific
     commands whose names collide with FORGE commands), present them to the user:

     ```
     ## Command Name Conflicts

     The following project commands share names with FORGE commands:

     | File | Project command purpose (first line) | FORGE command purpose |
     |------|-------------------------------------|---------------------|
     | .claude/commands/test.md | "Run pytest with coverage" | FORGE /test — run spec test plan |
     | .claude/commands/note.md | "Add meeting notes to wiki" | FORGE /note — append to scratchpad |
     ```

     For each conflict, ask:

     ```
     Conflict: .claude/commands/test.md
     Your version: <first non-empty, non-comment line from existing file>
     FORGE version: <first non-empty, non-comment line from template file>

     Choose:
     1. Keep yours — rename FORGE's to /forge-test
     2. Keep FORGE's — rename yours to /project-test (or a name you choose)
     3. Merge — I'll combine both into one command (show me a draft)
     4. Replace — overwrite with FORGE's version (your version will be lost)
     5. Skip — don't install this FORGE command
     ```

     Apply the chosen resolution:
     - **Option 1 (rename FORGE)**: Copy FORGE command as `forge-<name>.md` instead
     - **Option 2 (rename project)**: Rename existing to the chosen name, then copy FORGE command
     - **Option 3 (merge)**: Read both files, draft a merged version, show to user for approval
     - **Option 4 (replace)**: Overwrite with FORGE version
     - **Option 5 (skip)**: Do not copy this FORGE command

     Record all conflict resolutions in the report.

     If no conflicts: skip this step silently.

#### [mechanical] Step L3 — Obsolete file detection

17. Check the target for files listed in `obsolete.mappings` from the manifest. For each obsolete file that exists in the target:

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

#### [mechanical] Step L5 — Generate .copier-answers.yml

20. Create `.copier-answers.yml` in the target so future updates use `/forge stoke`:
    ```yaml
    # Changes here will be overwritten by Copier
    _commit: HEAD
    _src_path: <TEMPLATE_SRC>
    project_name: <inferred from CLAUDE.md header or directory name>
    project_slug: <directory name>
    ```

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
    Framework files updated: <count>
    Project files preserved: <count>
    Merge files processed: <count>
    New files added: <count>
    Obsolete files removed: <count>
    .copier-answers.yml: created
    Onboarding seed: .forge/onboarding.yaml (status: pending)
    Onboarding: .forge/onboarding.yaml planted (status: pending)
    On first agent session, run /onboarding to customize this project.

    Next steps:
    - Review merged CLAUDE.md and AGENTS.md
    - The onboarding flow will run automatically on first agent interaction
    - Or run /onboarding to start interactive project configuration
    - Future updates: use /forge stoke (Copier is now the sync mechanism)
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
