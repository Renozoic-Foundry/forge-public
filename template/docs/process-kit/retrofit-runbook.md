# Consumer Retrofit Runbook (Spec 577)

Last verified: 2026-07-21 (Spec 596)

Takes any existing project to the clean v3 shape: **de-vendor** (remove framework files the
installed plugin/runtime now owns), **reorganize** (contained layout), **reconcile** (seed the
spec corpus from history). Invoked via `/forge retrofit`; every phase is dry-run by default,
independently skippable, independently committed, and rollback-able.

Engine: `${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/retrofit.py <phase> [--dir D] [--apply] [--plugin-root P]`

## Phases

| Phase | Mutates | Gate | Rollback |
|---|---|---|---|
| `inventory` | nothing (read-only) | — | — |
| `devendor` | `git rm` of **pristine** vendored files only | Installed plugin/runtime required (refuses otherwise — AC9); shadow-delete + smoke-test scan (Spec 595) runs first and surfaces `orphaned-consumers`; operator confirms after seeing the FULL removal list; mixed-team re-confirmation (non-Claude devs ⇒ Spec 576 runtime or explicit Claude-only acceptance) | `migration-snapshot.sh restore` |
| `reorganize` | `git mv` process data → `.forge/project/`; writes `forge.paths` + `ownership.yaml` | operator confirms move list; verify after with `check-doc-links.py` + `forge-doctor` (D-PATHS) | snapshot / `git mv` back |
| `reconcile` | plants `reconcile-pending` marker or runs bounded `/reconcile` | scope choice (90d / 200 commits / full) | marker delete |

## Classification rules (inventory)

- **vendored-pristine** — byte-identical to the installed payload copy → removable in Phase 2.
- **vendored-modified** — hand-edited framework copy → HELD; port the edit upstream or explicitly accept loss. Never auto-removed. `inventory` additionally reports the total commit count for each entry (`git log --oneline -- <path>`, Spec 595 CI-012) — a low count (1-4) is almost always stock-with-version-drift, not a hand-edit worth preserving; diffstat alone false-positives version-skew as a local modification.
- **vendored-no-counterpart** — not in the installed payload → HELD; check plugin version or keep.
- **orphaned-consumers** (Spec 595) — a *different* category from the three above: files OUTSIDE the vendored prefixes (`bin/forge`, `bin/forge.ps1`, `.forge/bin/tests/*.py`, any repo-root `*.py` importing `.forge.lib.*`, etc.) that would break if the `vendored-pristine` set were actually removed. Detected empirically, not by pattern-matching: `devendor`'s dry-run path creates a disposable `git worktree` at the current commit, simulates removal (`git rm`) of the `removable` set inside that copy only, and runs a bounded smoke check before and after — Python `compileall`/import over retrofit's own test files and any `.forge.lib`-importing repo-root scripts, plus `bin/forge --version` / `bin/forge.ps1 --version` invocation if present. Whatever passed before the simulated deletion but fails after is reported as `orphaned-consumers`, naming the broken entry point and which check (compile/invoke) caught it. This directly replaces static literal/import/shell-reference scanning, which misses indirect consumption (dynamic imports, string-built paths, convention-based shell invocation) that an empirical "does it still work" check catches by construction. Never auto-removed — same disposition-gate posture as `vendored-modified`/`vendored-no-counterpart`; the operator decides per file: delete (genuinely dead), keep (still needed/project-owned), or defer. The disposable worktree/copy is always torn down afterward (success, failure, or error) — the real project tree is never mutated during detection.
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

## Split-file rendering + `forge.paths.generated` (Spec 596)

`docs/.generated/` (the split-file rendering sibling directory — Spec 398/399) is **never
moved** by `reorganize`: only the curated parent files (`docs/backlog.md`,
`docs/specs/README.md`, `docs/specs/CHANGELOG.md`, etc.) relocate to `.forge/project/`.
Their `<!-- FORGE-INCLUDE: ... -->` marker text is also never rewritten. Without a fix,
this leaves the marker's parent-relative path pointing at a now-wrong location once the
parent moves, and `derived_state.py --skip-canonical-write` fails with "degenerate
split-file state".

When `reorganize --apply` detects `docs/.generated/` present, it pins the directory's
repo-relative location explicitly by writing a `forge.paths.generated: docs/.generated`
entry into the same `forge: paths:` block it already writes for `specs`/`sessions`/etc.
(`.forge/lib/retrofit.py::phase_reorganize()`). No `forge.paths.generated` key is written
when `docs/.generated/` is absent (classic layout with no split-file adoption — a no-op for
this concern, unchanged from before this spec).

Consumers of the key:
- `.forge/lib/runtime_config.py` — `PATH_DEFAULTS["generated"] = "docs/.generated"`, resolved
  the same way as every other `forge.paths.*` key (Spec 564 mechanism).
- `.forge/lib/derived_state.py::detect_mode()` and `.forge/lib/assemble_view.py::assemble()`
  — both resolve a FORGE-INCLUDE marker's target by trying the marker's own parent-relative
  path first (unchanged, legacy-compatible), then falling back to the artifact's basename
  resolved against `forge.paths.generated` when the parent-relative path no longer exists
  (e.g. after `reorganize` moved the curated parent).
- `render_backlog.py`, `render_changelog.py`, `render_spec_index.py` — `--split-file-target`
  now defaults to `<forge.paths.generated>/<artifact-filename>` instead of a hardcoded
  `docs/.generated/<artifact-filename>`.

Idempotent: re-running `reorganize --apply` on an already-reorganized project is a no-op
before the `forge.paths` block is ever touched again (the phase's existing "nothing to
move" early-return), so the key is never duplicated.

## Runtime resolution — plugin-cache probe (Spec 583)

`retrofit.py` resolves its runtime in order: `--plugin-root` arg → `CLAUDE_PLUGIN_ROOT` →
`FORGE_RUNTIME_ROOT` → **standard plugin cache probe**
(`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>`, newest version by numeric-tuple
comparison). Explicit settings always win; the probe fires only when nothing is set — no more
manual `CLAUDE_PLUGIN_ROOT` exports just to run an inventory (SIG-SMILEY1 item 8). The refusal
message names every probed location.
