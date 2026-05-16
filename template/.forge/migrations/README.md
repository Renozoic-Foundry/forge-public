# Per-spec migration convention

> **PROVISIONAL** — this convention is documented after the first per-spec migration (Spec 398/400) shipped. It is subject to refactor by a successor spec when migration #2 lands or when dispatch friction at a second `_tasks` invocation line motivates a registry. Authors should not treat the convention as a frozen public API; expect it to evolve once a second concrete data point exists. See Spec 438 for the rationale and consensus history.

This README codifies how to add a **per-spec one-shot migration** to FORGE so the second migration's author has a stable contract to follow. It does not change anything about the existing Spec 398 migration; that script is grandfathered in place (see § Grandfathered: existing Spec 398 migration below).

## When to use this convention

Use a per-spec migration when a spec changes the **shape of consumer-project state** and that change must be applied exactly once per consumer when they next run `copier update` (typically via `/forge stoke`). Examples:

- Split-file refactor of a tracked artifact (Spec 398 → migration shipped under Spec 400).
- One-shot schema bump for a checked-in state file.
- One-shot relocation or rename of an operator-owned artifact.

Do **not** use this convention for:

- Recurring transformations or per-file conversion logic (those belong inline in `copier.yml` or as part of the template's normal rendering).
- Forward-and-backward-compatible schema changes (no migration needed).
- Anything that would re-run more than once against the same consumer.

## Script naming

Migration scripts live at:

```
template/.forge/migrations/spec-NNN-<slug>.py     # FORGE-internal path
.forge/migrations/spec-NNN-<slug>.py              # path as it appears in a consumer project
```

The script name encodes the spec number for traceability. Use a short `<slug>` after the spec number describing the transformation (e.g., `spec-398-split-file-rendering.py` would be the convention if a fresh-write of the existing migration ever happens — see § Grandfathered below).

## Script ABI

- `argv[1]` is the destination project root path, supplied by Copier as `{{ _copier_conf.dst_path }}` in the `_tasks` invocation.
- The script MUST refuse to operate if the resolved project root does not contain **both** `.copier-answers.yml` and a `.forge/` directory. This is a single-line sanity guard that fails loud — it prevents accidental invocation against arbitrary paths.
- The script writes its sentinel and exits 0 on success.
- The script exits non-zero with a single-line stderr diagnostic on failure (see § Halt-on-failure).

## Invocation (Spec 401)

Migration scripts MUST be invoked through `.forge/bin/forge-py` from the `_tasks` entry in `copier.yml`:

```yaml
  - command:
      - .forge/bin/forge-py
      - .forge/migrations/spec-NNN-<slug>.py
      - "{{ _copier_conf.dst_path }}"
```

**Bare `python3` is forbidden.** Spec 401 made `.forge/bin/forge-py` the mandatory Python invocation surface because:

- It resolves the correct interpreter cross-platform (Windows `python.exe` / `py.exe` / Linux/macOS `python3`).
- It enforces the FORGE Python floor (≥ 3.10) and surfaces a clear error if the consumer's environment is below floor.
- Bare `python3` fails on Windows consumers that lack `python3` on PATH — exactly the failure mode Spec 401 closed.

If you bypass `.forge/bin/forge-py`, you regress Spec 401's invariant for every Windows consumer. The CI/devil's-advocate gates will catch this if the spec's Implementation Summary touches `copier.yml`, but the simpler defense is to follow this section.

## `_tasks` glue requirements (Specs 401, 427, 430)

The `_tasks` entry that invokes a migration script is more than a one-liner. It MUST preserve four pieces of load-bearing shell glue that Spec 400 established empirically:

1. **Sentinel guard** — skip the migration entirely if `.forge/migrations/spec-NNN.applied` is present. This is the primary defense against `_tasks` re-running on every `copier update`. The script's own sentinel-skip is the secondary defense.
2. **Spec 427 stoke-in-progress sentinel detection** — when `/forge stoke` is running its own dirty-tree guard, it writes a PID-stamped sentinel at `.forge/state/stoke-in-progress-<pid>`. The migration entry must check for this and skip the migration when found, so stoke's outer-loop guard isn't double-tripped by the migration's inner-loop guard. See Spec 427 Req 10 / AC 9.
3. **Spec 430 liveness + TTL on the stoke sentinel** — the stoke-in-progress sentinel is honored only if the PID is still alive (`kill -0`) and the sentinel is fresh (within a 60s TTL). Stale sentinels from crashed stoke runs do not block the migration. Spec 430 tightened this from the original Spec 427 behavior.
4. **Spec 401 POSIX-sh prereq advisory** — if the `_tasks` block uses `sh -c` for any of the above guards, surface a clear advisory at the top of the block instructing Windows users to install Git for Windows with Unix tools on PATH (or run from Git Bash). Spec 401 codified this; do not silently fail.

**The recommended pattern is to copy the structure of the existing Spec 398 entry in the root `copier.yml`.** It is the working reference for all four pieces of glue. Adapt the sentinel path and the script invocation; leave the guards alone.

## Sentinel contract (Spec 400)

Each migration writes a sentinel at:

```
.forge/migrations/spec-NNN.applied
```

The sentinel content schema, established by Spec 400 Req 2, is **a single line**:

```
<ISO 8601 UTC timestamp> spec-NNN
```

Example:

```
2026-05-15T18:42:11Z spec-398
```

Write the sentinel **atomically** via tempfile + `os.replace`:

```python
import os, tempfile, pathlib, datetime
sentinel = pathlib.Path(project_root) / ".forge" / "migrations" / "spec-NNN.applied"
sentinel.parent.mkdir(parents=True, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=sentinel.parent, prefix=f"spec-NNN.applied.", suffix=".tmp")
try:
    with os.fdopen(fd, "w") as f:
        f.write(f"{datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')} spec-NNN\n")
    os.replace(tmp, sentinel)   # atomic on POSIX and Windows
except Exception:
    pathlib.Path(tmp).unlink(missing_ok=True)
    raise
```

`os.replace` is atomic on both POSIX and Windows. The tempfile + rename pattern prevents a partial-write window where the sentinel exists but is incomplete.

## Idempotency and halt-on-failure

- **Sentinel-skip on re-run is the primary defense.** Before doing any work, the script checks whether its sentinel is already present. If so, it logs `Spec NNN — skipped (sentinel present)` to stderr and exits 0 without side effects. This protects against `_tasks` running on every `copier update`.
- **Any unhandled exception or pre-condition violation** exits non-zero with a single-line stderr diagnostic that names the failure mode, e.g.:
  ```
  migration spec-NNN: <reason>
  ```
- **No partial sentinel writes.** The sentinel is written via tempfile + `os.replace` (see § Sentinel contract) so a crash mid-work never leaves a half-written sentinel. If the work raises before sentinel write, the migration is in an unmigrated state and will be retried on the next `copier update` invocation.

## Operator escape hatch

Operators may bypass the sentinel manually — there is no env-var bypass. The mechanisms are:

- **Force re-run** a migration: delete its sentinel.
  ```
  rm .forge/migrations/spec-NNN.applied
  ```
  The next `copier update` will re-execute the migration body.
- **Force-skip** a migration (mark it as already applied without running it): create the sentinel manually.
  ```
  touch .forge/migrations/spec-NNN.applied
  ```
  The next `copier update` will treat the migration as already done. Use this only when you know the consumer's state already matches the post-migration shape (e.g., manual fix).

Both mechanisms are explicit and discoverable. There is no env-var or config-flag bypass — the rationale is that hidden bypasses get forgotten and resurface as audit-trail gaps when something goes wrong.

## Grandfathered: existing Spec 398 migration

**The Spec 398 split-file rendering migration is grandfathered in its current location** at `scripts/migrate-to-derived-view.py`, invoked from the root `copier.yml` `_tasks` block as `--mode=split-file`. This script predates the convention documented in this README.

Do **not** relocate the existing script. Touching it would risk regressing Spec 401 (interpreter resolution), Spec 427 (stoke handshake), and Spec 430 (sentinel TTL/liveness) for no immediate user benefit. The convention above is the **going-forward** rule for migration #2 onward.

Migration #2's author should:

1. Author the new script at `template/.forge/migrations/spec-NNN-<slug>.py` per this convention.
2. Add a new `_tasks` entry in root `copier.yml` that invokes the new script through `.forge/bin/forge-py` and preserves the Spec 427/430 stoke-in-progress handshake (copy structure from the Spec 398 entry).
3. **File a successor spec to extract a generic dispatcher** as part of that work. When `_tasks` is about to grow a second migration invocation line, the dispatch surface is the natural point to generalize — but only with the second data point in hand, not before.

The successor spec is the appropriate place to revisit:

- Whether the YAML registry pattern (deferred from Spec 438's earlier draft) is now warranted.
- Whether the existing Spec 398 migration should be retroactively moved into the new convention as part of the same spec, or left in place permanently.
- Commit-range windowing semantics (`applies_from_commit` / `applies_to_commit`) if a real driving requirement appears.

## References

- **Spec 400** — sentinel contract, content schema, atomic write semantics (`spec-NNN.applied` single-line `<ISO timestamp> spec-NNN`).
- **Spec 401** — Python invocation through `.forge/bin/forge-py`; ≥ 3.10 floor; cross-platform interpreter resolution.
- **Spec 427** — stoke-in-progress PID-stamped sentinel handshake (`_tasks` migration entries must skip when stoke is running).
- **Spec 430** — 60s TTL + `kill -0` liveness check on the stoke-in-progress sentinel (tightens Spec 427 against stale sentinels from crashed runs).
- **Spec 438** — this README; rationale and consensus history for README-only scope.
- **ADR-438** — formal decision record at `docs/decisions/ADR-438-migration-script-convention.md`.
