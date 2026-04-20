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
  Existing files will NOT be overwritten — Copier only creates new files.

  Proceed? (yes / no)
  ```
  - If **no**: stop.
  - If **yes**: continue.

- If directory is empty: proceed silently.

## [mechanical] Step 4 — Run Copier

Run:
```bash
python -m copier copy gh:Renozoic-Foundry/forge-public . --defaults
```

If the command fails:
- Report the error output.
- If the error mentions "authentication" or "permission": "The forge-public repo is public — this error is unexpected. Check your network connection and try again."
- Stop.

## [mechanical] Step 5 — Verify and hand off

Check that `.copier-answers.yml` was created:
- If present: "Bootstrap complete. FORGE has been added to this project."
- If absent: "WARNING: .copier-answers.yml was not created. Bootstrap may have failed. Check the output above."

Initialize git if not already a repo:
```bash
git init  # only if .git/ does not exist
```

Report:
```
FORGE bootstrap complete.

**Before continuing**: If your IDE does not recognize new slash commands
(e.g., /onboarding), reload the editor window:
  - VS Code: Ctrl+Shift+P → "Developer: Reload Window"
  - JetBrains: restart the IDE
  - Terminal CLI: no reload needed — commands are available immediately

Next step: run `/onboarding` to configure this project for your team's needs.
This takes 2 quick confirmations and applies sensible defaults. To adjust any
setting afterward, run `/configure`.
```
