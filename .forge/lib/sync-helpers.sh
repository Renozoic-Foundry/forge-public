#!/usr/bin/env bash
# FORGE sync-helpers — frontmatter-aware helpers for forge-sync-commands.sh (Spec 329)
# Sourceable: pure functions, no main execution.
# Used by: .forge/bin/forge-sync-commands.sh, .forge/bin/tests/test-sync-refuse-overwrite.sh

# --- Strip YAML frontmatter from a file (read stdin, output body only) ---
# A leading "---" through the next "---" is treated as frontmatter and dropped.
# Files without leading frontmatter pass through unchanged.
# CRLF-tolerant: compares against trailing-CR-stripped line (Windows line endings).
strip_frontmatter() {
  local in_frontmatter=false
  local frontmatter_done=false
  local first_line=true
  local line line_stripped
  while IFS= read -r line; do
    line_stripped="${line%$'\r'}"
    if ! $frontmatter_done; then
      if $first_line; then
        first_line=false
        if [[ "$line_stripped" == "---" ]]; then
          in_frontmatter=true
          continue
        fi
        # No leading frontmatter — fall through to print
        frontmatter_done=true
        printf '%s\n' "$line"
        continue
      elif [[ "$line_stripped" == "---" ]] && $in_frontmatter; then
        frontmatter_done=true
        in_frontmatter=false
        continue
      elif $in_frontmatter; then
        continue
      fi
    fi
    printf '%s\n' "$line"
  done
}

# --- Extract just the YAML frontmatter block from a file ---
# Outputs the leading "---"..."---" block including the markers, or nothing if no frontmatter.
# CRLF-tolerant: matches "---" with optional trailing CR.
extract_frontmatter() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  awk '
    BEGIN { in_fm=0; done=0; first=1 }
    done { exit }
    {
      stripped = $0
      sub(/\r$/, "", stripped)
    }
    first {
      first=0
      if (stripped == "---") { in_fm=1; print; next }
      else { exit }
    }
    in_fm {
      print
      if (stripped == "---") { done=1 }
    }
  ' "$file"
}

# --- Check if file is a FORGE-managed command (frontmatter-aware) ---
# Returns 0 (true) if the body of the file (after any leading YAML frontmatter
# delimited by `---` on the first line and a closing `---`) contains
# "# Framework: FORGE" or "## Subcommand:" within the first 10 body lines.
# Returns 1 (false) otherwise. Files that do not exist return 1.
#
# Spec 385: structural skip-past-`---` detection — locate the closing `---` of the
# frontmatter and scan ≤10 lines after it. This replaces the prior fixed-line-window
# (`head -5`) approach, which broke when Spec 316 dropped `model_tier:` from wrapper
# frontmatter and shifted the marker line position. Three /consensus reviewers (DA,
# CTO, COO) flagged that any fixed N re-creates the regression class on the next
# frontmatter expansion, so the fix is structural rather than an N-bump.
#
# Pure-bash implementation (no pipes) — also resolves the Spec 364 SIGPIPE class by
# eliminating the strip_frontmatter | head | grep pipeline. CRLF-tolerant.
is_forge_command() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 1
  fi
  local in_frontmatter=false
  local past_frontmatter=false
  local first_line=true
  local body_count=0
  local line line_stripped
  while IFS= read -r line; do
    line_stripped="${line%$'\r'}"
    if $first_line; then
      first_line=false
      if [[ "$line_stripped" == "---" ]]; then
        in_frontmatter=true
        continue
      fi
      # No opening `---`: scan from line 1 (file has no frontmatter at all).
      past_frontmatter=true
    elif $in_frontmatter; then
      if [[ "$line_stripped" == "---" ]]; then
        in_frontmatter=false
        past_frontmatter=true
      fi
      continue
    fi
    if $past_frontmatter; then
      if [[ "$line_stripped" == "# Framework: FORGE"* ]] || [[ "$line_stripped" == "## Subcommand:"* ]]; then
        return 0
      fi
      body_count=$((body_count + 1))
      if [[ $body_count -ge 10 ]]; then
        return 1
      fi
    fi
  done < "$file"
  return 1
}

# --- Compare two files body-to-body (frontmatter stripped from both) ---
# Returns 0 if bodies are byte-identical post-strip, 1 otherwise.
# CRLF-tolerant (Spec 350): bodies are normalized via `tr -d '\r'` before diff,
# so files differing only in line-ending style (CRLF vs LF) compare equal.
# Use for --check and refuse-overwrite divergence detection.
bodies_equal() {
  local file_a="$1"
  local file_b="$2"
  if [[ ! -f "$file_a" || ! -f "$file_b" ]]; then
    return 1
  fi
  diff -q <(strip_frontmatter < "$file_a" | tr -d '\r') <(strip_frontmatter < "$file_b" | tr -d '\r') >/dev/null 2>&1
}
