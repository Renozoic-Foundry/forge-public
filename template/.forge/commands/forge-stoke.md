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

## [mechanical] Step 0z — Lane-mismatch warning (Spec 353)

If `.forge/state/active-tab-*.json` marker exists for this session, read its `lane` field.

This command's natural lane (per `docs/process-kit/multi-tab-quickstart.md` § Lane choice):

| Command | Lane |
|---------|------|
| /parallel | feature |
| /spec | feature OR process-only (depending on spec subject) |
| /scheduler | feature |
| /forge stoke | process-only |

If `marker.lane` does not match this command's natural lane, emit a one-line warning: `⚠ Action targets <expected> lane; active tab is '<marker.lane>'. Continue?` Soft-gate only — do not refuse. Operator decides whether the mismatch matters.

Skip silently if no marker exists.

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

### [mechanical] Step 0a.5 — Shadow-tree creation (Spec 381)

Before any mutation steps run (Step 0b restoration, Step 3 copier update, Step 3b conflict resolution, Step 3c deprecated cleanup), create a transient shadow tree under `$TMPDIR`. Steps 0b–3c then operate on the shadow, NOT on the live working tree. Live tree is read-only until Step 3c.6 apply step (after operator confirms the audit at Step 3c.5).

This makes stoke transactional: the audit runs upstream of any live-tree mutation, so abort is "discard shadow, exit" with no recovery needed. Eliminates the silent-content-loss class documented in the 2026-05-01 SmileyOne bug report (~700 lines lost across one stoke run, undetected for ~30 days).

Procedure:

1. Orphan-cleanup of stale shadows from prior runs (Spec 381 R9):
   ```bash
   .forge/bin/forge-py .forge/lib/stoke.py orphan-gc --max-age-hours 24
   ```
   Removes any `$TMPDIR/forge-stoke-shadow-*` directory older than 24h.

2. Create shadow:
   ```bash
   SHADOW=$(.forge/bin/forge-py .forge/lib/stoke.py shadow-create)
   echo "Shadow tree: $SHADOW"
   ```
   The helper copies all tracked files (`git ls-files`) into `$SHADOW` and captures an mtime baseline at `$SHADOW/.mtime-baseline.tsv`. Untracked files in the live tree NEVER enter the shadow — Step 0b restoration in shadow cannot collide with operator's untracked working-tree content (eliminates the Spec 379 "already exists" stash-pop bug as a side-effect).

3. Capture `SHADOW` for use in subsequent steps. All file operations from Step 0b through Step 3c that mutate tracked content MUST target paths under `$SHADOW`, not the live working tree.

**Constraint**: live tree is physically untouched between Step 0a.5 and Step 3c.6 apply step. Any Steps 0b–3c that say "write to <path>" mean "write to `$SHADOW/<path>`". Conflict resolution prompts at Step 3b operate on shadow paths but the operator-facing UX (showing local vs upstream content) is unchanged from today.

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

### [mechanical] Step 0b — Missing file restoration (Spec 068, reframed by Spec 297)

Before checking for updates, detect and restore files that exist in the FORGE template but are missing from this project. `copier update` only applies diffs — it will NOT restore locally-missing files.

**Mechanism (Spec 297 reframe)**: enumerate the upstream template's tracked files at `_commit` via `git ls-tree`, filter by the project's `.copier-answers.yml` `include_*` flags using each module's `module.yaml` `files:` list, and diff the resulting manifest against `git ls-files` in the local project. No Copier render. No prompt_toolkit. No render-tree temp directory. For remote `_src_path` forms, a shallow bare clone is the only temp surface and is cleaned on exit.

1. Read `.copier-answers.yml` to get `_src_path` (the template source) and `_commit` (the pinned ref). If `.copier-answers.yml` does not exist, skip Step 0b (Step 1 will handle detection). If `_src_path` or `_commit` is missing/empty, emit "Step 0b: `.copier-answers.yml` lacks `_src_path` or `_commit` — skipping manifest-diff." and proceed to Step 1.

2. Resolve `_src_path` to a local git repository for `git ls-tree` enumeration. Classify by form:

   - **Local path** (absolute Unix path, Windows drive path like `c:/`, or WSL `/mnt/<letter>/...`): use the path directly as the source repo. Normalize WSL paths to host form if running outside WSL. No clone.
   - **Remote shorthand or URL** (`gh:org/repo`, `https://…`, `git@…:…`, `git+https://…`): perform a shallow bare clone scoped to the pinned ref. The bare clone is the only temp surface introduced by Step 0b.

   ```bash
   FORGE_SRC_REPO=""
   FORGE_BARE_CLONE=""  # set only for remote _src_path
   case "$_src_path" in
     gh:*)
       FORGE_BARE_CLONE="${TMPDIR:-${TEMP:-/tmp}}/forge-manifest-clone-$$"
       mkdir -p "$FORGE_BARE_CLONE" && chmod 700 "$FORGE_BARE_CLONE"
       gh_repo="${_src_path#gh:}"
       git clone --bare --filter=blob:none "https://github.com/$gh_repo" "$FORGE_BARE_CLONE/repo.git" >/dev/null 2>&1 || {
         echo "Step 0b: shallow bare clone of $_src_path failed."
         rm -rf "$FORGE_BARE_CLONE"
         exit 1
       }
       FORGE_SRC_REPO="$FORGE_BARE_CLONE/repo.git"
       ;;
     https://*|git@*|git+*)
       FORGE_BARE_CLONE="${TMPDIR:-${TEMP:-/tmp}}/forge-manifest-clone-$$"
       mkdir -p "$FORGE_BARE_CLONE" && chmod 700 "$FORGE_BARE_CLONE"
       remote_url="${_src_path#git+}"
       git clone --bare --filter=blob:none "$remote_url" "$FORGE_BARE_CLONE/repo.git" >/dev/null 2>&1 || {
         echo "Step 0b: shallow bare clone of $_src_path failed."
         rm -rf "$FORGE_BARE_CLONE"
         exit 1
       }
       FORGE_SRC_REPO="$FORGE_BARE_CLONE/repo.git"
       ;;
     *)
       # Local path (absolute, drive-letter, or WSL-mounted). Use directly.
       if [ ! -d "$_src_path/.git" ] && [ ! -f "$_src_path/HEAD" ]; then
         echo "Step 0b: \`_src_path\` ($_src_path) is not a git repository — cannot enumerate manifest."
         exit 1
       fi
       FORGE_SRC_REPO="$_src_path"
       ;;
   esac

   # Verify _commit is reachable in the source repo (AC10).
   if ! git -C "$FORGE_SRC_REPO" rev-parse --verify "$_commit^{commit}" >/dev/null 2>&1; then
     echo "Step 0b: \`_commit\` ref ($_commit) is not reachable in source repo $_src_path."
     [ -n "$FORGE_BARE_CLONE" ] && rm -rf "$FORGE_BARE_CLONE"
     exit 1
   fi
   ```

3. Enumerate the upstream template manifest and filter by module-gate flags. The Copier template lives under `template/` in the source repo (`_subdirectory: template` in `copier.yml`); strip that prefix to produce consumer-project paths.

   ```bash
   # Raw upstream manifest, restricted to the template subdirectory and stripped of its prefix.
   UPSTREAM_MANIFEST=$(git -C "$FORGE_SRC_REPO" ls-tree -r --name-only "$_commit" -- template/ \
     | sed 's|^template/||')

   # Apply module-gate filter: for each include_<module>: false in .copier-answers.yml,
   # subtract the paths listed in template/.forge/modules/<module>/module.yaml `files:`.
   FILTERED_MANIFEST="$UPSTREAM_MANIFEST"
   while IFS= read -r flag_line; do
     # Parse "include_<module>: false" — module name is between "include_" and ":".
     case "$flag_line" in
       include_*:\ false|include_*:\ False|include_*:\ FALSE)
         module=$(echo "$flag_line" | sed -E 's/^include_([a-zA-Z0-9_-]+):.*/\1/')
         module_yaml=$(git -C "$FORGE_SRC_REPO" show "$_commit:template/.forge/modules/$module/module.yaml" 2>/dev/null || echo "")
         if [ -z "$module_yaml" ]; then
           # Module yaml missing entirely — skip silently (module may be off in this template version).
           continue
         fi
         # Extract files: list (lines starting with "  - " under a `files:` heading).
         files_block=$(echo "$module_yaml" | awk '
           /^files:/ { in_block=1; next }
           in_block && /^[a-zA-Z]/ { in_block=0 }
           in_block && /^[[:space:]]*-[[:space:]]/ {
             sub(/^[[:space:]]*-[[:space:]]*/, "")
             print
           }
         ')
         if [ -z "$files_block" ]; then
           echo "Step 0b: module \`$module\` is gated off (include_$module: false) but template/.forge/modules/$module/module.yaml has no \`files:\` field — cannot filter. Fail-fast per Spec 297 AC9."
           [ -n "$FORGE_BARE_CLONE" ] && rm -rf "$FORGE_BARE_CLONE"
           exit 1
         fi
         # Subtract each path (or path-prefix if entry ends with /) from the manifest.
         while IFS= read -r excl; do
           [ -z "$excl" ] && continue
           if [ "${excl%/}" != "$excl" ]; then
             # Directory entry — strip all paths under it.
             FILTERED_MANIFEST=$(echo "$FILTERED_MANIFEST" | grep -v "^${excl}" || true)
           else
             FILTERED_MANIFEST=$(echo "$FILTERED_MANIFEST" | grep -vxF "$excl" || true)
           fi
         done <<< "$files_block"
         ;;
     esac
   done < <(grep -E '^include_[a-zA-Z0-9_-]+:' .copier-answers.yml 2>/dev/null || true)

   # Local-project side: tracked files via git ls-files.
   LOCAL_FILES=$(git ls-files)
   ```

4. Diff the filtered upstream manifest against `LOCAL_FILES`. For each upstream entry not present locally, classify by path pattern (this table is the output contract consumed by Steps 3–6 — preserved byte-compatible with Spec 296):

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

   Sources for restoration: when an Auto-restore or Prompt action runs, fetch the file's bytes via `git -C "$FORGE_SRC_REPO" show "$_commit:template/<path>"` rather than reading from a rendered tree (no rendered tree exists). For `.jinja` template files: strip the suffix on the upstream side and write to the consumer path without it (Copier rendering of variables is not required for restoration of files that lack template variables; for files that DO contain variables, the operator can re-run `copier update` afterward to refresh — same behavior as Spec 296).

5. If no missing files detected: report "No missing files detected." and proceed to Step 1.

6. If missing files found, execute restoration (action lanes are byte-compatible with Spec 296):

   a. **Auto-restore** (template-command, template-infra, process-kit, spec-template): Write each file's bytes (from `git show`) to the local project. Create missing parent directories. Report each:
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

7. **Reject file cleanup**: Scan for `.rej` files (leftover failed patches from previous `copier update` runs):
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

8. Print restoration summary (output format unchanged from Spec 296 — consumed by Steps 3–6):
   ```
   ## Step 0b — Missing File Restoration Summary
   Auto-restored: <count> files (template commands, .forge infra, process kit)
   Prompted + restored: <count> files
   Skipped (project-specific): <count> files
   Rejected (user declined): <count> files
   .rej files cleaned: <count>

   Proceeding to upstream update check...
   ```

9. Clean up. If a shallow bare clone was created (`FORGE_BARE_CLONE` set): `rm -rf "$FORGE_BARE_CLONE"`. Local `_src_path` paths are never touched.

10. Proceed to Step 1.

**Notes for operators — shared tenancy**: For remote `_src_path` forms only, Step 0b creates a shallow bare clone under `${TMPDIR:-${TEMP:-/tmp}}`. The directory is created with `chmod 700` and removed at exit. On shared-tenancy systems (CI runners with shared `/tmp`, multi-user dev boxes), export `TMPDIR` to a per-user path before running `/forge stoke`. See [docs/process-kit/shared-tenancy-guidance.md](../../docs/process-kit/shared-tenancy-guidance.md) for concrete examples (GitHub Actions, generic Unix multi-user, CI container). Single-operator workstations and projects with local `_src_path` need no action — Step 0b creates no temp directory in that case.

### [mechanical] Step 0c — Split-file migration advisory (Spec 399)

After Step 0b's manifest-diff completes (or is skipped), surface a one-line advisory recommending split-file migration when ALL of the following hold:

1. Run `.forge/bin/forge-py .forge/lib/derived_state.py --detect-mode`. The stdout is the rendering mode (`split-file`, `generated`, or `skip-canonical`). If stdout is `split-file`, skip this Step entirely — consumer is already migrated. If the helper exits nonzero, surface stderr and skip this advisory (do NOT block stoke; degenerate-state diagnosis is a separate concern).
2. `.copier-answers.yml` exists AND its `_commit:` field indicates the consumer's template version is at-or-past the Spec-398-shipping commit. Determine "at-or-past" by checking whether the consumer's `_commit` is reachable from the merge commit that closed Spec 398. If `.copier-answers.yml` is missing or `_commit` is empty, skip this advisory.
3. The most recent operation on the project was NOT `copier update` — if it was, Spec 400's auto-migration hook would have already run, so re-emitting the advisory is noise. Detection: a fresh `.copier-answers.yml` modified within the current stoke invocation's parent process tree (or a `_commit` that matches the upstream HEAD exactly with no local edits between) suggests `copier update`. Conservative default: if uncertain, proceed to step 4.
4. `.forge/state/migration-advisory-shown.flag` does NOT exist.

If all four conditions hold, emit exactly:
```
SPLIT-FILE MIGRATION AVAILABLE — Run `python scripts/migrate-to-derived-view.py --mode=split-file` to adopt split-file rendering. See Spec 398.
```

After emission, create the suppression flag:
```bash
mkdir -p .forge/state
: > .forge/state/migration-advisory-shown.flag
```

The advisory MUST NOT re-emit on subsequent stoke runs unless the operator removes the flag (`rm .forge/state/migration-advisory-shown.flag`). The flag's existence is the suppression signal.

### [mechanical] Step 1 — Detect sync mechanism

1. Check the current working directory for sync files:
   - `.copier-answers.yml` exists → **Copier path** (proceed to Step 3). Read `_src_path` from the file and display:
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

### [mechanical] Step 3c.5 — Pre-commit audit (Spec 381)

Before applying shadow → live (Step 3c.6) and committing (Step 3d), audit the shadow tree against the live tree for governance-content loss in Tier 3 config files (`AGENTS.md`, `CLAUDE.md`, `.mcp.json`).

1. Run mtime drift check (Spec 381 R8/AC9):
   ```bash
   .forge/bin/forge-py .forge/lib/stoke.py mtime-check "$SHADOW" 2>/tmp/stoke-drift.txt
   if [ $? -ne 0 ]; then
       echo "⚠ The following live-tree files were modified during stoke:"
       cat /tmp/stoke-drift.txt
       echo "Proceed anyway (operator's edits will be overwritten unless excluded)? [y/abort]"
       # Wait for response. On abort: rm -rf "$SHADOW", exit. On y: continue.
   fi
   ```

2. Run audit:
   ```bash
   .forge/bin/forge-py .forge/lib/stoke.py audit "$SHADOW" > /tmp/stoke-audit.json
   fired=$(python3 -c "import json; print(json.load(open('/tmp/stoke-audit.json'))['fired'])")
   ```

3. **Audit silent on clean stokes** (Spec 381 R4): if `fired=False`, emit no output and proceed directly to Step 3c.6 with no exclusions.

4. **Decision gate** (only fires when `fired=True`):

   Read the flagged files from `/tmp/stoke-audit.json` and present, sorted by severity (sections-lost first, then delta_pct desc per Spec 381 R5):

   ```
   ⚠ Audit detected potential loss in <N> Tier 3 file(s):
   ! AGENTS.md: <pre> → <post> lines (-<delta>, -<pct>%)  [SECTIONS LOST: <count>]
       Missing: <comma-separated section names>
   · CLAUDE.md: <pre> → <post> lines (-<delta>, -<pct>%)  [SECTIONS LOST: 0]

   Press Enter to recover-all (recommended) — apply stoke updates EXCEPT to flagged files.
   Choose:
     1   continue            — apply all stoke updates (including loss)
     2   recover-selective   — per-file decision
     3   abort               — discard ALL stoke work, live tree unchanged
                                (NB: this discards any conflict resolutions you made during stoke)
   ```

   Severity prefix: `!` for files with `sections_lost > 0` OR `delta_pct > 30`; `·` for benign deltas.

   Wait for operator response.

5. **Apply decision** (sets exclusions for Step 3c.6):
   - **Enter / recover-all** (default): EXCLUDES = list of flagged file paths.
   - **continue** (option 1): EXCLUDES = empty list.
   - **recover-selective** (option 2): for each flagged file, prompt:
     ```
     Apply <file> from shadow (lose customization) or keep live (preserve customization)? [keep/apply]
     ```
     Default is `keep`. Build EXCLUDES from files where operator kept live.
   - **abort** (option 3): `.forge/bin/forge-py .forge/lib/stoke.py cleanup "$SHADOW"`, exit early. Skip Step 3c.6 and 3d. Print: `Aborted. Live tree unchanged. No commit made.`

### [mechanical] Step 3c.6 — Apply shadow → live (Spec 381)

If Step 3c.5 did not abort, apply the shadow tree to live with operator-determined exclusions:

```bash
EXCLUDE_ARGS=""
for f in "${EXCLUDES[@]}"; do
    EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude $f"
done
.forge/bin/forge-py .forge/lib/stoke.py apply "$SHADOW" $EXCLUDE_ARGS
```

The helper uses two-phase atomic apply per Spec 381 R7: writes to `<path>.new`, fsyncs, then `os.replace` (atomic on POSIX, MoveFileEx with REPLACE on Windows via Python's `os.replace`). No rsync dependency — pure Python `shutil.copy2` + `os.replace`.

Untracked files in live are NEVER touched (they never entered shadow per R1). Tracked files listed in EXCLUDES are skipped (live versions preserved).

After apply: proceed to Step 3d (auto-commit) which now runs against the updated live tree.

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

### [mechanical] Step 3d — Regenerate agent command wrappers (Spec 076)

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

8. **Shadow tree cleanup (Spec 381 R9)**: regardless of outcome (success, abort, error), remove the shadow directory:
   ```bash
   if [ -n "${SHADOW:-}" ]; then
       .forge/bin/forge-py .forge/lib/stoke.py cleanup "$SHADOW"
   fi
   ```
   No retention. The next stoke creates a fresh shadow at Step 0a.5.

9. **Post-stoke note (Spec 381 R10)**: emit:
   ```
   No stash was created — uncommitted work was preserved in your working tree throughout.
   Recovery if needed: git diff / git log -p / git reflog.
   ```
   This documents the operator-habit change from prior stoke (which used git-stash for dirty-tree handling). Spec 381's shadow-tree approach mirrors only TRACKED files into shadow; untracked files stay in live and are never touched, so no stash is needed.

10. Print post-upgrade checklist:
    ```
    ## /forge stoke — Complete
    Upstream update applied: YYYY-MM-DD
    Sync mechanism: Copier (transactional via shadow-tree per Spec 381)
    Files changed: <count>
    Conflicts resolved: <count>
    Audit fired: <yes/no>
    Decision: <continue/recover-all/recover-selective/abort/(none — clean)>
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
