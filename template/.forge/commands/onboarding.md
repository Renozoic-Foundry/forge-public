---
name: onboarding
description: "First-session interactive project configuration"
model_tier: sonnet
workflow_stage: lifecycle
---
# Framework: FORGE
# Onboarding — First-session interactive project configuration (Spec 073)

This command implements the 5-phase deferred onboarding flow. It reads `.forge/onboarding.yaml`
and walks the human through interactive customization of their FORGE-bootstrapped project.

**Resumability**: Each phase updates `.forge/onboarding.yaml` on completion. If the session
crashes, the next session resumes from the first incomplete phase. Completed phases are never
re-asked.

**Trigger**: AGENTS.md instructs every agent to check `.forge/onboarding.yaml` on session start.
If `status: pending` or `status: in-progress`, execute this flow before any other work.

> **Execution rule — one interaction at a time**: Each `[decision]` section is a discrete interaction point. Present the prompt, then **STOP and wait for the user's response** before advancing to the next section. Never generate multiple `[decision]` prompts in a single message.

---

## [mechanical] Step 0 — Load onboarding state

1. Read `.forge/onboarding.yaml`. Parse the current state:
   - `status` — must be `pending` or `in-progress` to proceed
   - `phases` — map of phase names to completion status (may not exist yet)
   - `features` — current feature toggle values
   - `project` — current project identity values

2. If `status` is `complete` or the file does not exist: print "Onboarding already complete or not required." and stop.

3. If `status` is `pending`: set `status: in-progress` in `.forge/onboarding.yaml` and write the file. Add a `phases` key if it does not exist:
   ```yaml
   phases:
     identity: null
     features: null
     mcp_servers: null
     credentials: null
     summary: null
   ```

4. Determine which phase to start from by finding the first phase in this order where the value is NOT `complete`:
   - `identity` → Phase 1
   - `features` → Phase 2
   - `mcp_servers` → Phase 3
   - `credentials` → Phase 4
   - `summary` → Phase 5

5. Print:
   ```
   ## FORGE Onboarding
   Welcome! This one-time setup customizes FORGE for your project.
   5 quick phases: Identity → Features → MCP Servers → Environment → Summary

   Resuming from: Phase <N> — <phase name>
   ```
   (If starting fresh from Phase 1, say "Starting from: Phase 1 — Project Identity")

6. Jump to the appropriate phase below.

---

## [decision] Phase 1 — Project Identity

### [mechanical] Greenfield detection (Spec 147)

Before starting Phase 1 questions, check whether this is a greenfield project:

1. List the contents of `docs/specs/`. Ignore structural files: `_template.md`, `_template-light.md`, `README.md`, `CHANGELOG.md`.
2. If no spec files remain after filtering (i.e., the directory contains only structural files or is empty), this is a **greenfield** project.
3. If greenfield is detected, adjust the Phase 1 opening message:
   ```
   This looks like a greenfield project — no specs have been created yet.
   After onboarding, the recommended first step is /interview to define your
   project vision and build a PRD (Project Requirements Document).
   ```

**Skip condition**: If `phases.identity` is `complete`, skip to Phase 2 with message:
```
Phase 1 — Project Identity: already configured via /forge init. Skipping.
```

**Dedup rule (Spec 141)**: Before presenting each question below, check if the corresponding field
in `.forge/onboarding.yaml` under `project` already has a non-null, non-empty value. If so,
**skip that question entirely** — do not ask, do not show a default. Report skipped fields:
```
Using existing value: <field> = <value>
```

**Input compatibility (Spec 141)**: Never instruct the user to "press Enter" or "leave blank"
to keep a default. If a question needs a keep-current option, instruct: `Type "keep" to keep
the current value.` However, prefer skipping already-answered questions entirely.

### [mechanical] Brownfield auto-detection (Spec 146)

Before asking questions, scan the project for existing configuration to pre-populate answers:

| Field | Detection sources (check in order) |
|-------|-----------------------------------|
| name | `package.json:name`, `pyproject.toml:project.name`, `Cargo.toml:package.name`, `go.mod` module (last segment), `README.md` first H1, git remote URL (last path segment), directory name (fallback) |
| description | `package.json:description`, `pyproject.toml:project.description`, `Cargo.toml:package.description`, `README.md` first paragraph after H1 |
| primary_stack | File extension analysis (`.py` → Python, `.ts`/`.tsx` → TypeScript, `.go` → Go, `.rs` → Rust, `.java` → Java), config file presence (`pyproject.toml` → Python, `package.json` → Node/TypeScript, `Cargo.toml` → Rust, `go.mod` → Go) |
| test_command | `package.json:scripts.test`, `pyproject.toml:tool.pytest` → `pytest -q`, `Cargo.toml` → `cargo test`, `go.mod` → `go test ./...` |
| lint_command | `package.json:scripts.lint`, `.eslintrc*` → `eslint src/`, `pyproject.toml:tool.ruff` → `ruff check .`, `Cargo.toml` → `cargo clippy` |
| author | `git config user.name` |

For each detected value, record the source in onboarding.yaml (e.g., `name_source: "package.json"`).

When presenting a detected value, use a confirmation prompt instead of an open question:
```
Project name: "my-app" (detected from package.json)
Accept? (yes / change)
```

If no value detected for a field, ask the question normally (below).

---

### [decision] 1a — Project name

**Skip if**: `project.name` is not null → report `Using existing value: name = <value>` and proceed to 1b.

If auto-detected: `Project name: "<detected>" (from <source>). Accept? (yes / change)`
If not detected: `What is the project name?`

**STOP — wait for user response before proceeding to 1b.**

---

### [decision] 1b — Project description

**Skip if**: `project.description` is not null → report `Using existing value: description = <value>` and proceed to 1c.

If auto-detected: `Description: "<detected>" (from <source>). Accept? (yes / change)`
If not detected: `Describe the project in 1-2 sentences.`

**STOP — wait for user response before proceeding to 1c.**

---

### [decision] 1c — Primary stack

**Skip if**: `project.primary_stack` is not null → report `Using existing value: primary_stack = <value>` and proceed to 1d.

If auto-detected (brownfield): `Primary stack: "<detected>" (from <source>). Accept? (yes / change)`

If not detected, present numbered choice:
```
Primary language/framework:

| # | Option |
|---|--------|
| 1 | Python |
| 2 | TypeScript / JavaScript |
| 3 | Go |
| 4 | Rust |
| 5 | Java / Kotlin |
| 6 | C# / .NET |
| 7 | Other (specify) |
| 8 | Undecided — I'll recommend based on project requirements (default) |
| 9 | Defer — decide after /interview and PRD creation |

Choose (1-9, or type a framework name):
```

- If **7**: ask "What language/framework?" before proceeding to 1d.
- If **8** (default for greenfield): set `primary_stack: null` and `deferred_stack: true` in onboarding.yaml. Skip 1d and 1e entirely. Report: `Stack undecided — test and lint commands also deferred. The post-onboarding message will recommend /interview to determine the optimal stack.`
- If **9** (Spec 162 — stack deferral): set `primary_stack: deferred`, `test_command: null`, `lint_command: null` in onboarding.yaml. Skip 1d and 1e entirely. Report:
  ```
  Stack selection deferred. Test and lint commands also deferred.
  Run /interview to build a PRD, then resolve your stack choice.
  ```

**STOP — wait for user response before proceeding to 1d.**

---

### [decision] 1d — Test command

**Skip if**: `project.test_command` is not null → report `Using existing value: test_command = <value>` and proceed to 1e.
**Skip if**: `project.primary_stack` is `deferred` or `deferred_stack` is `true` → proceed to 1e silently.

```
Do you have a preferred test tool, or should I use the standard one for <primary_stack>?
1. I have a preference (tell me what you'd like)
2. Use the default for <primary_stack>
```

- If **1**: ask for the test command before proceeding to 1e.
- If **2**: set to conventional default (e.g., Python → `pytest -q`, TypeScript → `npm test`). Report: `Using default: test=<cmd>`
- Type `none` to skip (sets to null).

**STOP — wait for user response before proceeding to 1e.**

---

### [decision] 1e — Lint command

**Skip if**: `project.lint_command` is not null → report `Using existing value: lint_command = <value>` and proceed to 1f.
**Skip if**: `project.primary_stack` is `deferred` or `deferred_stack` is `true` → proceed to 1f silently.

Same defer-to-AI pattern as test command:
```
Do you have a preferred lint tool, or should I use the standard one for <primary_stack>?
1. I have a preference (tell me what you'd like)
2. Use the default for <primary_stack>
```

- If **1**: ask for the lint command before proceeding to 1f.
- If **2**: set to conventional default (e.g., Python → `ruff check .`, TypeScript → `eslint src/`). Report: `Using default: lint=<cmd>`
- Type `none` to skip (sets to null).

**STOP — wait for user response before proceeding to 1f.**

---

### [decision] 1f — AI coding agents

```
Which AI coding agents does your team use? (select all that apply)
1. Claude Code
2. Cursor
3. GitHub Copilot
4. OpenAI Codex
5. Cline
6. Other / generic
```

**STOP — wait for user response before proceeding to step 8.**

---

8. [mechanical] Write the answers to `.forge/onboarding.yaml` under the `project` key
   (only update fields that were asked — preserve existing values for skipped fields):
   ```yaml
   project:
     name: <answer 1a or existing>
     description: <answer 1b or existing>
     primary_stack: <answer 1c or existing>
     test_command: <answer 1d or existing, null if 'none'>
     lint_command: <answer 1e or existing, null if 'none'>
   ```

8b. [mechanical] Write the agent selections to `.forge/onboarding.yaml` under the `agents` key:
    ```yaml
    agents:
      claude_code: <true if selected, false otherwise>
      cursor: <true if selected, false otherwise>
      copilot: <true if selected, false otherwise>
      codex: <true if selected, false otherwise>
      cline: <true if selected, false otherwise>
    ```
    If "Other / generic" was selected, record `generic: true` as well.

8c. [mechanical] Run `forge-sync-commands.sh` to generate agent-specific command wrappers
    for the selected agents:
    ```bash
    .forge/bin/forge-sync-commands.sh
    ```
    This reads the `agents:` key from `onboarding.yaml` and generates command files in each
    agent's native directory (e.g., `.cursor/commands/`, `.github/prompts/`).

9. [mechanical] Update CLAUDE.md:
   - Find the first `# ` heading (H1) in CLAUDE.md. Replace the project name placeholder or generic title with the project name.
   - If there is a description placeholder or the first paragraph after the H1 heading, update it with the project description.
   - If there is a "Key commands" or similar section, update test and lint commands if placeholders exist.
   - Do NOT overwrite project-specific content that the human has already customized. Only replace obvious template placeholders (e.g., `{{ project_name }}`, `My Project`, `PROJECT_NAME`, or the Copier default values).

10. [mechanical] Update `.copier-answers.yml` if it exists:
    - Set `project_name` to the project name
    - Set `project_slug` to a slugified version of the project name (lowercase, hyphens for spaces)
    - Set `project_description` to the description
    - Set `test_command` to the test command (or empty string if none)
    - Set `lint_command` to the lint command (or empty string if none)
    - Preserve all other existing keys (especially `_commit`, `_src_path`)

    **Note — `/forge stoke` upstream source**: The `_src_path` key in `.copier-answers.yml` determines where `/forge stoke` pulls template updates from. If this project was bootstrapped via `copier copy gh:bwcarty/forge-public`, the value is `gh:bwcarty/forge-public` and stoke works from any machine. If it contains a local path (e.g., `d:/forge`), stoke only works on the machine where that path exists. To switch to the public GitHub source: update `_src_path: gh:bwcarty/forge-public` in `.copier-answers.yml`.

### [conditional] Step 10a — Private repo authentication setup (Spec 200)

If `_src_path` does NOT start with `gh:bwcarty/forge-public` and does NOT look like a local path (i.e., it is a remote URL pointing to a private repo):

Present:
```
## Private Repo Authentication

Your FORGE template source is a private repository:
  <_src_path>

Every machine (and CI pipeline) that runs `/forge stoke` needs access to this repo.
Recommended setup — choose the option that fits your environment:

1. **SSH rewrite** (recommended for developers):
   ```
   git config --global url."git@<host>:".insteadOf "https://<host>/"
   ```
   Requires: SSH key added to your Git hosting provider.

2. **Git Credential Manager** (recommended for enterprise/firewalls):
   ```
   git config --global credential.helper manager
   ```
   GCM handles MFA, token refresh, and multi-provider support.

3. **CI/CD pipeline** (for automated environments):
   Use `GIT_ASKPASS` or `http.extraheader` with a PAT stored as a pipeline secret.
   See: docs/process-kit/private-repo-guide.md for patterns.

**Warning**: Never embed credentials directly in the URL (e.g., `https://user:TOKEN@host`).
Embedded credentials are stored in `.copier-answers.yml` and committed to version control.
```

If `_src_path` starts with `gh:bwcarty/forge-public` or is a local path: skip this section silently.

### [decision] 10b — Autonomy level

```
## Autonomy Level
FORGE defines 5 levels of AI agent autonomy:

| Level | Name                | What the agent can do |
|-------|---------------------|-----------------------|
| L0    | Full Manual         | Advise only — no file edits |
| L1    | Human-Gated (default) | Agent drives; human approves every gate |
| L2    | Supervised Autonomy | Agent auto-chains mechanical steps; human approves decisions |
| L3    | Trusted Autonomy    | Agent completes full spec cycle; human reviews async |
| L4    | Full Autonomy       | Agent end-to-end; human on exception only |

Choose a level (0-4, default: 1):
```

**STOP — wait for user response before proceeding to step 10c.**

10c. [mechanical] Based on the autonomy level, set Claude Code's permission mode in `.claude/settings.json`:
    - L0–L1 → `"defaultMode": "default"`
    - L2 → `"defaultMode": "auto"`
    - L3–L4 → `"defaultMode": "bypassPermissions"`

    Read `.claude/settings.json` (create if absent with `{}`). Set the `defaultMode` key. Write the file.
    Record in `.forge/onboarding.yaml`:
    ```yaml
    project:
      autonomy_level: L<N>
      permission_mode: <default|auto|bypassPermissions>
    ```
    Report:
    ```
    Autonomy: L<N> (<name>) → Claude Code permission mode: <mode>
    Written to: .claude/settings.json
    ```

### [decision] 10d — Development methodology

```
## Development Methodology
FORGE adapts its language to match your team's methodology.
This changes terminology only — not behavior.

| # | Methodology | Example: /now header |
|---|-------------|---------------------|
| 1 | Scrum       | "Daily standup" |
| 2 | SAFe        | "Iteration sync" |
| 3 | Kanban      | "Board review" |
| 4 | DevOps      | "Status check" |
| 5 | Safety-critical | "Safety status review" |
| 6 | None / Default | "Project status" |

Choose a methodology (1-6, default: 6):
```

**STOP — wait for user response before proceeding to step 10e.**

10e. [mechanical] Record the methodology in `.forge/onboarding.yaml`:
    ```yaml
    project:
      methodology: <scrum|safe|kanban|devops|safety-critical|none>
    ```
    Also update AGENTS.md — find the `forge:` config block and add or update:
    ```yaml
    forge:
      methodology: <selected value>
    ```
    Report:
    ```
    Methodology: <selected> — command output will use <methodology> terminology.
    ```

11. [mechanical] Set `phases.identity: complete` in `.forge/onboarding.yaml` and write the file.

12. Print:
    ```
    Phase 1 complete — Project identity saved.
    ```

---

## [decision] Phase 2 — Feature Selection

**Skip condition**: If `phases.features` is `complete`, skip to Phase 3.

13. [mechanical] Read `.forge/feature-files.yaml` to get the feature-to-file mapping.

14. [mechanical] Check current toggle values in `.forge/onboarding.yaml`. Features already set to `true` or `false` are already decided and will be noted in the menu, not re-presented as choices.

### [decision] Feature selection menu

<!-- Module-aware Phase 2: Read .forge/modules/*/module.yaml for available modules.
     Present each module's onboarding.prompt. If user asks "explain", show onboarding.explain.
     If user says "defer", leave toggle null and record phase as incomplete for re-ask.
     Fall back to hardcoded features below if no module manifests found. -->

### [mechanical] Feature menu filtering (Spec 202)

Before presenting the menu, read `.forge/onboarding.yaml` and check the `features` map. **Exclude any feature whose value is explicitly `false`** from the menu entirely — do not show it as an option, do not number it. This handles cases where a feature was pre-disabled (e.g., `nanoclaw: false` set during bootstrap or by organizational policy).

Feature visibility rules:
- `features.<name>: false` → **hidden** (do not show in menu, do not ask)
- `features.<name>: true` → **already decided** (show as "already enabled", not re-presented as a choice)
- `features.<name>: null` or key absent → **undecided** (show in menu as a selectable option)

Renumber the menu dynamically based on visible features. For example, if NanoClaw is `false`, the menu starts at Compliance as #1.

Present all undecided features in a single numbered menu. Features already set to `true` (from a resumed session) are shown with their current status — not re-presented as choices. Features set to `false` are hidden entirely:

```
## Optional Features

Select which features to keep enabled for this project:

| # | Feature | Description |
|---|---------|-------------|
<dynamically numbered rows for undecided features only>
| R | Recommend | Auto-select based on your project type |

Enter numbers to enable (e.g., `1 3`), `all`, `none`, or `R` for a recommendation.
Unselected features will be removed. Type `? <number>` for details on any feature.
```

The full feature list (shown only for undecided features):

| Feature key | Display name | Description |
|-------------|-------------|-------------|
| nanoclaw | NanoClaw | Async gate decisions via Telegram/WhatsApp/Slack — useful at L3+ autonomy |
| compliance | Compliance | Regulatory traceability (EU Machinery Regulation, ISO 13485, IEC 62443) |
| publications | Publications | HTML article, slide deck, and dashboard templates |
| devcontainer | Dev Container | VS Code Codespace configuration for consistent dev environments |

- If `R` selected: greenfield → recommend `none` (add features when needed); brownfield → if compliance-related keywords in project description recommend `2`, if publications-related keywords recommend `3`.
- If `? <n>` (e.g., `? 1`): show the full feature description for that feature (below), then re-present the menu.
- **Do not ask about features individually.** Process all selections at once after the user responds.

Full feature descriptions (shown on `? <n>` request only):

<!-- module:nanoclaw -->
**NanoClaw — Async Gate Decisions**
NanoClaw routes gate decisions (approve/reject) to your phone via Telegram,
WhatsApp, or Slack. Useful at Autonomy Level 3+ when the agent works
asynchronously and you review from mobile.

Files included:
- docker-compose.nanoclaw.yml
- .forge/adapters/nanoclaw.sh
- .forge/bin/forge-configure-nanoclaw.sh / .ps1
- .forge/bin/forge-setup-nanoclaw.sh / .ps1
- .forge/templates/nanoclaw-skill.json
- .claude/commands/configure-nanoclaw.md
- .claude/commands/nanoclaw.md
<!-- /module:nanoclaw -->

<!-- module:compliance -->
**Compliance Profiles — Regulatory Traceability**
Adds a compliance framework for regulated industries: traceability matrices,
V&V reports, compliance cases, and change impact analysis. Includes profiles
for EU Machinery Regulation, ISO 13485, IEC 62443.

Files included:
- docs/compliance/ (all files in directory)
<!-- /module:compliance -->

<!-- module:publications -->
**Publications — Article & Deck Templates**
HTML templates for generating project articles, slide decks, metrics
dashboards, and showcase pages from project data.

Files included:
- docs/publications/ (all files in directory)
<!-- /module:publications -->

<!-- module:devcontainer -->
**Dev Container — Codespace Configuration**
VS Code dev container configuration for consistent development environments.

Files included:
- .devcontainer/ (all files in directory)
<!-- /module:devcontainer -->

**STOP — wait for user response before proceeding to step 15.**

15. [mechanical] Process the feature selection:
    - Parse the user's response: extract feature numbers selected (1–4).
    - For each selected feature: set toggle to `true` in onboarding.yaml → execute step 17.
    - For each unselected feature: set toggle to `false` in onboarding.yaml → execute step 16.
    - Features already decided (from a resumed session) keep their existing value — do not re-process.

16. [mechanical] For each feature with toggle set to `false` (not selected):

    a. Read the file list from `.forge/feature-files.yaml` for that feature.
    b. Delete each listed file or directory. For directory entries (paths ending with `/`), delete the entire directory recursively.
    c. Check `agents_md_sections` in the feature mapping. For each listed section name:
       - Open AGENTS.md (or AGENTS.md.jinja if that is the file present)
       - Find the section by searching for the heading text (## or ### level)
       - Remove the entire section (from its heading to the next heading of equal or higher level)
    d. Check `claude_md_sections` in the feature mapping. For each listed section name:
       - Open CLAUDE.md (or CLAUDE.md.jinja if that is the file present)
       - Find and remove the section the same way
    e. Set the feature toggle to `false` in `.forge/onboarding.yaml`
    f. Count the files deleted and report: `Removed: <feature name> (<count> files deleted)`

17. [mechanical] For each feature with toggle set to `true` (selected):
    a. Leave all files in place.
    b. Set the feature toggle to `true` in `.forge/onboarding.yaml`.
    c. Report: `Kept: <feature name> (no changes)`

18. [mechanical] Set `phases.features: complete` in `.forge/onboarding.yaml` and write the file.

19. Print:
    ```
    Phase 2 complete — Feature selection saved.
    ```

---

## [decision] Phase 3 — MCP Server Configuration

**Skip condition**: If `phases.mcp_servers` is `complete`, skip to Phase 4.

20. Read `.mcp.json` from the project root. If the file does not exist, skip to step 25.

21. Parse the JSON. Extract the `mcpServers` object. For each server key, collect:
    - Server name (the key)
    - Command and args
    - Description (if present)

### [decision] MCP informed-consent disclaimer (Spec 202)

22. Present a single informed-consent disclaimer followed by a binary enable/disable choice.
    **Do not prompt for each server individually.** Instead, present all servers and one decision:

    ```
    ## MCP Servers

    MCP (Model Context Protocol) servers extend the AI agent's capabilities by
    connecting it to external tools and data sources. They run as local processes
    on your machine.

    **What they do**: Provide the agent with access to documentation search,
    code context, database queries, API calls, or other specialized tools.

    **Why they're useful**: MCP servers let the agent perform tasks that require
    external data or services (e.g., looking up library docs, querying a database,
    searching the web) without you copy-pasting the information manually.

    **Risks to be aware of**:
    - MCP servers run commands on your machine with your user permissions
    - They may make network requests to external services
    - Misconfigured servers could expose sensitive data or credentials
    - Each server adds a background process that consumes resources

    The following MCP servers are configured for this project:

    | # | Server | Description | Command |
    |---|--------|-------------|---------|
    | 1 | <server-name> | <description or "No description"> | <command> |
    | 2 | <server-name> | <description or "No description"> | <command> |
    | ... | ... | ... | ... |

    **Enable MCP servers for this project?**
    - **enable** — Keep all listed servers active (recommended for full functionality)
    - **disable** — Remove all MCP servers (agent will work without external tool access)
    - **pick** — Choose which servers to keep (I'll show the list for selection)
    ```

    **STOP — wait for user response before proceeding.**

23. [mechanical] Process the MCP server decision:

    - If **enable**: keep all servers in `.mcp.json`. Record `mcp_servers.<name>: true` for each server in onboarding.yaml.
      For each server, check if it has environment variables that look like placeholders (contain `YOUR_`, `CHANGEME`, `TODO`, `<`, `>`). If so, note them for Phase 4.
    - If **disable**: remove all server entries from the `mcpServers` object in `.mcp.json`. Record `mcp_servers.<name>: false` for each in onboarding.yaml.
      Report: `Removed: all MCP servers from .mcp.json`
    - If **pick**: present the numbered server list and ask the user to enter numbers to keep (e.g., `1 3`).
      Keep selected servers, remove unselected. Record each accordingly in onboarding.yaml.
      For kept servers, check for placeholder environment variables as above.

24. [mechanical] After processing:
    - If `mcpServers` is now empty: delete `.mcp.json` entirely. Report: `Deleted: .mcp.json (no servers remaining)`
    - Otherwise: write the updated `.mcp.json` with proper JSON formatting (2-space indent).

25. [mechanical] Set `phases.mcp_servers: complete` in `.forge/onboarding.yaml` and write the file.

26. Print:
    ```
    Phase 3 complete — MCP server configuration saved.
    ```

---

## [decision] Phase 4 — Credentials & Environment

**Skip condition**: If `phases.credentials` is `complete`, skip to Phase 5.

27. [mechanical] Scan the project for files containing credential or configuration placeholders. Check:
    - `.env.example` or `.env.template` — list all lines with `=` that have placeholder-like values
    - `docker-compose*.yml` — look for environment variables with placeholder values
    - Any config files (`.json`, `.yaml`, `.yml`, `.toml`, `.ini`) containing patterns: `TODO`, `CHANGEME`, `YOUR_`, `<placeholder>`, `your-`, `-here`, `xxx`
    - Skip files in `node_modules/`, `.venv/`, `.git/`, `docs/`

28. If no placeholders found:
    ```
    ## Environment Setup
    No credential placeholders found. Skipping this phase.
    ```
    Set `phases.credentials: complete` in onboarding.yaml and jump to Phase 5.

29. If placeholders found, present them grouped by file:
    ```
    ## Environment Setup
    Found placeholders that may need your input:

    1. <filename>:
       - <KEY>=<placeholder value>
       - <KEY>=<placeholder value>

    2. <filename>:
       - <KEY>=<placeholder value>

    Would you like to:
    a) Set these values now (I'll create/update .env)
    b) Skip for now (you'll set them before running the project)
    c) Not applicable (this project doesn't use these services)
    ```

30. [decision] Based on the human's choice:

    **Choice a — Set values now:**
    - For each placeholder, ask: `Value for <KEY>? (or 'skip' to leave for later)`
    - Create or update `.env` file:
      - If `.env` exists, only add/update keys that don't already have non-placeholder values
      - If `.env` does not exist, create it with all provided values
    - Verify `.env` is listed in `.gitignore`. If not, append `.env` to `.gitignore`.
    - Record in onboarding.yaml `setup_tasks`:
      ```yaml
      setup_tasks:
        - file: .env
          keys_set: <count>
          keys_skipped: <count>
      ```
    - Report: `Updated: .env (<count> values set, <count> skipped)`

    **Choice b — Skip:**
    - Record in onboarding.yaml:
      ```yaml
      setup_tasks:
        - action: deferred
          placeholders_found: <count>
      ```
    - Report: `Skipped: environment setup (you'll need to configure before running)`

    **Choice c — Not applicable:**
    - Record in onboarding.yaml:
      ```yaml
      setup_tasks:
        - action: not_applicable
      ```
    - Report: `Noted: environment placeholders marked as not applicable`

31. [mechanical] Set `phases.credentials: complete` in `.forge/onboarding.yaml` and write the file.

32. Print:
    ```
    Phase 4 complete — Environment configuration saved.
    ```

---

## [mechanical] Phase 5 — Summary & Commit

**Skip condition**: If `phases.summary` is `complete`, skip (onboarding already done).

33. Read the final state of `.forge/onboarding.yaml`. Build and present the summary:

    ```
    ## Onboarding Complete

    Project: <project.name>
    Description: <project.description>
    Stack: <project.primary_stack>
    Test command: <project.test_command or "not set">
    Lint command: <project.lint_command or "not set">

    Features:
      NanoClaw: <enabled | disabled (N files removed)>
      Compliance: <enabled | disabled (N files removed)>
      Publications: <enabled | disabled (N files removed)>
      Dev Container: <enabled | disabled (N files removed)>

    MCP Servers:
      <server-name>: <enabled | removed>
      ...
      (or "No MCP servers configured" if .mcp.json was absent)

    Environment:
      <summary from setup_tasks, e.g., ".env: 3 values configured, 1 deferred" or "skipped" or "no placeholders found">
    ```

34. [decision] Ask: `Commit these onboarding changes? (yes / no)`

    - If **yes**:
      ```bash
      git add -A
      git commit -m "FORGE onboarding: configure project settings"
      ```
      Report: `Committed: FORGE onboarding changes`

    - If **no**:
      Report: `Changes left uncommitted. You can commit later when ready.`

35. [mechanical] Set `status: complete` and `phases.summary: complete` in `.forge/onboarding.yaml` and write the file.

36. Print a context-aware completion message:

    **If greenfield and stack is deferred (`deferred_stack: true`):**
    ```
    ## Onboarding complete — your project is ready

    ### What's next

    Requirements are still forming — `/interview` will surface unstated assumptions and
    help determine the optimal stack before spec ideation begins.

    | # | Action | Description |
    |---|--------|-------------|
    | **1** | `/interview` | **Recommended** — Build a PRD through guided discussion. Surfaces assumptions, clarifies scope, and generates your first specs. |
    | 2 | `/brainstorm` | Skip straight to spec ideation if direction is already clear |
    | 3 | `/now` | View project state and recommended actions |

    ### Keeping FORGE current

    Run `/forge stoke` periodically to pull the latest FORGE framework improvements
    into this project. This updates slash commands, process templates, and runtime
    scripts — it does not touch your project code or specs.

    ### Finding your way around

    your-project/
      CLAUDE.md           <- Start here — project rules and workflow
      AGENTS.md           <- Agent configuration and autonomy settings
      .claude/commands/   <- All slash commands (type / in chat to see them)
      .forge/             <- FORGE runtime (scripts, modules, templates)
      docs/
        specs/            <- Your specs live here
        sessions/         <- Session logs and signals
        process-kit/      <- Scoring rubric, runbooks, checklists
        backlog.md        <- Prioritized work queue

    See docs/QUICK-REFERENCE.md for all available commands grouped by workflow stage.
    ```

    **If greenfield and stack is confirmed (`deferred_stack: false` or not set, `primary_stack` is set):**
    ```
    ## Onboarding complete — your project is ready

    ### What's next

    Context is in place — `/brainstorm` will surface spec candidates from your project
    description and any early signals. Run `/interview` first if scope is still uncertain.

    | # | Action | Description |
    |---|--------|-------------|
    | **1** | `/brainstorm` | **Recommended** — Surface spec candidates from your project context |
    | 2 | `/interview` | Dig deeper into requirements if scope needs clarification |
    | 3 | `/now` | View project state and recommended actions |
    ```

    **If brownfield (mode is `legacy-upgrade` or `brownfield`):**
    ```
    ## Onboarding complete — your project is ready

    ### What's next

    Existing signals and structure can seed the spec backlog — `/brainstorm` will surface
    the highest-value work from what you already have. Run `/interview` if the problem
    space needs deeper exploration first.

    | # | Action | Description |
    |---|--------|-------------|
    | **1** | `/brainstorm` | **Recommended** — Scan existing signals and structure for spec opportunities |
    | 2 | `/interview` | Explore the problem space if requirements need clarification |
    | 3 | `/now` | Review project state and see what FORGE recommends |

    ### Keeping FORGE current

    Run `/forge stoke` periodically to pull the latest FORGE framework improvements
    into this project. This updates slash commands, process templates, and runtime
    scripts — it does not touch your project code or specs.

    ### Finding your way around

    your-project/
      CLAUDE.md           <- Start here — project rules and workflow
      AGENTS.md           <- Agent configuration and autonomy settings
      .claude/commands/   <- All slash commands (type / in chat to see them)
      .forge/             <- FORGE runtime (scripts, modules, templates)
      docs/
        specs/            <- Your specs live here
        sessions/         <- Session logs and signals
        process-kit/      <- Scoring rubric, runbooks, checklists
        backlog.md        <- Prioritized work queue

    See docs/QUICK-REFERENCE.md for all available commands grouped by workflow stage.
    ```

---

## Error handling

- If any file operation fails (file not found, permission denied), report the error and continue with the next step. Do not abort the entire onboarding.
- If `.forge/onboarding.yaml` cannot be written, report the error prominently — state cannot be saved, so resumability is compromised.
- If the human provides an ambiguous answer (not clearly yes/no), ask for clarification before proceeding.
