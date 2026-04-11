#!/usr/bin/env bash
# forge-test-skills.sh -- FORGE Skill Auto-Testing Framework
# Static analysis and sidecar-driven validation for command files.
set -euo pipefail

VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source logging if available, else plain echo
if [[ -f "${PROJECT_ROOT}/.forge/lib/logging.sh" ]]; then
  # shellcheck source=/dev/null
  source "${PROJECT_ROOT}/.forge/lib/logging.sh"
  forge_log_init "forge-test-skills"
fi
_log_error() { echo "[ERROR] $*" >&2; }

# --- Argument parsing ---
VERBOSE=0; COMMAND_FILTER=""; MODE="static"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose) VERBOSE=1; shift ;;
    --command) COMMAND_FILTER="${2:?--command requires NAME}"; shift 2 ;;
    --eval) MODE="eval"; shift ;;
    --benchmark) MODE="benchmark"; shift 2 ;;
    --trigger-check) MODE="trigger-check"; shift ;;
    -h|--help) echo "Usage: forge-test-skills.sh [--verbose] [--command NAME] [--eval] [--benchmark CMD] [--trigger-check]"; exit 0 ;;
    *) _log_error "Unknown argument: $1"; exit 1 ;;
  esac
done

# Stub modes
case "$MODE" in
  eval) echo "eval mode requires LLM, not yet implemented"; exit 0 ;;
  benchmark) echo "benchmark mode not yet implemented"; exit 0 ;;
  trigger-check) echo "trigger check mode not yet implemented"; exit 0 ;;
esac

TOTAL_PASS=0; TOTAL_FAIL=0; TOTAL_FILES=0
_verbose() { [[ "$VERBOSE" -eq 1 ]] && echo "    $*" || true; }

# --- YAML mini-parser (no yq dependency) ---
yaml_get_scalar() {
  local file="$1" key="$2"
  sed -n "s/^${key}:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*$/\1/p" "$file" | head -1
}
yaml_get_array() {
  local file="$1" key="$2" in_block=0
  while IFS= read -r line; do
    if [[ "$in_block" -eq 1 ]]; then
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
        local val="${BASH_REMATCH[1]}"; val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"; echo "$val"
      elif [[ "$line" =~ ^[[:space:]]*[^#[:space:]] ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then break; fi
    fi
    [[ "$line" =~ ^${key}: ]] && in_block=1
  done < "$file"
}

# Helper: strip whitespace/CR from numeric values (wc on Windows/Git Bash)
_num() { tr -dc '0-9' ; }

# --- Static checks (each sets check_pass and check_msg) ---
check_nonempty() {
  local sz; sz=$(wc -c < "$1" | _num); local ln; ln=$(wc -l < "$1" | _num)
  if [[ "$sz" -gt 0 ]]; then check_pass=1; check_msg="non-empty (${ln} lines)"
  else check_pass=0; check_msg="file is empty"; fi
}
check_markdown_wellformed() {
  local ct; ct=$(grep -c '```' "$1" 2>/dev/null || echo 0); ct=$(echo "$ct" | _num)
  if (( ct % 2 == 0 )); then check_pass=1; check_msg="markdown well-formed"
  else check_pass=0; check_msg="unclosed code block (${ct} fences)"; fi
}
check_has_heading() {
  local ct; ct=$(grep -c '^#' "$1" 2>/dev/null || echo 0); ct=$(echo "$ct" | _num)
  if [[ "$ct" -gt 0 ]]; then check_pass=1; check_msg="has heading (${ct} H2 sections)"
  else check_pass=0; check_msg="no heading found"; fi
}
check_no_template_artifacts() {
  if [[ "$1" == *.jinja ]]; then check_pass=1; check_msg="skipped (jinja file)"; return; fi
  local f=0
  grep -q '{{ *cookiecutter\.' "$1" 2>/dev/null && f=1
  grep -q '{%[-[:space:]]*raw[-[:space:]]*%}' "$1" 2>/dev/null && f=1
  grep -q '{%[-[:space:]]*endraw[-[:space:]]*%}' "$1" 2>/dev/null && f=1
  if [[ "$f" -eq 0 ]]; then check_pass=1; check_msg="no template artifacts"
  else check_pass=0; check_msg="raw template artifacts found"; fi
}
check_encoding() {
  if command -v iconv >/dev/null 2>&1; then
    if iconv -f UTF-8 -t UTF-8 "$1" >/dev/null 2>&1; then check_pass=1; check_msg="valid UTF-8"
    else check_pass=0; check_msg="not valid UTF-8"; fi
  else check_pass=1; check_msg="encoding check skipped (no iconv)"; fi
}
check_broken_links() {
  local dir; dir="$(dirname "$1")"; local broken=0 blist=""
  while IFS= read -r link; do
    [[ "$link" =~ ^https?:// || "$link" =~ ^# ]] && continue
    local path="${link%%#*}"; [[ -z "$path" ]] && continue
    [[ "$path" != /* ]] && path="${dir}/${path}"
    [[ ! -e "$path" ]] && broken=$((broken + 1)) && blist="${blist} ${link}"
  done < <(grep -oP '\[([^\]]*)\]\(\K[^)]+' "$1" 2>/dev/null || true)
  if [[ "$broken" -eq 0 ]]; then check_pass=1; check_msg="no broken links"
  else check_pass=0; check_msg="${broken} broken link(s):${blist}"; fi
}
check_line_count_bounds() {
  local ln; ln=$(wc -l < "$1" | _num); check_pass=1
  if [[ "$ln" -gt 1000 ]]; then check_pass=0; check_msg="too long (${ln} lines, max 1000)"
  elif [[ "$ln" -lt 5 ]]; then check_pass=0; check_msg="too short (${ln} lines, min 5)"
  else check_msg="line count OK (${ln})"; fi
}

# --- Sidecar checks ---
sidecar_required_sections() {
  local fail=0 missing=""
  while IFS= read -r p; do [[ -z "$p" ]] && continue
    grep -q "${p}" "$1" 2>/dev/null || { fail=1; missing="${missing} '${p}'"; }
  done < <(yaml_get_array "$2" "required_sections")
  [[ "$fail" -eq 0 ]] && { check_pass=1; check_msg="required sections present"; } || { check_pass=0; check_msg="missing sections:${missing}"; }
}
sidecar_required_strings() {
  local fail=0 missing=""
  while IFS= read -r s; do [[ -z "$s" ]] && continue
    grep -qi "${s}" "$1" 2>/dev/null || { fail=1; missing="${missing} '${s}'"; }
  done < <(yaml_get_array "$2" "required_strings")
  [[ "$fail" -eq 0 ]] && { check_pass=1; check_msg="required strings present"; } || { check_pass=0; check_msg="missing strings:${missing}"; }
}
sidecar_forbidden_strings() {
  local fail=0 flist=""
  while IFS= read -r s; do [[ -z "$s" ]] && continue
    grep -qi "${s}" "$1" 2>/dev/null && { fail=1; flist="${flist} '${s}'"; }
  done < <(yaml_get_array "$2" "forbidden_strings")
  [[ "$fail" -eq 0 ]] && { check_pass=1; check_msg="no forbidden strings"; } || { check_pass=0; check_msg="forbidden strings found:${flist}"; }
}
sidecar_line_bounds() {
  local ln; ln=$(wc -l < "$1" | _num); local mx; mx=$(yaml_get_scalar "$2" "max_lines"); local mn; mn=$(yaml_get_scalar "$2" "min_lines")
  check_pass=1; check_msg="line bounds OK (${ln})"
  if [[ -n "$mx" ]] && [[ "$ln" -gt "$mx" ]]; then check_pass=0; check_msg="exceeds max_lines (${ln} > ${mx})"; fi
  if [[ -n "$mn" ]] && [[ "$ln" -lt "$mn" ]]; then check_pass=0; check_msg="below min_lines (${ln} < ${mn})"; fi
}
sidecar_files_must_exist() {
  local fail=0 missing=""
  while IFS= read -r p; do [[ -z "$p" ]] && continue
    if [[ ! -e "${PROJECT_ROOT}/${p}" ]]; then fail=1; missing="${missing} '${p}'"; fi
  done < <(yaml_get_array "$1" "files_must_exist")
  [[ "$fail" -eq 0 ]] && { check_pass=1; check_msg="referenced files exist"; } || { check_pass=0; check_msg="missing files:${missing}"; }
}
sidecar_commands_must_exist() {
  local fail=0 missing=""
  while IFS= read -r c; do [[ -z "$c" ]] && continue
    local ok=0
    [[ -f "${PROJECT_ROOT}/.forge/commands/${c}.md" ]] && ok=1
    [[ -f "${PROJECT_ROOT}/.claude/commands/${c}.md" ]] && ok=1
    if [[ "$ok" -eq 0 ]]; then fail=1; missing="${missing} '${c}'"; fi
  done < <(yaml_get_array "$1" "commands_must_exist")
  [[ "$fail" -eq 0 ]] && { check_pass=1; check_msg="referenced commands exist"; } || { check_pass=0; check_msg="missing commands:${missing}"; }
}
sidecar_must_not_contain_raw() {
  local fail=0 flist=""
  while IFS= read -r p; do [[ -z "$p" ]] && continue
    grep -q "${p}" "$1" 2>/dev/null && { fail=1; flist="${flist} '${p}'"; }
  done < <(yaml_get_array "$2" "must_not_contain_raw")
  [[ "$fail" -eq 0 ]] && { check_pass=1; check_msg="no raw template vars"; } || { check_pass=0; check_msg="raw template vars found:${flist}"; }
}
sidecar_model_tier() {
  local expected; expected=$(yaml_get_scalar "$2" "expected")
  if [[ -z "$expected" ]]; then check_pass=1; check_msg="model tier not specified"; return; fi
  local actual; actual=$(grep -i '# Model-Tier:' "$1" 2>/dev/null | head -1 | sed 's/.*Model-Tier:[[:space:]]*//' | tr '[:upper:]' '[:lower:]')
  expected=$(echo "$expected" | tr '[:upper:]' '[:lower:]')
  if [[ -z "$actual" ]]; then check_pass=0; check_msg="no Model-Tier header (expected: ${expected})"
  elif [[ "$actual" == "$expected" ]]; then check_pass=1; check_msg="model tier matches (${expected})"
  else check_pass=0; check_msg="tier mismatch (expected: ${expected}, got: ${actual})"; fi
}

# --- Run a single sidecar check if data present ---
_run_sidecar() {
  local fn="$1" key="$2" cmd_file="$3" test_file="$4" is_array="${5:-1}"
  if [[ "$is_array" -eq 1 ]]; then
    yaml_get_array "$test_file" "$key" | grep -q . || return 0
  else
    yaml_get_scalar "$test_file" "$key" | grep -q . || return 0
  fi
  "$fn" "$cmd_file" "$test_file"
  sc_total=$((sc_total + 1))
  if [[ "$check_pass" -eq 1 ]]; then sc_pass=$((sc_pass + 1)); _verbose "[PASS] ${check_msg}"
  else any_fail=1; _verbose "[FAIL] ${check_msg}"; fi
}

# --- Test one command file ---
test_command_file() {
  local cmd_file="$1" basename; basename="$(basename "$cmd_file")"
  local name="${basename%.md}" st_pass=0 st_total=0 sc_pass=0 sc_total=0 any_fail=0
  if [[ "$VERBOSE" -eq 1 ]]; then echo "  ${basename}:"; fi

  # Static checks
  local checks=(check_nonempty check_markdown_wellformed check_has_heading \
    check_no_template_artifacts check_encoding check_broken_links check_line_count_bounds)
  for fn in "${checks[@]}"; do
    check_pass=0; check_msg=""
    "$fn" "$cmd_file"; st_total=$((st_total + 1))
    if [[ "$check_pass" -eq 1 ]]; then st_pass=$((st_pass + 1)); _verbose "[PASS] ${check_msg}"
    else any_fail=1; _verbose "[FAIL] ${check_msg}"; fi
  done

  # Sidecar
  local test_file="" cmd_dir; cmd_dir="$(dirname "$cmd_file")"
  [[ -f "${cmd_dir}/tests/${name}.test.yaml" ]] && test_file="${cmd_dir}/tests/${name}.test.yaml"
  if [[ -n "$test_file" ]]; then
    _run_sidecar sidecar_required_sections "required_sections" "$cmd_file" "$test_file"
    _run_sidecar sidecar_required_strings "required_strings" "$cmd_file" "$test_file"
    _run_sidecar sidecar_forbidden_strings "forbidden_strings" "$cmd_file" "$test_file"
    # line bounds: check both keys
    local has_bounds=0
    yaml_get_scalar "$test_file" "max_lines" | grep -q . && has_bounds=1
    yaml_get_scalar "$test_file" "min_lines" | grep -q . && has_bounds=1
    if [[ "$has_bounds" -eq 1 ]]; then
      sidecar_line_bounds "$cmd_file" "$test_file"; sc_total=$((sc_total + 1))
      if [[ "$check_pass" -eq 1 ]]; then sc_pass=$((sc_pass + 1)); _verbose "[PASS] ${check_msg}"
      else any_fail=1; _verbose "[FAIL] ${check_msg}"; fi
    fi
    _run_sidecar sidecar_files_must_exist "files_must_exist" "$test_file" "$test_file"
    _run_sidecar sidecar_commands_must_exist "commands_must_exist" "$test_file" "$test_file"
    _run_sidecar sidecar_must_not_contain_raw "must_not_contain_raw" "$cmd_file" "$test_file"
    _run_sidecar sidecar_model_tier "expected" "$cmd_file" "$test_file" 0
  fi

  TOTAL_FILES=$((TOTAL_FILES + 1))
  local detail="${st_pass}/${st_total} static"
  if [[ -n "$test_file" ]] && [[ "$sc_total" -gt 0 ]]; then detail="${detail} + ${sc_pass}/${sc_total} sidecar"
  elif [[ -z "$test_file" ]]; then detail="${detail}, no sidecar"; fi

  if [[ "$any_fail" -eq 0 ]]; then
    TOTAL_PASS=$((TOTAL_PASS + 1))
    if [[ "$VERBOSE" -eq 0 ]]; then printf "  %-30s PASS (%s)\n" "$basename" "$detail"; fi
  else
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    if [[ "$VERBOSE" -eq 0 ]]; then printf "  %-30s FAIL (%s)\n" "$basename" "$detail"; fi
  fi
}

# --- Test a directory ---
test_command_dir() {
  local dir="$1" label="$2"
  if [[ ! -d "$dir" ]]; then return; fi
  local files=()
  while IFS= read -r -d '' f; do files+=("$f")
  done < <(find "$dir" -maxdepth 1 -name '*.md' -print0 2>/dev/null | sort -z)
  if [[ ${#files[@]} -eq 0 ]]; then return; fi
  if [[ -n "$COMMAND_FILTER" ]]; then
    local filtered=()
    for f in "${files[@]}"; do
      if [[ "$(basename "$f" .md)" == "$COMMAND_FILTER" ]]; then filtered+=("$f"); fi
    done
    if [[ ${#filtered[@]} -eq 0 ]]; then return; fi
    files=("${filtered[@]}")
  fi
  echo ""; echo "Testing ${label} (${#files[@]} files)"
  for f in "${files[@]}"; do test_command_file "$f"; done
}

# --- Main ---
echo "forge-test-skills v${VERSION} -- FORGE Skill Auto-Testing"
test_command_dir "${PROJECT_ROOT}/.forge/commands" ".forge/commands/"
test_command_dir "${PROJECT_ROOT}/.claude/commands" ".claude/commands/"
echo ""; echo "Summary: ${TOTAL_PASS}/${TOTAL_FILES} PASS, ${TOTAL_FAIL}/${TOTAL_FILES} FAIL"
if [[ "$TOTAL_FAIL" -gt 0 ]]; then exit 1; fi
exit 0
