#!/usr/bin/env bash
# FORGE safety-config helpers — Spec 387 Component A library.
# Sourceable: pure functions, no main execution.
#
# Public functions:
#   safety_config_load <path>         — read patterns array from yaml; emit one per line on stdout
#   safety_config_match_diff <yaml> <diff-output>
#                                     — given diff (one path per line on stdin or arg), emit
#                                       matching paths to stdout (each path printed once)
#   safety_config_validate_override <reason>
#                                     — exit 0 if reason is valid (≥50 chars, non-trivial),
#                                       exit 1 + stderr message otherwise
#   safety_config_bootstrap_fallback <diff-output>
#                                     — exit 0 if diff includes registry add/delete (R1c),
#                                       exit 1 otherwise
#   safety_config_load_ignore_list <path>
#                                     — read ignore-yaml (Spec 397); emit one token name per line
#                                       on stdout. Verifies version: 1; warns on empty reason;
#                                       exit 1 + stderr on missing/wrong-version yaml.
#   safety_config_spec_files <spec-num> <baseline> [<head>] [<spec-file>]
#                                     — Spec 542 R1: emit the spec-under-review's own changed
#                                       files (one per line), attributed via commits whose
#                                       message tags "Spec <NUM>", falling back to the spec's
#                                       Implementation Summary "Changed files" list. Exit 0 if
#                                       per-spec data was found, exit 1 if neither source
#                                       yielded data (caller falls back to cumulative diff + WARN).
#   safety_config_region_touched <baseline> <head> <file> <heading>
#                                     — Spec 542 R2: exit 0 if the diff between baseline and head
#                                       touches any line inside the markdown section starting at
#                                       <heading> (through the next heading of equal-or-lesser
#                                       depth, or EOF) in <file> at <head>. Exit 1 otherwise.
#   safety_config_registry_files <yaml>
#                                     — Spec 542 R2: emit registry patterns with any `::<heading>`
#                                       region suffix stripped, deduplicated (one file-glob per
#                                       line). For consumers that enumerate whole files (e.g. the
#                                       backfill audit's wide-net scan), which are region-agnostic
#                                       by design — the audit sweeps a file for un-annotated safety
#                                       declarations regardless of which section they land in.

# Trivial-string patterns that auto-reject as override reasons (R4b).
# Case-insensitive match against trimmed reason text.
SAFETY_TRIVIAL_PATTERNS=(wip ok later fix tbd n/a na none pass "done")

# Load patterns array from a yaml registry file. Emits one pattern per line.
# Comments (#) and blank lines stripped. Quoted values unquoted.
# Returns non-zero if file is missing or malformed.
safety_config_load() {
  local yaml_file="$1"
  if [[ ! -f "$yaml_file" ]]; then
    return 1
  fi
  # Extract list items under `patterns:` (lines starting with "  - ").
  # Strip surrounding quotes and trailing CR.
  local in_patterns=false
  local line stripped item
  while IFS= read -r line; do
    stripped="${line%$'\r'}"
    if [[ "$stripped" =~ ^patterns:[[:space:]]*$ ]]; then
      in_patterns=true
      continue
    fi
    if $in_patterns; then
      # Stop at any non-list, non-blank, non-comment line.
      if [[ -z "$stripped" ]] || [[ "$stripped" =~ ^[[:space:]]*# ]]; then
        continue
      fi
      if [[ "$stripped" =~ ^[[:space:]]+-[[:space:]]+(.+)$ ]]; then
        item="${BASH_REMATCH[1]}"
        # Strip surrounding quotes (single or double).
        item="${item#\"}"; item="${item%\"}"
        item="${item#\'}"; item="${item%\'}"
        printf '%s\n' "$item"
      else
        in_patterns=false
      fi
    fi
  done < "$yaml_file"
}

# Match a list of diff paths (stdin) against registry patterns.
# Emits matching diff paths to stdout (one per line, deduplicated, in input order).
#
# $2/$3 (optional, Spec 542 R2) — baseline/head revisions. Required only to evaluate
# region-scoped entries (pattern form `<file>::<heading>`); whole-file entries match
# regardless. Without $2, region entries are silently skipped (never match) — callers
# that only need whole-file matching (e.g. existing Spec 387 tests) are unaffected.
safety_config_match_diff() {
  local yaml_file="$1"
  local baseline="${2:-}"
  local head="${3:-HEAD}"
  local -a patterns=()
  local pattern
  while IFS= read -r pattern; do
    patterns+=("$pattern")
  done < <(safety_config_load "$yaml_file")
  if [[ ${#patterns[@]} -eq 0 ]]; then
    return 0
  fi
  # shellcheck disable=SC2034
  declare -A seen=()
  local diff_path
  while IFS= read -r diff_path; do
    [[ -z "$diff_path" ]] && continue
    if [[ -n "${seen[$diff_path]:-}" ]]; then
      continue
    fi
    for pattern in "${patterns[@]}"; do
      if [[ "$pattern" == *"::"* ]]; then
        # Region-scoped entry: <file>::<heading>. Only fires if the diff's changed
        # lines intersect the named heading's section in the file at $head.
        local region_file="${pattern%%::*}"
        local region_heading="${pattern#*::}"
        if [[ "$diff_path" == "$region_file" && -n "$baseline" ]] \
          && safety_config_region_touched "$baseline" "$head" "$region_file" "$region_heading"; then
          printf '%s\n' "$diff_path"
          seen[$diff_path]=1
          break
        fi
        continue
      fi
      # Convert glob pattern to bash extended-glob form.
      # `**/*.yaml` -> nested-dir match via `==` glob.
      # bash `[[ str == pattern ]]` honors * and ? but NOT **.
      # Translate `**` to `*` for matching purposes (good enough for our patterns).
      local bash_pattern="${pattern//\*\*/\*}"
      # shellcheck disable=SC2053
      if [[ "$diff_path" == $bash_pattern ]]; then
        printf '%s\n' "$diff_path"
        seen[$diff_path]=1
        break
      fi
    done
  done
}

# Line range [start end] (1-indexed, inclusive) of a markdown heading's section in
# <file> as it exists at <rev>. The section runs from the heading line through the
# line before the next heading of equal-or-lesser depth, or EOF. Prints "start end"
# to stdout; returns 1 if the file or heading is not found at that revision.
safety_config_region_line_range() {
  local rev="$1" file="$2" heading="$3"
  local content
  content="$(git show "${rev}:${file}" 2>/dev/null)" || return 1
  local start_line
  start_line="$(printf '%s\n' "$content" | grep -nF -- "$heading" | head -1 | cut -d: -f1)"
  if [[ -z "$start_line" ]]; then
    return 1
  fi
  local depth_marker="${heading%%[! #]*}"
  depth_marker="${depth_marker// /}"
  [[ -z "$depth_marker" ]] && depth_marker="#"
  local depth="${#depth_marker}"
  local total_lines
  total_lines="$(printf '%s\n' "$content" | wc -l)"
  # Find the next real markdown heading of depth <= $depth after $start_line, skipping
  # lines inside fenced code blocks (```) — a YAML `# comment` inside a fence would
  # otherwise false-match as a markdown heading.
  local end_line
  end_line="$(printf '%s\n' "$content" | awk -v start="$start_line" -v depth="$depth" -v total="$total_lines" '
    NR <= start { next }
    /^```/ { infence = !infence; next }
    infence { next }
    $0 ~ ("^#{1," depth "}[[:space:]]") { print NR - 1; found=1; exit }
    END { if (!found) print total }
  ')"
  printf '%d %d\n' "$start_line" "$end_line"
}

# Exit 0 if the diff between <baseline> and <head> touches any changed line inside
# <heading>'s section of <file> (per safety_config_region_line_range at <head>).
# Exit 1 if the heading is not found, or the diff doesn't intersect its line range.
safety_config_region_touched() {
  local baseline="$1" head="$2" file="$3" heading="$4"
  local range
  range="$(safety_config_region_line_range "$head" "$file" "$heading")" || return 1
  local region_start region_end
  read -r region_start region_end <<< "$range"
  local hunk_line
  while IFS= read -r hunk_line; do
    if [[ "$hunk_line" =~ ^@@\ -[0-9]+(,[0-9]+)?\ \+([0-9]+)(,([0-9]+))?\ @@ ]]; then
      local new_start="${BASH_REMATCH[2]}"
      local new_count="${BASH_REMATCH[4]:-1}"
      local new_end=$((new_start + new_count - 1))
      if (( new_count == 0 )); then
        new_end="$new_start"
      fi
      if (( new_start <= region_end && new_end >= region_start )); then
        return 0
      fi
    fi
  done < <(git diff --unified=0 "$baseline" "$head" -- "$file" 2>/dev/null | grep -E '^@@ ')
  return 1
}

# Emit registry patterns with any `::<heading>` region suffix stripped (Spec 542 R2),
# deduplicated. Whole-file entries pass through unchanged.
safety_config_registry_files() {
  local yaml_file="$1"
  local pattern
  # shellcheck disable=SC2034
  declare -A seen=()
  while IFS= read -r pattern; do
    local file_only="${pattern%%::*}"
    if [[ -z "${seen[$file_only]:-}" ]]; then
      printf '%s\n' "$file_only"
      seen[$file_only]=1
    fi
  done < <(safety_config_load "$yaml_file")
}

# Spec 542 R1 — emit the spec-under-review's own changed files (one per line),
# attributed via commits whose message tags "Spec <NUM>" (word-boundary match, so
# "Spec 54" doesn't match "Spec 540"), between <baseline> and <head>. Falls back to
# the spec file's "## Implementation Summary" backtick-quoted "Changed files" list
# when no tagged commits are found. Exit 0 if either source yielded files (even an
# empty list from zero-touch commits), exit 1 if neither source is available —
# callers should fall back to the cumulative baseline..head diff with a WARN.
safety_config_spec_files() {
  local spec_num="$1" baseline="$2" head="${3:-HEAD}" spec_file="${4:-}"
  local commits
  commits="$(git log --no-merges --pretty=format:%H -E --grep="Spec ${spec_num}([^0-9]|\$)" "${baseline}..${head}" 2>/dev/null || true)"
  if [[ -n "$commits" ]]; then
    local c
    while IFS= read -r c; do
      [[ -z "$c" ]] && continue
      git diff-tree --no-commit-id --name-only -r "$c" 2>/dev/null
    done <<< "$commits" | sort -u
    return 0
  fi
  if [[ -n "$spec_file" && -f "$spec_file" ]]; then
    local summary files
    summary="$(awk '/^## Implementation Summary$/{p=1; next} /^## /{p=0} p' "$spec_file")"
    files="$(printf '%s\n' "$summary" | grep -oE '`[^`]+`' | tr -d '`' | grep -vE '\s' || true)"
    if [[ -n "$files" ]]; then
      printf '%s\n' "$files"
      return 0
    fi
  fi
  return 1
}

# Validate Safety-Override reason text per R4b.
# Exit 0 if valid, exit 1 + stderr on failure.
safety_config_validate_override() {
  local reason="$1"
  # Trim leading/trailing whitespace.
  local trimmed="${reason#"${reason%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  local len="${#trimmed}"
  if (( len < 50 )); then
    printf 'Safety-Override reason too short (%d chars, minimum 50). Provide a sentence of reasoning.\n' "$len" >&2
    return 1
  fi
  # Lowercase comparison for trivial-string match.
  local lower="${trimmed,,}"
  local trivial
  for trivial in "${SAFETY_TRIVIAL_PATTERNS[@]}"; do
    if [[ "$lower" == "$trivial" ]]; then
      printf 'Safety-Override reason too trivial (matched: %s). Provide a sentence of reasoning.\n' "$trivial" >&2
      return 1
    fi
  done
  return 0
}

# Validate ## Safety Enforcement section in a spec body per R2d.
# Inputs:
#   $1 — spec file path
#   $2 — repo root (for resolving file paths in the section). Defaults to PWD.
# Exits 0 if section valid, 2 if invalid (matching R2e). Writes detail to stderr on failure.
safety_config_validate_section() {
  local spec_file="$1"
  local repo_root="${2:-.}"
  if [[ ! -f "$spec_file" ]]; then
    printf 'safety_config_validate_section: spec file not found: %s\n' "$spec_file" >&2
    return 2
  fi
  local section
  section="$(awk '/^## Safety Enforcement$/{p=1; next} /^## /{p=0} p' "$spec_file")"
  if [[ -z "$section" ]]; then
# forge:path-literal-ok (docstring/prose — classic-default spelling in help text; Spec 575)
    printf 'Safety enforcement section incomplete or missing. See template/docs/process-kit/safety-property-gate-guide.md.\n' >&2
    return 2
  fi
  local ep_line np_line val_line
  ep_line="$(echo "$section" | grep -E '^Enforcement code path: ' || true)"
  np_line="$(echo "$section" | grep -E '^Negative-path test: ' || true)"
  val_line="$(echo "$section" | grep -E '^Validates' || true)"
  if [[ -z "$ep_line" || -z "$np_line" || -z "$val_line" ]]; then
    # forge:path-literal-ok (prose — guide pointer in operator message; Spec 575)
    printf 'Safety enforcement section incomplete or missing. See template/docs/process-kit/safety-property-gate-guide.md.\n' >&2
    return 2
  fi
  local val_text="${val_line#Validates}"
  if (( ${#val_text} < 10 )); then
    printf 'Safety-Enforcement Validates description too short (<10 chars).\n' >&2
    return 2
  fi
  local ep_file ep_sym np_file
  ep_file="$(echo "$ep_line" | sed -E 's/^Enforcement code path: ([^:]+)::.*/\1/')"
  ep_sym="$(echo  "$ep_line" | sed -E 's/^Enforcement code path: [^:]+::(.*)$/\1/')"
  np_file="$(echo "$np_line" | sed -E 's/^Negative-path test: ([^:]+)::.*/\1/')"
  # UNENFORCED deferral path (R3): placeholder requires Spec NNN reference.
  if [[ "$ep_sym" == "<placeholder>" || "$np_line" == *"<deferred to Spec"* ]]; then
    local ref ref_num ref_file ref_status
    ref="$(echo "$section" | grep -oE 'Spec [0-9]{3}' | head -1)"
    if [[ -z "$ref" ]]; then
      printf 'Placeholder used without Spec NNN reference. Per R3, placeholders require an UNENFORCED-pointer.\n' >&2
      return 2
    fi
    ref_num="$(echo "$ref" | awk '{print $2}')"
    local _sc_specs; _sc_specs="$(cd "${repo_root}" && forge_path specs 2>/dev/null || echo docs/specs)"
    ref_file="$(ls "${repo_root}"/${_sc_specs}/${ref_num}-*.md 2>/dev/null | head -1)"
    if [[ -z "$ref_file" ]]; then
      printf 'Referenced %s does not exist.\n' "$ref" >&2
      return 2
    fi
    ref_status="$(grep -E '^- Status: ' "$ref_file" | sed -E 's/^- Status: //')"
    case "$ref_status" in
      draft|in-progress|implemented|closed) return 0 ;;
      *)
        printf 'Referenced %s has invalid status (%s). Per R3c, must be draft|in-progress|implemented|closed.\n' "$ref" "$ref_status" >&2
        return 2
        ;;
    esac
  fi
  # Non-placeholder: file paths must resolve relative to repo root.
  if [[ ! -f "${repo_root}/${ep_file}" ]]; then
    printf 'Enforcement code path file not found: %s\n' "$ep_file" >&2
    return 2
  fi
  if [[ ! -f "${repo_root}/${np_file}" ]]; then
    printf 'Negative-path test file not found: %s\n' "$np_file" >&2
    return 2
  fi
  return 0
}

# Load ignore-list from a Spec 397 ignore yaml. Emits one token name per line.
# Verifies `version: 1` is present (refuses any other version with stderr error).
# Warns to stderr on entries with empty reason; still emits the token.
# Pure bash — same parsing approach as safety_config_load (no yaml library).
safety_config_load_ignore_list() {
  local yaml_file="$1"
  if [[ ! -f "$yaml_file" ]]; then
    printf 'safety_config_load_ignore_list: file not found: %s\n' "$yaml_file" >&2
    return 1
  fi
  local version_line
  version_line="$(grep -E '^version:[[:space:]]*' "$yaml_file" | head -1 || true)"
  if [[ -z "$version_line" ]]; then
    printf 'safety_config_load_ignore_list: unsupported ignore-list schema version (expected 1)\n' >&2
    return 1
  fi
  local version_val
  version_val="$(printf '%s' "$version_line" | sed -E 's/^version:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')"
  if [[ "$version_val" != "1" ]]; then
    printf 'safety_config_load_ignore_list: unsupported ignore-list schema version (expected 1)\n' >&2
    return 1
  fi
  # Walk the file; each ignore entry begins with `- token: <name>`.
  # Track whether the most recent entry has a reason; warn on empty reasons.
  local in_ignore=false
  local current_token=""
  local current_reason=""
  local line stripped
  local -a tokens=()
  local -A token_reasons=()
  while IFS= read -r line; do
    stripped="${line%$'\r'}"
    if [[ "$stripped" =~ ^ignore:[[:space:]]*$ ]]; then
      in_ignore=true
      continue
    fi
    if ! $in_ignore; then continue; fi
    # Skip comments / blank lines.
    if [[ -z "$stripped" ]] || [[ "$stripped" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    # New entry.
    if [[ "$stripped" =~ ^[[:space:]]+-[[:space:]]+token:[[:space:]]*(.+)$ ]]; then
      # Flush previous entry.
      if [[ -n "$current_token" ]]; then
        tokens+=("$current_token")
        token_reasons["$current_token"]="$current_reason"
      fi
      current_token="${BASH_REMATCH[1]}"
      current_token="${current_token#\"}"; current_token="${current_token%\"}"
      current_token="${current_token#\'}"; current_token="${current_token%\'}"
      current_token="${current_token%"${current_token##*[![:space:]]}"}"
      current_reason=""
      continue
    fi
    # Reason line.
    if [[ "$stripped" =~ ^[[:space:]]+reason:[[:space:]]*(.*)$ ]]; then
      current_reason="${BASH_REMATCH[1]}"
      current_reason="${current_reason#\"}"; current_reason="${current_reason%\"}"
      current_reason="${current_reason#\'}"; current_reason="${current_reason%\'}"
      continue
    fi
    # Top-level key (no leading space) ends the ignore section.
    if [[ "$stripped" =~ ^[^[:space:]] ]]; then
      in_ignore=false
    fi
  done < "$yaml_file"
  # Flush final entry.
  if [[ -n "$current_token" ]]; then
    tokens+=("$current_token")
    token_reasons["$current_token"]="$current_reason"
  fi
  # Emit; warn on empty reason.
  local t
  for t in "${tokens[@]}"; do
    if [[ -z "${token_reasons[$t]}" ]]; then
      printf 'safety_config_load_ignore_list: warning: token %s has empty reason\n' "$t" >&2
    fi
    printf '%s\n' "$t"
  done
}

# Detect registry-file add/delete in a diff (R1c bootstrap fallback).
# Reads `git diff --name-status` output (stdin or arg).
# Exit 0 if registry file appears with status A or D, exit 1 otherwise.
safety_config_bootstrap_fallback() {
  local registry_path=".forge/safety-config-paths.yaml"
  local line status path
  while IFS=$'\t' read -r status path; do
    [[ -z "$status" ]] && continue
    if [[ "$path" == "$registry_path" ]]; then
      if [[ "$status" == "A" ]] || [[ "$status" == "D" ]]; then
        return 0
      fi
    fi
  done
  return 1
}
