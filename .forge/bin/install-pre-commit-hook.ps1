# install-pre-commit-hook.ps1 — Install FORGE combined pre-commit hook (Specs 314 + 320 + 367; Spec 270 retired by Spec 558)
# forge:path-literal-ok (file: framework-structure — framework-repo hook installer; Spec 575)
#
# PowerShell counterpart to install-pre-commit-hook.sh. Produces a byte-identical
# pre-commit hook (UTF-8 no-BOM, LF line endings) so operators on Windows without
# Git Bash can install the hook. The hook itself runs under bash regardless of how
# it was installed (Git for Windows ships bash; the hook's bash shebang is honored
# by Git's hook runner).
#
# Usage:
#   pwsh -File .forge/bin/install-pre-commit-hook.ps1
#
# Idempotent: hook body is byte-identical across re-installs.
# Operators with custom pre-commit hooks must back up .git/hooks/pre-commit before running.

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$scriptDir  = $PSScriptRoot
$projectDir = (Resolve-Path (Join-Path $scriptDir '..\..')).Path

# Resolve .git — either a directory (normal repo) or a file (worktree pointer).
$gitDirFile = Join-Path $projectDir '.git'
if (Test-Path -LiteralPath $gitDirFile -PathType Container) {
    $hooksDir = Join-Path $gitDirFile 'hooks'
} elseif (Test-Path -LiteralPath $gitDirFile -PathType Leaf) {
    # Worktree — .git is a pointer file like "gitdir: /path/to/main/.git/worktrees/<name>"
    $gitdirRaw = (Get-Content -LiteralPath $gitDirFile -Raw) -replace '^gitdir:\s*', '' -replace '\s+$', ''
    # Normalize Windows backslashes to forward slashes so the /worktrees/ strip works regardless of source.
    $gitdirRaw = $gitdirRaw -replace '\\', '/'
    # Hooks are shared with main .git dir (strip /worktrees/<name> suffix).
    $mainGitDir = $gitdirRaw -replace '/worktrees/.*$', ''
    $hooksDir = Join-Path $mainGitDir 'hooks'
} else {
    Write-Error "Not in a git repository (no .git found at $gitDirFile)"
    exit 1
}

if (-not (Test-Path -LiteralPath $hooksDir)) {
    New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
}
$hook = Join-Path $hooksDir 'pre-commit'

# Hook body — byte-identical to the bash heredoc body in install-pre-commit-hook.sh.
# Single-quoted here-string (@'...'@) prevents PS variable interpolation.
# forge:path-literal-ok (framework-structure) — the docs/process-kit reference inside
# governs FORGE's own repo, not a generic consumer's process state.
$hookBody = @'
#!/usr/bin/env bash
# FORGE combined pre-commit hook — Specs 314 + 320 + 367 (Spec 270's cross-level
# check was retired by Spec 558 with the template/ surface).
# Runs commands-sync (Spec 314), choice-block convention (Spec 320), and
# spec-integrity sentinel parity + token-set coherence (Spec 367) checks. All
# checks run to completion. Hook fails if any reports a violation.
# FORGE_SKIP_SYNC=1 bypasses all checks but emits a stderr audit-trail warning.

set +e  # do not abort on individual check failure — we want all to run

REPO_ROOT="$(git rev-parse --show-toplevel)"
COMMANDS_CHECK="${REPO_ROOT}/.forge/bin/forge-sync-commands.sh"
CHOICE_BLOCK_CHECK="${REPO_ROOT}/scripts/tests/test-choice-block-conventions.sh"
SENTINEL_CHECK="${REPO_ROOT}/scripts/validate-spec-integrity-sentinels.sh"

STAGED="$(git diff --cached --name-only --diff-filter=ACMR)"

# Determine which checks are relevant based on staged paths.
RUN_COMMANDS=0
RUN_CHOICE_BLOCK=0
RUN_SENTINEL=0
# forge:path-literal-ok (framework-structure) — this hook governs FORGE's own repo,
# not a generic consumer project's process-state location.
if grep -qE '^\.forge/commands/' <<<"${STAGED}"; then
  RUN_COMMANDS=1
fi
if grep -qE '^(\.forge/commands/|\.claude/commands/)' <<<"${STAGED}"; then
  RUN_CHOICE_BLOCK=1
fi
# Spec 367: sentinel parity + token-set coherence runs when staged paths touch
# any of the 16 sentinel-bearing files OR the canonical coverage doc OR the
# Lane B compliance profile. Pattern matches the union of:
#   - .forge/commands/{implement,close,revise}.md
#   - .claude/commands/{implement,close,revise}.md
#   - docs/process-kit/close-validator-coverage.md
#   - docs/compliance/profile.yaml
if grep -qE '^((\.forge|\.claude)/commands/(implement|close|revise)\.md|docs/process-kit/close-validator-coverage\.md|docs/compliance/profile\.yaml)$' <<<"${STAGED}"; then  # forge:path-literal-ok (framework-structure)
  RUN_SENTINEL=1
fi

# No watched paths staged — nothing to do.
if [[ ${RUN_COMMANDS} -eq 0 && ${RUN_CHOICE_BLOCK} -eq 0 && ${RUN_SENTINEL} -eq 0 ]]; then
  exit 0
fi

# Run commands-sync check (Spec 314).
COMMANDS_EXIT=0
COMMANDS_OUTPUT=""
if [[ ${RUN_COMMANDS} -eq 1 && -x "${COMMANDS_CHECK}" ]]; then
  COMMANDS_OUTPUT="$("${COMMANDS_CHECK}" --check 2>&1)"
  COMMANDS_EXIT=$?
fi

# Run choice-block convention check (Spec 320).
CHOICE_BLOCK_EXIT=0
CHOICE_BLOCK_OUTPUT=""
if [[ ${RUN_CHOICE_BLOCK} -eq 1 && -f "${CHOICE_BLOCK_CHECK}" ]]; then
  CHOICE_BLOCK_OUTPUT="$(bash "${CHOICE_BLOCK_CHECK}" --staged 2>&1)"
  CHOICE_BLOCK_EXIT=$?
fi

# Run spec-integrity sentinel check (Spec 367).
SENTINEL_EXIT=0
SENTINEL_OUTPUT=""
if [[ ${RUN_SENTINEL} -eq 1 && -f "${SENTINEL_CHECK}" ]]; then
  SENTINEL_OUTPUT="$(bash "${SENTINEL_CHECK}" 2>&1)"
  SENTINEL_EXIT=$?
fi

# Override path: FORGE_SKIP_SYNC=1 bypasses but leaves an audit trail.
if [[ "${FORGE_SKIP_SYNC:-0}" = "1" ]]; then
  BYPASSED=()
  if [[ ${COMMANDS_EXIT} -ne 0 ]]; then
    BYPASSED+=("forge-sync-commands.sh")
  fi
  if [[ ${CHOICE_BLOCK_EXIT} -ne 0 ]]; then
    BYPASSED+=("test-choice-block-conventions.sh")
  fi
  if [[ ${SENTINEL_EXIT} -ne 0 ]]; then
    BYPASSED+=("validate-spec-integrity-sentinels.sh")
  fi
  if [[ ${#BYPASSED[@]} -gt 0 ]]; then
    echo "" >&2
    echo "FORGE_SKIP_SYNC=1 — bypassing pre-commit checks" >&2
    echo "Bypassed checks: ${BYPASSED[*]}" >&2
    if [[ ${COMMANDS_EXIT} -ne 0 ]]; then
      echo "--- Drift from forge-sync-commands.sh ---" >&2
      echo "${COMMANDS_OUTPUT}" >&2
    fi
    if [[ ${CHOICE_BLOCK_EXIT} -ne 0 ]]; then
      echo "--- Violations from test-choice-block-conventions.sh ---" >&2
      echo "${CHOICE_BLOCK_OUTPUT}" >&2
    fi
    if [[ ${SENTINEL_EXIT} -ne 0 ]]; then
      echo "--- Violations from validate-spec-integrity-sentinels.sh ---" >&2
      echo "${SENTINEL_OUTPUT}" >&2
    fi
    echo "--- end FORGE_SKIP_SYNC audit trail ---" >&2
  else
    echo "FORGE_SKIP_SYNC=1 set but all checks pass — no bypass needed" >&2
  fi
  exit 0
fi

# Standard path: report any failing check and abort if any failed.
if [[ ${COMMANDS_EXIT} -ne 0 ]]; then
  echo "" >&2
  echo "ERROR: commands-sync drift detected (Spec 314)." >&2
  echo "${COMMANDS_OUTPUT}" >&2
  echo "" >&2
  echo "Recovery:" >&2
  echo "  bash .forge/bin/forge-sync-commands.sh" >&2
fi
if [[ ${CHOICE_BLOCK_EXIT} -ne 0 ]]; then
  echo "" >&2
  echo "ERROR: choice-block convention violations detected (Spec 320)." >&2
  echo "${CHOICE_BLOCK_OUTPUT}" >&2
  echo "" >&2
  echo "Recovery:" >&2
  echo "  Update the choice block to match docs/process-kit/implementation-patterns.md § Choice Blocks." >&2  # forge:path-literal-ok (comment)
fi
if [[ ${SENTINEL_EXIT} -ne 0 ]]; then
  echo "" >&2
  echo "ERROR: spec-integrity sentinel violation detected (Spec 367)." >&2
  echo "${SENTINEL_OUTPUT}" >&2
  echo "" >&2
  echo "Recovery:" >&2
  echo "  Re-sync the canonical sentinel block then run:" >&2
  echo "    bash scripts/spec-344-sync-sentinels.sh" >&2
  echo "    bash scripts/validate-spec-integrity-sentinels.sh" >&2
  echo "  See docs/process-kit/close-validator-coverage.md § Spec 367 CI parity gate" >&2  # forge:path-literal-ok (comment)
fi

if [[ ${COMMANDS_EXIT} -ne 0 || ${CHOICE_BLOCK_EXIT} -ne 0 || ${SENTINEL_EXIT} -ne 0 ]]; then
  echo "" >&2
  echo "Re-stage updated files and retry the commit, or set FORGE_SKIP_SYNC=1 to bypass." >&2
  exit 1
fi

exit 0
'@

# Normalize line endings: strip CRLF AND stray CR-only sequences to LF-only.
# This matters because PS here-strings can pick up CRLF from autocrlf settings on the source file.
$hookBody = [regex]::Replace($hookBody, "`r`n?", "`n")

# Ensure exactly one trailing newline (matches bash heredoc behavior).
$hookBody = $hookBody.TrimEnd("`n") + "`n"

# Write UTF-8 WITHOUT BOM. Set-Content/Out-File default to BOM under PS 5.1.
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($hook, $hookBody, $utf8NoBom)

Write-Output "Installed FORGE combined pre-commit hook at: $hook"
Write-Output "It runs:"
Write-Output "  - .forge/bin/forge-sync-commands.sh --check          (Spec 314)"
Write-Output "  - scripts/tests/test-choice-block-conventions.sh --staged"
Write-Output "                                                       (Spec 320)"
Write-Output "on staged changes. FORGE_SKIP_SYNC=1 bypasses all checks (audit-trail warning emitted on stderr)."
