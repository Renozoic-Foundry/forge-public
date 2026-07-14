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
# Output: JSON on stdout — {"flagged_acs":[{"ac_number":N,"text":"...","pattern":"..."}]}
#         Empty array when the spec's Acceptance Criteria contain no matches.
set -euo pipefail

SPEC_FILE="${1:?usage: ac-pattern-scanner.sh <spec-file> [browser|runnable]}"
MODE="${2:-browser}"

if [[ ! -f "$SPEC_FILE" ]]; then
  echo '{"flagged_acs":[]}'
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

# Extract the "## Acceptance Criteria" section body (up to the next "## " heading).
ac_section="$(awk '
  /^## Acceptance Criteria/ { p=1; next }
  /^## / { p=0 }
  p { print }
' "$SPEC_FILE")"

entries=()
ac_num=""
ac_text=""

flush() {
  if [[ -n "$ac_num" ]]; then
    local pat
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
        if is_weak_pattern "$pat" && has_exclusion_context "$ac_text"; then
          continue
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

if [[ ${#entries[@]} -eq 0 ]]; then
  echo '{"flagged_acs":[]}'
else
  joined="$(IFS=,; echo "${entries[*]}")"
  echo "{\"flagged_acs\":[${joined}]}"
fi
