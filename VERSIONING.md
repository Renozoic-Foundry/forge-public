# Versioning Policy

FORGE uses [Copier](https://copier.readthedocs.io/) to distribute template updates. This document defines what constitutes a breaking vs non-breaking change and how `/forge stoke` (Copier update) handles each category.

## Version Scheme

FORGE uses semantic version tags. Released tags to date: **v1.0.0**, **v2.0.0**, **v2.1.0**, with **v3.0.0** as the next MAJOR (the plugin-primary release). Each tag corresponds to a commit on the `main` branch of the upstream source; consumer projects also record the exact synced commit in `.copier-answers.yml` as `_commit`.

The scheme follows:
- **MAJOR**: Breaking template changes (file renames, removed variables, restructured directories)
- **MINOR**: New features, new files, new commands (backward-compatible)
- **PATCH**: Bug fixes, documentation updates, process-only changes

| Tag | Bump | Summary |
|-----|------|---------|
| v1.0.0 | — | First tagged release of the FORGE template. |
| v2.0.0 | MAJOR | Template restructure and command-surface changes. |
| v2.1.0 | MINOR | Additive commands and process refinements. |
| v3.0.0 | MAJOR (pending cut) | Plugin-primary distribution; Copier `_min_copier_version` pin (Spec 294) and always-on signal capture (Spec 340). See migration note below. |

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

When a breaking change ships, it is documented here with migration steps.

### Format

```
## vX.Y.Z (or commit hash) — YYYY-MM-DD

**Breaking**: <description>

Migration steps:
1. <step>
2. <step>
```

### v3.0.0 — plugin-primary release

**Breaking**:
- **Copier minimum-version pin** (Spec 294): `copier.yml` now sets `_min_copier_version`. Consumers on an older Copier must upgrade before `/forge stoke` / `copier update` will run.
- **Always-on signal capture** (Spec 340): signal capture is no longer opt-in. Closing a spec records retro signals automatically.

**Also in v3.0.0** (additive, non-breaking): the FORGE command/agent/skill/hook payload is now installable as a Claude Code plugin from a checkout (`claude plugin install ./`), alongside the existing Copier project-scaffolding path.

Migration steps:
1. Upgrade Copier to satisfy the new `_min_copier_version` pin: `pip install -U copier`.
2. Run `/forge stoke` (Claude Code) or `copier update` (other IDEs) to pull the v3.0.0 template.
3. Resolve any merge prompts per your `update-manifest.yaml` classifications.
