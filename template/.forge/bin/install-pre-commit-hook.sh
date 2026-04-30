#!/usr/bin/env bash
# install-pre-commit-hook.sh — Install FORGE combined pre-commit hook (Specs 270 + 314 + 320 + 367)
#
# Installs a pre-commit hook that runs FOUR checks:
#   - .forge/bin/forge-sync-cross-level.sh --check       (Spec 270 — template/ ↔ repo-root sync)
#   - .forge/bin/forge-sync-commands.sh --check          (Spec 314 — .forge/commands/ ↔ .claude/commands/ sync)
#   - scripts/tests/test-choice-block-conventions.sh --staged
#                                                        (Spec 320 — choice-block convention enforcement)
#   - scripts/validate-spec-integrity-sentinels.sh       (Spec 367 — sentinel byte-parity +
#                                                        token-set coherence across the 16
#                                                        Spec-344 sentinel locations)
#
# All four checks run to completion (no short-circuit). Hook exit is the OR of their exit codes.
# FORGE_SKIP_SYNC=1 bypasses all three checks but emits a stderr audit-trail warning.
#
# Usage: .forge/bin/install-pre-commit-hook.sh
#
# Idempotent: hook body is byte-identical across re-installs.
# Operators with custom pre-commit hooks must back up .git/hooks/pre-commit before running.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Resolve .git — either a directory (normal repo) or a file (worktree)
GIT_DIR_FILE="${PROJECT_DIR}/.git"
if [[ -d "${GIT_DIR_FILE}" ]]; then
  HOOKS_DIR="${GIT_DIR_FILE}/hooks"
elif [[ -f "${GIT_DIR_FILE}" ]]; then
  # Worktree — .git is a pointer file like "gitdir: /path/to/main/.git/worktrees/<name>"
  GIT_DIR_RAW="$(sed -n 's/^gitdir: //p' "${GIT_DIR_FILE}")"
  # Hooks are shared with main .git dir (strip worktrees/<name>)
  MAIN_GIT_DIR="${GIT_DIR_RAW%%/worktrees/*}"
  HOOKS_DIR="${MAIN_GIT_DIR}/hooks"
else
  echo "ERROR: Not in a git repository (no .git found at ${GIT_DIR_FILE})" >&2
  exit 1
fi

mkdir -p "${HOOKS_DIR}"
HOOK="${HOOKS_DIR}/pre-commit"

cat > "${HOOK}" <<'HOOK_EOF'
#!/usr/bin/env bash
# FORGE combined pre-commit hook — Specs 270 + 314 + 320 + 367
# Runs cross-level sync (Spec 270), commands-sync (Spec 314), choice-block
# convention (Spec 320), and spec-integrity sentinel parity + token-set
# coherence (Spec 367) checks. All checks run to completion. Hook fails if any
# reports a violation.
# FORGE_SKIP_SYNC=1 bypasses all checks but emits a stderr audit-trail warning.

set +e  # do not abort on individual check failure — we want all to run

REPO_ROOT="$(git rev-parse --show-toplevel)"
CROSS_LEVEL_CHECK="${REPO_ROOT}/.forge/bin/forge-sync-cross-level.sh"
COMMANDS_CHECK="${REPO_ROOT}/.forge/bin/forge-sync-commands.sh"
CHOICE_BLOCK_CHECK="${REPO_ROOT}/scripts/tests/test-choice-block-conventions.sh"
SENTINEL_CHECK="${REPO_ROOT}/scripts/validate-spec-integrity-sentinels.sh"

STAGED="$(git diff --cached --name-only --diff-filter=ACMR)"

# Determine which checks are relevant based on staged paths.
RUN_CROSS_LEVEL=0
RUN_COMMANDS=0
RUN_CHOICE_BLOCK=0
RUN_SENTINEL=0
if grep -qE '^(\.forge/commands/|\.claude/agents/|docs/process-kit/|template/)' <<<"${STAGED}"; then
  RUN_CROSS_LEVEL=1
fi
if grep -qE '^\.forge/commands/' <<<"${STAGED}"; then
  RUN_COMMANDS=1
fi
if grep -qE '^(\.forge/commands/|\.claude/commands/|template/\.forge/commands/|template/\.claude/commands/)' <<<"${STAGED}"; then
  RUN_CHOICE_BLOCK=1
fi
# Spec 367: sentinel parity + token-set coherence runs when staged paths touch
# any of the 16 sentinel-bearing files OR the canonical coverage doc OR the
# Lane B compliance profile. Pattern matches the union of:
#   - .forge/commands/{implement,close,revise}.md
#   - .claude/commands/{implement,close,revise}.md
#   - template/{.forge,.claude}/commands/{implement,close,revise}.md
#   - docs/process-kit/close-validator-coverage.md
#   - docs/compliance/profile.yaml
if grep -qE '^((\.forge|\.claude|template/\.forge|template/\.claude)/commands/(implement|close|revise)\.md|docs/process-kit/close-validator-coverage\.md|docs/compliance/profile\.yaml)$' <<<"${STAGED}"; then
  RUN_SENTINEL=1
fi

# No watched paths staged — nothing to do.
if [[ ${RUN_CROSS_LEVEL} -eq 0 && ${RUN_COMMANDS} -eq 0 && ${RUN_CHOICE_BLOCK} -eq 0 && ${RUN_SENTINEL} -eq 0 ]]; then
  exit 0
fi

# Run cross-level check (Spec 270).
CROSS_LEVEL_EXIT=0
CROSS_LEVEL_OUTPUT=""
if [[ ${RUN_CROSS_LEVEL} -eq 1 && -x "${CROSS_LEVEL_CHECK}" ]]; then
  CROSS_LEVEL_OUTPUT="$("${CROSS_LEVEL_CHECK}" --check 2>&1)"
  CROSS_LEVEL_EXIT=$?
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
  if [[ ${CROSS_LEVEL_EXIT} -ne 0 ]]; then
    BYPASSED+=("forge-sync-cross-level.sh")
  fi
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
    if [[ ${CROSS_LEVEL_EXIT} -ne 0 ]]; then
      echo "--- Drift from forge-sync-cross-level.sh ---" >&2
      echo "${CROSS_LEVEL_OUTPUT}" >&2
    fi
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
if [[ ${CROSS_LEVEL_EXIT} -ne 0 ]]; then
  echo "" >&2
  echo "ERROR: cross-level sync drift detected (Spec 270)." >&2
  echo "${CROSS_LEVEL_OUTPUT}" >&2
  echo "" >&2
  echo "Recovery:" >&2
  echo "  bash .forge/bin/forge-sync-cross-level.sh" >&2
fi
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
  echo "  Update the choice block to match docs/process-kit/implementation-patterns.md § Choice Blocks." >&2
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
  echo "  See docs/process-kit/close-validator-coverage.md § Spec 367 CI parity gate" >&2
fi

if [[ ${CROSS_LEVEL_EXIT} -ne 0 || ${COMMANDS_EXIT} -ne 0 || ${CHOICE_BLOCK_EXIT} -ne 0 || ${SENTINEL_EXIT} -ne 0 ]]; then
  echo "" >&2
  echo "Re-stage updated files and retry the commit, or set FORGE_SKIP_SYNC=1 to bypass." >&2
  exit 1
fi

exit 0
HOOK_EOF

chmod +x "${HOOK}"
echo "Installed FORGE combined pre-commit hook at: ${HOOK}"
echo "It runs:"
echo "  - .forge/bin/forge-sync-cross-level.sh --check       (Spec 270)"
echo "  - .forge/bin/forge-sync-commands.sh --check          (Spec 314)"
echo "  - scripts/tests/test-choice-block-conventions.sh --staged"
echo "                                                       (Spec 320)"
echo "  - scripts/validate-spec-integrity-sentinels.sh       (Spec 367)"
echo "on staged changes. FORGE_SKIP_SYNC=1 bypasses all checks (audit-trail warning emitted on stderr)."
