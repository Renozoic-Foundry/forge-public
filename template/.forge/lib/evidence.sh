#!/usr/bin/env bash
# FORGE evidence.sh — evidence capture library for gate decision artifacts
# Source this file; do not execute directly.
#
# Usage:
#   source "${FORGE_DIR}/lib/evidence.sh"
#   forge_evidence_init "NNN"                            # create evidence dir for spec NNN
#   forge_evidence_capture_output "label" "cmd args..."  # run cmd, capture stdout+stderr
#   forge_evidence_diff_summary                          # git diff --stat summary
#   forge_evidence_ac_checklist "spec_file"             # parse ACs from spec, output checklist
#   forge_evidence_manifest                             # list all artifacts with sizes
#   forge_evidence_attach_format                        # output artifact paths for NanoClaw
#
# Artifacts are stored in: tmp/evidence/SPEC-NNN-YYYYMMDD/
# All paths are relative to the project root (PROJECT_DIR or CWD).

# Guard against double-sourcing
if [[ -n "${_FORGE_EVIDENCE_LOADED:-}" ]]; then return 0; fi
_FORGE_EVIDENCE_LOADED=1

# Load logging if available
_FORGE_EVIDENCE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${_FORGE_EVIDENCE_SCRIPT_DIR}/logging.sh" ]]; then
  # shellcheck source=logging.sh
  source "${_FORGE_EVIDENCE_SCRIPT_DIR}/logging.sh"
fi

# --- Internal state ---
_FORGE_EVIDENCE_DIR=""
_FORGE_EVIDENCE_SPEC=""
_FORGE_EVIDENCE_DATE=""
_FORGE_EVIDENCE_ARTIFACTS=()

# --- Resolve project root ---
_forge_evidence_project_root() {
  if [[ -n "${PROJECT_DIR:-}" ]]; then
    echo "$PROJECT_DIR"
  else
    # Walk up until we find .forge/ or fall back to CWD
    local dir
    dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
      if [[ -d "${dir}/.forge" ]]; then
        echo "$dir"
        return 0
      fi
      dir="$(dirname "$dir")"
    done
    echo "$(pwd)"
  fi
}

# --- Initialize evidence directory for a spec ---
# Usage: forge_evidence_init "051"
forge_evidence_init() {
  local spec_num="${1:?forge_evidence_init requires a spec number}"
  _FORGE_EVIDENCE_SPEC="SPEC-${spec_num}"
  _FORGE_EVIDENCE_DATE="$(date '+%Y%m%d-%H%M%S')"

  local project_root
  project_root="$(_forge_evidence_project_root)"
  _FORGE_EVIDENCE_DIR="${project_root}/tmp/evidence/${_FORGE_EVIDENCE_SPEC}-${_FORGE_EVIDENCE_DATE}"

  mkdir -p "$_FORGE_EVIDENCE_DIR"
  _FORGE_EVIDENCE_ARTIFACTS=()

  # Write manifest header
  {
    echo "# FORGE Evidence Manifest"
    echo "# Spec: ${_FORGE_EVIDENCE_SPEC}"
    echo "# Captured: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# Dir: ${_FORGE_EVIDENCE_DIR}"
    echo ""
  } > "${_FORGE_EVIDENCE_DIR}/manifest.md"

  if command -v forge_log_info &>/dev/null; then
    forge_log_info "Evidence directory: ${_FORGE_EVIDENCE_DIR}"
  fi
  echo "Evidence dir: ${_FORGE_EVIDENCE_DIR}"
}

# --- Capture command output as a text artifact ---
# Usage: forge_evidence_capture_output "test-run" "pytest -q"
# Runs the command, captures stdout+stderr, saves to evidence dir.
# Returns the command's exit code.
forge_evidence_capture_output() {
  local label="${1:?forge_evidence_capture_output requires a label}"
  shift
  local cmd=("$@")

  if [[ -z "$_FORGE_EVIDENCE_DIR" ]]; then
    echo "ERROR: Call forge_evidence_init first." >&2
    return 1
  fi

  local artifact_file="${_FORGE_EVIDENCE_DIR}/${label}.txt"
  local exit_code=0

  {
    echo "# FORGE Evidence — ${label}"
    echo "# Command: ${cmd[*]}"
    echo "# Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
  } > "$artifact_file"

  # Run command, capture output, preserve exit code
  "${cmd[@]}" >> "$artifact_file" 2>&1 || exit_code=$?

  {
    echo ""
    echo "# Exit code: ${exit_code}"
  } >> "$artifact_file"

  _FORGE_EVIDENCE_ARTIFACTS+=("${label}.txt")
  _forge_evidence_manifest_append "${label}.txt" "command output: ${cmd[*]}" "$exit_code"

  if command -v forge_log_info &>/dev/null; then
    forge_log_info "Evidence captured: ${label}.txt (exit: ${exit_code})"
  fi

  return "$exit_code"
}

# --- Generate git diff summary artifact ---
# Usage: forge_evidence_diff_summary [base_ref]
# Captures git diff --stat and a condensed diff summary.
forge_evidence_diff_summary() {
  local base_ref="${1:-HEAD~1}"

  if [[ -z "$_FORGE_EVIDENCE_DIR" ]]; then
    echo "ERROR: Call forge_evidence_init first." >&2
    return 1
  fi

  local artifact_file="${_FORGE_EVIDENCE_DIR}/diff-summary.md"

  {
    echo "# FORGE Evidence — Diff Summary"
    echo "# Base: ${base_ref}"
    echo "# Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## Changed Files"
    echo '```'
    git diff --stat "${base_ref}" 2>/dev/null || git status --short 2>/dev/null || echo "(no git diff available)"
    echo '```'
    echo ""
    echo "## Summary"
    echo '```'
    git diff --shortstat "${base_ref}" 2>/dev/null || echo "(no shortstat available)"
    echo '```'
    echo ""
    echo "## Recent Commits"
    echo '```'
    git log --oneline -5 2>/dev/null || echo "(no git log available)"
    echo '```'
  } > "$artifact_file"

  _FORGE_EVIDENCE_ARTIFACTS+=("diff-summary.md")
  _forge_evidence_manifest_append "diff-summary.md" "git diff summary (base: ${base_ref})" 0

  if command -v forge_log_info &>/dev/null; then
    forge_log_info "Diff summary captured: diff-summary.md"
  fi
}

# --- Generate AC checklist artifact ---
# Usage: forge_evidence_ac_checklist "docs/specs/031-evidence-capture.md"
# Parses the ## Acceptance Criteria section and produces a pass/fail checklist.
forge_evidence_ac_checklist() {
  local spec_file="${1:?forge_evidence_ac_checklist requires a spec file path}"

  if [[ -z "$_FORGE_EVIDENCE_DIR" ]]; then
    echo "ERROR: Call forge_evidence_init first." >&2
    return 1
  fi

  if [[ ! -f "$spec_file" ]]; then
    echo "ERROR: Spec file not found: ${spec_file}" >&2
    return 1
  fi

  local artifact_file="${_FORGE_EVIDENCE_DIR}/ac-checklist.md"
  local spec_num
  spec_num="$(basename "$spec_file" | grep -oE '^[0-9]+')"

  {
    echo "# FORGE Evidence — AC Checklist"
    echo "# Spec: ${spec_num}"
    echo "# Source: ${spec_file}"
    echo "# Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## Acceptance Criteria — Pass/Fail"
    echo ""
    echo "> Update each item below with PASS, FAIL, or CONDITIONAL_PASS and evidence reference."
    echo ""

    # Extract AC section — lines between ## Acceptance Criteria and next ## heading
    local in_ac=0
    local ac_num=0
    while IFS= read -r line; do
      if [[ "$line" =~ ^##[[:space:]]Acceptance[[:space:]]Criteria ]]; then
        in_ac=1
        continue
      fi
      if [[ $in_ac -eq 1 && "$line" =~ ^## ]]; then
        break
      fi
      if [[ $in_ac -eq 1 ]]; then
        # Convert numbered list items to checklist rows
        if [[ "$line" =~ ^[0-9]+\. ]]; then
          ac_num=$(( ac_num + 1 ))
          local ac_text="${line#[0-9]*. }"
          echo "- [ ] AC${ac_num}: ${ac_text}"
          echo "  - Status: \`PENDING\`"
          echo "  - Evidence: (add reference)"
          echo ""
        fi
      fi
    done < "$spec_file"

    if [[ $ac_num -eq 0 ]]; then
      echo "(No numbered acceptance criteria found in spec file)"
    fi

    echo ""
    echo "---"
    echo "**Total ACs:** ${ac_num}"
    echo "**Gate decision:** PASS when all ACs are \`PASS\` or \`CONDITIONAL_PASS\`"
  } > "$artifact_file"

  _FORGE_EVIDENCE_ARTIFACTS+=("ac-checklist.md")
  _forge_evidence_manifest_append "ac-checklist.md" "AC checklist (${ac_num} criteria)" 0

  if command -v forge_log_info &>/dev/null; then
    forge_log_info "AC checklist generated: ac-checklist.md (${ac_num} criteria)"
  fi
}

# --- List all captured artifacts ---
forge_evidence_manifest() {
  if [[ -z "$_FORGE_EVIDENCE_DIR" ]]; then
    echo "No evidence session active. Call forge_evidence_init first."
    return 1
  fi

  echo "Evidence artifacts for ${_FORGE_EVIDENCE_SPEC}:"
  echo "Directory: ${_FORGE_EVIDENCE_DIR}"
  echo ""
  cat "${_FORGE_EVIDENCE_DIR}/manifest.md"
}

# --- Format artifact paths for NanoClaw gate messages ---
# Output: newline-separated list of absolute artifact paths for attachment
forge_evidence_attach_format() {
  if [[ -z "$_FORGE_EVIDENCE_DIR" ]]; then
    echo "No evidence session active."
    return 1
  fi

  echo "## Evidence Artifacts"
  echo "Directory: \`${_FORGE_EVIDENCE_DIR}\`"
  echo ""
  for artifact in "${_FORGE_EVIDENCE_ARTIFACTS[@]}"; do
    local fpath="${_FORGE_EVIDENCE_DIR}/${artifact}"
    if [[ -f "$fpath" ]]; then
      local size
      size="$(wc -c < "$fpath" 2>/dev/null || echo '?')"
      echo "- \`${artifact}\` (${size} bytes): ${fpath}"
    fi
  done
}

# --- Internal: append entry to manifest ---
_forge_evidence_manifest_append() {
  local filename="$1"
  local description="$2"
  local exit_code="$3"
  local status="OK"
  if [[ "$exit_code" -ne 0 ]]; then
    status="EXIT:${exit_code}"
  fi

  {
    echo "## ${filename}"
    echo "- Description: ${description}"
    echo "- Status: ${status}"
    echo "- Path: ${_FORGE_EVIDENCE_DIR}/${filename}"
    echo ""
  } >> "${_FORGE_EVIDENCE_DIR}/manifest.md"
}
