# Framework: FORGE
## Subcommand: stoke

> **Note (Spec 131):** Also accessible as `/forge stoke` (subcommand of `/forge`).

> Pull upstream FORGE updates into this project using Copier. Handles migration from Cruft if needed.
>
> **Chicken-and-egg note**: If `forge.md` itself is missing from your project (so you can't run `/forge stoke`), copy it manually first:
> ```bash
> FORGE_TMP="${TMPDIR:-${TEMP:-/tmp}}/forge-rescue"
> python -m copier copy <template-path> "$FORGE_TMP" --defaults
> mkdir -p .claude/commands
> cp "$FORGE_TMP/.claude/commands/forge.md" .claude/commands/forge.md
> rm -rf "$FORGE_TMP"
> ```
> Then run `/forge stoke` to restore all remaining files.

### [mechanical] Step 0a — Dirty working tree check (Spec 166)

Before any update operations, check for uncommitted changes:

1. Run `git status --porcelain` in the project directory.
2. If output is non-empty (dirty working tree):
   - Warn: "**Uncommitted changes detected.** Running stoke on a dirty working tree risks merge conflicts and lost changes. Recommend: commit or stash your changes first."
   - Present options:
     - **commit** — run `git add -A && git commit -m "Pre-stoke checkpoint"` then proceed
     - **proceed** — continue anyway (not recommended)
     - **abort** — stop stoke
   - If the user selects **abort**, stop. Otherwise, proceed to Step 0b.
3. If working tree is clean: proceed silently to Step 0a+.

### [decision] Step 0a+ — Template version drift and yank check (Spec 291)

After the dirty-tree check and before the expensive template render in Step 0b, detect whether this project is behind the latest `forge-public` tag. A MAJOR-drift block aborts here so we never do render work that will be thrown away.

1. **Skip conditions**:
   - If `.copier-answers.yml` does not exist: skip (bootstrap/rescue path — drift is N/A).
   - If `_commit` is empty or malformed: emit diagnostic "Drift check: `_commit` missing or malformed in `.copier-answers.yml` — skipping version drift detection." Proceed to Step 0b.

2. **Detect `--allow-major` flag** in the `/forge stoke` invocation. Set `ALLOW_MAJOR=1` if present; otherwise `ALLOW_MAJOR=0`.

3. **Resolve consumer version**. Read `_commit` from `.copier-answers.yml`:
   - If `_commit` matches `^v[0-9]+\.[0-9]+\.[0-9]+$` (already a tag): set `CONSUMER_TAG=$_commit`.
   - Else (SHA): attempt tag resolution:
     ```bash
     REPO="Renozoic-Foundry/forge-public"
     CONSUMER_TAG=""
     if command -v gh >/dev/null 2>&1; then
       CONSUMER_TAG=$(gh api "repos/$REPO/git/refs/tags" --paginate --jq '.[] | .ref + " " + .object.sha' 2>/dev/null \
         | awk -v c="$_commit" '$2 == c {sub(/refs\/tags\//,"",$1); print $1; exit}')
     fi
     ```
     If resolution fails: emit warning "Drift check: could not resolve `_commit` (`$_commit`) to a tagged version — proceeding without drift classification. Consider reinstalling via `/forge-bootstrap` to pin to a tagged release." Proceed to Step 0b.

4. **Resolve latest forge-public tag**:
   ```bash
   LATEST_TAG=""
   if command -v gh >/dev/null 2>&1; then
     LATEST_TAG=$(gh api "repos/$REPO/releases/latest" --jq '.tag_name' 2>/dev/null || true)
   fi
   if [ -z "$LATEST_TAG" ]; then
     LATEST_TAG=$(git ls-remote --tags --refs --sort='-v:refname' "https://github.com/$REPO" 2>/dev/null \
       | awk '{print $2}' | sed 's|refs/tags/||' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)
   fi
   ```
   If still empty: emit diagnostic "Drift check: unable to reach forge-public to resolve latest tag — network unreachable or repo inaccessible. Run `/forge stoke` again when network is available to verify you're on latest." Proceed to Step 0b.

5. **Semver compare** `CONSUMER_TAG` vs `LATEST_TAG` (strip leading `v`; split on `.`; compare MAJOR, MINOR, PATCH as integers):
   - Equal, or consumer ahead → report "Drift check: on latest (`$CONSUMER_TAG`)." Proceed to Step 0b.
   - MAJOR delta == 0, consumer behind on MINOR or PATCH → emit warning and proceed:
     ```
     ⚠ Template drift: project is on $CONSUMER_TAG, latest is $LATEST_TAG.
     Changes in this window are additive (MINOR/PATCH) per forge-public's versioning contract.
     Proceeding with stoke. See forge-public CHANGELOG for release notes.
     ```
   - MAJOR delta ≥ 1 → if `ALLOW_MAJOR=1`, emit warning and proceed; otherwise BLOCK:
     ```
     ⛔ MAJOR TEMPLATE DRIFT — project ($CONSUMER_TAG) is <delta> major version(s) behind latest ($LATEST_TAG).

     A MAJOR bump indicates breaking changes to at least one of:
       • Surface 1 — copier.yml variables
       • Surface 2 — slash-command names or arguments
       • Surface 3 — .forge/templates/project-schema.yaml

     Review the breaking changes before upgrading:
       https://github.com/Renozoic-Foundry/forge-public/blob/main/docs/specs/CHANGELOG.md
     (entries between $CONSUMER_TAG and $LATEST_TAG)

     To proceed with the MAJOR upgrade:
       /forge stoke --allow-major

     Aborting stoke.
     ```
     Stop.

6. **Yank check** (Spec 291 Req 1 rollback/yank policy): fetch the forge-public CHANGELOG and parse the `## Yanked Tags` section to catch consumers pinned to a yanked tag.
   ```bash
   FORGE_TMP_YANK="${TMPDIR:-${TEMP:-/tmp}}/forge-yank-check"
   mkdir -p "$FORGE_TMP_YANK" && chmod 700 "$FORGE_TMP_YANK"
   YANKED_CHANGELOG="$FORGE_TMP_YANK/remote-CHANGELOG.md"
   rm -f "$YANKED_CHANGELOG"
   if command -v gh >/dev/null 2>&1; then
     gh api "repos/$REPO/contents/docs/specs/CHANGELOG.md" --jq '.content' 2>/dev/null | base64 -d > "$YANKED_CHANGELOG" 2>/dev/null \
       || gh api "repos/$REPO/contents/CHANGELOG.md" --jq '.content' 2>/dev/null | base64 -d > "$YANKED_CHANGELOG" 2>/dev/null \
       || rm -f "$YANKED_CHANGELOG"
   fi
   ```
   - If `$YANKED_CHANGELOG` is missing (fetch failed): emit diagnostic "Yank check: could not fetch forge-public CHANGELOG — skipping yank verification." Proceed to Step 0b.
   - If no `## Yanked Tags` heading is present: proceed silently (zero-yank is the expected case).
   - If `## Yanked Tags` heading is present:
     - Parse entries. Expected format (whitespace-tolerant): `- v<tag> — superseded by v<successor>: <reason>`.
     - If the section is present but NO entries match the expected format (malformed / unparseable): emit a diagnostic — **not a silent skip** per Spec 291 `/consensus` round-5 note 1: "⚠ Yank check: `## Yanked Tags` section found in forge-public CHANGELOG but could not be parsed. Inspect manually for yank disclosures affecting `$CONSUMER_TAG`: https://github.com/Renozoic-Foundry/forge-public/blob/main/docs/specs/CHANGELOG.md#yanked-tags". Proceed to Step 0b.
     - If an entry matches `$CONSUMER_TAG`: emit warning (not a block — the stoke itself moves the consumer off the yanked pin):
       ```
       ⚠ YANKED TAG — project is pinned to a yanked tag: $CONSUMER_TAG
       Yank reason: <reason from CHANGELOG entry>
       Superseded by: <successor from CHANGELOG entry>
       Recommendation: stoke will update to $LATEST_TAG; that supersedes the yanked pin.
       ```
   - Clean up: `rm -rf "$FORGE_TMP_YANK"`.

7. Proceed to Step 0b.

### [mechanical] Step 0b — Missing file restoration (Spec 068)

Before checking for updates, detect and restore files that exist in the FORGE template but are missing from this project. `copier update` only applies diffs — it will NOT restore locally-missing files.

1. Read `.copier-answers.yml` to get `_src_path` (the template path). If `.copier-answers.yml` does not exist, skip Step 0b (Step 1 will handle detection).

2. Render the current template to a temp directory. The path is deterministic so later Step 0b sub-steps (3 walk, 5 restore, 8 cleanup) can reconstruct it across separate Bash invocations. `chmod 700` applies owner-only access regardless of umask, closing the multi-user disclosure window on systems where `$TMPDIR` maps to a shared location. Then copy the project's `.copier-answers.yml` into `$FORGE_TMP` before invoking Copier so that module-gated files (NanoClaw, publications, Lane B, etc.) render according to the project's actual module selections — not template defaults. Without pre-seeding, Copier falls back to defaults for every gated module and the missing-file scan below produces false positives (Spec 296):
   ```bash
   FORGE_TMP="${TMPDIR:-${TEMP:-/tmp}}/forge-manifest-check"
   mkdir -p "$FORGE_TMP" && chmod 700 "$FORGE_TMP"
   if [ -f .copier-answers.yml ]; then
     cp .copier-answers.yml "$FORGE_TMP/.copier-answers.yml"
     python -m copier copy "$_src_path" "$FORGE_TMP" --overwrite --vcs-ref=HEAD
   else
     # Fallback: no project answers file — render with template defaults.
     python -m copier copy "$_src_path" "$FORGE_TMP" --defaults --overwrite --vcs-ref=HEAD
   fi
   ```

3. Walk the temp directory and compare against the local project. For each file in the template output, check if it exists locally. Build a list of missing files, classified by path pattern:

   | Path pattern | Category | Action |
   |-------------|----------|--------|
   | `.claude/commands/*.md` | template-command | Auto-restore |
   | `.forge/**` | template-infra | Auto-restore |
   | `docs/process-kit/*.md` | process-kit | Auto-restore |
   | `docs/specs/_template.md` | spec-template | Auto-restore |
   | `AGENTS.md` | config | Prompt before restore |
   | `CLAUDE.md` | config | Prompt before restore |
   | `.mcp.json` | config | Prompt before restore |
   | `docs/backlog.md` | project-data | Skip (project-specific) |
   | `docs/sessions/*` | project-data | Skip (project-specific) |
   | `docs/specs/[0-9]*` | project-data | Skip (project-specific) |
   | `docs/specs/README.md` | project-data | Skip (project-specific) |
   | `docs/specs/CHANGELOG.md` | project-data | Skip (project-specific) |
   | Everything else | unknown | Prompt before restore |

4. If no missing files detected: report "No missing files detected." and proceed to Step 1.

5. If missing files found, execute restoration:

   a. **Auto-restore** (template-command, template-infra, process-kit, spec-template): Copy each file from the temp directory to the local project. Create missing parent directories. Report each:
   ```
   Restored: .claude/commands/forge.md (template-command)
   Restored: .forge/lib/logging.sh (template-infra)
   ...
   ```

   b. **Prompt** (config, unknown): For each file, ask:
   ```
   Missing: AGENTS.md (config — may need project-specific customization after restore)
   Restore from template? (yes / no)
   ```

   c. **Skip** (project-data): Do not restore, do not prompt. These are project-specific files.

6. **Reject file cleanup**: Scan for `.rej` files (leftover failed patches from previous `copier update` runs):
   ```bash
   find . -name "*.rej" -not -path "./node_modules/*" -not -path "./.venv/*"
   ```
   If found, list them and ask:
   ```
   Found <count> .rej files from previous update attempts:
     <file list>
   These are leftover failed patches and are safe to delete.
   Delete all .rej files? (yes / no)
   ```
   If yes, delete them. If no, leave them.

7. Print restoration summary:
   ```
   ## Step 0b — Missing File Restoration Summary
   Auto-restored: <count> files (template commands, .forge infra, process kit)
   Prompted + restored: <count> files
   Skipped (project-specific): <count> files
   Rejected (user declined): <count> files
   .rej files cleaned: <count>

   Proceeding to upstream update check...
   ```

8. Clean up the temp directory.

9. Proceed to Step 1.

**Notes for operators — shared tenancy**: Step 0b's `$FORGE_TMP` lives under `${TMPDIR:-${TEMP:-/tmp}}`. On shared-tenancy systems (CI runners with shared `/tmp`, multi-user dev boxes), export `TMPDIR` to a per-user path before running `/forge stoke`. See [docs/process-kit/shared-tenancy-guidance.md](../../docs/process-kit/shared-tenancy-guidance.md) for concrete examples (GitHub Actions, generic Unix multi-user, CI container). Single-operator workstations (most operators) need no action.

### [mechanical] Step 0c — Credential leakage check (Spec 200)

After reading `_src_path` (from `.copier-answers.yml` in Step 0b, or detected in Step 1), check for embedded credentials:

1. If `_src_path` matches the regex pattern `://[^@]+:[^@]+@` (i.e., contains `user:secret@host`):
   - Warn:
     ```
     **CREDENTIAL LEAKAGE WARNING** — `_src_path` appears to contain an embedded credential:
       <_src_path>
     Credentials in `.copier-answers.yml` are committed to version control and visible to anyone with repo access.
     Recommended: use SSH keys or Git Credential Manager instead of embedded tokens.
     See: docs/process-kit/private-repo-guide.md
     ```
   - Present options: **proceed** (continue with warning noted) | **abort** (stop to fix credentials)
2. If `_src_path` contains `@` but does NOT match `://[^@]+:[^@]+@` (e.g., plain `username@host` with no colon-separated secret): proceed silently — this is a normal username in the URL.
3. If `_src_path` does not contain `@`: proceed silently.

### [mechanical] Step 0d — Preflight connectivity check (Spec 200)

Before running `copier update`, verify that the template source is reachable:

1. If `_src_path` starts with `gh:`, `/`, or a drive letter (e.g., `c:/`, `d:/`): skip this check — GitHub shorthand and local paths don't need remote auth verification.
2. Otherwise, run:
   ```bash
   git ls-remote "$_src_path" HEAD 2>&1
   ```
3. If the command succeeds (exit code 0): proceed silently.
4. If the command fails:
   - Report:
     ```
     **TEMPLATE SOURCE UNREACHABLE** — cannot connect to `<_src_path>`.
     Error: <git ls-remote error output>

     This usually means one of:
     - Authentication credentials are not configured for this repository
     - The URL format is incorrect (Azure DevOps URLs need `git+https://` prefix)
     - The repository does not exist or you don't have access

     Setup options:
     1. **SSH rewrite** (recommended): `git config --global url."git@<host>:".insteadOf "https://<host>/"`
     2. **Git Credential Manager**: `git config --global credential.helper manager`
     3. **Azure DevOps URL fix**: prefix with `git+` → `git+https://org@dev.azure.com/...`

     See: docs/process-kit/private-repo-guide.md for full setup instructions.
     ```
   - **Do NOT proceed to `copier update`.** Stop here.

### [mechanical] Step 1 — Detect sync mechanism

1. Check the current working directory for sync files:
   - `.copier-answers.yml` exists → **Copier path** (proceed to Step 0c credential check, then Step 0d preflight, then Step 3). Read `_src_path` from the file and display:
     ```
     Upstream source: <_src_path>
     To change the upstream source: update `_src_path` in .copier-answers.yml
     ```
   - `.cruft.json` exists but no `.copier-answers.yml` → **migration path** (proceed to Step 2)
   - Neither exists → print error and stop:
     ```
     No sync file found (.copier-answers.yml or .cruft.json).
     This project is not linked to an upstream FORGE template.
     Run /forge init to bootstrap FORGE into this project first.
     ```

### [mechanical] Step 2 — Migrate .cruft.json → .copier-answers.yml (one-time)

2. Read `.cruft.json` and extract the context values. Build `.copier-answers.yml`:

   a. Map Cookiecutter keys to Copier answer keys (strip `cookiecutter.` prefix):
      - `cookiecutter.project_name` → `project_name`
      - `cookiecutter.project_slug` → `project_slug`
      - `cookiecutter.project_description` → `project_description`
      - `cookiecutter.author` → `author`
      - `cookiecutter.test_command` → `test_command`
      - `cookiecutter.lint_command` → `lint_command`
      - `cookiecutter.python_version` → `python_version`
      - `cookiecutter.use_wsl2` → `use_wsl2`
      - `cookiecutter.harness_command` → `harness_command`
      - Any additional keys: map with the same name (prefix stripped)

   b. Set `_src_path` from `.cruft.json`'s `template` field. **Normalize paths**:
      - WSL paths (`/mnt/c/...`) → Windows paths (`c:/...`)
      - Backslashes → forward slashes

   c. Set `_commit`: read the `commit` field from `.cruft.json`.
      - If `null`, empty, or the commit predates `copier.yml` with `_templates_suffix`:
        use the minimum safe baseline: `bfd40476a553bb50576acd80fcc4ad2b1ee9419b`
      - Otherwise: validate that the commit exists in the template repo and contains
        `copier.yml` with `_templates_suffix` defined. If not, fall back to the safe baseline.

   d. Write `.copier-answers.yml` in Copier's expected format:
      ```yaml
      # Changes here will be overwritten by Copier
      _commit: <commit hash>
      _src_path: <normalized template path>
      project_name: <value>
      project_slug: <value>
      # ... remaining keys
      ```

   e. Report what was migrated:
      ```
      ## Migration: .cruft.json → .copier-answers.yml
      Source template: <_src_path>
      Baseline commit: <_commit> (safe baseline applied: yes/no)
      Keys migrated: <count>
      Path normalization: <original> → <normalized> (if changed)

      .copier-answers.yml has been created. .cruft.json is no longer needed.
      You can safely delete .cruft.json — Copier is now the sync mechanism.
      ```

   f. Ask for confirmation before proceeding to Step 3.

### [decision] Step 3 — Check for updates

3. Run:
   ```bash
   python -m copier update --vcs-ref=HEAD --skip-answered --defaults
   ```
   Note: `python -m copier` is used instead of bare `copier` to avoid PATH issues.

4. After Copier finishes, check for conflict markers:
   ```bash
   grep -rl "^<<<<<<<" .
   ```
   If no conflicts found: skip Step 3b and proceed to Step 4.
   If conflicts found: proceed to Step 3b.

### [mechanical] Step 3b — AI-assisted conflict resolution (Spec 067)

5. **Scan and extract**: For each conflicted file, extract individual conflict hunks. Each hunk has: file path, line range, "ours" content (local project), "theirs" content (upstream FORGE template), and 3 lines of surrounding context.

6. **Classify each file** by path pattern to determine default resolution strategy:

   | Path pattern | Category | Default strategy |
   |-------------|----------|-----------------|
   | `.claude/commands/*.md` | template-command | Auto: take upstream |
   | `docs/process-kit/*.md` | process-kit | Auto: take upstream |
   | `docs/specs/_template.md` | spec-template | Auto: take upstream |
   | `docs/specs/CHANGELOG.md` | changelog | Recommend: merge both (append upstream entries) |
   | `AGENTS.md` | config | Escalate: human decides |
   | `CLAUDE.md` | config | Escalate: human decides |
   | `.mcp.json` | config | Recommend: merge server lists (add new, keep existing) |
   | `docs/backlog.md` | project-data | Auto: keep local |
   | `docs/sessions/*` | project-data | Auto: keep local |
   | `docs/specs/[0-9]*` | project-data | Auto: keep local |
   | `src/*`, `tests/*`, `*.py`, `*.js`, `*.ts` | project-code | Escalate: never auto-resolve |
   | `*.sh` (in `.forge/`) | template-script | Auto: take upstream |
   | Everything else | unknown | Escalate: human decides |

7. **Resolve by tier**:

   **Tier 1 — Auto-resolve** (no prompt): Apply the default strategy from the table above. Replace conflict markers with the chosen side. Report each resolution briefly:
   ```
   Auto-resolved: .claude/commands/implement.md → took upstream (template command)
   Auto-resolved: docs/backlog.md → kept local (project data)
   ```

   **Tier 2 — Recommend** (prompt with suggestion): Present the conflict with a recommendation:
   ```
   ## Conflict: <file> (lines <range>)
   Category: <category> | Recommendation: <strategy>

   LOCAL (your project):
   <ours content>

   UPSTREAM (FORGE template):
   <theirs content>

   Recommendation: <explain why and what the recommended resolution is>

   Apply recommendation? (yes / no / show full file / edit)
   ```
   If accepted, apply. If rejected, ask what to do.

   **Tier 3 — Escalate** (prompt with no default): Present the conflict with context but no recommendation:
   ```
   ## Conflict: <file> (lines <range>)
   Category: <category> | Requires human decision

   LOCAL (your project):
   <ours content>

   UPSTREAM (FORGE template):
   <theirs content>

   Context: <why this needs human judgment>

   Choose: (local / upstream / edit / skip)
   ```
   If skipped, leave conflict markers in place.

8. **Resolution summary**: After all conflicts processed, print:
   ```
   ## Conflict Resolution Summary
   Total conflicted files: <count> | Total hunks: <count>

   Auto-resolved (Tier 1): <count>
   Recommended + accepted (Tier 2): <count>
   Human-decided (Tier 3): <count>
   Skipped (unresolved): <count>

   Remaining conflicts: <count> (resolve manually before committing)
   ```

   If all conflicts resolved (remaining = 0): proceed to Step 3c (deprecated file cleanup).
   If unresolved conflicts remain: warn but still proceed to Step 3c. The human can resolve remaining conflicts after the stoke completes.

### [mechanical] Step 3c — Deprecated file cleanup (Spec 166)

After copier update and conflict resolution, remove files that have been deleted from the FORGE template:

1. Read `.forge/update-manifest.yaml` and check for a `removed` section.
2. If the `removed` section exists, iterate over each entry:
   - If the file exists in the project: delete it and report "Removed deprecated file: `<path>`"
   - If the file does not exist: skip silently
3. If no `removed` section or no files to remove: skip silently.

### [mechanical] Step 3d — Auto-commit (Spec 069)

After file restoration (Step 0b), copier update (Step 3), conflict resolution (Step 3b), and deprecated file cleanup (Step 3c), commit all changes so the project is in a clean state.

1. Check for unresolved conflict markers:
   ```bash
   grep -rl "^<<<<<<<" . --include="*.md" --include="*.yml" --include="*.yaml" --include="*.json" --include="*.sh" --include="*.py" --include="*.js" --include="*.ts" 2>/dev/null
   ```
   If any files still have conflict markers: skip the commit and report:
   ```
   Skipping auto-commit — <count> files still have conflict markers.
   Resolve them manually, then commit with: git add -A && git commit -m "forge stoke: sync with FORGE template"
   ```
   Proceed to Step 4.

2. Run `git status`. If no changes (clean working tree): report "No changes to commit — project is already in sync." Proceed to Step 4.

3. If changes exist, stage and commit:
   ```bash
   git add -A
   git commit -m "forge stoke: sync with FORGE template

   Restored: <count> missing files (Step 0b)
   Updated: copier update applied (Step 3)
   Conflicts resolved: <count> (Step 3b)"
   ```
   Omit lines for steps that didn't produce changes (e.g., if no files were restored, omit the Restored line).

4. Report:
   ```
   Auto-committed: <short commit hash> — forge stoke: sync with FORGE template
   Files changed: <count>
   ```

### [mechanical] Step 3e — Regenerate agent command wrappers (Spec 076)

After auto-commit, regenerate agent-specific command wrappers from the updated canonical
commands in `.forge/commands/`. This ensures all configured agents stay in sync with the
latest FORGE commands.

1. Run the sync script:
   ```bash
   .forge/bin/forge-sync-commands.sh
   ```
   This reads `.forge/onboarding.yaml` for the configured agents and regenerates wrappers
   in each agent's native directory (`.claude/commands/`, `.cursor/commands/`, etc.).

2. If new files were generated, stage and commit them:
   ```bash
   git add -A
   git commit -m "forge stoke: regenerate agent command wrappers"
   ```
   If no changes, skip the commit.

3. Report:
   ```
   Agent wrappers regenerated for: <agent list>
   ```

### [mechanical] Step 4 — Evidence gate

5. After update completes (and conflicts resolved if any), run project harness to verify nothing broke:
   - Report: "Upstream update applied. Run your project test suite to verify no regressions."

6. Log the update as a signal in `docs/sessions/signals.md`:
   ```
   SIG-NNN | insight | FORGE upstream update applied via Copier — YYYY-MM-DD
   Details: copier update applied upstream changes. Files updated: <list>. Conflicts: <count>.
   Action: none | review spec triggers if new template features were added
   ```

7. **Session auto-capture** (Spec 164): Before printing the reload checklist, run `/session` inline to capture any accumulated session context (decisions, insights, errors) from this conversation. This is best-effort — if `/session` fails or there is no meaningful content, continue without blocking. Add a note to the session log: "Session auto-captured before /forge stoke reload."

8. Print post-upgrade checklist:
   ```
   ## /forge stoke — Complete
   Upstream update applied: YYYY-MM-DD
   Sync mechanism: Copier
   Files changed: <count>
   Conflicts resolved: <count>
   Signal logged: SIG-NNN
   Session captured: yes (auto-captured before reload)

   ## Post-upgrade steps (human action required)
   1. Reload your VS Code window (Ctrl+Shift+P → "Developer: Reload Window")
      — picks up new/changed .claude/commands/ and .mcp.json
   2. Start a new chat session (updated CLAUDE.md and commands need fresh context)
   3. Run /now to orient and check project state

   If new FORGE commands were added, review them in .claude/commands/
   ```

---

## [mechanical] Next action

After stoke completes, print:

```
## What's next

Existing signals and structure can seed the spec backlog — `/brainstorm` will surface
the highest-value work from what you already have. Run `/interview` if the problem
space needs deeper exploration first.

| # | Action | Description |
|---|--------|-------------|
| **1** | `/brainstorm` | **Recommended** — Scan signals and backlog for spec opportunities |
| 2 | `/interview` | Explore requirements if the next problem area needs clarification |
| 3 | `/now` | Review project state and see what FORGE recommends |
```
