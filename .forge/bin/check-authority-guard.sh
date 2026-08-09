#!/usr/bin/env bash
# FORGE Authority Guard — PreToolUse hook (Spec 469, NC-2 slice 2)
# Defense-in-depth for the ADR-046 no-self-escalation invariant: denies agent-driven
# writes to the Authority Constitution protected set across BOTH Edit/Write/NotebookEdit
# tool calls AND Bash-mediated write forms (redirect, tee, mv, cp, sed -i, append).
#
# TRUST BOUNDARY — read this (Spec 469 honesty constraint):
#   This hook is NECESSARY-BUT-INSUFFICIENT. It is enforced for L0–L2 and on unmanaged
#   machines. It is BYPASSABLE AT L3 (bypassPermissions): an agent at L3 can edit
#   .claude/settings.json to remove this hook entry, because bypassPermissions auto-allows
#   .claude writes. The real trust root is the OS-level managed-settings.json (admin-installed,
#   agent-immutable) — see docs/process-kit/authority-constitution-guide.md. This hook is
#   defense-in-depth, NOT the trust root. Do not read "guard active" as "ADR-046 enforced."
#
# Protected set (self-protecting — the guard scripts are in their own deny set):
#   .forge/config/authority.yaml
#   .claude/settings.json, .claude/settings.local.json
#   .forge/bin/check-authority-guard.sh  (self)
#   .forge/bin/check-edit-gate.sh
#   .forge/bin/check-commit-guard.sh
#   .forge/bin/check-push-guard.sh             (Spec 498)
#   .forge/bin/lib/git-command-detect.sh       (Spec 498 / CISO R2 — shared detection helper)
#   .forge/bin/check-role-permissions.sh
#
# Apply-flow (Spec 667 / ADR-667) — this guard is self-protected, so guard-family edits
# use the operator-mediated patch handoff: the agent stages a unified diff under
# tmp/guard-patches/, the operator reviews it and applies it with git apply from the
# repo root, then re-verifies (forge-parity.sh --check; validate-bash.sh for scripts).
# See docs/process-kit/guard-family-apply-note.md. This edit itself was the flow's
# first self-hosting use (Spec 667 AC3).
#
# Behavior:
#   - jq missing                         -> allow (fail-open — matches the Spec 457 hooks)
#   - Edit/Write/NotebookEdit on a        -> block
#     protected path
#   - Bash command writing a protected    -> block (redirect >, >>, tee, mv, cp, sed -i,
#     path                                   install, dd of=, truncate, ln)
#   - agent patch-apply (git apply/patch) -> block, FAIL-CLOSED: denied unless every
#     referenced patch file is readable and its diff headers name zero protected paths
#     (Spec 667 AC3b — authorization decision; deliberate exception to fail-open)
#   - anything else                       -> allow
#
# Schema (Spec 499): blocks via the documented PreToolUse
# hookSpecificOutput.permissionDecision="deny" form. The prior top-level
# {"decision":"block"} was honored only via undocumented backward-compat (verified
# 2026-06-24), not the documented PreToolUse contract. When blocked, deny is a HARD
# BLOCK — it raises no in-session permission dialog; an operator-mediated change is
# run manually in the terminal. The agent cannot self-authorize a bypass via this hook.

INPUT=$(cat)

# Fail-open without jq (same posture as check-commit-guard.sh / check-edit-gate.sh).
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Protected basenames + their canonical repo-relative paths. We match on a normalized
# repo-relative path so an absolute path, a ./-prefixed path, and a bare relative path
# all compare equal.
# Canonical deny-set — the ONE literal listing of protected paths (Spec 503 de-dup).
# Both consumers read this single array: _is_protected_rel (exact-match — Edit/Write +
# redirect-target channel) AND the Bash verb-class branch (2) substring scan below. The
# de-dup is literal-only: membership and match semantics are unchanged (Spec 503).
_PROTECTED=(
  ".forge/config/authority.yaml"
  ".claude/settings.json"
  ".claude/settings.local.json"
  ".forge/bin/check-authority-guard.sh"
  ".forge/bin/check-edit-gate.sh"
  ".forge/bin/check-commit-guard.sh"
  ".forge/bin/check-push-guard.sh"
  ".forge/bin/lib/git-command-detect.sh"
  ".forge/bin/check-role-permissions.sh"
)

# Exact-match membership over the canonical _PROTECTED array (branch (1) / Edit-Write +
# redirect-target channel). Semantics identical to the prior case statement.
_is_protected_rel() {
  local _p
  for _p in "${_PROTECTED[@]}"; do
    [ "$1" = "$_p" ] && return 0
  done
  return 1
}

# Normalize a path to repo-relative form: backslashes->slashes, strip ./, strip an
# absolute repo-root prefix.
_normalize() {
  local p rel root
  p="$1"
  rel=$(printf '%s' "$p" | tr '\\' '/')
  rel="${rel#./}"
  root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$root" ]; then
    root=$(printf '%s' "$root" | tr '\\' '/')
    case "$rel" in
      "$root"/*) rel="${rel#"$root"/}" ;;
    esac
  fi
  printf '%s' "$rel"
}

_block() {
  local reason
  reason="AUTHORITY GUARD (Spec 469): write to the Authority Constitution protected set ($1) is denied. "
  reason+="This file is the autonomy/budget enforcement trust root (ADR-046 / ADR-453) and must not be agent-edited. "
  reason+="hooks-only tier is bypassable at L3 — the authoritative control is the OS managed-settings install "
  reason+="(see docs/process-kit/authority-constitution-guide.md). "
  reason+="If this is a legitimate operator-mediated change, run it yourself in the terminal (deny is a hard block with no in-session permission dialog)."
  jq -nc --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# --- Edit/Write/NotebookEdit channel ---
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.notebook_path // empty' 2>/dev/null)
if [ -n "$FILE" ]; then
  REL=$(_normalize "$FILE")
  if _is_protected_rel "$REL"; then
    _block "$REL"
  fi
fi

# --- Bash channel: detect any shell form that writes a protected path ---
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -n "$COMMAND" ]; then
  # Normalize newlines to spaces and backslashes to slashes so multi-line and
  # Windows-style paths still match.
  NORM=$(printf '%s' "$COMMAND" | tr '\n' ' ' | tr '\\' '/')
  # (1) Redirect-target check (Spec 484): an output redirect counts as a write to a
  # protected path ONLY when the redirect TARGET normalizes to a protected path.
  # Extract each redirect target (the token after > or >>, with an optional fd-number
  # or & prefix) and run it through the SAME _normalize + _is_protected_rel path the
  # Edit/Write channel uses. This stops the pre-484 false-positive where a benign
  # redirect anywhere in the command (e.g. `2>/dev/null`) tripped the block merely
  # because the command also NAMED a protected path as a read argument (SIG-469-BUG-01).
  while IFS= read -r rtok; do
    [ -z "$rtok" ] && continue
    tgt=$(printf '%s' "$rtok" | sed -E "s/^([0-9]*|&)>>?[[:space:]]*//; s/^[\"']//; s/[\"']\$//")
    [ -z "$tgt" ] && continue
    rel=$(_normalize "$tgt")
    if _is_protected_rel "$rel"; then
      _block "$rel (via Bash redirect)"
    fi
  done <<EOF
$(printf '%s' "$NORM" | grep -oE '([0-9]*|&)>>?[[:space:]]*[^[:space:];|&]+' || true)
EOF

  # (2) Verb-class write tokens: naming a protected path alongside a write verb still
  # blocks. Verb-to-target association is deferred (Spec 484 Out of scope) — the
  # over-block here fails TOWARD the safe direction for an authority-enforcement guard
  # (Spec 469 Constraint 3).
  #   - tee (with or without -a)
  #   - mv / cp / install / ln (rename, copy, link a file onto/from the target)
  #   - sed -i / perl -i (in-place edit)
  #   - dd of= , truncate (rewrite)
  # Branch (2) iterates the SAME canonical _PROTECTED array (Spec 503 de-dup). The
  # substring case is kept VERBATIM — no operand-position / per-token logic is added, so
  # a protected-path substring in ANY position (incl. as a substring of a larger token,
  # e.g. .claude/settings.json.bak) keeps blocking.
  for prot in "${_PROTECTED[@]}"; do
    case "$NORM" in
      *"$prot"*)
        if printf '%s' "$NORM" | grep -qE '(^|[[:space:]])(tee|mv|cp|install|ln|truncate)([[:space:]]|$)|(sed|perl)[[:space:]]+([^[:space:]]+[[:space:]]+)*-i|dd[[:space:]]+([^[:space:]]+[[:space:]]+)*of='; then
          _block "$prot (via Bash)"
        fi
        ;;
    esac
  done

  # (3) Patch-apply channel (Spec 667 AC3b): `git apply` / `patch` can write a protected
  # path that appears ONLY inside the patch FILE, never on the command line — invisible
  # to branches (1) and (2). This is an AUTHORIZATION decision, not a detection helper,
  # so it FAILS CLOSED (deliberate exception to the family's fail-open posture): an
  # agent-invoked apply is denied unless EVERY referenced *.patch/*.diff file is readable
  # and its diff headers name zero protected paths. Undeterminable input (stdin apply,
  # no patch-file token, unreadable or header-less file) -> deny. Path-re-rooting options
  # (--directory, --unsafe-paths) -> deny. Command-position anchoring (start-of-command,
  # or after one of ; | & or a command substitution) keeps prose mentions of the verbs in
  # heredocs and log appends from tripping this branch. The operator's own terminal apply
  # never passes through PreToolUse hooks and is unaffected.
  if printf '%s' "$NORM" | grep -qE '(^|[;|&]|\$\()[[:space:]]*(git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+|-[^[:space:]]+[[:space:]]+)*apply|patch)([[:space:]]|$)'; then
    if printf '%s' "$NORM" | grep -qE -- '--directory|--unsafe-paths'; then
      _block "patch-apply with a path-re-rooting option (fail-closed — Spec 667 AC3b)"
    fi
    PATCH_TOKENS=$(printf '%s' "$NORM" | grep -oE '[^[:space:];|&<>]+\.(patch|diff)' || true)
    if [ -z "$PATCH_TOKENS" ]; then
      _block "agent patch-apply with no determinable patch file (fail-closed — Spec 667 AC3b)"
    fi
    while IFS= read -r pf; do
      [ -z "$pf" ] && continue
      pf="${pf#\"}"; pf="${pf%\"}"; pf="${pf#\'}"; pf="${pf%\'}"
      if [ ! -r "$pf" ]; then
        _block "agent patch-apply: patch file not readable: $pf (fail-closed — Spec 667 AC3b)"
      fi
      HDRS=$(grep -E '^(diff --git|---|\+\+\+|rename to|copy to) ' "$pf" 2>/dev/null | tr '\\' '/' || true)
      if [ -z "$HDRS" ]; then
        _block "agent patch-apply: no parseable diff headers in $pf (fail-closed — Spec 667 AC3b)"
      fi
      for prot in "${_PROTECTED[@]}"; do
        case "$HDRS" in
          *"$prot"*)
            _block "$prot (via agent patch-apply content — fail-closed, Spec 667 AC3b)"
            ;;
        esac
      done
    done <<PATCHTOKENS
$PATCH_TOKENS
PATCHTOKENS
  fi
fi

exit 0
