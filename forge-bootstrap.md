# FORGE Bootstrap
# Install: copy this file to ~/.claude/commands/forge-bootstrap.md
# Usage: run /forge-bootstrap in any project directory

> This command clones a template repository. It does not push, publish, or modify external systems.

Bootstrap FORGE into the current project directory using the public GitHub template.

---

## [mechanical] Step 1 — Prerequisite check

Check that required tools are installed:

1. **Python 3.9+**: run `python3 --version` or `python --version`. Extract major.minor version.
2. **Git**: run `git --version`.
3. **Copier 9.0+**: run `python -m copier --version`.

For each missing prerequisite, report what's missing and offer to install:

```
## Missing Prerequisites

The following tools are required but not found:

| # | Tool | Install command |
|---|------|----------------|
| 1 | Python 3.9+ | `winget install Python.Python.3.12` (Windows) / `brew install python` (macOS) / `apt install python3` (Linux) |
| 2 | Copier 9.0+ | `pip install copier>=9.0` |

Install now? (yes / no)
```

- If **yes**: run the install commands for the detected platform, re-verify, then continue.
- If **no**: stop with message listing what to install manually.
- If all prerequisites are met: proceed silently.

## [mechanical] Step 2 — Check for existing FORGE installation

Check if the current directory already has `.copier-answers.yml`:

- If `.copier-answers.yml` exists:
  ```
  This project already has a FORGE template linked.
  Source: <_src_path from .copier-answers.yml>

  To update: run `/forge stoke`
  To re-bootstrap: delete .copier-answers.yml first (this will lose your update history)
  ```
  Stop — do not overwrite.

- If `.copier-answers.yml` does not exist: proceed.

## [decision] Step 3 — Non-empty directory check

Check if the current directory contains files (excluding `.git/`, `.gitignore`, and other dotfiles):

```bash
find . -maxdepth 1 -not -name '.*' -not -name '.' | head -5
```

- If files found:
  ```
  This directory contains existing files. FORGE template files will be added alongside them.
  Existing files will NOT be overwritten silently — if any root-level files collide with the FORGE template
  (README.md, CLAUDE.md, AGENTS.md, memory files), you'll get a single batched prompt with diffs and
  per-file choices (merge / keep-original + append / overwrite). See Step 3c.

  Proceed? (yes / no)
  ```
  - If **no**: stop.
  - If **yes**: continue.

- If directory is empty: proceed silently.

## [decision] Step 3b — Version disclosure and ref selection (Spec 291)

Before running Copier, resolve the latest forge-public release tag and let the operator choose what to install. This prevents the silent-stale-install failure where `--defaults` with no `--vcs-ref` pins to the repo's latest tag without surfacing which tag that is.

1. Query the latest tag (prefer `gh` CLI when installed; fall back to `git ls-remote`):
   ```bash
   REPO="Renozoic-Foundry/forge-public"
   LATEST_TAG=""
   MAIN_SHA=""
   COMMITS_AHEAD=""
   if command -v gh >/dev/null 2>&1; then
     LATEST_TAG=$(gh api "repos/$REPO/releases/latest" --jq '.tag_name' 2>/dev/null || true)
     MAIN_SHA=$(gh api "repos/$REPO/commits/main" --jq '.sha' 2>/dev/null | cut -c1-7 || true)
     if [ -n "$LATEST_TAG" ]; then
       COMMITS_AHEAD=$(gh api "repos/$REPO/compare/$LATEST_TAG...main" --jq '.ahead_by' 2>/dev/null || true)
     fi
   fi
   if [ -z "$LATEST_TAG" ]; then
     LATEST_TAG=$(git ls-remote --tags --refs --sort='-v:refname' "https://github.com/$REPO" 2>/dev/null \
       | awk '{print $2}' | sed 's|refs/tags/||' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)
   fi
   ```

2. If `LATEST_TAG` is still empty (no network, repo unreachable): report:
   ```
   Could not resolve latest forge-public tag — network unreachable or repo inaccessible.
   Proceeding with default install (Copier will pin to its resolved latest tag).
   ```
   Skip to Step 4 with no `--vcs-ref` override.

3. Display the version disclosure and present the 3-option choice block:
   ```
   About to install FORGE template <LATEST_TAG> (gh:Renozoic-Foundry/forge-public @ tag <LATEST_TAG>)
   Latest main-branch commit: <MAIN_SHA or "unknown"> (<COMMITS_AHEAD or "?"> commits ahead of <LATEST_TAG>)
   ```
   > **Choose** — type a number or keyword:
   > | # | Action | What happens |
   > |---|--------|--------------|
   > | **1** | `latest` | Install <LATEST_TAG> (default — recommended for production) |
   > | **2** | `main` | Install unreleased HEAD of main branch (bleeding edge — may contain untagged breaking changes) |
   > | **3** | `tag <name>` | Install a specific tag (prompt for tag name) |

4. Resolve the operator's choice to `FORGE_VCS_REF`:
   - Choice `1` / `latest` / empty default → `FORGE_VCS_REF=$LATEST_TAG`
   - Choice `2` / `main` → `FORGE_VCS_REF=main`
   - Choice `3` / `tag` → prompt "Enter tag name (e.g. v1.2.0):"; validate with `gh api "repos/$REPO/git/refs/tags/<tag>"` (or `git ls-remote`); if unknown, re-prompt up to 2 times then abort. Set `FORGE_VCS_REF=<validated-tag>`.

5. Report: `Resolved install ref: $FORGE_VCS_REF`.

## [decision] Step 3c — Root-file conflict detection (Spec 307)

Before running Copier directly over the project tree, detect conflicts between pre-existing root-level files and the files the template is about to write. The full rules (canonical file list, detection order, recommendation rules R1–R6, merge/append/overwrite output formats) are authoritative in [`docs/process-kit/bootstrap-conflict-resolution.md`](docs/process-kit/bootstrap-conflict-resolution.md). This step summarizes the flow — **always follow the rules doc when there's a conflict between this summary and the doc**.

### 3c.1 — Render template to a scratch dir

Render the resolved `$FORGE_VCS_REF` to a scratch location (OS-aware temp path):

```bash
# OS-aware temp dir (Git Bash on Windows maps /tmp/ to AppData\Local\Temp).
FORGE_SCRATCH="${TMPDIR:-${TEMP:-/tmp}}/forge-bootstrap-preview-$$"
mkdir -p "$FORGE_SCRATCH"
python -m copier copy "gh:Renozoic-Foundry/forge-public" "$FORGE_SCRATCH" --defaults --vcs-ref "$FORGE_VCS_REF" >/dev/null 2>&1
```

If the scratch render fails for any reason: **skip conflict detection** (report the reason), fall through to Step 4 with the pre-Spec-307 behavior (Copier's skip-if-exists + `.original.<ext>` preservation). Do not block bootstrap on preview failure.

### 3c.2 — Enumerate canonical conflict set

For each path in the canonical set (see rules doc §1):
- `README.md`
- `CLAUDE.md`
- `AGENTS.md`
- any root-level `*MEMORY*.md` (match: `MEMORY.md`, `PROJECT_MEMORY.md`, etc.)
- **skip** `.copier-answers.yml` — Step 2 already handled it

check whether BOTH `$FORGE_SCRATCH/<path>` AND `./<path>` exist with different content. If content is identical (sha256 match), drop the entry (rule R1).

If the resulting conflict list is empty: **proceed silently to Step 4.** No prompt. (AC 4 — greenfield-safe / zero-impact.)

### 3c.3 — Apply recommendation rules

For each entry, apply rules R1 → R2 → R3 → R4 → R5 → R6 (see rules doc §4). First-match wins. Capture the rule name in the rationale.

### 3c.4 — Emit the batched prompt

Emit a **single** prompt covering all conflicts (AC 5 — no N separate blocking prompts):

```
Root-file conflicts detected (<N> files). Resolve before bootstrap:

────────────────────────────────────────────────────
[1] README.md
    Diff (original → FORGE template):
    --- original
    +++ template
    <unified diff, truncated per §3 of rules doc: 120 line cap, 60+30 window>
    Recommendation: merge  —  <rationale keyed to rule R4>

[2] CLAUDE.md
    Diff:
    <…>
    Recommendation: keep-append  —  <rationale keyed to rule R5>

[3] AGENTS.md
    Diff:
    <…>
    Recommendation: overwrite  —  <rationale keyed to rule R2 / R3>
────────────────────────────────────────────────────

Choose per-file or accept all recommendations:

  [Enter]            accept-all  (apply the recommendation for each)
  merge N            force merge on file N
  keep-append N      force keep-original + append on file N
  overwrite N        force overwrite (original preserved as .original) on file N
  show full N        expand truncated diff for file N and re-prompt
  cancel             abort bootstrap — touch nothing

Example: "merge 1, overwrite 3" (comma-separated per-file overrides; remaining files use recommendation)
```

### 3c.5 — Apply choices

For each file, apply the chosen action per the rules doc:
- **merge** (§6): write merged file with `<!-- BEGIN FORGE-inserted (spec-307) -->` / `<!-- END FORGE-inserted (spec-307) -->` source markers around inserted sections. No `.original.*` file produced.
- **keep-append** (§7): write original verbatim + blank line + `<!-- BEGIN FORGE-inserted (spec-307) -->` marker + `## FORGE Process` heading + downshifted template content + `<!-- END FORGE-inserted (spec-307) -->`. No `.original.*` file produced.
- **overwrite** (§8): rename original to `<stem>.original.<ext>` (collision-suffixed `.1`, `.2` … if needed), then let Copier write the template version. **This is the regression-guard path — matches pre-Spec-307 behavior.**

Apply choices to the project tree **before** invoking Copier in Step 4 so Copier's own skip-if-exists logic treats them as "already present".

### 3c.6 — Clean up

Remove `$FORGE_SCRATCH` on success or failure: `rm -rf "$FORGE_SCRATCH"`.

## [mechanical] Step 4 — Run Copier

Run (substitute `$FORGE_VCS_REF` from Step 3b; if Step 3b was skipped due to network failure, omit the `--vcs-ref` flag entirely):
```bash
python -m copier copy "gh:Renozoic-Foundry/forge-public" . --defaults --vcs-ref "$FORGE_VCS_REF"
```

If the command fails:
- Report the error output.
- If the error mentions "authentication" or "permission": "The forge-public repo is public — this error is unexpected. Check your network connection and try again."
- If the error mentions "ref" or "not found" and `$FORGE_VCS_REF` was a specific tag: "Tag `$FORGE_VCS_REF` not found in forge-public. Re-run `/forge-bootstrap` and pick a different tag."
- Stop.

## [mechanical] Step 5 — Verify and hand off

Check that `.copier-answers.yml` was created:
- If present: "Bootstrap complete. FORGE has been added to this project."
- If absent: "WARNING: .copier-answers.yml was not created. Bootstrap may have failed. Check the output above."

Initialize git if not already a repo:
```bash
git init  # only if .git/ does not exist
```

### Step 5b — Write install manifest (Spec 431; Reqs 1, 1a, 1b)

Record provenance for every FORGE file placed under `~/.claude/` by this
bootstrap. The manifest at `~/.claude/.forge-installed.json` is the spine
for future `/forge-stoke` legacy detection — without it, no manifest-orphan
detection is possible for this install.

```bash
# Atomic-write under advisory lock (Req 1a). Records FORGE:BEGIN/END
# delimited sections under ~/.claude/CLAUDE.md for manifest-attestation
# (Req 1b).
.forge/bin/forge-py .forge/lib/stoke.py manifest-init \
  --project-root . \
  --template-root .forge \
  --spec-id 431-bootstrap
```

If the command fails (manifest lock contention, schema mismatch, etc.), it
emits a diagnostic and exits non-zero. Bootstrap continues — the manifest is
provenance-only; absence does not block bootstrap, but downstream
`/forge-stoke` legacy detection will be limited to the hash-pinned catalog
migration shim until the next stoke run writes the manifest.

**Delimiter convention (Req 8)**: any FORGE-injected section in
`~/.claude/CLAUDE.md` MUST be wrapped in
`<!-- FORGE:BEGIN <section-id> -->` / `<!-- FORGE:END <section-id> -->`
markers. `manifest-init` records the `(section_id, content_sha256)` pair
so that future cleanup can refuse to act on unattested delimited blocks
(forgery defense per AC 22).

Report:
```
FORGE bootstrap complete.
Installed ref: $FORGE_VCS_REF  (verify in .copier-answers.yml → _commit)

**Before continuing**: If your IDE does not recognize new slash commands
(e.g., /onboarding), reload the editor window:
  - VS Code: Ctrl+Shift+P → "Developer: Reload Window"
  - JetBrains: restart the IDE
  - Terminal CLI: no reload needed — commands are available immediately

Next step: run `/onboarding` to configure this project for your team's needs.
This takes 2 quick confirmations and applies sensible defaults. To adjust any
setting afterward, run `/configure`.
```
