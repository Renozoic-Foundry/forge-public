# Consumer Retrofit Runbook (Spec 577)

Last verified: 2026-07-17 (Spec 577)

Takes any existing project to the clean v3 shape: **de-vendor** (remove framework files the
installed plugin/runtime now owns), **reorganize** (contained layout), **reconcile** (seed the
spec corpus from history). Invoked via `/forge retrofit`; every phase is dry-run by default,
independently skippable, independently committed, and rollback-able.

Engine: `${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/retrofit.py <phase> [--dir D] [--apply] [--plugin-root P]`

## Phases

| Phase | Mutates | Gate | Rollback |
|---|---|---|---|
| `inventory` | nothing (read-only) | — | — |
| `devendor` | `git rm` of **pristine** vendored files only | Installed plugin/runtime required (refuses otherwise — AC9); operator confirms after seeing the FULL removal list; mixed-team re-confirmation (non-Claude devs ⇒ Spec 576 runtime or explicit Claude-only acceptance) | `migration-snapshot.sh restore` |
| `reorganize` | `git mv` process data → `.forge/project/`; writes `forge.paths` + `ownership.yaml` | operator confirms move list; verify after with `check-doc-links.py` + `forge-doctor` (D-PATHS) | snapshot / `git mv` back |
| `reconcile` | plants `reconcile-pending` marker or runs bounded `/reconcile` | scope choice (90d / 200 commits / full) | marker delete |

## Classification rules (inventory)

- **vendored-pristine** — byte-identical to the installed payload copy → removable in Phase 2.
- **vendored-modified** — hand-edited framework copy → HELD; port the edit upstream or explicitly accept loss. Never auto-removed.
- **vendored-no-counterpart** — not in the installed payload → HELD; check plugin version or keep.
- **process-data / config / project** — FORGE process files, identity/config, and everything else. Project files are untouched by every phase.
- **ambiguous** — `docs/` content outside process-data locations → operator disposition, never guessed.

## Safety contract

Dry-run default; `--` separators and control-character rejection on all git path arguments;
explicit-path commits per phase; no history rewrite, no force-push, no remote touch; phases are
idempotent (mid-phase kill → re-run the phase or restore the snapshot).

## Interrupted-phase recovery

Re-run the phase: `devendor` skips already-removed files; `reorganize` skips already-moved keys;
`reconcile` re-plants the marker harmlessly. Full restore: `bash .forge/lib/migration-snapshot.sh restore`.

## After retrofit

`/forge stoke`'s framework-file classifications become no-ops for this project (framework updates
arrive via the plugin); scaffold-file updates still apply for Copier-era projects. Run
`forge-doctor` — D-PATHS should be clean (no split-brain) and `ownership.py --partition` should
show the exact FORGE/solution split.
