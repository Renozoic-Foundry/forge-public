---
name: configure
description: "Adjust any defaulted onboarding setting (stack, agents, autonomy, methodology, features, MCP servers)"
workflow_stage: lifecycle
---
# Framework: FORGE
# Configure — Post-onboarding advanced settings menu (Spec 266)

Adjusts any of the settings that were defaulted during `/onboarding`. Idempotent — safe to run at any time, regardless of onboarding status.

Reads current values from `.forge/onboarding.yaml`, presents a numbered menu, and routes to the matching configuration flow. Writes back to the same files `/onboarding` does (`.forge/onboarding.yaml`, `.claude/settings.json`, `CLAUDE.md`, `AGENTS.md`, `.copier-answers.yml`, `.mcp.json`).

> **Execution rule — one interaction at a time**: Each `[decision]` section is a discrete interaction point. Present the prompt, then **STOP and wait for the user's response** before advancing.

---

## [mechanical] Step 0 — Load current configuration

1. Read `.forge/onboarding.yaml`. If it does not exist, report:
   ```
   No onboarding state found. Run `/onboarding` first.
   ```
   Stop.

2. Extract current values for presentation in the menu.

---

## [decision] Step 1 — Main menu

Present the numbered menu with current values in brackets:

```
## Configure

| # | Setting               | Current value |
|---|-----------------------|---------------|
| 1 | Primary stack         | [<primary_stack or "deferred">] |
| 2 | Test command          | [<test_command or "not set">] |
| 3 | Lint command          | [<lint_command or "not set">] |
| 4 | AI coding agents      | [<comma-separated list from agents map>] |
| 5 | Autonomy level        | [L<N> — <name>] |
| 6 | Methodology           | [<methodology>] |
| 7 | Optional features     | [<comma-separated list of enabled features, or "none">] |
| 8 | MCP servers           | [<enabled | disabled | N configured>] |
| 9 | Project name & description | [<name> — <description>] |

Type a number to change that setting, `all` to walk through every setting, or `done` to exit.
```

**STOP — wait for the user's response.**

Dispatch based on response:
- `1` → Step 2a (Primary stack)
- `2` → Step 2b (Test command)
- `3` → Step 2c (Lint command)
- `4` → Step 2d (AI agents)
- `5` → Step 2e (Autonomy)
- `6` → Step 2f (Methodology)
- `7` → Step 2g (Features)
- `8` → Step 2h (MCP servers)
- `9` → Step 2i (Name & description)
- `all` → run Steps 2a through 2i in order, returning to the main menu at the end
- `done` → stop

After each sub-step completes, return to Step 1 (main menu).

---

### [decision] Step 2a — Primary stack

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
| 8 | Undecided — defer to /interview |
| 9 | Keep current ([<current>]) |

Choose (1-9, or type a framework name):
```

**STOP — wait for response.**

- If **7**: ask "What language/framework?" then record.
- If **8**: set `primary_stack: null`, `deferred_stack: true`.
- If **9**: no change.
- Otherwise: record the selected stack.

Write the value to `.forge/onboarding.yaml` under `project.primary_stack`. Return to main menu.

---

### [decision] Step 2b — Test command

```
Test command:
1. I have a preference (tell me what you'd like)
2. Use the default for <primary_stack>  (<proposed default>)
3. none — no test command
4. Keep current ([<current>])
```

**STOP — wait for response.**

- **1**: ask for the command.
- **2**: apply the conventional default (Python → `pytest -q`, TypeScript → `npm test`, Go → `go test ./...`, Rust → `cargo test`, Java → `mvn test`, C# → `dotnet test`).
- **3**: set to `null`.
- **4**: no change.

Write to `.forge/onboarding.yaml` under `project.test_command`. Return to main menu.

---

### [decision] Step 2c — Lint command

Same structure as 2b. Defaults: Python → `ruff check .`, TypeScript → `eslint src/`, Go → `golangci-lint run`, Rust → `cargo clippy`, Java → `mvn verify`, C# → `dotnet format --verify-no-changes`.

Write to `.forge/onboarding.yaml` under `project.lint_command`. Return to main menu.

---

### [decision] Step 2d — AI coding agents

```
Which AI coding agents does your team use? (select all that apply)

| # | Agent           | Current |
|---|-----------------|---------|
| 1 | Claude Code     | [<true/false>] |
| 2 | Cursor          | [<true/false>] |
| 3 | GitHub Copilot  | [<true/false>] |
| 4 | OpenAI Codex    | [<true/false>] |
| 5 | Cline           | [<true/false>] |
| 6 | Other / generic | [<true/false>] |

Enter numbers to enable (e.g., `1 3`), `keep` to leave unchanged.
```

**STOP — wait for response.**

Process selections, updating `.forge/onboarding.yaml` under `agents`. Then run `.forge/bin/forge-sync-commands.sh` to generate wrappers for the enabled agents. Return to main menu.

---

### [decision] Step 2e — Autonomy level

```
## Autonomy Level

| Level | Name                | What the agent can do |
|-------|---------------------|-----------------------|
| L0    | Full Manual         | Advise only — no file edits |
| L1    | Human-Gated         | Agent drives; human approves every gate |
| L2    | Supervised Autonomy | Agent auto-chains mechanical steps; human approves decisions |
| L3    | Trusted Autonomy    | Agent completes full spec cycle; human reviews async |
| L4    | Full Autonomy       | Agent end-to-end; human on exception only |

Current: [L<N>]

Choose a level (0-4, or `keep`):
```

**STOP — wait for response.**

Map level to permission mode:
- L0–L1 → `"defaultMode": "default"`
- L2 → `"defaultMode": "auto"`
- L3–L4 → `"defaultMode": "bypassPermissions"`

Update `.claude/settings.json` and `.forge/onboarding.yaml` (`project.autonomy_level`, `project.permission_mode`). Return to main menu.

---

### [decision] Step 2f — Methodology

```
## Development Methodology

| # | Methodology     | Example: /now header |
|---|-----------------|---------------------|
| 1 | Scrum           | "Daily standup" |
| 2 | SAFe            | "Iteration sync" |
| 3 | Kanban          | "Board review" |
| 4 | DevOps          | "Status check" |
| 5 | Safety-critical | "Safety status review" |
| 6 | None / Default  | "Project status" |

Current: [<methodology>]

Choose (1-6, or `keep`):
```

**STOP — wait for response.**

Write to `.forge/onboarding.yaml` (`project.methodology`) and update the `forge:` block in `AGENTS.md`. Return to main menu.

---

### [decision] Step 2g — Optional features

Read `.forge/feature-files.yaml`. Present all features with their current toggle state:

```
## Optional Features

| # | Feature       | Description | Current |
|---|---------------|-------------|---------|
| 1 | NanoClaw      | Async gate decisions via Telegram/WhatsApp/Slack — useful at L3+ | [<enabled/disabled>] |
| 2 | Compliance    | Regulatory traceability (EU Machinery, ISO 13485, IEC 62443) | [<enabled/disabled>] |
| 3 | Publications  | HTML article, slide deck, and dashboard templates | [<enabled/disabled>] |
| 4 | Dev Container | VS Code Codespace configuration | [<enabled/disabled>] |

Type numbers to toggle (e.g., `1 3`), `all`, `none`, or `keep`.
Type `? <number>` for details on any feature.
```

**STOP — wait for response.**

For each feature toggled to `true` where it was `false`: leave files in place (they may have been deleted if feature was previously disabled — re-run `/forge stoke` to restore). Set toggle `true`.

For each feature toggled to `false` where it was `true`: delete files listed in `.forge/feature-files.yaml`; remove corresponding sections from `AGENTS.md` / `CLAUDE.md` per `agents_md_sections` / `claude_md_sections`. Set toggle `false`.

Report each change with file counts, then return to main menu.

---

### [decision] Step 2h — MCP servers

Read `.mcp.json`. If absent, report: "No MCP servers configured. Consumer projects typically inherit `context7` and `fetch` from the FORGE template — run `/forge stoke` if expected." Return to main menu.

If present, list all servers with their pinned versions (Spec 284). For each server, read the vendored lockfile:
- For `context7` (npm): parse `.mcp-lock/npm/package-lock.json` → extract `packages['node_modules/@upstash/context7-mcp'].version` and first 8 chars of `.integrity`.
- For `fetch` (pip): parse `.mcp-lock/python/requirements.lock` → extract the `mcp-server-fetch==X.Y.Z` version and first 8 chars of the first `--hash=sha256:` value.
- If a lockfile is missing: mark the pin column as `UNPINNED — integrity cannot be verified` (persistent fail-closed surface).

```
## MCP Servers

MCP (Model Context Protocol) servers extend the AI agent with external tools
and data sources. They run as local processes with your user permissions and
may make network requests. Packages are hash-verified at activation time via
.mcp-lock/ — see docs/process-kit/mcp-pinning-policy.md.

| # | Server | Description | Pinned Version | Hash (prefix) |
|---|--------|-------------|----------------|---------------|
| 1 | <name> | <description> | <version or UNPINNED> | <first 8 chars or N/A> |
| 2 | <name> | <description> | <version or UNPINNED> | <first 8 chars or N/A> |

Options:
- `enable`  — keep all servers active
- `disable` — remove all servers from .mcp.json
- `pick`    — keep only the selected servers (enter numbers to keep)
- `keep`    — no change
```

**STOP — wait for response.**

Process the decision:
- **enable**: ensure all servers remain in `.mcp.json`; record `mcp_servers.<name>: true` for each.
- **disable**: remove all entries from `mcpServers`; write the file. If `mcpServers` becomes empty, delete `.mcp.json`. Record `mcp_servers.<name>: false` for each.
- **pick**: keep numbered servers, remove the rest, write the updated file; record per-server state.
- **keep**: no change.

For kept servers, scan their env vars for placeholders (`YOUR_`, `CHANGEME`, `TODO`, `<`, `>`) and note any in `.forge/onboarding.yaml` under `setup_tasks`.

Return to main menu.

---

### [decision] Step 2i — Name and description

```
Project identity:
  name:        [<current name>]
  description: [<current description>]

Enter new values in the form `<name> — <description>`, or `keep` to leave unchanged.
```

**STOP — wait for response.**

Write to `.forge/onboarding.yaml` under `project.name` / `project.description`. Update CLAUDE.md first H1 and description. Update `.copier-answers.yml` (`project_name`, `project_slug`, `project_description`). Return to main menu.

---

## [mechanical] Step 3 — Exit

When the user types `done` at the main menu:

1. Write the final `.forge/onboarding.yaml`.
2. If any `AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, `.mcp.json`, or `.copier-answers.yml` writes occurred this session, offer:
   ```
   Commit configuration changes? (yes / no)
   ```
   - **yes**: `git add -A && git commit -m "FORGE configure: update project settings"`.
   - **no**: leave uncommitted.

3. Report:
   ```
   Configuration saved. Run `/configure` again any time to adjust further.
   ```

---

## Error handling

- File operations that fail (permission, not found): report, skip that sub-step, continue.
- `.forge/onboarding.yaml` write failure: prominently report — subsequent runs will lose the changes made this session.
- Ambiguous response at any menu: re-present the menu, do not assume a default.
