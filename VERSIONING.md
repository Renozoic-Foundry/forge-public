# Versioning Policy

FORGE uses [Copier](https://copier.readthedocs.io/) to distribute template updates. This document defines what constitutes a breaking vs non-breaking change and how `/forge stoke` (Copier update) handles each category.

## Version Scheme

FORGE does not use semver tags yet. The canonical version is the git commit on the `main` branch of the upstream source (recorded in `.copier-answers.yml` as `_commit`). Consumer projects track which commit they last synced to.

When semver is adopted (planned), the scheme will follow:
- **MAJOR**: Breaking template changes (file renames, removed variables, restructured directories)
- **MINOR**: New features, new files, new commands (backward-compatible)
- **PATCH**: Bug fixes, documentation updates, process-only changes

## What's Breaking

A **breaking change** requires consumer action during `/forge stoke`:

| Category | Example | Consumer Impact |
|----------|---------|-----------------|
| **File rename/move** | `.forge/commands/foo.md` → `.claude/commands/foo.md` | Old path orphaned; new path created as untracked |
| **Removed Copier variable** | `use_wsl2` removed from `copier.yml` | `.copier-answers.yml` has stale key; Copier may warn |
| **Changed directory structure** | `docs/process-kit/` → `.forge/docs/` | Existing files at old path not moved automatically |
| **Removed file from template** | `template/.forge/commands/deprecated.md` deleted | Consumer's copy persists (Copier doesn't delete) |
| **Changed Copier variable semantics** | `project_slug` now used differently in paths | Existing projects may have wrong paths after update |

## What's Not Breaking

These changes are absorbed by `/forge stoke` automatically:

| Category | Example | Why Safe |
|----------|---------|----------|
| **New file added** | New command file in `template/.claude/commands/` | Copier creates it; no conflict with existing files |
| **Content update to existing file** | Updated instructions in `implement.md` | Copier merges via `update-manifest.yaml` classification |
| **New Copier variable with default** | New `copier.yml` question with sensible default | Default applies; no user action needed |
| **Process-kit updates** | Revised runbook, scoring rubric, checklist | Merge or overwrite per manifest classification |
| **Bug fixes in scripts** | Fixed path handling in `forge-install.sh` | Overwrite per manifest classification |

## How `/forge stoke` Handles Updates

Each template file has a classification in `.forge/update-manifest.yaml`:

| Classification | Behavior | Use For |
|---------------|----------|---------|
| `merge` | Copier attempts 3-way merge | Command files, CLAUDE.md, AGENTS.md |
| `overwrite` | Replace consumer's copy entirely | Scripts, libraries, CI configs |
| `skip` | Never update (consumer owns it) | Project-specific files |
| `prompt` | Ask consumer before updating | Files that may have local customizations |

When conflicts occur during merge, `/forge stoke` pauses for manual resolution.

## Migration Notes

When a breaking change ships, it will be documented here with migration steps.

### Format

```
## vX.Y.Z (or commit hash) — YYYY-MM-DD

**Breaking**: <description>

Migration steps:
1. <step>
2. <step>
```

_(No breaking changes have been released yet.)_
