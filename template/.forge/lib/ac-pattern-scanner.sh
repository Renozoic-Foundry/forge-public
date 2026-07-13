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
# Usage: ac-pattern-scanner.sh <spec-file>
# Output: JSON on stdout — {"flagged_acs":[{"ac_number":N,"text":"...","pattern":"..."}]}
#         Empty array when the spec's Acceptance Criteria contain no matches.
set -euo pipefail

SPEC_FILE="${1:?usage: ac-pattern-scanner.sh <spec-file>}"

if [[ ! -f "$SPEC_FILE" ]]; then
  echo '{"flagged_acs":[]}'
  exit 0
fi

# Pattern list (case-insensitive, extended regex). Order = precedence when an
# AC matches more than one pattern — the first match wins for that AC's
# reported "pattern" field.
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
    for pat in "${PATTERNS[@]}"; do
      if printf '%s' "$ac_text" | grep -Eiq "$pat"; then
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
