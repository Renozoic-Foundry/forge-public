#!/usr/bin/env bash
# generate-sprint-prompt.sh — Spec 656
#
# WHAT THIS IS: a PROMPT GENERATOR. It reads the operator-ratified autopilot loop template
# (.forge/prompts/autopilot-loop.md, Spec 528), fills its {{PLACEHOLDER}} blocks from spec
# frontmatter, prints an advisory pre-flight report, and prints the exact /loop line.
#
# WHAT IT IS NOT: a supervisor. It NEVER launches the loop, never runs /implement or /close,
# never pushes. The operator launches. That boundary is what makes this shippable ahead of the
# ADR-453 6.1 trust root — Spec 612 owns the command-logic scope and stays blocked on it.
#
# CAPABILITY NEUTRALITY IS A DESIGN PROPERTY, NOT A CONTROL ENFORCED HERE. The deny-list in
# test-spec-656-capability-neutrality.sh is a REGRESSION DETECTOR co-editable with this file;
# it catches accidental reintroduction of execution capability in review and CI. It does not
# withstand an adversary who edits both in one commit. The real bound is that this script adds
# no new code-execution path: the push guard and the /close authorization rule are independent
# of it and unmodified by it.
#
# CONTROL-CHARACTER SANITIZATION IS LOAD-BEARING (Spec 656 AC12, DA-gate critical finding).
# Spec frontmatter is agent-writable and its values are printed to a live terminal. A crafted
# field carrying ANSI/OSC sequences could visually spoof the operator's pre-launch review — the
# single control the capability-neutral argument rests on. Every frontmatter-derived value goes
# through sanitize() before it reaches stdout or the artifact. Do not add an output path that
# bypasses it.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TEMPLATE=".forge/prompts/autopilot-loop.md"
SPECS_DIR="docs/specs"
ARTIFACT_DIR=""
RUN_GOAL=""
END_CONDITION=""
EXTRA_RULES=""
declare -a TARGETS=()

usage() {
  cat <<'USAGE'
generate-sprint-prompt.sh — fill the ratified autopilot loop prompt (Spec 656)

Usage:
  generate-sprint-prompt.sh <spec-id> [<spec-id> ...] [options]

Options:
  --goal "<text>"       RUN_GOAL text (default: derived from the spec list)
  --end "<text>"        END_CONDITION text (default: derived from the spec list)
  --extra "<text>"      EXTRA_RULES text (default: the placeholder line is dropped)
  --artifact-dir <dir>  where to write the run artifact
  -h, --help            this text

Prints the filled prompt and the exact /loop line. Does NOT launch anything.
USAGE
}

# --- sanitize(): strip control characters except newline and tab (AC12) -------------
# perl, not sed: GNU sed accepts \xNN escapes but BSD sed does not, and this must behave
# identically on macOS. Strips CSI/OSC/Fe escape sequences first, then any surviving C0/C1
# control bytes. Printable UTF-8 (em-dashes, box drawing) is preserved on purpose — FORGE
# specs use those freely and mangling them would make the artifact harder to read.
sanitize() {
  # The C1 class MUST match code points, not bytes. Matching bytes ate every em-dash on the
  # first live run (U+2014 is E2 80 94; the 80 and 94 hit the C1 range) — AC12's positive
  # control is exactly what caught it. utf8::decode makes the class code-point-scoped.
  printf '%s' "$1" | perl -CSD -pe 'utf8::decode($_) unless utf8::is_utf8($_); s/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a\e]*(?:\a|\e\\)//g; s/\e[@-Z\\-_]//g; s/[\x{0000}-\x{0008}\x{000b}\x{000c}\x{000e}-\x{001f}\x{007f}-\x{009f}]//g;'
}

# --- frontmatter field read (single-line) ------------------------------------------
fm_field() {
  local file="$1" key="$2" v
  v="$(grep -m1 -E "^- ${key}:" "$file" 2>/dev/null | sed -E "s/^- ${key}:[[:space:]]*//")" || v=""
  v="${v%%<!--*}"
  v="$(printf '%s' "$v" | sed -E 's/[[:space:]]+$//')"
  sanitize "$v"
}

# --- Changed-files extraction (BODY content, NOT frontmatter) -----------------------
# parse_frontmatter (spec_frontmatter.py) breaks at the first '## ' heading by design and
# structurally cannot reach ## Implementation Summary. This awk is the SAME extraction
# safety-config.sh::safety_config_spec_files uses (Spec 542) — reused, not re-authored.
# Body-content readers are explicitly exempt from Spec 656's no-second-parser Constraint.
changed_files() {
  awk '/^## Implementation Summary$/{p=1; next} /^## /{p=0} p' "$1" 2>/dev/null \
    | grep -oE '`[^`]+`' | tr -d '`' \
    | grep -E '[/\\]|\.(md|sh|ps1|py|ya?ml|json|js|txt)$' | sort -u
}

spec_path() { ls "${SPECS_DIR}/${1}-"*.md 2>/dev/null | head -1; }

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --goal) RUN_GOAL="${2:-}"; shift 2 ;;
    --end) END_CONDITION="${2:-}"; shift 2 ;;
    --extra) EXTRA_RULES="${2:-}"; shift 2 ;;
    --artifact-dir) ARTIFACT_DIR="${2:-}"; shift 2 ;;
    -*) echo "generate-sprint-prompt: unknown option '$1'" >&2; usage >&2; exit 2 ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

[ "${#TARGETS[@]}" -gt 0 ] || { echo "generate-sprint-prompt: no spec ids given" >&2; usage >&2; exit 2; }
[ -f "$TEMPLATE" ] || { echo "generate-sprint-prompt: template missing at $TEMPLATE" >&2; exit 1; }

ARTIFACT_DIR="${ARTIFACT_DIR:-tmp/evidence/sprint-run-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$ARTIFACT_DIR"

# --- provenance: git SHA + sha256 of the template bytes actually read (AC8) ---------
TEMPLATE_SHA256="$( (sha256sum "$TEMPLATE" 2>/dev/null || shasum -a 256 "$TEMPLATE" 2>/dev/null) | awk '{print $1}')"
GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

declare -A STATUS LANE DEPS TITLE CFILES MALFORMED
PREFLIGHT=""
add_pf() { PREFLIGHT="${PREFLIGHT}$1"$'\n'; }

for id in "${TARGETS[@]}"; do
  f="$(spec_path "$id")"
  if [ -z "$f" ]; then
    add_pf "  MISSING   spec ${id}: no file matching ${SPECS_DIR}/${id}-*.md"
    MALFORMED[$id]=1; STATUS[$id]="unknown"; LANE[$id]="unknown"; TITLE[$id]="(missing)"; CFILES[$id]=""
    continue
  fi
  STATUS[$id]="$(fm_field "$f" 'Status')"
  LANE[$id]="$(fm_field "$f" 'Change-Lane')"
  DEPS[$id]="$(fm_field "$f" 'Dependencies')"
  TITLE[$id]="$(sanitize "$(grep -m1 -E '^# Spec ' "$f" | sed -E 's/^# Spec [0-9]+ [^ ]* //')")"
  cf="$(changed_files "$f")"
  CFILES[$id]="$cf"
  if [ -z "$cf" ]; then
    # AC6: report it, bar it from parallel bundling — but KEEP it in the ordered list.
    add_pf "  MALFORMED spec ${id}: no parseable Implementation Summary Changed-files — barred from parallel bundling (stays in the ordered list)"
    MALFORMED[$id]=1
  fi
  [ -n "$(fm_field "$f" 'Consensus-Review')" ] || add_pf "  MISSING   spec ${id}: no Consensus-Review field"
  [ -n "$(fm_field "$f" 'Token-Cost')" ]      || add_pf "  MISSING   spec ${id}: no Token-Cost field"
done

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  add_pf "  DIRTY     working tree has uncommitted changes — the plan reads the tree as-is"
fi
[ -n "$PREFLIGHT" ] || PREFLIGHT="  clean — no advisory conditions"$'\n'

# --- dependency-respecting order (stable topological sort) ---------------------------
declare -a ORDER=()
declare -A PLACED=()
declare -a remaining=("${TARGETS[@]}")
guard=0
while [ "${#remaining[@]}" -gt 0 ] && [ "$guard" -lt 100 ]; do
  guard=$((guard+1)); progress=0
  declare -a nextr=()
  for id in "${remaining[@]}"; do
    ready=1
    for d in $(printf '%s' "${DEPS[$id]:-}" | grep -oE '[0-9]{3}' || true); do
      for t in "${TARGETS[@]}"; do
        if [ "$d" = "$t" ] && [ -z "${PLACED[$d]:-}" ]; then ready=0; fi
      done
    done
    if [ "$ready" -eq 1 ]; then ORDER+=("$id"); PLACED[$id]=1; progress=1; else nextr+=("$id"); fi
  done
  remaining=("${nextr[@]+"${nextr[@]}"}")
  if [ "$progress" -eq 0 ]; then
    for id in "${remaining[@]}"; do ORDER+=("$id"); PLACED[$id]=1; done
    break
  fi
done

# --- parallel bundling: only declared-file-disjoint, non-malformed specs -------------
# AC5 requires that ANY TWO specs sharing a bundle have disjoint declared files. The first
# implementation compared each candidate against the SEED only, which is NOT sufficient:
# disjointness is not transitive. A∩B=∅ and A∩C=∅ says nothing about B∩C. On the first live
# run over the real 631-655 corpus, 640/641/655 all landed in one bundle despite all three
# declaring AGENTS.md — a bundle the operator could have acted on by running /parallel over
# three specs that would collide on the same file.
#
# The three-spec fixture could not express the failing shape (it needs two NON-seed specs that
# overlap each other but not the seed), so the fixture passed and the independent validator,
# reading that same fixture, passed it too. Both gates agreed and both were wrong.
#
# Now: a candidate must be disjoint from EVERY member already in the bundle.
declare -a BUNDLES=()
declare -A BUNDLED=()
disjoint_from_all() {   # $1 = candidate id, $2.. = current bundle members
  local cand="$1" m; shift
  for m in "$@"; do
    local n
    n="$(comm -12 <(printf '%s\n' "${CFILES[$cand]}" | sort -u) \
                  <(printf '%s\n' "${CFILES[$m]}"    | sort -u) | grep -c . || true)"
    [ "${n:-0}" -eq 0 ] || return 1
  done
  return 0
}
for id in "${ORDER[@]}"; do
  [ -n "${MALFORMED[$id]:-}" ] && continue
  [ -n "${BUNDLED[$id]:-}" ] && continue
  members=("$id"); BUNDLED[$id]=1
  for other in "${ORDER[@]}"; do
    [ "$other" = "$id" ] && continue
    [ -n "${MALFORMED[$other]:-}" ] && continue
    [ -n "${BUNDLED[$other]:-}" ] && continue
    if disjoint_from_all "$other" "${members[@]}"; then
      members+=("$other"); BUNDLED[$other]=1
    fi
  done
  # Single-member bundles carry no parallel-execution information; omit them.
  if [ "${#members[@]}" -gt 1 ]; then BUNDLES+=("${members[*]}"); fi
done

# --- build ORDERED_SPEC_LIST ---------------------------------------------------------
OSL=""
n=0
for id in "${ORDER[@]}"; do
  n=$((n+1))
  d="${DEPS[$id]:-}"
  case "$d" in ""|"—"|"-") d="none" ;; esac
  OSL="${OSL}${n}. Spec ${id} — ${TITLE[$id]}"$'\n'
  OSL="${OSL}   status: ${STATUS[$id]:-unknown} | lane: ${LANE[$id]:-unknown} | depends: ${d}"$'\n'
  if [ -n "${MALFORMED[$id]:-}" ]; then
    OSL="${OSL}   NOTE: declared-file list unparseable — run sequentially, never in a parallel bundle."$'\n'
  fi
done

RUN_GOAL="${RUN_GOAL:-specs ${TARGETS[*]} all at implemented}"
END_CONDITION="${END_CONDITION:-specs ${TARGETS[*]} all at implemented (or paused awaiting my gated input)}"

BODY="$(awk '/^---8<---$/{p=1; next} p' "$TEMPLATE")"
# NO -CSD here, deliberately. -CS decodes stdin and re-encodes stdout as UTF-8, but perl never
# decodes %ENV — the placeholder values would arrive as raw bytes, get spliced into a decoded
# buffer, and be double-encoded on the way out (that is what turned every em-dash into "â" on
# the first live run). Byte-oriented in, byte-oriented out: the placeholders are ASCII, so
# byte-level substitution is correct and leaves multi-byte content untouched.
OUT="$(printf '%s' "$BODY" | F_GOAL="$RUN_GOAL" F_OSL="$OSL" F_END="$END_CONDITION" F_EXTRA="$EXTRA_RULES" perl -0777 -pe '
  s/\{\{RUN_GOAL.*?\}\}/$ENV{F_GOAL}/gs;
  s/\{\{ORDERED_SPEC_LIST.*?\}\}/$ENV{F_OSL}/gs;
  s/\{\{END_CONDITION.*?\}\}/$ENV{F_END}/gs;
  if (length $ENV{F_EXTRA}) { s/\{\{EXTRA_RULES.*?\}\}/$ENV{F_EXTRA}/gs }
  else { s/^- \{\{EXTRA_RULES.*?\}\}\n//gsm }
')"

PROMPT_FILE="$ARTIFACT_DIR/prompt.txt"
printf '%s\n' "$OUT" > "$PROMPT_FILE"

{
  echo "spec-ids: ${TARGETS[*]}"
  echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "template: $TEMPLATE"
  echo "template_sha256: $TEMPLATE_SHA256"
  echo "git_sha: $GIT_SHA"
  echo "resolved_order: ${ORDER[*]}"
  # Join bundles with " | " — a space-joined list makes two bundles indistinguishable from
  # one, which is exactly how the AC5 defect above read as a single 24-spec bundle. The
  # fixture's own regex already assumed a "|" delimiter (SIG-656-08).
  if [ "${#BUNDLES[@]}" -eq 0 ]; then
    echo "parallel_bundles: none"
  else
    printf 'parallel_bundles: '; printf '%s' "${BUNDLES[0]}"
    for b in "${BUNDLES[@]:1}"; do printf ' | %s' "$b"; done; printf '
'
  fi
  echo "--- pre-flight ---"
  printf '%s' "$PREFLIGHT"
} > "$ARTIFACT_DIR/plan.txt"

echo "== Pre-flight report (ADVISORY — never blocks; exit code is always 0) =="
printf '%s' "$PREFLIGHT"
echo
echo "== Provenance =="
echo "  template : $TEMPLATE"
echo "  sha256   : $TEMPLATE_SHA256"
echo "  git HEAD : $GIT_SHA"
echo "  artifact : $ARTIFACT_DIR"
echo
echo "== Filled prompt =="
cat "$PROMPT_FILE"
echo
echo "== Launch it yourself (this script does not) =="
echo "  /loop \$(cat $PROMPT_FILE)"
exit 0
