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

### Step 0pre.0a — Legacy artifact detection (Spec 431, report-only)

Run **before** the `.gitignore` audit so legacy findings surface in the same
operator interaction window as the consent prompts that follow. Detection is
report-only by default — no file is touched, no cleanup runs at this step.

```bash
# Manifest + hash-pinned catalog scan against ~/.claude/ + project tree.
.forge/bin/forge-py .forge/lib/stoke.py detect-legacy \
  --project-root . \
  --template-root .forge
```

The detect-legacy helper enumerates three classes:

- **Manifest-orphan** (Req 2): files recorded in `~/.claude/.forge-installed.json`
  for this project's `_src_path` that the current template no longer ships.
  Provably FORGE-placed.
- **Legacy-signature match** (Req 3): pre-manifest artifacts matching the
  hash-pinned catalog at `template/.forge/data/legacy-signatures.yaml`.
  Exact-sha256 only; no fuzzy match.
- **Project-orphan** (Req 10): files in the project tree the install manifest
  recorded but the current template no longer ships. `copier update --pretend`
  is additive and does NOT report orphans, so this scope is in.

**Opt-out flags (operator-explicit per invocation; no env, no config)**:

- `--skip-legacy-scan` — bypass detection entirely for tight-loop iteration
  sessions (Req 12). The helper exits 0 immediately.
- `--ack <artifact-id>` — suppress re-reporting a stable artifact. Ack is
  stored in `.copier-answers.yml::_acknowledged_legacy_artifacts`
  (project-local). Ack **does NOT** grant cleanup consent (Req 11, AC 14) —
  it only mutes the report.

**Cleanup is a separate operator action** — never auto-triggered from
detection. To act on detected findings:

```bash
# Preview only (no deletion, no backup write):
.forge/bin/forge-py .forge/lib/stoke.py cleanup-legacy --dry-run

# Perform deletion with backup snapshot (per-invocation consent; no
# persistent consent, no env var):
.forge/bin/forge-py .forge/lib/stoke.py cleanup-legacy --consent
```

Cleanup hard-refuses on: symlinks (Req 7, AC 10), paths canonicalizing outside
`~/.claude/` or the project tree (AC 11), and `~/.claude/CLAUDE.md` sections
whose `FORGE:BEGIN <id>` is not manifest-attested for this `_src_path`
(Req 1b, AC 22). Backups land at
`$TMPDIR/forge-stoke-legacy-cleanup-<ISO8601>-<PID>/` with mode 0700;
30-day retention warning emitted (Req 6).

**Offline source** (Req 13): if `_src_path` is unreachable, detection falls
back to manifest-only mode (no `current_template_user_files` set comparison)
and emits a diagnostic naming the unreachable source. No silent failure.

**Non-blocking**: detection errors emit a diagnostic and stoke continues. The
gate is detection-first, never silent deletion — Constraints from spec hold.

**Stale `include_*` flag advisory (Spec 429)**: in the same operator-interaction
window, run the stale-flag scan so any `include_*` answers in
`.copier-answers.yml` that reference no module at the pinned `_commit` are
surfaced alongside legacy/orphan findings:

```bash
.forge/bin/forge-py .forge/lib/stoke.py audit-stale-flags
```

Each stale flag emits one line to stdout: `Stale flag: <flag>: <value>
references no module at _commit <short-sha>. Remove from .copier-answers.yml
if unused.` Resolver-unreachable cases (offline / shallow / `_src_path`
missing / sparse-checkout incomplete) silent-skip with a stderr diagnostic;
the gate is advisory and never blocks. Exit code is always 0 — operator
discretion drives any cleanup.

### Step 0pre.0 — Consumer `.gitignore` audit (Spec 433)

Run the consumer-`.gitignore` audit BEFORE the `--trust` consent prompt so the operator decides on `.gitignore` updates and Copier `--trust` in a single up-front interaction window.

```bash
# Report-only (no file changes):
.forge/bin/forge-py .forge/lib/stoke.py audit-gitignore
```

The audit:

- Detects active project types via Spec 432's catalog (`template/.forge/data/project-type-exclusions.yaml`).
- For each active type, checks the consumer's project-root `.gitignore` for the corresponding required rules.
- Match semantics: substring + trailing-slash equivalence. Comment lines (`#...`) and negation lines (`!...`) are stripped before matching to eliminate false positives (DA W-1).
- Emits a terse per-type line ("Maven: missing `target/`") plus a copy-pasteable diff block if anything is missing.

**Operator consent — `--apply`**: if the audit reports missing rules, the calling command body prompts:

```
Append missing rules to .gitignore? (y/N)
```

- On `y`: re-invoke `audit-gitignore --apply`. The helper appends with a single header comment (`# Added by /forge stoke <YYYY-MM-DD>`), preserves existing content byte-for-byte, and preserves the file's line ending (CRLF or LF).
- On `n` / empty: stoke proceeds. No nagging. The operator can run the audit again later.

**Skip flag**: `--no-gitignore-audit` short-circuits the audit for the current invocation. Operator-explicit per invocation — no env-var, no config (Req 4).

**Non-blocking** (Req 5): audit-helper errors emit a warning and the stoke flow continues. A `n` answer never aborts.

### Step 0pre.1 — Operator `--trust` consent prompt (CISO Req 1 / AC 7; Spec 428 dynamic enumeration)

Copier `--trust` is **per-invocation operator-explicit** — never baked into defaults, never from env, never from config. Before invoking `direct-apply`, the calling agent MUST enumerate the `_tasks` declared in the source `copier.yml` and present them verbatim to the operator. Per Spec 428, the task list is sourced at prompt time — never hardcoded — so the prompt stays accurate as the template evolves.

```bash
# Enumerate tasks dynamically (Spec 428):
.forge/bin/forge-py .forge/lib/stoke.py list-tasks
```

Then build the prompt by substituting the helper's stdout into `<tasks>` below. If `list-tasks` exits non-zero (malformed `copier.yml` or unreachable source), abort the stoke and surface the error — do not proceed to the consent prompt with stale or partial data.

```
This stoke run will invoke `copier update`, which executes `_tasks` defined by
the template. copier requires --trust to execute template tasks. The following
tasks will run if you consent:

<tasks>

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

### Step 0pre.2b — Refresh install manifest (Spec 431, Req 1)

If `direct-apply` exited 0, refresh `~/.claude/.forge-installed.json` so the
manifest reflects the post-stoke file set under `~/.claude/` for this
project's `_src_path`. The manifest is the spine for future legacy detection;
without this refresh, Step 0pre.0a's manifest-orphan detection would report
the just-applied state as orphans.

```bash
.forge/bin/forge-py .forge/lib/stoke.py manifest-init \
  --project-root . \
  --template-root .forge \
  --spec-id 431-stoke-refresh
```

Skip this step if `direct-apply` exited non-zero — the apply didn't land, so
the manifest should still reflect the prior state. Failure of `manifest-init`
itself is non-blocking: the apply succeeded, the manifest just falls one
stoke behind and will catch up on the next run.

### Step 0pre.2c — Pre-commit hook install (Spec 440)

Install the backlog-render pre-commit hook so `docs/backlog.md` stays current with per-spec frontmatter. **Idempotent** — safe to run on every stoke. Skip silently if the hook scripts are absent (consumer hasn't migrated past Spec 440).

```bash
# Skip if hook source files are missing (pre-Spec-440 consumer)
if [ ! -f .forge/hooks/pre-commit-render-backlog.sh ]; then
  : # nothing to install yet
else
  marker='# FORGE-PRE-COMMIT-HOOK: spec-440-backlog-render'
  hook_path='.git/hooks/pre-commit'
  mkdir -p .git/hooks
  if [ ! -f "$hook_path" ]; then
    # No existing hook — create a minimal dispatcher
    cat > "$hook_path" <<HOOK
#!/usr/bin/env bash
$marker
exec .forge/hooks/pre-commit-render-backlog.sh "\$@"
HOOK
    chmod +x "$hook_path"
    echo "Spec 440: installed pre-commit hook"
  elif ! grep -qF "$marker" "$hook_path"; then
    # Existing hook — chain to ours
    printf '\n%s\n.forge/hooks/pre-commit-render-backlog.sh "$@" || exit $?\n' "$marker" >> "$hook_path"
    echo "Spec 440: chained pre-commit hook into existing $hook_path"
  fi
fi
```

**PowerShell parity**:

```powershell
if (-not (Test-Path '.forge/hooks/pre-commit-render-backlog.ps1')) {
  # Pre-Spec-440 consumer — nothing to install
} else {
  $marker = '# FORGE-PRE-COMMIT-HOOK: spec-440-backlog-render'
  $hookPath = '.git/hooks/pre-commit'
  New-Item -ItemType Directory -Force -Path '.git/hooks' | Out-Null
  if (-not (Test-Path $hookPath)) {
    @"
#!/usr/bin/env bash
$marker
# Cross-platform dispatch — bash on POSIX, PowerShell on Windows
if command -v pwsh >/dev/null 2>&1 && [ -f .forge/hooks/pre-commit-render-backlog.ps1 ]; then
  exec pwsh -NoProfile -File .forge/hooks/pre-commit-render-backlog.ps1
else
  exec .forge/hooks/pre-commit-render-backlog.sh "`$@"
fi
"@ | Set-Content -NoNewline -Path $hookPath
    Write-Host "Spec 440: installed pre-commit hook"
  } elseif (-not (Select-String -Path $hookPath -SimpleMatch $marker -Quiet)) {
    Add-Content -Path $hookPath -Value "`n$marker`n.forge/hooks/pre-commit-render-backlog.sh `"`$@`" || exit `$?"
    Write-Host "Spec 440: chained pre-commit hook into existing $hookPath"
  }
}
```

This step is the **migration vector** for Spec 440 — consumers who upgrade past this spec receive the hook on their next `/forge stoke`. Consumers who skip stoke see no change (file remains tracked, no hook, frontmatter edits don't auto-rerender) — that's the status quo, not a regression.

**Hook bypass paths** (CI bots, GitHub web-UI, `--no-verify`, second machines without install) skip the render. Recovery is automatic on the next operator-side commit, or explicit via re-running `/forge stoke` or `/matrix`. See `docs/decisions/ADR-440-generated-backlog-storage-model.md` § Consequences for the full residual-risk discussion.

### Step 0pre.3 — STOP

**After `direct-apply` (and manifest refresh) exits**, `/forge stoke` is COMPLETE. Report the helper's exit code and any recovery output it emitted, then end the command.

> **DO NOT proceed to Step 0z below. DO NOT proceed to Step 0a, Step 0a.5, Step 0b, Step 3, or any subsequent section. The text below Step 0pre is LEGACY REFERENCE ONLY — it documents a removed apply pipeline (shadow-tree) whose underlying stoke.py subcommands no longer exist. Executing any of it will error.**

Acceptable terminal actions after Step 0pre completes:
- Report `direct-apply` exit code + backup snapshot path to the operator
- If exit code != 0: surface the recovery output that the helper already emitted
- If exit code == 0: confirm success ("stoke complete; backup at `<path>`")
- Run the post-apply audit if desired: `.forge/bin/forge-py .forge/lib/stoke.py audit <backup-dir>` (this is the only legacy step worth preserving — it inspects governance-file deltas against the backup snapshot rather than against a removed shadow tree)
- End the command

## [mechanical] Scoped-staging contract (Spec 432)

When `/forge stoke` needs to commit on the consumer's behalf — for example to persist Step 0b restorations before `copier update`, or to satisfy Copier's clean-tree requirement on retry — the calling agent MUST use the `safe-stage` subcommand. **Never** `git add -A` or `git add .` from the stoke flow:

```bash
# Stage tracked + restored files through the project-type exclusion filter:
.forge/bin/forge-py .forge/lib/stoke.py safe-stage \
    --restored .forge/state/restored.json other/restored/file \
    --commit-message "Spec 432: persist Step 0b restorations"
```

Behavior:

- Detects active project types by scanning the project root for manifest files (`pom.xml`, `package.json`, `pyproject.toml`, etc. — see `template/.forge/data/project-type-exclusions.yaml`).
- Builds an exclusion pattern set from the catalog plus any `project_type_exclusions_extra:` list in `.copier-answers.yml` (Req 8 — operator extras EXTEND, do not replace the template catalog).
- Stages `git ls-files` tracked paths plus the `--restored` set, with any exclusion-matching paths filtered out. Each path is added via explicit `git add -- <path>` — no wildcards.
- `--allow-dirty` (when threaded through from `direct-apply`) does NOT relax the exclusion catalog (Req 5). It only authorizes proceeding with a dirty tree; build artifacts remain blocked.
- After commit (`--commit-message` set), runs the post-commit audit. Any exclusion-listed path that landed in the commit exits non-zero and prints recovery commands naming the offending paths.

Standalone post-hoc audit of an existing commit:

```bash
.forge/bin/forge-py .forge/lib/stoke.py audit-commit --commit-ref HEAD
# exit 0  → clean
# exit 8  → offenders printed; commit must be amended/reset before pushing
```

Catalog extension (operator-curated, no code change): add new project types or extra patterns by editing `template/.forge/data/project-type-exclusions.yaml`, or set `project_type_exclusions_extra:` in `.copier-answers.yml` for consumer-specific paths.

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
