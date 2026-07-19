# Versioning Policy

FORGE v3 is distributed as a **signed Claude Code plugin** — the plugin version
(`.claude-plugin/plugin.json`) is the framework version. The legacy Copier template scaffold is
versioned by the same release tags for projects still on that path. This document defines the
version scheme, what constitutes a breaking change on each surface, and how updates land.

## Version Scheme

FORGE uses semantic version tags. Released tags to date: **v1.0.0**, **v2.0.0**, **v2.1.0**, and
**v3.0.0** (released 2026-07-16 — the plugin-primary release). Each tag corresponds to a commit on
the `main` branch of the upstream source.

The scheme follows:
- **MAJOR**: Breaking changes (removed/renamed commands, removed variables, restructured directories, delivery-model changes)
- **MINOR**: New features, new files, new commands (backward-compatible)
- **PATCH**: Bug fixes, documentation updates, process-only changes

| Tag | Bump | Summary |
|-----|------|---------|
| v1.0.0 | — | First tagged release of the FORGE template. |
| v2.0.0 | MAJOR | Template restructure and command-surface changes. |
| v2.1.0 | MINOR | Additive commands and process refinements. |
| v3.0.0 | MAJOR | **Plugin-primary distribution** (released 2026-07-16): the framework surface ships as a Claude Code plugin; `/forge init` scaffolds projects with no Copier; Copier retained as the explicit legacy path. Also: Copier `_min_copier_version` pin (Spec 294), always-on signal capture (Spec 340). See migration note below. |

## Two versioned surfaces

| Surface | Versioned by | How updates arrive |
|---|---|---|
| **Plugin (the framework runtime)** | `plugin.json` `version` — matches the release tag | Reinstall/update the plugin; commands, agents, skills, and hooks all move together |
| **Project scaffold (your project's data)** | The release that scaffolded it; legacy Copier projects record the exact synced commit in `.copier-answers.yml` (`_commit`) | Plugin-native scaffolds: nothing to re-render — project files are yours; generated docs refresh with the plugin. Legacy Copier projects: `/forge stoke` / `copier update` |

Generated reference documents (quick reference, command reference, configuration reference) carry
a provenance header naming the plugin version and source content hash, plus a revision-history
section — you can always tell which framework version produced them.

## What's Breaking

A **breaking change** requires consumer action:

| Category | Example | Consumer Impact |
|----------|---------|-----------------|
| **Removed/renamed command** | A standalone command's function is folded into `/close` and the old name retired | Muscle memory + automation referencing the old name breaks |
| **Delivery-model change** | v3 plugin-primary cutover | One-time migration (see v3.0.0 notes) |
| **File rename/move** (legacy scaffold) | `.forge/commands/foo.md` → `.claude/commands/foo.md` | Old path orphaned on `copier update` |
| **Removed Copier variable** (legacy scaffold) | `use_wsl2` removed from `copier.yml` | `.copier-answers.yml` has stale key; Copier may warn |
| **Changed directory structure** (legacy scaffold) | `docs/process-kit/` → `.forge/docs/` | Existing files at old path not moved automatically |

## What's Not Breaking

These changes are absorbed automatically:

| Category | Example | Why Safe |
|----------|---------|----------|
| **New command/skill/agent** | New command in the plugin payload | Arrives with the plugin update; purely additive |
| **Content update to an existing command** | Updated instructions in `implement.md` | Plugin update replaces the payload atomically |
| **Generated-doc refresh** | Quick reference regenerated | Provenance header records the new source version |
| **Process-kit updates** (legacy scaffold) | Revised runbook, scoring rubric | Merge or overwrite per `update-manifest.yaml` classification |

## How legacy Copier updates are handled

For projects on the legacy scaffold path, each template file has a classification in
`.forge/update-manifest.yaml` (`merge` / `overwrite` / `skip` / `prompt`); `/forge stoke` applies
them and pauses on merge conflicts for manual resolution.

## Migration Notes

When a breaking change ships, it is documented here with migration steps.

### v3.0.0 — plugin-primary release (2026-07-16)

**Breaking**:
- **Plugin-primary distribution**: the framework surface (commands, agents, skills, hooks) is delivered by the installed plugin, not by files rendered into your project. Pre-v3 projects keep working, but framework updates arrive via the plugin from here on.
- **Copier minimum-version pin** (Spec 294): `copier.yml` sets `_min_copier_version` — legacy-path consumers on an older Copier must upgrade before `copier update` runs.
- **Always-on signal capture** (Spec 340): closing a spec records retro signals automatically.

Migration steps (pre-v3 FORGE project → plugin consumer):
1. Install the plugin: `claude plugin marketplace add Renozoic-Foundry/forge-public`, then `/plugin install forge@forge`.
2. Run `/forge init` in the project — it detects the pre-plugin layout and offers the upgrade path (project-local command copies are superseded by the plugin's).
3. Staying on the legacy Copier path instead? Upgrade Copier (`pip install -U copier`) to satisfy the version pin, then `/forge stoke`.

**Erratum (2026-07-17)**: the v3.0.0 release notes initially described `/forge-init` greenfield
scaffolding as Copier-free before the zero-Copier scaffolder had shipped in the public cut; the
capability landed with the Spec 557 cutover included in v3.0.0's final re-cut. The public
CHANGELOG carries the corresponding erratum entry.
