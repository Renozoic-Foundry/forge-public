<!-- Last updated: 2026-04-25 -->
# Sync Runbook — forge-public Distribution

Step-by-step guide for syncing FORGE upstream changes to the public distribution repo.

## Canonical ↔ Mirror Sync (`.forge/commands/` → `.claude/commands/`) — Spec 329

`forge-sync-commands.sh` regenerates per-agent mirrors from canonical commands. Spec 329 fixed
four runtime defects: frontmatter-preservation, frontmatter-aware `is_forge_command`,
body-to-body `--check`, and refuse-overwrite-without-force.

```bash
# Verify mirrors are in sync (body-to-body)
bash .forge/bin/forge-sync-commands.sh --check

# Regenerate mirrors (will refuse to overwrite if any mirror body diverges)
bash .forge/bin/forge-sync-commands.sh

# Force-overwrite divergent mirrors (only after reviewing the diff)
bash .forge/bin/forge-sync-commands.sh --force

# Run the refuse-overwrite self-test (programmatic AC 4 verification)
bash .forge/bin/tests/test-sync-refuse-overwrite.sh
```

### Exit codes

| Exit | Meaning | When |
|------|---------|------|
| 0    | Success | Clean state, or sync completed without divergence |
| 1    | Drift detected (or argument error) | `--check` found drift, or unknown flag |
| 2    | **Refused overwrite** | A mirror body diverges from canonical and `--force` was not passed |

### When to use `--force`

Only after reviewing the per-file diff that the script printed at exit 2. The diff tells you exactly what content would be lost. Use `--force` when:

1. The mirror has stale content from an earlier session and canonical is now authoritative.
2. You have already moved any mirror-only content that should be preserved into canonical (per the canonical-is-truth principle — see Spec 329 reconciliation rubric).
3. The operator has consented to the overwrite (not implicitly via convenience).

Do NOT use `--force` to bypass the diff display — it is the safety net for the data-loss primitive flagged at /consensus 314.

### Frontmatter-aware behavior

For the `claude-code` agent branch, regen now PRESERVES the mirror's existing frontmatter and replaces only the body. This protects Claude Code's slash-command metadata (`name`, `description`, `workflow_stage`) from being stripped on every sync. Other agent branches (cursor, copilot, cline) retain their pre-329 behavior.

### Cross-agent rubric for mirror-only body content (Spec 329)

When `--check` reports drift in a mirror that has body content not in canonical, classify by:

- `move-to-canonical` — content is general FORGE logic; copy into `.forge/commands/<name>.md` then regen.
- `preserve-as-claude-code-drift` — content references Claude Code-specific features (e.g., `/ultrareview`); move to canonical with graceful degradation for non-Claude agents (recommended) OR leave in mirror only with a documented reason.
- `pull-from-canonical-to-mirror` — REVERSE direction (canonical has content the mirror lacks); regen will pull it in.

## Cross-Level Sync (repo-root ↔ template/) — Spec 270

Run **before** the distribution syncs below. This propagates canonical repo-root sources to their `template/` mirrors so the template reflects current FORGE.

```bash
# Dry-run — preview what would change
bash .forge/bin/forge-sync-cross-level.sh --dry-run

# Apply — propagate repo-root canonical sources to template/ mirrors
bash .forge/bin/forge-sync-cross-level.sh

# Verify — confirm tree is clean (pre-commit safe)
bash .forge/bin/forge-sync-cross-level.sh --check
```

Covers:
- `.forge/commands/*.md` → `template/.forge/commands/*` (Spec 111's per-level sync then regenerates `template/.claude/commands/`)
- `.claude/agents/*.md` → `template/.claude/agents/*`
- `docs/process-kit/*.md` → `template/docs/process-kit/*` (subject to escape hatch)

Escape hatch (intentional-drift list): `.forge/state/expected-cross-level-drift.txt` — FORGE-only docs and command variants with intentional divergence.

Composition: reads `.forge/update-manifest.yaml` — honors `project` (never mirror) and `removed` (delete from mirror) classifications.

Pre-commit install (one-time): `bash .forge/bin/install-pre-commit-hook.sh` (Linux/macOS/Git-Bash) OR `pwsh -File .forge/bin/install-pre-commit-hook.ps1` (Windows without Git Bash) — installs the **combined** pre-commit hook (see next section). Both installers produce a byte-identical hook (UTF-8 no-BOM, LF line endings, same sha256). The hook now invokes both the cross-level check (Spec 270) AND the canonical↔mirror commands-sync check (Spec 314).

**Superseded by Spec 270**: the former `scripts/validate-command-sync.sh` (Specs 132 + 195) is retired. All parity checks are now subsumed by `forge-sync-cross-level.sh --check`.

## Combined Pre-Commit Hook — Specs 270 + 314 + 336

Two byte-identical installers ship the same `.git/hooks/pre-commit` body that runs both sync checks on staged changes. Operators get one hook, two safety nets, with explicit override semantics for emergencies.

**Installer invocation by platform:**

| Platform | Installer command |
|----------|-------------------|
| Linux / macOS / Git-Bash on Windows | `bash .forge/bin/install-pre-commit-hook.sh` |
| Windows native (no Git Bash) | `pwsh -File .forge/bin/install-pre-commit-hook.ps1` |

Both produce a byte-identical hook file (verifiable via `sha256sum` ↔ `Get-FileHash -Algorithm SHA256`). The hook itself runs under bash regardless of how it was installed (Git for Windows ships bash; the hook's `#!/usr/bin/env bash` shebang is honored by Git's hook runner).

### What the hook does

On every `git commit`, the hook inspects staged paths and decides which checks to run:

| Staged path matches | Cross-level check (Spec 270) | Commands-sync check (Spec 314) |
|---------------------|:-----------------------------:|:-------------------------------:|
| `.forge/commands/`        | ✓ | ✓ |
| `.claude/agents/`         | ✓ | — |
| `docs/process-kit/`       | ✓ | — |
| `template/`               | ✓ | — |
| anything else only        | — | — |

When both checks are scheduled, **both run to completion** — no short-circuit on the first failure. Both drift lists and both remediation commands are surfaced together so the operator sees the full picture in one pass.

### Exit semantics

| Hook exit | Meaning |
|-----------|---------|
| 0 | No watched paths staged, OR both relevant checks passed |
| 1 | One or both checks reported drift — commit aborted; stderr lists each failing check with its recovery command |
| 0 (with `FORGE_SKIP_SYNC=1`) | Override path — see below |

### Override: `FORGE_SKIP_SYNC=1`

For genuine emergencies, the override bypasses both checks but **always emits a stderr audit trail** so the bypass is visible in commit logs and shell history:

```bash
FORGE_SKIP_SYNC=1 git commit -m "emergency hotfix"
```

When a check would have failed, the hook prints (to stderr):

```
FORGE_SKIP_SYNC=1 — bypassing pre-commit sync checks
Bypassed checks: forge-sync-cross-level.sh forge-sync-commands.sh
--- Drift from forge-sync-cross-level.sh ---
<full drift list>
--- Drift from forge-sync-commands.sh ---
<full drift list>
--- end FORGE_SKIP_SYNC audit trail ---
```

The override never silences the bypass — the audit trail is the cost of using it. Set `FORGE_SKIP_SYNC=1` only on the single commit that needs it (no `export`).

If both checks would have passed, the override emits a single notice (`FORGE_SKIP_SYNC=1 set but both checks pass — no bypass needed`) and exits 0 normally.

### Idempotent installer

Both installers overwrite `.git/hooks/pre-commit` with the same body — re-running either installer (or alternating between them) produces a byte-identical hook (verifiable via `sha256sum` / `Get-FileHash`). Operators with project-custom pre-commit content must back up their hook **before** running the installer:

```bash
cp .git/hooks/pre-commit .git/hooks/pre-commit.local-backup
bash .forge/bin/install-pre-commit-hook.sh
# Manually merge backup content into the FORGE hook body if needed.
```

Or on Windows native:

```powershell
Copy-Item .git/hooks/pre-commit .git/hooks/pre-commit.local-backup
pwsh -File .forge/bin/install-pre-commit-hook.ps1
# Manually merge backup content into the FORGE hook body if needed.
```

Cross-platform parity is verified by `.forge/bin/tests/test-install-pre-commit-parity.sh` (skips with PASS-SKIP if pwsh is unavailable).

### Recovery if the hook misfires

If the hook is installed but the underlying scripts are broken, missing, or the operator needs a clean slate:

```bash
rm .git/hooks/pre-commit                       # remove the broken hook
git commit -m "..."                            # commit normally (no hook fires)
# After fix lands:
bash .forge/bin/install-pre-commit-hook.sh     # re-install the combined hook
# OR on Windows native:
# pwsh -File .forge/bin/install-pre-commit-hook.ps1
```

The hook itself short-circuits to exit 0 if either underlying script is missing or non-executable — a fresh consumer-bootstrap clone without the FORGE scripts won't see spurious commit failures.

## CI Enforcement — Spec 337

The pre-commit hook is local-only. An operator who skips installation, or who uses `FORGE_SKIP_SYNC=1` to push, can land drift in `main`. CI is the durable backstop.

`.github/workflows/sync-and-lint.yml` runs the same three checks the local hook runs (and one more — repo-wide shellcheck) on every push to `main` and on every PR:

| Step | Script | Spec | What it catches |
|------|--------|------|-----------------|
| Cross-level sync | `bash .forge/bin/forge-sync-cross-level.sh --check` | 270 | template/ ↔ repo-root parity drift |
| Commands sync | `bash .forge/bin/forge-sync-commands.sh --check` | 314 | `.forge/commands/` ↔ `.claude/commands/` parity drift |
| Shellcheck | `bash scripts/validate-bash.sh --verbose` | 313 | shellcheck violations across `.forge/bin/`, `scripts/`, `template/.forge/bin/`, etc. |

**Configuration**: `permissions: contents: read` (least-privilege; no token writes), `timeout-minutes: 5` (runaway insurance). Workflow invokes scripts via `bash <path>` (scripts are tracked `100644` without exec bit by design).

**Failure surface**: each script's own failure message surfaces in the CI log — no custom wrapper. The cross-level and commands scripts emit `FAILED: <N> file(s) out of sync. Run <script> to fix.` on drift; shellcheck emits per-file diagnostics on lint violations.

**Allowlist**: `.forge/state/expected-cross-level-drift.txt` is honored automatically (the workflow runs the unmodified script). No commands-level allowlist exists — by design, the `.claude/commands/` mirror is body-equal to canonical with no exceptions.

**What CI does NOT replace**: the local pre-commit hook is still the fast-feedback path. CI is the merge-blocker for what slips through.

## Pre-Sync Checklist

- [ ] All target specs are `closed` (not `implemented` or `in-progress`)
- [ ] Run `/consensus` with sync-readiness topic — address any CONCERN or REJECT findings before proceeding
- [ ] Working tree is clean (`git status` shows no changes)
- [ ] Run `bash scripts/validate-bash.sh` — confirm no new shellcheck failures
- [ ] Run `bash .forge/bin/forge-sync-cross-level.sh --check` — confirm repo-root ↔ template/ parity

## Phase 1: FORGE → forge-public

```bash
# 1. Dry-run — review what would change
bash scripts/sync-to-public.sh

# 2. Execute sync
bash scripts/sync-to-public.sh --execute
# PII verification runs automatically after copy

# 3. Commit and push
cd d:/forge-public
git add -A
git commit -m "Sync from FORGE upstream — Specs NNN-MMM"
git push
```


## Post-Sync Verification

- [ ] forge-public: `copier copy gh:Renozoic-Foundry/forge-public /tmp/test --defaults` succeeds
- [ ] Re-enable branch protection on forge-public if it was temporarily disabled

## When to Squash forge-public History

If PII is discovered in forge-public's git history (not just working tree):
1. Create orphan branch: `git checkout --orphan fresh-main`
2. Add all files: `git add -A && git commit -m "Clean release"`
3. Force push: `git branch -M main && git push --force origin main`
4. Re-enable branch protection

This is consistent with ADR-165a — forge-public is a distribution channel, not a development repo.
