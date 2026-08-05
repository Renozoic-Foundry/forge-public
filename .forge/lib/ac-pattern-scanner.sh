#!/usr/bin/env bash
# FORGE AC pattern scanner (Spec 540).
#
# Single pattern source (AC7) for browser-verb/deferred-AC detection, unifying
# the Spec 349 `/spec` Step 6d behavioral-AC regexes with the Spec 540
# browser-verb set. Two consumers share this one script:
#   - `/spec` Step 6d (authoring-time nudge, non-blocking)
#   - `/close` Step 2b2 / the validator subagent Stage-1 check (close-time gate)
# No second, divergent regex copy may exist in either consumer after this spec.
#
# Boundary vs Spec 403 (documented per Requirement 4): Spec 403's live-smoke
# gate keys on Test-Plan keywords ("smoke test", "live dry-run"). This scanner
# keys on Acceptance-Criteria browser verbs and behavioral phrasing. The two
# gates scan different sections for different signals and do not double-fire.
#
# Usage: ac-pattern-scanner.sh <spec-file> [mode]
#   mode: browser (default — Spec 540 browser-verb set, Spec 550 exclusions)
#         runnable (Spec 548 — ACs naming a runnable command/suite/script; the
#                   SINGLE shared command-detection source consumed by the
#                   validator execution-evidence post-check. No second heuristic
#                   may exist outside this script.)
# Output: JSON on stdout —
#   browser mode (Spec 618 three-state):
#     {"section_found":true|false,"flagged_acs":[{"ac_number":N,"text":"...","pattern":"..."}]}
#     section_found:false = NO recognized AC heading found; the scan read nothing and the
#     empty flagged_acs means nothing (could-not-check). An empty flagged_acs only ever
#     means "section read, no matches" when section_found is true.
#   runnable mode: {"flagged_acs":[...]} — schema unchanged (Spec 618 AC6 byte-parity).
set -euo pipefail

SPEC_FILE="${1:?usage: ac-pattern-scanner.sh <spec-file> [browser|runnable]}"
MODE="${2:-browser}"

if [[ ! -f "$SPEC_FILE" ]]; then
  if [[ "$MODE" == "runnable" ]]; then
    echo '{"flagged_acs":[]}'
  else
    echo '{"section_found":false,"flagged_acs":[]}'
  fi
  exit 0
fi

# Pattern list (case-insensitive, extended regex). Order = precedence when an
# AC matches more than one pattern — the first NON-EXCLUDED match wins for that
# AC's reported "pattern" field (Spec 550: an excluded weak match falls through
# to later patterns, so a strong verb elsewhere in the same AC still flags).
PATTERNS=(
  '(running|run|invoke|execute) /[a-z-]+'
  '(fresh|new) (fixture|copy|repo|project)'
  'after .+, the operator (sees|observes)'
  '\b(click|clicks|clicking)\b'
  '\b(hover|hovers|hovering)\b'
  '\b(render|renders|rendering)\b'
  '\b(show|shows|showing)\b'
  '\bvisible\b'
  '\b(display|displays|displaying)\b'
  '\b(scroll|scrolls|scrolling)\b'
)

# Spec 550 — weak patterns: ambiguous verbs that also occur in Copier/CI/fixture
# prose (6 recorded false positives: SIG-529-01, 532-01, 546-01, 526-02, 531-02,
# 536-02). A weak match flags only when no exclusion context matches the AC
# text. Strong verbs (click/hover/scroll and the phrase patterns) always flag.
# "console" is deliberately NOT an exclusion — it is legitimate UI vocabulary
# (DA finding: over-broad exclusions create silent false negatives at /close).
WEAK_PATTERNS=(
  '\b(render|renders|rendering)\b'
  '\b(show|shows|showing)\b'
  '\bvisible\b'
  '\b(display|displays|displaying)\b'
)

EXCLUSIONS=(
  '\bcopier\b'
  '\brender(s|ed|ing)?[ -]test'
  '\brenderer\b'
  '\bci (run|log)s?\b'
  '\bfixture(s)?\b'
  '\b(stdout|stderr|log line|log output|exit code)\b'
)

# Spec 548 — runnable-command pattern set (mode=runnable). Detects ACs whose
# text names a runnable suite/script/lint invocation; such ACs require
# execution evidence (exit code + output excerpt) in the validator report.
# Exclusions do NOT apply in runnable mode (different semantics: we WANT
# fixture/CI/suite vocabulary to match here).
RUNNABLE_PATTERNS=(
  '(bash|sh|pwsh|powershell|python[0-9]*|forge-py|npm|npx|node|copier|shellcheck|grep) [^ ]'
  '\b(validate|test)-[a-z0-9_-]+\.(sh|ps1|py)\b'
  '\b[a-z0-9_-]+\.(sh|ps1|py)\b'
  '\b(suite|suites|shellcheck|lint|linter) (pass|passes|passed|stays green|stay green|green|clean|PASS)'
  '\b(runs?|running|invoke[sd]?|execut(e|es|ed|ing)|re-?runs?) (the )?(suite|test|tests|script|fixture|linter|scanner|post-?check|helper)'
  'exit (code|status)'
)

is_weak_pattern() {
  local p="$1" w
  for w in "${WEAK_PATTERNS[@]}"; do
    if [[ "$p" == "$w" ]]; then return 0; fi
  done
  return 1
}

has_exclusion_context() {
  local t="$1" e
  for e in "${EXCLUSIONS[@]}"; do
    if printf '%s' "$t" | grep -Eiq "$e"; then return 0; fi
  done
  return 1
}

# Spec 618 — strip backticked spans so a weak token matching ONLY inside `...`
# is excluded (CLI subcommands, quoted flags/identifiers). Strong verbs are
# unaffected — only the WEAK_PATTERNS re-test uses the stripped text.
strip_backticks() {
  printf '%s' "$1" | sed -E 's/`[^`]*`//g'
}

# Spec 618 — token-scoped exclusion contexts (browser mode, weak patterns only).
# Unlike the whole-AC EXCLUSIONS above, each context binds to ONE token, so a
# CLI-subcommand `show` cannot excuse an unrelated `displays` in the same AC.
# NEVER add a bare `render` exclusion here — genuine "renders the page/view"
# browser ACs must keep flagging (same non-overreach stance as `console`).
has_token_exclusion() {
  local pat="$1" t="$2"
  case "$pat" in
    *show*)
      # `show` as a CLI subcommand: az pipelines runs show / git show / gh run show
      if printf '%s' "$t" | grep -Eiq '\b(az|kubectl|gh|docker|git)( [a-z0-9._-]+){0,6} show(s)?\b'; then return 0; fi
      ;;
    *visible*)
      # CLI-stdout prose (`visible` adjacent to `output`) and changelog-exemption
      # prose (`user-visible ... change`)
      if printf '%s' "$t" | grep -Eiq '\bvisible\b[^.]{0,16}\boutput\b|\boutput\b[^.]{0,16}\bvisible\b'; then return 0; fi
      if printf '%s' "$t" | grep -Eiq '\buser-visible\b[^.]{0,30}\bchange\b'; then return 0; fi
      ;;
    *render*)
      # render-tooling prose (Spec 625 live shapes): re-render forms; render
      # immediately adjacent to a tooling noun
      if printf '%s' "$t" | grep -Eiq '\bre-render(s|ed|ing)?\b|\brender (trigger|pipeline|source)s?\b'; then return 0; fi
      ;;
  esac
  return 1
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Extract the acceptance-criteria section body (up to the next "## " heading).
# Spec 618: case-insensitive, alternate heading names (Acceptance criteria /
# Definition of done), trailing parentheticals allowed via prefix match.
# section_found=false means NO recognized heading exists — the three-state
# signal that gate consumers treat as could-not-check, never a silent pass.
if grep -Eiq '^## (acceptance criteria|definition of done)' "$SPEC_FILE"; then
  section_found=true
else
  section_found=false
fi
ac_section="$(awk '
  tolower($0) ~ /^## (acceptance criteria|definition of done)/ { p=1; next }
  /^## / { p=0 }
  p { print }
' "$SPEC_FILE")"

entries=()
ac_num=""
ac_text=""

flush() {
  if [[ -n "$ac_num" ]]; then
    local pat stripped
    if [[ "$MODE" == "runnable" ]]; then
      for pat in "${RUNNABLE_PATTERNS[@]}"; do
        if printf '%s' "$ac_text" | grep -Eiq "$pat"; then
          entries+=("{\"ac_number\":${ac_num},\"text\":\"$(json_escape "$ac_text")\",\"pattern\":\"$(json_escape "$pat")\"}")
          break
        fi
      done
      return
    fi
    for pat in "${PATTERNS[@]}"; do
      if printf '%s' "$ac_text" | grep -Eiq "$pat"; then
        # Spec 550: excluded weak matches fall through to later patterns.
        if is_weak_pattern "$pat"; then
          if has_exclusion_context "$ac_text"; then continue; fi
          # Spec 618: the weak token must match OUTSIDE backticked spans...
          stripped="$(strip_backticks "$ac_text")"
          if ! printf '%s' "$stripped" | grep -Eiq "$pat"; then continue; fi
          # ...and outside its token-scoped exclusion contexts.
          if has_token_exclusion "$pat" "$stripped"; then continue; fi
        fi
        entries+=("{\"ac_number\":${ac_num},\"text\":\"$(json_escape "$ac_text")\",\"pattern\":\"$(json_escape "$pat")\"}")
        break
      fi
    done
  fi
}

while IFS= read -r line; do
  if [[ "$line" =~ ^([0-9]+)\.[[:space:]]+(.*)$ ]]; then
    flush
    ac_num="${BASH_REMATCH[1]}"
    ac_text="${BASH_REMATCH[2]}"
  elif [[ -n "$ac_num" ]]; then
    trimmed="$(trim "$line")"
    if [[ -n "$trimmed" ]]; then
      ac_text="${ac_text} ${trimmed}"
    fi
  fi
done <<< "$ac_section"
flush

if [[ "$MODE" == "runnable" ]]; then
  # Spec 618 AC6: runnable-mode output schema unchanged (byte-parity for Spec 548
  # consumers) — no section_found key here.
  if [[ ${#entries[@]} -eq 0 ]]; then
    echo '{"flagged_acs":[]}'
  else
    joined="$(IFS=,; echo "${entries[*]}")"
    echo "{\"flagged_acs\":[${joined}]}"
  fi
else
  if [[ ${#entries[@]} -eq 0 ]]; then
    echo "{\"section_found\":${section_found},\"flagged_acs\":[]}"
  else
    joined="$(IFS=,; echo "${entries[*]}")"
    echo "{\"section_found\":${section_found},\"flagged_acs\":[${joined}]}"
  fi
fi
