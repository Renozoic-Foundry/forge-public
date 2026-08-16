---
name: forge-stoke
description: "Pull upstream FORGE updates into this project using Copier"
workflow_stage: lifecycle
argument-hint: "[--to-plugin] [--dry-run] [--merge-native] [--consent-key KEY=true]"
---
# Framework: FORGE
## Subcommand: stoke

> **(compat: prefer /forge <sub>)** — `/forge stoke` is the advertised form (Spec 579 single
> advertised path); this top-level alias remains for compatibility.

> Pull upstream FORGE updates into this project via the content-merge engine (Spec 559/591).
> The Copier apply path was deleted in v4.0.0 (Spec 558).
>
> **Chicken-and-egg note**: if the `/forge` command surface itself is missing, (re)install the
> plugin — `claude plugin marketplace add Renozoic-Foundry/forge-public`, then
> `/plugin install forge@forge` — and run `/forge stoke` from the restored surface.

## [mechanical] Step 0pre — Apply pipeline (content-merge; Spec 559/591, Copier path deleted by Spec 558)

Step 0pre is the ENTIRE apply pipeline. The legacy shadow-tree steps were excised by Spec 430; the Copier-direct (`copier update`) backend that replaced them was deleted by Spec 558 (v4.0.0). The only step that follows Step 0pre is Step 0z (lane-mismatch warning, advisory only).

### Step 0pre.-2 — `--to-plugin` opt-in converter dispatch (Spec 560)

**Check FIRST, before Step 0pre.-1 and every other Step 0pre sub-step.** If `$ARGUMENTS` contains `--to-plugin`: this invocation is a one-shot **un-embed migration** off Copier-managed classic mode onto plugin consumption (the field-validated F9 playbook) — NOT the ongoing `--merge-native` content-merge mechanism (Spec 559, a different job). Skip every other Step 0pre sub-step and run only this branch, then STOP.

**Never auto-triggered (Req 5)**: absent an explicit `--to-plugin` flag on THIS invocation, this step is a silent no-op. No default `/forge stoke` path, env var, `.copier-answers.yml` key, or persisted config routes here — every migration requires the operator to type `--to-plugin` again, every time (mirrors the `--trust` consent-gate pattern).

**Lane B / regulated / pinned-kit consumers stay opt-in-never-forced (Req 8)**: if `docs/compliance/profile.yaml` (or an equivalent pinned-kit marker) is present, the converter refuses by default. Passing `--override-lane-b` in addition to `--to-plugin` proceeds anyway — an explicit second signal, not a silent bypass.

```bash
# Dry run — report only, zero filesystem writes:
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke.py to-plugin \
    --dry-run --project-root .

# Live run — reuses Spec 297's pristine-vs-forked byte-diff and Spec 427's
# backup/consent pattern; never invented fresh:
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke.py to-plugin \
    --project-root .

# Lane B / pinned-kit override (only after the operator has confirmed the
# consumer intends to leave the pinned-kit posture):
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke.py to-plugin \
    --project-root . --override-lane-b
```

The helper orchestrates (in order), all in-scope for the current invocation only:

1. **Preflight** — confirms a canonical plugin framework tree is reachable (`--plugin-root`, or `$CLAUDE_PLUGIN_ROOT` when the FORGE plugin is installed) and reads `.copier-answers.yml`'s `_commit` for the embedded framework version. Aborts with a clear message if neither is set — nothing to migrate to.
2. **Manifest walk** — reads `.forge/update-manifest.yaml`'s `framework` bucket, diffs each tracked framework-code file's embedded copy against the plugin's canonical version at the same relative path. **Byte-identical (pristine)** → removal candidate. **Locally modified (forked)** → always kept as a project override and always named in the report — a fork is never silently deleted (Req 6). `project`/`merge`-bucket files (specs, sessions, CLAUDE.md/AGENTS.md, etc.) are untouched by this step.
3. **Hook rewire** — removes `.claude/settings.json` hook entries that invoke `.forge/bin/*` scripts (the plugin registers its own hooks via its manifest); a hook group that doesn't match the expected embedded shape is left alone and flagged for manual review rather than silently overwritten.
4. **Apply** — with `--dry-run`, only the report above is printed (no writes). Without it, `git rm` removes exactly the pristine files, the settings.json rewrite (if any) is staged, and the whole change lands as **exactly one commit** (via explicit-path `git add`, never `git add -A`).

**Rollback**: the migration is always a single commit — `git revert <migration-sha>` restores every removed pristine file and the pre-migration hook entries. The converter itself never invokes `git reset --hard`, `git push --force`, or any other destructive/history-rewriting operation.

**No regression to the default path**: `/forge stoke`'s no-flag behavior (content-merge apply below) is unchanged by this step's existence — `to-plugin` is purely additive.

### Step 0pre.-1 — the apply pipeline: content-merge (Spec 559/591; sole backend since v4.0.0)

The content-merge upgrade mechanism (`.forge/lib/upgrade_merge.py`, invoked via
`stoke.py apply`) is the ONLY `/forge stoke` backend — Spec 558 deleted the classic
`copier update` pipeline and its `--classic` flag (now an unknown-argument error).
A classic-mode invocation (`.copier-answers.yml` present, no plugin runtime) gets the
documented converter-pointer error naming `forge stoke --to-plugin` and
`docs/process-kit/migration-decision-guide.md`. `--merge-native` is accepted as a
no-op alias (content-merge is already the default; the flag exists for consumers'
explicit scripts/muscle memory). Run this branch, then go straight to Step 0pre.3 STOP.
(The advisory sub-steps 0pre.0a/0pre.0 below run in the same interaction window.)

1. **One-shot migration (idempotent, safe to run every invocation)**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/upgrade_migrate_once.py migrate --project-root .
   ```
   Reports `migrated` (first run against a copier-era project — bridges
   `.copier-answers.yml`'s `_commit` / `_acknowledged_legacy_artifacts` into the
   merge-native state format) or `already migrated` (no-op thereafter).

2. **Resolve upstream source**: the installed plugin runtime (`$CLAUDE_PLUGIN_ROOT`)
   is the default "theirs" tree; `--upstream <dir>` overrides it (e.g. a fresh
   checkout at a specific tag). **The merge candidates are exactly the paths the
   consumer's `.forge/update-manifest.yaml` declares FORGE-owned** (its `framework:`
   bucket, minus anything the `project:`/`merge:` buckets claim — Spec 636). Undeclared
   upstream paths are NEVER written to the consumer; the default apply **fails closed**
   (non-zero, no merge) if that manifest is missing or malformed. `--files` overrides
   the manifest for an operator-directed subset. The manifest governs everything except
   itself: `.forge/update-manifest.yaml` sits in the `merge:` bucket so an upstream
   edit can never blind-overwrite it, and an upstream widening of the FORGE-owned set is
   surfaced as a reviewable `ownership-growth` diff rather than silently applied.

3. **Run the default apply** (content-merge via `stoke.py apply`; `.forge/lib/upgrade_merge.py`
   under the hood):
   ```bash
   ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke.py apply \
     --live-root . \
     --upstream <scratch-upstream-dir> \
     --consent-key <key>=true   # repeatable, one per operator-consented key (Spec 591 Req 1)
   ```
   Base-snapshot state lives at `.forge/state/upgrade-base/` — OUTSIDE `.git/`; the
   engine never writes git objects/refs/index directly (closes the git-corruption
   defect class in `docs/process-kit/stoke-recovery-runbook.md` Sec 1a). **First-merge
   safety (Spec 636):** a file with no recorded base is handled by its actual state — a
   brand-new upstream file is adopted, an already-aligned file records its base as a
   no-op, and a **consumer-diverged file is kept as-is and reported `first-adoption-
   required`** (never silently overwritten with upstream). **Installed-base backfill
   (Spec 636):** an already-onboarded consumer (migration marker present, no seeded
   bases) gets its base snapshots seeded from current content in a write-state-only pass
   — no consumer file is touched, no merge runs that invocation; re-run apply to perform
   the real 3-way merge. Every merge invocation also runs the live six-key consent gate
   (see below) ahead of the merge, and appends one `stoke-merge-apply` soak event to
   `docs/sessions/activity-log.jsonl`.

4. **Report**: exit 0 (all files merged clean) — confirm success. Exit nonzero (one
   or more conflicts) — surface the helper's own recovery output verbatim; it names
   the conflicted file(s) and `docs/process-kit/stoke-recovery-runbook.md` (same
   runbook the classic path uses — no parallel recovery reference).

**PowerShell parity**:
```powershell
& ${env:CLAUDE_PLUGIN_ROOT:-'.'}/.forge/bin/forge-py ${env:CLAUDE_PLUGIN_ROOT:-'.'}/.forge/lib/upgrade_migrate_once.py migrate --project-root .
& ${env:CLAUDE_PLUGIN_ROOT:-'.'}/.forge/bin/forge-py ${env:CLAUDE_PLUGIN_ROOT:-'.'}/.forge/lib/stoke.py apply --live-root . --upstream <scratch-upstream-dir>
```

**Live-wired (Spec 591)**: the five consent-gated keys (`test_command`,
`lint_command`, `harness_command`, `include_advanced_autonomy`,
`include_two_stage_review`) now resolve through `runtime_consent_gate.py`'s live gate
as well — `stoke.py apply`'s shared `_live_gate_six_keys` call site runs ahead of
every merge, logging one `consent-gate-live` JSONL event per resolved key to
`docs/sessions/activity-log.jsonl` (fields `{key, event_type, outcome, timestamp}`
only — never the resolved value). This live gate is the SOLE consent mechanism —
the render-time `secret: true` / `forge_consent_gate.py` backstop was deleted with
the Copier surface (Spec 558). Supply per-key CLI consent with repeatable
`--consent-key KEY=true|false` (operator-explicit per invocation — never persisted,
never env/config).

### Step 0pre.0a — Legacy artifact detection (Spec 431, report-only)

Run **before** the `.gitignore` audit so legacy findings surface in the same
operator interaction window as the consent prompts that follow. Detection is
report-only by default — no file is touched, no cleanup runs at this step.

```bash
# Manifest + hash-pinned catalog scan against ~/.claude/ + project tree.
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke.py detect-legacy \
  --project-root . \
  --template-root .forge
```

The detect-legacy helper enumerates three classes:

- **Manifest-orphan** (Req 2): files recorded in `~/.claude/.forge-installed.json`
  for this project's `_src_path` that the current template no longer ships.
  Provably FORGE-placed.
- **Legacy-signature match** (Req 3): pre-manifest artifacts matching the
  hash-pinned catalog at `.forge/data/legacy-signatures.yaml` (payload-resident
  since Spec 558; a `--template-root`-relative copy is honored first when present).
  Exact-sha256 only; no fuzzy match.
- **Project-orphan** (Req 10): files in the project tree the install manifest
  recorded but the current upstream no longer ships.

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
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke.py cleanup-legacy --dry-run

# Perform deletion with backup snapshot (per-invocation consent; no
# persistent consent, no env var):
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke.py cleanup-legacy --consent
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
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke.py audit-stale-flags
```

Each stale flag emits one line to stdout: `Stale flag: <flag>: <value>
references no module at _commit <short-sha>. Remove from .copier-answers.yml
if unused.` Resolver-unreachable cases (offline / shallow / `_src_path`
missing / sparse-checkout incomplete) silent-skip with a stderr diagnostic;
the gate is advisory and never blocks. Exit code is always 0 — operator
discretion drives any cleanup.

### Step 0pre.0 — Consumer `.gitignore` audit (Spec 433)

Run the consumer-`.gitignore` audit before the apply so the operator decides on `.gitignore` updates and the six-key consent answers in a single up-front interaction window.

```bash
# Report-only (no file changes):
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke.py audit-gitignore
```

The audit:

- Detects active project types via Spec 432's catalog (`.forge/data/project-type-exclusions.yaml`).
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

<!-- Step 0pre.05 (unified gate-mediation pre-flight, Spec 444) retired by Spec 558: its
     subject — the gates `copier update` would hit (--trust, Spec 090/437 render validators) —
     was deleted with the Copier surface. The strict-literal consent parser below survives as
     the generic consent-hygiene contract for the live six-key gate. -->

### Step 0pre.05a — Strict-literal consent parser (Spec 444 Req 3a / AC 9; R-Sec-1 — retained post-558 for the live consent gate)

Every consent question `/forge stoke` asks (the Spec 591 six-key live gate, the
`.gitignore` audit `--apply` prompt, cleanup consent) parses answers through this
contract. The AI MUST recognize operator consent ONLY from this exact allow-list,
case-insensitive, after trimming whitespace:

- **Accept**: `yes`, `y`, `confirm`, `approve`, `ok`, `okay`
- **Reject**: `no`, `n`, `cancel`
- **Anything else** (hedged like "yes but only for docs", paraphrased like "go ahead", silence, "sure", restated question, etc.): re-prompt with literal text "Please answer yes or no. To proceed, type one of: yes, y, confirm, approve, ok, okay. To cancel, type: no, n, cancel."

The reference Python implementation of this parser lives in `.forge/tests/test_stoke_consent_parser.py::parse_consent`. The contract is regression-tested mechanically; if the chat-layer behavior drifts from the reference, the tests FAIL.

**Re-prompt limit (Req 3b)**: at most two re-prompts per gate. After the third ambiguous answer, treat as cancel and abort the stoke. Prevents stuck-prompt loops.

**Constraints (load-bearing — closes DA + CISO R1)**:
- The AI MUST NOT infer consent from prior session context, from operator tone, or from the operator having said yes to a different gate earlier.
- The AI MUST NOT cache consent across `/forge stoke` invocations. Each invocation is its own consent boundary.
- The AI MUST NOT construct `--consent-key` flags from any source other than the operator's literal yes-answers in the current chat turn.

<!-- Steps 0pre.05b (copier error-fallback mediation, Spec 444), 0pre.1 (copier --trust
     consent prompt, Spec 427/428) and 0pre.2 (classic `apply --classic` invocation,
     Spec 427/591) retired by Spec 558: `copier update`, its `_tasks` trust gate, and the
     `--classic` branch were all deleted in v4.0.0. Step numbers retired, not reused. -->

### Step 0pre.2a — Doctrine drift report (Spec 640, advisory)

Report whether this project's authorization-core managed block (the condensed
Priority-ordering/Requires-Confirmation/Authorization-required/Prohibited block
delivered into `AGENTS.md` or `CLAUDE.md` by Spec 640) is current against the
installed plugin. **Report-only** — like the other advisory sub-steps above, this
never blocks or auto-regenerates anything.

```bash
DOCTRINE_GEN="${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/doctrine_gen.py"
if [ -f "$DOCTRINE_GEN" ]; then
  INSTALLED_V="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('version',''))" "${CLAUDE_PLUGIN_ROOT:-.}/.claude-plugin/plugin.json" 2>/dev/null)"
  for cand in AGENTS.md CLAUDE.md; do
    if [ -f "$cand" ] && grep -q 'FORGE:DOCTRINE-BEGIN id=authorization-core' "$cand"; then
      python3 "$DOCTRINE_GEN" check --target "$cand" --id authorization-core --installed-version "${INSTALLED_V:-0}"
      break
    fi
  done
fi
```

Surface the result to the operator:
- `DRIFT ...` — names both versions; suggest regenerating (`doctrine_gen.py generate`)
  once the operator confirms. Stoke does not regenerate the managed block
  automatically — the operator decides, matching the report-only pattern above.
- `CONFLICT ...` — a hand-edit was made inside the managed block since it was last
  generated; name the file and let the operator decide (resolve manually, or
  regenerate with `--force` to discard the hand-edit — never silent).
- `OK ...` — current, no action needed.
- `NONE ...` — no managed block found (pre-Spec-640 project, or the markers were
  removed — a silent opt-out per the ADR-640 residual-risk note); informational only.

Skip silently if `doctrine_gen.py` is absent (pre-Spec-640 plugin version).

### Step 0pre.2b — Refresh install manifest (Spec 431, Req 1)

If the apply (Step 0pre.-1) exited 0, refresh `~/.claude/.forge-installed.json` so the
manifest reflects the post-stoke file set under `~/.claude/` for this
project's `_src_path`. The manifest is the spine for future legacy detection;
without this refresh, Step 0pre.0a's manifest-orphan detection would report
the just-applied state as orphans.

```bash
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke.py manifest-init \
  --project-root . \
  --template-root .forge \
  --spec-id 431-stoke-refresh
```

Skip this step if the apply exited non-zero — the apply didn't land, so
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

**After the apply (and manifest refresh) exits**, `/forge stoke` is COMPLETE. Report the helper's exit code and any recovery output it emitted, then end the command.

> **DO NOT proceed to Step 0z below. DO NOT proceed to Step 0a, Step 0a.5, Step 0b, Step 3, or any subsequent section. The text below Step 0pre is LEGACY REFERENCE ONLY — it documents a removed apply pipeline (shadow-tree) whose underlying stoke.py subcommands no longer exist. Executing any of it will error.**

Acceptable terminal actions after Step 0pre completes:
- Report the apply's exit code to the operator
- If exit code != 0: surface the recovery output that the helper already emitted
- If exit code == 0: confirm success ("stoke complete")
- Run the post-apply audit if desired: `${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke.py audit <backup-dir>` (inspects governance-file deltas against a snapshot dir, when one exists)
- End the command

## [mechanical] Scoped-staging contract (Spec 432)

When `/forge stoke` needs to commit on the consumer's behalf — for example to persist restorations ahead of an apply — the calling agent MUST use the `safe-stage` subcommand. **Never** `git add -A` or `git add .` from the stoke flow:

```bash
# Stage tracked + restored files through the project-type exclusion filter:
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke.py safe-stage \
    --restored .forge/state/restored.json other/restored/file \
    --commit-message "Spec 432: persist Step 0b restorations"
```

Behavior:

- Detects active project types by scanning the project root for manifest files (`pom.xml`, `package.json`, `pyproject.toml`, etc. — see `.forge/data/project-type-exclusions.yaml`).
- Builds an exclusion pattern set from the catalog plus any `project_type_exclusions_extra:` list in `.copier-answers.yml` (Req 8 — operator extras EXTEND, do not replace the template catalog).
- Stages `git ls-files` tracked paths plus the `--restored` set, with any exclusion-matching paths filtered out. Each path is added via explicit `git add -- <path>` — no wildcards.
- The exclusion catalog is never relaxed by any flag (Req 5); build artifacts remain blocked.
- After commit (`--commit-message` set), runs the post-commit audit. Any exclusion-listed path that landed in the commit exits non-zero and prints recovery commands naming the offending paths.

Standalone post-hoc audit of an existing commit:

```bash
${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/stoke.py audit-commit --commit-ref HEAD
# exit 0  → clean
# exit 8  → offenders printed; commit must be amended/reset before pushing
```

Catalog extension (operator-curated, no code change): add new project types or extra patterns by editing `.forge/data/project-type-exclusions.yaml`, or set `project_type_exclusions_extra:` in `.copier-answers.yml` (classic-scaffolded projects) for consumer-specific paths.

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
