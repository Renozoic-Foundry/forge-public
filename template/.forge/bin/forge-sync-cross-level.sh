#!/usr/bin/env bash
# FORGE forge-sync-cross-level — propagate canonical repo-root sources to template/ mirrors
#
# Spec 270: Generalized Cross-Level Sync (Template <-> Repo-Root)
#
# Sync pairs (canonical -> mirror):  # forge:path-literal-ok (framework-structure — FORGE's own docs/ tree, not a consumer's)
#   .forge/commands/*.md           -> template/.forge/commands/*.md (or .md.jinja)
#   .claude/agents/*.md            -> template/.claude/agents/*.md
#   docs/process-kit/*.md          -> template/docs/process-kit/*.md (or .md.jinja)
#                                    (subject to intentional-subset rule)
#
# Usage:
#   forge-sync-cross-level.sh [--check] [--dry-run] [--verbose]
#
# Flags:
#   --check     Non-zero exit if any unexpected drift found (pre-commit safe)
#   --dry-run   Print what would be written/deleted without making changes
#   --verbose   Show all file comparisons, not just drift
#
# Escape hatch:
#   .forge/state/expected-cross-level-drift.txt  — files to ignore in --check mode
#
# Composition:
#   Reads .forge/update-manifest.yaml for framework/project/obsolete/removed
#   classifications. Project-owned files are never mirrored. Removed-manifest
#   entries cause the mirror file to be deleted.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_DIR="$(cd "${FORGE_DIR}/.." && pwd)"
TEMPLATE_DIR="${PROJECT_DIR}/template"
MANIFEST_FILE="${FORGE_DIR}/update-manifest.yaml"
ESCAPE_HATCH="${FORGE_DIR}/state/expected-cross-level-drift.txt"

# --- Flags ---
CHECK_MODE=false
DRY_RUN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)    CHECK_MODE=true; shift ;;
    --dry-run)  DRY_RUN=true;    shift ;;
    --verbose)  VERBOSE=true;    shift ;;
    -h|--help)
      cat <<'HELP'
Usage: forge-sync-cross-level.sh [--check] [--dry-run] [--verbose]

Propagate repo-root canonical sources to template/ mirrors.

Options:
  --check     Non-zero exit on unexpected drift (pre-commit safe)
  --dry-run   Report what would change without writing files
  --verbose   Show all file comparisons, not just drifted ones

Sync pairs:  # forge:path-literal-ok (framework-structure — FORGE's own docs/ tree, not a consumer's)
  .forge/commands/*.md        -> template/.forge/commands/*
  .claude/agents/*.md         -> template/.claude/agents/*
  docs/process-kit/*.md       -> template/docs/process-kit/*

Escape hatch: .forge/state/expected-cross-level-drift.txt
Composition:  .forge/update-manifest.yaml (project, removed sections)
HELP
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

vlog() {
  if $VERBOSE; then
    echo "$1"
  fi
}

# --- Load escape hatch (expected intentional drift) ---
declare -A EXPECTED_DRIFT
if [[ -f "$ESCAPE_HATCH" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and blank lines
    if [[ "$line" =~ ^[[:space:]]*# ]]; then continue; fi
    if [[ -z "${line// /}" ]]; then continue; fi
    # Entry format: "relative/path/file.md | rationale" — use the path portion
    local_path="${line%%|*}"
    # Trim leading and trailing whitespace (including tabs, CR from CRLF)
    local_path="${local_path#"${local_path%%[![:space:]]*}"}"
    local_path="${local_path%"${local_path##*[![:space:]]}"}"
    # Guard: skip empty paths to avoid `bad array subscript` (Spec 343)
    if [[ -z "$local_path" ]]; then continue; fi
    EXPECTED_DRIFT["$local_path"]=1
  done < "$ESCAPE_HATCH"
fi

# --- Load manifest: extract project-owned and removed paths ---
declare -a PROJECT_PATHS=()
declare -a REMOVED_PATHS=()

_parse_manifest() {
  local section=""
  local in_paths=false
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Top-level section keys (no leading whitespace)
    if [[ "$line" =~ ^(framework|project|merge|obsolete|removed): ]]; then
      section="${BASH_REMATCH[1]}"
      in_paths=false
      continue
    fi
    # paths: subkey under a section
    if [[ -n "$section" ]] && [[ "$line" =~ ^[[:space:]]+paths: ]]; then
      in_paths=true
      continue
    fi
    # mappings: subkey stops paths
    if [[ -n "$section" ]] && [[ "$line" =~ ^[[:space:]]+mappings: ]]; then
      in_paths=false
      continue
    fi
    # List items under paths:
    if $in_paths && [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.*) ]]; then
      local entry="${BASH_REMATCH[1]}"
      # Strip trailing inline comment
      entry="${entry%%#*}"
      # Trim trailing whitespace
      entry="${entry%"${entry##*[![:space:]]}"}"
      # Strip surrounding quotes if present
      entry="${entry#\"}"
      entry="${entry%\"}"
      case "$section" in
        project) PROJECT_PATHS+=("${entry}") ;;
        removed) REMOVED_PATHS+=("${entry}") ;;
      esac
    fi
  done < "$MANIFEST_FILE"
}

if [[ -f "$MANIFEST_FILE" ]]; then
  _parse_manifest
fi

# --- Check if a path is project-owned (should not be mirrored) ---
_is_project_owned() {
  local relpath="$1"
  local pattern
  if [[ ${#PROJECT_PATHS[@]} -eq 0 ]]; then
    return 1
  fi
  for pattern in "${PROJECT_PATHS[@]}"; do
    # shellcheck disable=SC2254
    case "$relpath" in
      $pattern) return 0 ;;
    esac
    # Also match directory-prefix patterns ("path/" should match "path/anything")
    if [[ "$pattern" == */ ]] && [[ "$relpath" == "$pattern"* ]]; then
      return 0
    fi
  done
  return 1
}

_is_expected_drift() {
  local relpath="$1"
  if [[ -n "${EXPECTED_DRIFT[$relpath]+_}" ]]; then
    return 0
  fi
  return 1
}

# --- Three-state drift detection (Spec 481) -------------------------------
# An expected-drift entry is a *permission* to drift, not an assertion that
# drift exists. Three states for a drift-listed (canonical, mirror) pair:
#   1. currently-identical  — canonical == mirror at HEAD: the permitted drift
#                             has NOT been applied. Additive edits are safe to
#                             propagate (nothing intentional to protect).
#   2. currently-divergent  — canonical != mirror at HEAD: genuine intentional
#                             drift. Never clobber; skip.
#   3. newly-divergent      — identical at HEAD, but canonical changed in the
#                             working set while mirror is stale: surfaced as a
#                             WARN by forge-parity --check.
#
# _drift_identical_at_head returns 0 (true) when the canonical file and its
# mirror were byte-identical at HEAD (state 1). Returns 1 (false) when they
# differed at HEAD (state 2) OR when HEAD state cannot be determined (no git,
# untracked file, detached blob) — false is the conservative answer because it
# preserves the legacy skip behavior and never clobbers.
_drift_identical_at_head() {
  local canonical_rel="$1"
  local mirror_rel="$2"
  # Need a git repo to inspect HEAD.
  if ! git -C "$PROJECT_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
    return 1
  fi
  local head_canonical head_mirror
  # git show prints the blob at HEAD; capture failures (untracked) as a miss.
  if ! head_canonical="$(git -C "$PROJECT_DIR" show "HEAD:${canonical_rel}" 2>/dev/null)"; then
    return 1
  fi
  if ! head_mirror="$(git -C "$PROJECT_DIR" show "HEAD:${mirror_rel}" 2>/dev/null)"; then
    return 1
  fi
  if [[ "$head_canonical" == "$head_mirror" ]]; then
    return 0
  fi
  return 1
}

# --- Counters ---
SYNCED=0
CREATED=0
DELETED=0
SKIPPED=0
DRIFT_COUNT=0
WARN_COUNT=0

# --- Find mirror target for a canonical file ---
# Prefers .jinja suffix if a .jinja mirror already exists. Otherwise plain.
_find_mirror_target() {
  local canonical_rel="$1"
  local mirror_base="${TEMPLATE_DIR}/${canonical_rel}"
  if [[ -f "${mirror_base}.jinja" ]]; then
    echo "${mirror_base}.jinja"
    return
  fi
  echo "${mirror_base}"
}

# --- Process a single canonical -> mirror pair ---
_process_file() {
  local canonical_file="$1"
  local canonical_rel="$2"
  local mirror_target="$3"
  local mirror_rel="${mirror_target#"${PROJECT_DIR}/"}"

  if $CHECK_MODE; then
    if [[ ! -f "$mirror_target" ]]; then
      if _is_expected_drift "$mirror_rel" || _is_expected_drift "$canonical_rel"; then
        vlog "  OK (expected missing): ${canonical_rel}"
        SKIPPED=$((SKIPPED + 1))
      else
        echo "DRIFT [missing]: ${canonical_rel} — new canonical file not mirrored at ${mirror_rel}"
        DRIFT_COUNT=$((DRIFT_COUNT + 1))
      fi
      return
    fi

    local expected actual
    expected="$(cat "${canonical_file}")"
    actual="$(cat "${mirror_target}")"
    if [[ "$expected" != "$actual" ]]; then
      if _is_expected_drift "$mirror_rel" || _is_expected_drift "$canonical_rel"; then
        # Three-state visibility (Spec 481): if the pair was byte-identical at
        # HEAD but now differs, this is "newly-divergent" — the canonical file
        # changed and the mirror is stale, but the drift entry only permits
        # (does not assert) drift. Surface as a WARN so the gap is visible.
        # Genuine intentional drift (divergent at HEAD) stays a silent skip.
        if _drift_identical_at_head "$canonical_rel" "$mirror_rel"; then
          echo "WARN [stale-mirror]: ${canonical_rel} changed but mirror ${mirror_rel} is stale (identical at HEAD; drift-listed entry permits but does not assert drift). Remediate: run .forge/bin/forge-parity.sh to regenerate, or accept the divergence."
          WARN_COUNT=$((WARN_COUNT + 1))
        else
          vlog "  OK (expected drift): ${canonical_rel}"
        fi
        SKIPPED=$((SKIPPED + 1))
      else
        echo "DRIFT [content]: ${canonical_rel} -> ${mirror_rel}"
        DRIFT_COUNT=$((DRIFT_COUNT + 1))
      fi
    else
      vlog "  OK: ${canonical_rel}"
    fi
    return
  fi

  # Dry-run or sync: three-state drift handling (Spec 481).
  # A drift-listed file is only protected (skipped) when REAL divergence
  # already exists at HEAD. If canonical and mirror were byte-identical at
  # HEAD, the permitted drift has not been applied — additive edits must
  # propagate, so we fall through to the normal sync path.
  if _is_expected_drift "$mirror_rel" || _is_expected_drift "$canonical_rel"; then
    if _drift_identical_at_head "$canonical_rel" "$mirror_rel"; then
      vlog "  Propagate (drift-listed but identical at HEAD): ${canonical_rel}"
    else
      vlog "  Skip (expected drift — divergent at HEAD): ${canonical_rel}"
      SKIPPED=$((SKIPPED + 1))
      return
    fi
  fi

  if $DRY_RUN; then
    if [[ ! -f "$mirror_target" ]]; then
      echo "  Would create: ${mirror_rel}"
      CREATED=$((CREATED + 1))
    else
      local expected actual
      expected="$(cat "${canonical_file}")"
      actual="$(cat "${mirror_target}")"
      if [[ "$expected" != "$actual" ]]; then
        echo "  Would update: ${mirror_rel}"
        SYNCED=$((SYNCED + 1))
      else
        vlog "  No change: ${mirror_rel}"
      fi
    fi
    return
  fi

  # Sync mode
  if [[ ! -f "$mirror_target" ]]; then
    mkdir -p "$(dirname "${mirror_target}")"
    cp "${canonical_file}" "${mirror_target}"
    CREATED=$((CREATED + 1))
    vlog "  Created: ${mirror_rel}"
    return
  fi

  local expected actual
  expected="$(cat "${canonical_file}")"
  actual="$(cat "${mirror_target}")"
  if [[ "$expected" != "$actual" ]]; then
    cp "${canonical_file}" "${mirror_target}"
    SYNCED=$((SYNCED + 1))
    vlog "  Synced: ${mirror_rel}"
  else
    vlog "  No change: ${mirror_rel}"
  fi
}

# --- Process a canonical dir against its template mirror ---
_process_dir() {
  local canonical_dir="$1"
  local canonical_prefix="$2"

  shopt -s nullglob
  for canonical_file in "${canonical_dir}"/*.md "${canonical_dir}"/*.md.jinja; do
    [[ -f "$canonical_file" ]] || continue

    local base canonical_rel
    base="$(basename "${canonical_file}")"
    canonical_rel="${canonical_prefix}/${base}"

    # Skip project-owned files
    if _is_project_owned "${canonical_rel}"; then
      vlog "  Skip (project-owned): ${canonical_rel}"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    local mirror_target
    mirror_target="$(_find_mirror_target "${canonical_rel}")"
    _process_file "${canonical_file}" "${canonical_rel}" "${mirror_target}"
  done
  shopt -u nullglob
}

# --- Process removed entries from manifest ---
_process_removed() {
  local removed_path mirror_target mirror_rel
  if [[ ${#REMOVED_PATHS[@]} -eq 0 ]]; then return; fi
  for removed_path in "${REMOVED_PATHS[@]}"; do
    mirror_target="${TEMPLATE_DIR}/${removed_path}"
    mirror_rel="template/${removed_path}"

    if [[ ! -f "${mirror_target}" ]]; then continue; fi

    if $CHECK_MODE; then
      echo "DRIFT [removed]: ${removed_path} — should be deleted from ${mirror_rel} (manifest: removed)"
      DRIFT_COUNT=$((DRIFT_COUNT + 1))
    elif $DRY_RUN; then
      echo "  Would delete (removed in manifest): ${mirror_rel}"
      DELETED=$((DELETED + 1))
    else
      rm -f "${mirror_target}"
      DELETED=$((DELETED + 1))
      vlog "  Deleted (removed in manifest): ${mirror_rel}"
    fi
  done
}

echo "## forge-sync-cross-level"
echo ""

# Sync pair 1: .forge/commands/
if [[ -d "${PROJECT_DIR}/.forge/commands" ]]; then
  echo "=== .forge/commands -> template/.forge/commands ==="
  _process_dir "${PROJECT_DIR}/.forge/commands" ".forge/commands"
  echo ""
fi

# Sync pair 2: .claude/agents/
if [[ -d "${PROJECT_DIR}/.claude/agents" ]]; then
  echo "=== .claude/agents -> template/.claude/agents ==="
  _process_dir "${PROJECT_DIR}/.claude/agents" ".claude/agents"
  echo ""
fi

# Sync pair 3: docs/process-kit/  # forge:path-literal-ok (framework-structure — FORGE's own process-kit, mirrored into template/)
if [[ -d "${PROJECT_DIR}/docs/process-kit" ]]; then
  echo "=== docs/process-kit -> template/docs/process-kit ==="
  _process_dir "${PROJECT_DIR}/docs/process-kit" "docs/process-kit"
  echo ""
fi

# Process removed entries from manifest
if [[ ${#REMOVED_PATHS[@]} -gt 0 ]]; then
  echo "=== Processing manifest removals ==="
  _process_removed
  echo ""
fi

# Summary
echo "## Summary"
if $CHECK_MODE; then
  echo "Expected drift (skipped): ${SKIPPED}"
  echo "Stale-mirror warnings (Spec 481): ${WARN_COUNT}"
  echo "Unexpected drift: ${DRIFT_COUNT}"
  echo ""
  if [[ ${DRIFT_COUNT} -gt 0 ]]; then
    echo "FAILED: ${DRIFT_COUNT} file(s) out of sync."
    echo "Run .forge/bin/forge-sync-cross-level.sh to fix, then re-commit."
    exit 1
  else
    echo "PASS: All cross-level mirrors are in sync."
    exit 0
  fi
elif $DRY_RUN; then
  echo "Mode: dry-run (no files written)"
  echo "Would create: ${CREATED}"
  echo "Would update: ${SYNCED}"
  echo "Would delete (manifest removed): ${DELETED}"
  echo "Skipped (expected drift/project-owned): ${SKIPPED}"
else
  echo "Created: ${CREATED}"
  echo "Synced: ${SYNCED}"
  echo "Deleted (manifest removed): ${DELETED}"
  echo "Skipped (expected drift/project-owned): ${SKIPPED}"
fi
