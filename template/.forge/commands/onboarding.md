---
name: onboarding
description: "First-session interactive project configuration"
workflow_stage: lifecycle
---
# Framework: FORGE
# Onboarding — Fast-path project configuration (Spec 266, staged writes + mature-repo detection added by Spec 315)

This command configures your FORGE-bootstrapped project with sensible defaults. Core onboarding is 2 interactions. Every defaulted setting is adjustable afterward via `/configure`.

**Resumability**: The flow reads `.forge/onboarding.yaml`. If the file already records `status: complete`, this command stops. If it records a partially-populated project state (e.g., name already set), the matching prompt is skipped.

**Trigger**: AGENTS.md instructs every agent to check `.forge/onboarding.yaml` on session start. If `status: pending` or `status: in-progress`, execute this flow before any other work.

> **Execution rule — one interaction at a time**: Each `[decision]` section is a discrete interaction point. Present the prompt, then **STOP and wait for the user's response** before advancing.

> **Safety rule (Spec 315)**: All Step B writes go to a staging directory before any commit prompt. Answering "no" leaves the working tree pristine. Answering "yes" applies staged files atomically with halt-on-failure semantics.

---

## [mechanical] Step 0 — Mature-repo detection (Spec 315)

Before any state load, check whether this repo is already past onboarding's intended scope. If three independent signals agree (any 2-of-3), short-circuit to `/configure` and skip the write path entirely.

**Heuristic 1 — Spec corpus**: count files in `docs/specs/` whose `Status:` frontmatter is `closed` OR `implemented`. Ignore `_template.md`, `_template-light.md`, `README.md`, `CHANGELOG.md`. Threshold: **≥ 20** matching files → signal fires.

**Heuristic 2 — Copier provenance**: read `.copier-answers.yml`. If absent → signal does not fire. Otherwise:
  - Confirm `_commit:` is a 40-character lowercase hex SHA. Confirm `_src_path:` is a non-empty string. Both required.
  - **Online validation (preferred)**: if FORGE template is locally accessible (`_src_path` resolves to a path with a `.git/` directory, or to a recognized FORGE template URL — see allowlist in `docs/process-kit/onboarding-recovery.md` § "Recognized template sources"), attempt `git -C <template-path> cat-file -e <commit>`. If exit 0 → signal fires.
  - **Structural fallback (offline / disconnected setup)**: if the template's commit graph is not consultable (air-gapped, no network, no local clone), accept the structural-only check (40-hex SHA + non-empty `_src_path`). Document as advisory: this fallback reduces forgery cost to single-signal in offline scenarios. Operators in air-gapped environments treat the mature-repo skip as advisory and verify manually.
  - **Local-path `_src_path`**: paths like `c:/Code/local/forge`, `/home/user/code/forge`, or any non-URL filesystem path are accepted under the structural fallback regardless of online/offline status (FORGE-developer test repos use this pattern). The 2-of-3 combining rule still requires another signal to agree.

**Heuristic 3 — Customized CLAUDE.md**: read `CLAUDE.md`. If absent → signal does not fire. Otherwise signal fires if either:
  - File contains a heading `# Model override` (operator-specific configuration), OR
  - Byte size > 2× the template default (`template/CLAUDE.md.jinja` rendered baseline; if the rendered baseline is unavailable, use 8 KB as the conservative threshold — most consumer customizations push past 8 KB quickly).

**Combining rule**: signal count ≥ 2 → repo is **mature**. The 2-of-3 threshold raises the forgery cost from "edit one file" (single-signal) to "produce a 20-spec corpus AND match a commit-graph-resolvable SHA" (or equivalent two-signal forgery). Threat model documented in Spec 315 § Scope. Strict 3-of-3 was rejected because it excludes legitimate consumer projects that customize CLAUDE.md but haven't yet built a 20-spec corpus.

### Mature path — auto-completion

If the combining rule fires:

1. Read `.forge/onboarding.yaml`. Ensure top-level `status:` is set to `complete`. Append the comment line `# Auto-set by mature-repo detection (Spec 315) on YYYY-MM-DD` (use today's date; UTC).
2. Write `.forge/onboarding.yaml`. **No other file is touched on this path.**
3. Print the auto-completion exit message:

   ```
   ## Onboarding skipped — mature repo detected

   Signals matched (any 2-of-3):
     [<spec count>] closed/implemented specs in docs/specs/
     [<provenance>] .copier-answers.yml _commit resolved (or structural fallback for offline)
     [<custom>] CLAUDE.md customization beyond template defaults

   `.forge/onboarding.yaml` set to `status: complete`. No other file was modified.

   Run `/configure` to adjust any defaulted setting.

   ### If detector fired incorrectly

   To revert: edit .forge/onboarding.yaml — set status to pending and remove the
   `# Auto-set by mature-repo detection` comment. Or run `/forge init` to restart.
   See docs/process-kit/onboarding-recovery.md for full recovery procedure.
   ```
4. Stop.

If the combining rule does NOT fire, fall through to Step 0.5 below (full onboarding flow).

---

## [mechanical] Step 0.5 — Pre-existing staging-directory check (Spec 315 Req 11)

Before loading state, check if `.forge/state/onboarding-staging/` exists from a prior incomplete session.

If the directory does **not** exist: proceed to Step 1.

If the directory **exists**:

1. Read `.forge/state/onboarding-staging/.manifest.sha256` if present. Extract the timestamp comment line (`# staged: <ISO-8601-UTC>`). Compute hours-since-staging.
2. **Stale-staging warning threshold (Req 14)**: if hours-since-staging > 24, prepend the prompt below with the warning text: `⚠ Staging directory is from <N> hours ago — likely abandoned. Recommend "discard-and-restart".` (Threshold is fixed at 24h; no configuration knob.)
3. **Manifest integrity check (Req 12)**: for each staged file in the manifest, recompute its sha256 using the LF-normalized byte stream protocol (see § Cross-platform hashing protocol below). If any hash mismatches the manifest entry, OR if the manifest is absent when staged files exist, prepend a hard warning: `⚠ Manifest integrity check FAILED: <file>: expected <hash>, got <hash>. Staged content may have been tampered with.`
4. Present the two-option prompt:

   ```
   Pre-existing staging directory found at .forge/state/onboarding-staging/
   <stale warning if applicable>
   <integrity warning if applicable>

   Choose:
   1. inspect-resume — show diff between staged content and current working-tree, then re-prompt accept/decline
   2. discard-restart — remove staging directory and start onboarding from Step 0
   ```

   **STOP — wait for response.**

5. **inspect-resume path**:
   - For each staged file in the manifest, present a diff between the staged content and the current working-tree counterpart. If no working-tree file exists at the target path, label as `(would be created — no current file)`. Showing only the staged content alone is forbidden — operators cannot judge benign vs adversarial without the diff.
   - **If integrity check failed**: do NOT proceed to the standard accept/decline. Force the explicit choice: `discard-restart` or `proceed-despite-tampering`. There is no silent-trust path. Record the operator's choice in `.forge/onboarding.yaml` under `setup_tasks` for audit.
   - After the operator reviews the diffs, present the standard commit prompt (see § Interaction 2).
6. **discard-restart path**:
   - Remove `.forge/state/onboarding-staging/` recursively (and its manifest).
   - Continue to Step 1 (full onboarding flow from the beginning).

### Cross-platform hashing protocol (Req 12, CTO round-3 specification)

All staged-file hashes are computed over the **LF-normalized byte stream** of each file, NOT over the file's native bytes. This prevents false-positive tampering warnings when a staging directory is written on one platform and resumed on another (CRLF on Windows vs LF on Unix).

**Normalization rules** (apply in this order):
1. Strip UTF-8 BOM if present (bytes `EF BB BF` at offset 0).
2. Replace every `CR LF` (`0x0D 0x0A`) with `LF` (`0x0A`).
3. Replace every remaining bare `CR` (`0x0D`) with `LF` (`0x0A`).
4. Do NOT enforce a trailing newline — observe whatever the source had after CR-stripping. Files lacking a final LF stay that way; this preserves source fidelity.

**Bash / Unix recipe**:
```bash
# Strip BOM, then CRLF→LF→strip-bare-CR, then sha256
sed '1s/^\xEF\xBB\xBF//' "$file" | sed 's/\r$//' | tr -d '\r' | sha256sum | awk '{print $1}'
```

**PowerShell / Windows recipe** (the concrete one-liner — DO NOT use `Get-FileHash` directly on the file; that hashes native line endings):
```powershell
$bytes = [System.IO.File]::ReadAllBytes($file)
# Strip BOM
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
  $bytes = $bytes[3..($bytes.Length - 1)]
}
# Decode as UTF-8, normalize line endings, re-encode
$text = [System.Text.Encoding]::UTF8.GetString($bytes)
$normalized = $text -replace "`r`n","`n" -replace "`r","`n"
$normBytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
$sha = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha.ComputeHash($normBytes)
$hex = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
$sha.Dispose()
$hex
```

The hex digest is **lowercase** on both platforms.

**Manifest format**:
```
<sha256-hex>  <relative-path>
<sha256-hex>  <relative-path>
# staged: 2026-04-28T01:30:00Z
```
Two-space separator (matches `sha256sum` convention). Timestamp is a comment line at the end; not hashed (informational only). The manifest itself is not self-hashed — see Spec 315 § Verification Scope (c) for the coordinated-tampering residual.

---

## [mechanical] Step 1 — Load state and detect project type

1. **Snapshot pre-session yaml state (Spec 315 Req 8)**: before any write, read `.forge/onboarding.yaml` and cache the exact bytes (or record "no yaml existed" if the file is absent). Cache lives in memory for the duration of this session; on a "no" decision at Interaction 2, the cached baseline is restored (delete if it didn't exist; overwrite with cached content if it did). This rollback is an operator-triggered restoration, not an active flip — the file's pre-session state is what it returns to, regardless of what that state was.

2. Read `.forge/onboarding.yaml`. If it does not exist, create it now with the initial seed:
   ```yaml
   status: pending
   project: {}
   features: {}
   agents: {}
   mcp_servers: {}
   ```
   (This seed is created by `/forge init` on a greenfield setup; the `/onboarding` flow only re-creates it as a fallback if the file is missing entirely.)

3. If `status: complete`: print "Onboarding already complete. Run `/configure` to adjust any setting." and stop. (Step 0 already short-circuits mature repos; this is the legacy already-complete path.)

4. Set `status: in-progress` and write the file.

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
| `compliance` | `false` | `true` if any keyword from Step 1.5 matched, else `false` |
| `publications` | `false` | `false` |
| `devcontainer` | `false` | `false` |

**MCP servers**: Read `.mcp.json`. For each server entry, record `mcp_servers.<name>: true` in `.forge/onboarding.yaml`. Do not modify `.mcp.json` — the servers stay enabled. For each kept server, check for placeholder environment variables (patterns: `YOUR_`, `CHANGEME`, `TODO`, `<`, `>`) and note them for Interaction 2.

`.forge/onboarding.yaml` is the only file modified before the commit prompt — it is the persistence record of the onboarding session itself, not a "real" working-tree write. All other writes are staged.

### [mechanical] Step B — Compute staged writes (Spec 315)

**This step computes intended file changes into a staging directory. NO file outside `.forge/onboarding.yaml` is written to its live location until the operator confirms at Interaction 2.**

1. Create `.forge/state/onboarding-staging/` if it does not exist. (If it does exist at this point, Step 0.5 already prompted the operator.)

2. For each target file below, compute the new content and write it to the staging directory at the **mirrored relative path** (e.g., staged CLAUDE.md goes to `.forge/state/onboarding-staging/CLAUDE.md`).

   **Targets**:
   - `CLAUDE.md` — find the first `# ` heading. If it matches a placeholder (`{{ project_name }}`, `My Project`, `PROJECT_NAME`, or a Copier default), replace with `project.name`. Same for the first paragraph after the H1 vs. `project.description`. Do not overwrite customized content.
   - `.claude/settings.json` — start from `{}` if absent, otherwise the existing content. Set `"defaultMode": "default"` (L1 autonomy default).
   - `AGENTS.md` — find the `forge:` config block. Set `forge.methodology: none` (preserve other fields).
   - `.copier-answers.yml` — if present, set `project_name`, `project_slug` (lowercase+hyphen), `project_description`, `test_command`, `lint_command`. Preserve `_commit` and `_src_path`. (Note: `_src_path` determines where `/forge stoke` pulls updates from — `gh:Renozoic-Foundry/forge-public` works from any machine; a local path only works on that machine.)
   - **Agent wrappers** (output of `.forge/bin/forge-sync-commands.sh`) — generate the wrappers into the staging directory's `.claude/commands/` and similar subdirs, NOT into the live tree. Reproducing the script's output deterministically into staging keeps Step B's contract: nothing goes live until "yes".

3. **Credential placeholder scan**: scan `.env.example`, `.env.template`, `docker-compose*.yml`, and config files for placeholder patterns (`TODO`, `CHANGEME`, `YOUR_`, `<...>`, `your-`, `-here`, `xxx`). Record any findings under `setup_tasks` in `.forge/onboarding.yaml`:
   ```yaml
   setup_tasks:
     - file: <filename>
       placeholders: [<KEY>, <KEY>]
   ```
   Placeholders are reported in the Interaction 2 summary and handled in `/configure` later.

4. **Compute feature-file deletion list**: for each feature set to `false` in `.forge/onboarding.yaml`, read `.forge/feature-files.yaml` for that feature's file list. Record the list of files-to-delete in `.forge/state/onboarding-staging/.deletion-plan.txt` (one path per line). Also record the AGENTS.md / CLAUDE.md sections to remove (per `agents_md_sections` / `claude_md_sections` in the feature mapping). Files-to-delete are NOT yet deleted — that happens in the atomic-apply phase.

5. **Write integrity manifest** at `.forge/state/onboarding-staging/.manifest.sha256`. For each staged file (everything under `.forge/state/onboarding-staging/` EXCEPT the manifest itself and the deletion-plan), compute the LF-normalized sha256 (see § Cross-platform hashing protocol). Write one line per file: `<hash>  <relative-path>`. Append a final timestamp comment: `# staged: <ISO-8601-UTC>`.

---

## [mechanical] Interaction 2 — Summary and commit

Read `.forge/onboarding.yaml` AND read the staged files in `.forge/state/onboarding-staging/` (NOT the live working tree — staged content is what will be applied). Render the summary:

```
## Configuration summary (staged — not yet applied)

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

Staged files (review before accept):
  <list of files in .forge/state/onboarding-staging/, with byte-size>
  Files to delete (feature pruning):
  <list from .deletion-plan.txt, or "none">

All settings above can be changed with `/configure`.
```

### [decision] Commit prompt

Ask:
```
Apply these staged onboarding changes? (yes / no)
```

**STOP — wait for response.**

- **yes** — atomic application with halt-on-failure (Spec 315 Req 10):

  Apply staged files to the live working tree in this **dependency order** — yaml/answers files first (other files may reference them), then command-mirror files (sync wrappers), then top-level operator-visible docs (CLAUDE.md, AGENTS.md):

  1. `.copier-answers.yml`
  2. `.claude/settings.json`
  3. Sync-wrapper command files under `.claude/commands/` (and other agent subdirs as applicable)
  4. AGENTS.md
  5. CLAUDE.md
  6. Feature-file deletions per `.deletion-plan.txt` (last — they remove content; do them after all writes succeed)

  **Halt-on-failure rule**: on any per-file write failure (disk full, permission denied, lock contention, integrity mismatch on re-read), application HALTS at that file. Subsequent staged files are NOT written. The operator sees a partial-state report:

  ```
  ⚠ Atomic application halted at <file>: <error>
  Files applied (in order): <list>
  Files pending: <list>
  Staging directory PRESERVED at .forge/state/onboarding-staging/ for inspection.

  To continue: re-run /onboarding — the inspect-resume / discard-restart prompt will fire.
  See docs/process-kit/onboarding-recovery.md § "Partial-failure resumption".
  ```

  The staging directory is **preserved** on partial failure — do not remove it.

  On full success (all files applied, all deletions done):
  ```bash
  git add -A
  git commit -m "FORGE onboarding: configure project settings"
  ```
  Remove the staging directory: `rm -rf .forge/state/onboarding-staging/`.

  Report: `Committed: FORGE onboarding changes`.

- **no** — discard staging cleanly:

  Remove `.forge/state/onboarding-staging/` recursively. The working tree was never modified beyond `.forge/onboarding.yaml`. **Restore `.forge/onboarding.yaml` to its pre-session baseline** using the snapshot cached at Step 1.1: if the snapshot recorded "no yaml existed", delete the file; if the snapshot recorded prior content, overwrite the live file with the cached bytes. This is an operator-triggered restoration, not a fresh write of any specific status value — whatever was there before is what is there after. Verify with `git status`: zero modifications should appear after rollback.

  Report: `Onboarding declined. Staging discarded; working tree pristine. Re-run /onboarding to retry.`

### [mechanical] Step C — Mark complete and hand off

Set `status: complete` in `.forge/onboarding.yaml` and write the file. (This runs only on the "yes" path — declined sessions are restored to their pre-session baseline at the "no" branch above.)

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

- If any file operation fails (file not found, permission denied), report the error and continue with the remaining steps. **Exception**: atomic-application halt-on-failure (Spec 315 Req 10) overrides — when applying staged writes after "yes", a per-file failure HALTS application; the staging directory is preserved.
- If `.forge/onboarding.yaml` cannot be written, report prominently — resumability is compromised.
- If the user provides an ambiguous answer at either interaction, ask for clarification before proceeding.
- If `.forge/state/onboarding-staging/` cannot be created or written (Step B), abort with a clear error before reaching Interaction 2 — do not fall back to live writes.
