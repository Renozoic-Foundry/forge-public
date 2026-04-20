---
name: onboarding
description: "First-session interactive project configuration"
model_tier: sonnet
workflow_stage: lifecycle
---
# Framework: FORGE
# Onboarding — Fast-path project configuration (Spec 266)

This command configures your FORGE-bootstrapped project with sensible defaults. Core onboarding is 2 interactions. Every defaulted setting is adjustable afterward via `/configure`.

**Resumability**: The flow reads `.forge/onboarding.yaml`. If the file already records `status: complete`, this command stops. If it records a partially-populated project state (e.g., name already set), the matching prompt is skipped.

**Trigger**: AGENTS.md instructs every agent to check `.forge/onboarding.yaml` on session start. If `status: pending` or `status: in-progress`, execute this flow before any other work.

> **Execution rule — one interaction at a time**: Each `[decision]` section is a discrete interaction point. Present the prompt, then **STOP and wait for the user's response** before advancing.

---

## [mechanical] Step 0 — Load state and detect project type

1. Read `.forge/onboarding.yaml`. If it does not exist, create it with:
   ```yaml
   status: pending
   project: {}
   features: {}
   agents: {}
   mcp_servers: {}
   ```

2. If `status: complete`: print "Onboarding already complete. Run `/configure` to adjust any setting." and stop.

3. Set `status: in-progress` and write the file.

4. **Greenfield detection**: List `docs/specs/`. Ignore `_template.md`, `_template-light.md`, `README.md`, `CHANGELOG.md`. If no spec files remain, this is a **greenfield** project. Otherwise **brownfield**.

5. **Brownfield auto-detection** (only runs if brownfield): scan the project for existing configuration to pre-populate fields. Detection sources:

   | Field | Detection sources (check in order) |
   |-------|-----------------------------------|
   | name | `package.json:name`, `pyproject.toml:project.name`, `Cargo.toml:package.name`, `go.mod` module (last segment), `README.md` first H1, git remote URL (last path segment), directory name (fallback) |
   | description | `package.json:description`, `pyproject.toml:project.description`, `Cargo.toml:package.description`, `README.md` first paragraph after H1 |
   | primary_stack | `.py` → Python, `.ts`/`.tsx` → TypeScript, `.go` → Go, `.rs` → Rust, `.java` → Java; `pyproject.toml` → Python, `package.json` → Node/TypeScript, `Cargo.toml` → Rust, `go.mod` → Go |
   | test_command | `package.json:scripts.test`, `pyproject.toml:tool.pytest` → `pytest -q`, `Cargo.toml` → `cargo test`, `go.mod` → `go test ./...` |
   | lint_command | `package.json:scripts.lint`, `.eslintrc*` → `eslint src/`, `pyproject.toml:tool.ruff` → `ruff check .`, `Cargo.toml` → `cargo clippy` |
   | compliance signal | Keyword-scan the detected description against: `compliance`, `regulatory`, `FDA`, `ISO 13485`, `ISO 9001`, `HIPAA`, `GDPR`, `safety-critical`, `61508`, `13485`, `62443`. Any match → suggest `features.compliance: true`. |

   Record each detected value in `.forge/onboarding.yaml` under `project`. Missing values stay absent.

6. Print a short greeting:
   ```
   ## FORGE Onboarding
   Two quick confirmations and you're done. Every default below can be changed later via `/configure`.
   ```

---

## [decision] Interaction 1 — Project identity

**Skip condition**: If `project.name` AND `project.description` are both already populated in `.forge/onboarding.yaml`, skip to Interaction 2 silently.

### Greenfield path

If greenfield, present:
```
What is the project name and a one-sentence description?

(You can answer in any format — e.g., "MyApp — a team scheduling tool" or answer them separately.)
```

### Brownfield path — both detected

If brownfield and both `name` and `description` were detected:
```
Detected:
  name:        <detected name>  (from <source>)
  description: <detected description>  (from <source>)

Accept both? (yes / change)
```
- **yes**: proceed to Interaction 2.
- **change**: ask for the replacement values, then proceed to Interaction 2.

### Brownfield path — partial detection

If brownfield and only some fields detected, combine detected + missing into a single prompt:
```
Detected:
  <field>: <value>  (from <source>)

Still needed:
  <missing field>: ?

Reply with the missing value(s), or paste a complete "<name> — <description>" line.
```

**STOP — wait for the user's response before advancing to Interaction 2.**

### [mechanical] Step A — Persist identity

After the user responds, write to `.forge/onboarding.yaml`:
```yaml
project:
  name: <value>
  description: <value>
```

Apply defaults silently for all remaining fields:

| Field | Greenfield | Brownfield |
|-------|------------|------------|
| `primary_stack` | `null` (deferred — use `/interview` later) | Auto-detected value (or `null` if none) |
| `test_command` | `null` | Auto-detected (or `null`) |
| `lint_command` | `null` | Auto-detected (or `null`) |
| `autonomy_level` | `L1` | `L1` |
| `permission_mode` | `default` | `default` |
| `methodology` | `none` | `none` |
| `deferred_stack` | `true` | `false` (if stack detected) / `true` (otherwise) |

Write `.forge/onboarding.yaml` with these values. Set `agents` to:
```yaml
agents:
  claude_code: true
  cursor: false
  copilot: false
  codex: false
  cline: false
```

Set `features`:

| Feature | Greenfield | Brownfield |
|---------|------------|------------|
| `nanoclaw` | preserve existing value (org policy may have pre-set `false`); otherwise `false` | same |
| `compliance` | `false` | `true` if any keyword from Step 0.5 matched, else `false` |
| `publications` | `false` | `false` |
| `devcontainer` | `false` | `false` |

**MCP servers**: Read `.mcp.json`. For each server entry, record `mcp_servers.<name>: true` in `.forge/onboarding.yaml`. Do not modify `.mcp.json` — the servers stay enabled. For each kept server, check for placeholder environment variables (patterns: `YOUR_`, `CHANGEME`, `TODO`, `<`, `>`) and note them for Interaction 2.

### [mechanical] Step B — Write CLAUDE.md, AGENTS.md, settings, copier answers

Apply identity + defaults to the standard target files:

1. **CLAUDE.md**: find the first `# ` heading. If it matches a placeholder (`{{ project_name }}`, `My Project`, `PROJECT_NAME`, or a Copier default), replace with `project.name`. Same for the first paragraph after the H1 vs. `project.description`. Do not overwrite customized content.

2. **`.claude/settings.json`**: create with `{}` if absent. Set `"defaultMode": "default"` (L1 autonomy default). Write the file.

3. **AGENTS.md**: find the `forge:` config block. Set:
   ```yaml
   forge:
     methodology: none
   ```

4. **`.copier-answers.yml`**: if present, set `project_name`, `project_slug` (lowercase+hyphen), `project_description`, `test_command`, `lint_command`. Preserve `_commit` and `_src_path`.

   **Note — `/forge stoke` upstream source**: `_src_path` determines where `/forge stoke` pulls updates from. If bootstrapped from `gh:Renozoic-Foundry/forge-public`, stoke works from any machine. If a local path, stoke only works on that machine.

5. **Agent wrappers**: run `.forge/bin/forge-sync-commands.sh` to generate wrappers for the enabled agents (currently just Claude Code).

6. **Credential placeholder scan**: scan `.env.example`, `.env.template`, `docker-compose*.yml`, and config files for placeholder patterns (`TODO`, `CHANGEME`, `YOUR_`, `<...>`, `your-`, `-here`, `xxx`). Record any findings under `setup_tasks` in `.forge/onboarding.yaml`:
   ```yaml
   setup_tasks:
     - file: <filename>
       placeholders: [<KEY>, <KEY>]
   ```
   Do not prompt — placeholders are reported in the Interaction 2 summary and handled in `/configure` later.

---

## [mechanical] Interaction 2 — Summary and commit

Read the current `.forge/onboarding.yaml` and render the summary:

```
## Configuration summary

Project:          <name>
Description:      <description>
Stack:            <primary_stack or "deferred — set via /configure or /interview">
Test command:     <test_command or "not set">
Lint command:     <lint_command or "not set">

AI agents:        Claude Code
Autonomy:         L1 (Human-Gated)
Permission mode:  default
Methodology:      none

Features:
  NanoClaw:       <enabled | disabled>
  Compliance:     <enabled | disabled>  <auto-detected if brownfield match>
  Publications:   <enabled | disabled>
  Dev Container:  <enabled | disabled>

MCP servers:
  <server>:       enabled
  <server>:       enabled
  (or "none configured" if .mcp.json absent or empty)

Setup tasks:
  <file>:         <N placeholder(s) to fill later>
  (or "none detected")

All settings above can be changed with `/configure`.
```

### [decision] Commit prompt

Ask:
```
Commit these onboarding changes? (yes / no)
```

**STOP — wait for response.**

- **yes**:
  1. **Feature-file pruning**: for each feature set to `false` in `.forge/onboarding.yaml`, read `.forge/feature-files.yaml` for that feature's file list and delete the files. Remove the corresponding sections from AGENTS.md and CLAUDE.md per `agents_md_sections` / `claude_md_sections` in the feature mapping. Features set to `true` keep their files.
  2. Commit:
     ```bash
     git add -A
     git commit -m "FORGE onboarding: configure project settings"
     ```
  Report: `Committed: FORGE onboarding changes`.

- **no**:
  Leave the disk pristine — no feature-file pruning, no section removals. The user can re-run `/onboarding` and see the same choices.
  Report: `Changes left uncommitted. Commit manually when ready.`

### [mechanical] Step C — Mark complete and hand off

Set `status: complete` in `.forge/onboarding.yaml` and write the file.

Print the context-aware completion message:

### Greenfield with deferred stack

```
## Onboarding complete — your project is ready

### What's next

Requirements are still forming — `/interview` will surface unstated assumptions and
help determine the optimal stack before spec ideation begins.

| # | Action | Description |
|---|--------|-------------|
| **1** | `/interview` | **Recommended** — Build a PRD through guided discussion. Surfaces assumptions, clarifies scope, and generates your first specs. |
| 2 | `/brainstorm` | Skip straight to spec ideation if direction is already clear |
| 3 | `/configure` | Adjust any defaulted setting (stack, test, lint, autonomy, methodology, features, MCP servers) |
| 4 | `/now` | View project state and recommended actions |

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

### Greenfield with stack detected

```
## Onboarding complete — your project is ready

### What's next

Context is in place — `/brainstorm` will surface spec candidates from your project
description and any early signals. Run `/interview` first if scope is still uncertain.

| # | Action | Description |
|---|--------|-------------|
| **1** | `/brainstorm` | **Recommended** — Surface spec candidates from your project context |
| 2 | `/interview` | Dig deeper into requirements if scope needs clarification |
| 3 | `/configure` | Adjust any defaulted setting |
| 4 | `/now` | View project state and recommended actions |
```

### Brownfield

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
| 3 | `/configure` | Adjust any defaulted setting (stack, test, lint, autonomy, methodology, features, MCP servers) |
| 4 | `/now` | Review project state and see what FORGE recommends |

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

- If any file operation fails (file not found, permission denied), report the error and continue with the remaining steps. Do not abort the entire onboarding.
- If `.forge/onboarding.yaml` cannot be written, report prominently — resumability is compromised.
- If the user provides an ambiguous answer at either interaction, ask for clarification before proceeding.
