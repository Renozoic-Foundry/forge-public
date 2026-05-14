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

## [mechanical] Step 0pre — Copier-direct apply (Spec 427 mechanism; legacy shadow-tree text excised by Spec 430)

Step 0pre is the ENTIRE apply pipeline. The legacy shadow-tree steps were excised by Spec 430 per /consensus 427 round-4 cross-cutting note. The only step that follows Step 0pre is Step 0z (lane-mismatch warning, advisory only).

Spec 427 replaces the legacy shadow-tree apply mechanism with `copier update` running directly against the consumer's working tree. The apply pipeline is now a single helper invocation, gated by an operator `--trust` consent prompt:

### Step 0pre.1 — Operator `--trust` consent prompt (CISO Req 1 / AC 7)

Copier `--trust` is **per-invocation operator-explicit** — never baked into defaults, never from env, never from config. Before invoking `direct-apply`, the calling agent MUST prompt the operator:

```
This stoke run will invoke `copier update`, which executes `_tasks` defined by
the template (currently: scripts/copier-hooks/scrub_answers.py + Spec 400 split-file
migration). copier requires --trust to run these tasks.

Pass --trust to copier? (y/N)
```

- On operator `y` / `yes`: invoke `direct-apply` with `--trust`.
- On any other response (including empty / `n` / `no` / ambiguous): invoke `direct-apply` WITHOUT `--trust`. Copier will refuse to run the `_tasks` and stoke will report which template-side automation was skipped.

The prompt is unconditional per invocation. There is NO env-var override, NO config file that grants persistent consent, NO `--trust-always` flag. /consensus 427 round 3 CISO hard finding closed by this gate.

### Step 0pre.2 — direct-apply invocation

After collecting `--trust` consent, invoke the helper:

```bash
# Operator answered 'y' to the --trust prompt:
.forge/bin/forge-py .forge/lib/stoke.py direct-apply --trust

# Operator answered 'n' / empty / anything else:
.forge/bin/forge-py .forge/lib/stoke.py direct-apply
```

**PowerShell parity**:

```powershell
# With consent:
.forge/bin/forge-py .forge/lib/stoke.py direct-apply --trust
# Without consent:
.forge/bin/forge-py .forge/lib/stoke.py direct-apply
```

The helper orchestrates (in order):

1. **`_exclude` integrity preflight** — aborts if `copier.yml::_exclude` is empty, missing, or malformed (AC 17).
2. **Dirty-tree guard** — aborts unless `--allow-dirty` is passed.
3. **Old-backup cleanup** — prunes `$TMPDIR/forge-stoke-backup-*` dirs older than 30 days (best-effort).
4. **Pre-apply backup snapshot** — mode-0700 `$TMPDIR/forge-stoke-backup-<ISO8601>-<PID>/` with `.git/` + every file matching `copier.yml::_exclude`.
5. **PID-stamped sentinel write** — `.forge/state/stoke-in-progress-<PID>` so copier.yml `_tasks` can disarm their own dirty-tree check ONLY for this stoke invocation (no inheritable env-var back-channel — /consensus 427 round 3 MT + CISO fix).
6. **`copier update --vcs-ref=$_commit --skip-answered --defaults [--trust]`** — direct in-place. `--trust` only passed if the operator consented at Step 0pre.1.
7. **Sentinel cleanup** — removed on exit (success or failure).
8. **Conflict-marker scan + recovery output** — on copier error or `<<<<<<<` markers, emits operator-actionable recovery commands naming specific files and the backup directory.

Operator override flags (operator-explicit per Req 4 + Constraint):
- `--allow-dirty` — proceed despite uncommitted changes (NOT default; NOT env/config-settable)
- `--no-cleanup-old-backups` — preserve old backups across this invocation
- `--trust` — operator-explicit per-invocation copier consent (NOT default; NOT env/config-settable; /consensus 427 round 3 CISO fix)

### Step 0pre.3 — STOP

**After `direct-apply` exits** (whether 0 or non-zero), `/forge stoke` is COMPLETE. Report the helper's exit code and any recovery output it emitted, then end the command.

> **DO NOT proceed to Step 0z below. DO NOT proceed to Step 0a, Step 0a.5, Step 0b, Step 3, or any subsequent section. The text below Step 0pre is LEGACY REFERENCE ONLY — it documents a removed apply pipeline (shadow-tree) whose underlying stoke.py subcommands no longer exist. Executing any of it will error.**

Acceptable terminal actions after Step 0pre completes:
- Report `direct-apply` exit code + backup snapshot path to the operator
- If exit code != 0: surface the recovery output that the helper already emitted
- If exit code == 0: confirm success ("stoke complete; backup at `<path>`")
- Run the post-apply audit if desired: `.forge/bin/forge-py .forge/lib/stoke.py audit <backup-dir>` (this is the only legacy step worth preserving — it inspects governance-file deltas against the backup snapshot rather than against a removed shadow tree)
- End the command

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
