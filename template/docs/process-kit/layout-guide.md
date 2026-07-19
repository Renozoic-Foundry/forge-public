# Project Layout Guide — classic vs contained (Spec 575)

Last verified: 2026-07-17 (Spec 575)

FORGE process data (specs, sessions, decisions, research, process-kit, backlog) lives at
locations resolved through the `forge.paths.*` config family (Spec 564). Two named presets:

| Preset | Where process data lives | When to use |
|---|---|---|
| `classic` | `docs/specs`, `docs/sessions`, … `docs/backlog.md` | Existing projects (the pre-575 default); teams whose `docs/` tree is FORGE-first |
| `contained` | `.forge/project/specs`, `.forge/project/sessions`, … `.forge/project/backlog.md` | **Default for new scaffolds.** Keeps FORGE files cleanly segregated from the solution's own `docs/` |

**Behavior-neutral rule**: an absent `forge.paths` block IS the classic layout — existing projects
are untouched until they opt in. The block lives under `## Runtime Configuration` in `AGENTS.md`;
both helpers read it: `forge_path <key>` (bash, after `forge_config_load AGENTS.md`) and
`forge-py …/runtime_config.py path <key>` (python).

## Choosing at scaffold time

`/forge init` asks; `contained` is the default (opt out with `--layout classic`). Both layouts
write `.forge/ownership.yaml` (schema 1) — the machine-readable manifest of FORGE-owned paths.
List it or partition the whole repo with:

```bash
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/ownership.py --list
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/ownership.py --partition
```

## Switching an existing project

`/configure` → Layout: writes (or removes) the config block — **config only, no file moves**.
The physical migration (git mv of process data, reference rewrites) is the Spec 577 retrofit
flow (`/forge retrofit`, Phase 3). Between the config switch and the migration, `forge-doctor`
reports the interim state:

- **pre-migration WARN** — configured location absent while classic location holds data;
- **SPLIT-BRAIN HIGH** — files present in BOTH locations for one key. One location must end up
  owning the data; the doctor finding names the migration flow.

## Runtime-root resolution chain (Spec 576)

The full idiom chain is `CLAUDE_PLUGIN_ROOT` → `FORGE_RUNTIME_ROOT` → `~/.forge/runtime-root`
(pointer file to a pinned framework checkout) → project-local. `bin/forge` honors it end-to-end;
the documented `${CLAUDE_PLUGIN_ROOT:-.}` prefix gains the same reach by setting
`FORGE_RUNTIME_ROOT` in the shell. Optional per-project integrity pin: `forge.runtime.pin`.

## For command prose and scripts (maintainers)

Command bodies carry a `forge:paths-note` header declaring that `docs/...` literals are
classic-default *spellings* to be resolved via the helpers. Runtime scripts resolve through
`forge_path`/`runtime_config.py` or carry a `forge:path-literal-ok (<reason>)` marker
(framework-structure / comment / fixture). `scripts/validate-paths-sweep.sh` guards both —
advisory until its graduation trigger (Spec 577 close or +30 days), then strict.
