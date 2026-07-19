#!/usr/bin/env bash
# forge-doctor.sh — read-only distribution/provenance diagnostic (Spec 520, ADR-502 Phase 1)
#
# Emits five advisory checks and NEVER writes, deletes, blocks, or auto-fixes
# (guardrail G4). The only writes it performs are its own coverage state file under
# .forge/state/ (gitignored) — everything else is pure read.
#
#   D-PROVENANCE                 — .copier-answers.yml pinned _commit sanity (best-effort);
#                                  a non-consumer repo reports "not a copier consumer"
#   D-CURRENCY                   — ahead/behind vs the configured upstream (warns behind>0)
#   D-TAXONOMY-COVERAGE          — % of tracked paths matched by a taxonomy rule + delta
#   D-CONFIDENTIALITY-CONSISTENCY — private/customer-classified paths inside the
#                                  publish-reachable set (from sync-to-public.sh
#                                  --print-public-set — single source; this script never
#                                  parses the publish manifest DSL itself)
#   D-PUBLIC-CHECKOUT            — sibling ../forge-public branch/currency (best-effort)
#
# GRACEFUL DEGRADATION (consumer checkouts): the taxonomy map and the sync script are
# private dev-repo artifacts that do NOT ship with this script. When either is absent —
# or the print flag itself fails — the affected check prints an advisory note and the
# run still exits 0.
#
# Usage:
#   bash .forge/bin/forge-doctor.sh              # full run — advisory, always exit 0
#   bash .forge/bin/forge-doctor.sh --strict     # exit 1 on HIGH findings or behind>0 (CI)
#   bash .forge/bin/forge-doctor.sh --summary    # one-line currency summary (SessionStart)
#
# Env:
#   FORGE_DOCTOR_ROOT       — project root override (default: git toplevel of cwd)
#   FORGE_DOCTOR_TAXONOMY   — taxonomy file override (fixtures)
#   FORGE_DOCTOR_STATE_DIR  — coverage state dir override (default: <root>/.forge/state)
#   FORGE_DOCTOR_NO_FETCH=1 — skip the best-effort `git fetch` in D-CURRENCY
#
# Spec: 520

set -uo pipefail

STRICT=false
SUMMARY=false
VERBOSE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=true ;;
    --summary) SUMMARY=true ;;
    --verbose) VERBOSE=true ;;
    --help|-h)
      sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "forge doctor: unknown flag: $1 (supported: --strict, --summary, --verbose)" >&2; exit 2 ;;
  esac
  shift
done

# --- root resolution (env override -> git toplevel -> script-relative) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${FORGE_DOCTOR_ROOT:-}"
if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$ROOT" ]]; then
  ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
fi
if ! cd "$ROOT" 2>/dev/null; then
  echo "forge doctor: cannot resolve project root — nothing to diagnose (advisory, exit 0)" >&2
  exit 0
fi

TAXONOMY="${FORGE_DOCTOR_TAXONOMY:-${ROOT}/.forge/distribution-taxonomy.yaml}"
STATE_DIR="${FORGE_DOCTOR_STATE_DIR:-${ROOT}/.forge/state}"
SYNC_SCRIPT="${ROOT}/scripts/sync-to-public.sh"
PY="$(command -v python3 || command -v python || true)"

HIGH_COUNT=0
MEDIUM_COUNT=0
PROV_STATUS=""
PCT=""
DELTA=
BEHIND_COUNT=0
INSTALLED_STALE_COUNT=0

TMPD="$(mktemp -d "${TMPDIR:-${TEMP:-/tmp}}/forge-doctor-XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

# --- currency computation (shared by --summary and the full D-CURRENCY section) ---
CUR_BRANCH=""
CUR_UPSTREAM=""
CUR_AHEAD=""
CUR_BEHIND=""
CUR_NOTE=""
compute_currency() {
  local do_fetch="$1" counts remote
  CUR_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(unknown)")"
  CUR_UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ -z "$CUR_UPSTREAM" ]]; then
    CUR_NOTE="no upstream configured for '${CUR_BRANCH}' — currency unknown"
    return 0
  fi
  if [[ "$do_fetch" == "true" && "${FORGE_DOCTOR_NO_FETCH:-0}" != "1" ]]; then
    remote="${CUR_UPSTREAM%%/*}"
    if ! git fetch --quiet "$remote" 2>/dev/null; then
      CUR_NOTE="fetch failed — comparing against last-known remote refs"
    fi
  fi
  counts="$(git rev-list --left-right --count "${CUR_UPSTREAM}...HEAD" 2>/dev/null || true)"
  if [[ -z "$counts" ]]; then
    CUR_NOTE="cannot compare against ${CUR_UPSTREAM} — currency unknown"
    return 0
  fi
  CUR_BEHIND="$(echo "$counts" | awk '{print $1}')"
  CUR_AHEAD="$(echo "$counts" | awk '{print $2}')"
}

# --- Spec 530: durable JSONL history + cached last-full state -------------------
# Every doctor run appends exactly ONE history record (silent or not). --summary
# reads HIGH/coverage from the LAST FULL RUN's cached state (staleness accepted —
# DA decision 2026-07-07 option (b): re-running the taxonomy/consistency pipeline
# on every session start would break the fast/no-fetch --summary contract).
# mode values: full | summary | summary-verbose. provenance: pinned | unpinned | "".
# Overridable for hermetic tests (Spec 535 — the 520 suite's read-only assert
# must not see history appends land in the live tracked file).
_dh_sessions="$(forge_path sessions 2>/dev/null || echo docs/sessions)"  # classic-default fallback
HISTORY_FILE="${FORGE_DOCTOR_HISTORY_FILE:-${ROOT}/${_dh_sessions}/doctor-history.jsonl}"
LAST_FULL_FILE="${STATE_DIR}/doctor-last-full.state"

read_cached_full() {
  CACHED_PCT=""; CACHED_DELTA=""; CACHED_HIGH=""; CACHED_MEDIUM=""; CACHED_PROV=""
  [[ -f "$LAST_FULL_FILE" ]] || return 0
  CACHED_PCT="$(sed -n 's/^pct=//p' "$LAST_FULL_FILE" | head -1)"
  CACHED_DELTA="$(sed -n 's/^delta=//p' "$LAST_FULL_FILE" | head -1)"
  CACHED_HIGH="$(sed -n 's/^high=//p' "$LAST_FULL_FILE" | head -1)"
  CACHED_MEDIUM="$(sed -n 's/^medium=//p' "$LAST_FULL_FILE" | head -1)"
  CACHED_PROV="$(sed -n 's/^provenance=//p' "$LAST_FULL_FILE" | head -1)"
}

# Single printf >> append — one short line per call is an atomic-enough write for
# concurrent worktree sessions until Spec 529's union-merge attributes land
# (interim risk documented in the spec; .gitattributes merge=union entry added now).
history_append() {
  local mode="$1" ahead="$2" behind="$3" pct="$4" delta="$5" high="$6" medium="$7" prov="$8" notes="$9"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$HISTORY_FILE")" 2>/dev/null || return 0
  printf '{"ts":"%s","mode":"%s","ahead":"%s","behind":"%s","coverage_pct":"%s","coverage_delta":"%s","high":"%s","medium":"%s","provenance":"%s","notes":"%s"}
'     "$ts" "$mode" "$ahead" "$behind" "$pct" "$delta" "$high" "$medium" "$prov" "$notes" >> "$HISTORY_FILE" 2>/dev/null || true
}

if [[ "$SUMMARY" == "true" ]]; then
  # One-line SessionStart surface (Spec 520 R5/AC6). No fetch — must be fast + offline-safe.
  # Spec 530: silent unless ACTIONABLE (behind>0, cached HIGH>0, cached coverage delta<0).
  # ahead-only is informational (the operator's own unpushed work) and stays silent.
  compute_currency false
  read_cached_full
  actionable=""
  if [[ -n "$CUR_BEHIND" && "${CUR_BEHIND:-0}" -gt 0 ]]; then
    actionable="behind upstream by ${CUR_BEHIND} commit(s) — fetch/pull before starting work"
  fi
  if [[ -n "$CACHED_HIGH" && "${CACHED_HIGH:-0}" -gt 0 ]] 2>/dev/null; then
    actionable="${actionable:+${actionable}; }${CACHED_HIGH} HIGH consistency finding(s) at last full run"
  fi
  case "${CACHED_DELTA:-}" in
    -0.0|"") : ;;
    -*) actionable="${actionable:+${actionable}; }coverage delta ${CACHED_DELTA} at last full run" ;;
  esac
  mode="summary"
  [[ "$VERBOSE" == "true" ]] && mode="summary-verbose"
  history_append "$mode" "${CUR_AHEAD:-}" "${CUR_BEHIND:-}" "${CACHED_PCT}" "${CACHED_DELTA}" "${CACHED_HIGH}" "${CACHED_MEDIUM}" "${CACHED_PROV}" "${CUR_NOTE:-}"
  if [[ "$VERBOSE" == "true" ]]; then
    if [[ -n "$CUR_AHEAD" ]]; then
      line="doctor currency: ahead ${CUR_AHEAD} / behind ${CUR_BEHIND} (vs ${CUR_UPSTREAM})"
      if [[ "$CUR_BEHIND" -gt 0 ]]; then
        line="${line} — WARN: behind upstream, fetch/pull before starting work"
      fi
      echo "$line"
    else
      echo "doctor currency: ${CUR_NOTE:-unknown}"
    fi
  elif [[ -n "$actionable" ]]; then
    echo "doctor: ${actionable} (run .forge/bin/forge-doctor.sh for detail)"
  fi
  exit 0
fi

echo "forge doctor — read-only distribution diagnostic (Spec 520, ADR-502 Phase 1)"
echo "root: ${ROOT}"
echo ""

# =============================== D-PROVENANCE ===================================
echo "== D-PROVENANCE =="
if [[ -f ".copier-answers.yml" ]]; then
  PIN_COMMIT="$(sed -n 's/^_commit:[[:space:]]*//p' .copier-answers.yml | head -1)"
  PIN_SRC="$(sed -n 's/^_src_path:[[:space:]]*//p' .copier-answers.yml | head -1)"
  echo "  pinned _commit: ${PIN_COMMIT:-(missing)}"
  echo "  template source: ${PIN_SRC:-(missing)}"
  PROV_STATUS="pinned"
  if [[ -z "$PIN_COMMIT" ]]; then
    PROV_STATUS="unpinned"
    echo "  WARN  .copier-answers.yml carries no _commit pin — provenance unverifiable"
  elif [[ -n "$PIN_SRC" && -d "$PIN_SRC" ]] && git -C "$PIN_SRC" rev-parse --git-dir >/dev/null 2>&1; then
    if git -C "$PIN_SRC" cat-file -e "${PIN_COMMIT}^{commit}" 2>/dev/null; then
      echo "  OK    pinned _commit is reachable in the local template source"
    else
      echo "  WARN  pinned _commit ${PIN_COMMIT} NOT reachable in ${PIN_SRC} — the pin names a ref the source does not have"
    fi
  else
    echo "  note  template source is remote or unavailable — reachability not verified (best-effort check)"
  fi
else
  echo "  not a copier consumer (no .copier-answers.yml) — provenance check not applicable"
fi
echo ""

# ================================ D-CURRENCY ====================================
echo "== D-CURRENCY =="
compute_currency true
echo "  branch: ${CUR_BRANCH}"
if [[ -n "$CUR_AHEAD" ]]; then
  echo "  upstream: ${CUR_UPSTREAM}"
  if [[ -n "$CUR_NOTE" ]]; then
    echo "  note  ${CUR_NOTE}"
  fi
  echo "  ahead: ${CUR_AHEAD} / behind: ${CUR_BEHIND}"
  if [[ "$CUR_BEHIND" -gt 0 ]]; then
    echo "  WARN  behind upstream by ${CUR_BEHIND} commit(s) — start from a current base (fetch/pull before work)"
    BEHIND_COUNT="$CUR_BEHIND"
  else
    echo "  OK    checkout is current with its upstream"
  fi
else
  echo "  note  ${CUR_NOTE:-currency unknown}"
fi
echo ""

# --- shared taxonomy classifier (small embedded helper; parses ONLY the taxonomy map —
#     the publish manifest is never parsed here; its set arrives via the shared flag) ---
# stdin-free contract: classify <taxonomy> <paths-file> -> "origin<TAB>confidentiality<TAB>path"
# origin is "rule" (explicit rule matched, first match wins) or "default" (fail-closed).
# CRLF guard: native Windows Python re-expands \n to \r\n on redirected stdout; strip it
# so downstream `read` never carries a trailing \r in the path field.
classify() {
  "$PY" - "$1" "$2" << 'PYCLS' | tr -d '\r'
import re, sys

tax_path, paths_file = sys.argv[1], sys.argv[2]
rules = []          # [(compiled_regex, confidentiality)]
default_conf = "private"   # fail-closed even if the default block is malformed
in_rules = False
cur_glob = None

def glob_to_re(g):
    r = re.escape(g)
    r = r.replace(r"\*\*", "*").replace(r"\*", "*")   # collapse escaped stars
    r = r.replace("*", ".*")
    return re.compile("^" + r + "$")

for raw in open(tax_path, encoding="utf-8"):
    line = raw.rstrip("\n")
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    if s == "rules:":
        in_rules = True
        continue
    m = re.match(r'^\s*-\s*path:\s*"?([^"]+?)"?\s*$', line)
    if in_rules and m:
        cur_glob = m.group(1)
        continue
    m = re.match(r"^\s*confidentiality:\s*(\S+)", line)
    if m:
        if in_rules and cur_glob is not None:
            rules.append((glob_to_re(cur_glob), m.group(1)))
            cur_glob = None
        elif not in_rules:
            default_conf = m.group(1)

with open(paths_file, encoding="utf-8") as fh:
    for raw in fh:
        p = raw.strip().replace("\\", "/")
        if not p:
            continue
        for rx, conf in rules:
            if rx.match(p):
                print("rule\t%s\t%s" % (conf, p))
                break
        else:
            print("default\t%s\t%s" % (default_conf, p))
PYCLS
}

# ============================ D-TAXONOMY-COVERAGE ===============================
echo "== D-TAXONOMY-COVERAGE =="
if [[ ! -f "$TAXONOMY" ]]; then
  echo "  note  taxonomy map not present — coverage skipped (expected on consumer checkouts; the map is a private dev-repo artifact)"
elif [[ -z "$PY" ]]; then
  echo "  note  python3 not available — coverage skipped (advisory)"
elif ! git ls-files > "${TMPD}/tracked.txt" 2>/dev/null; then
  echo "  note  not a git repository — coverage skipped (advisory)"
else
  RULE_COUNT="$(grep -c '^[[:space:]]*- path:' "$TAXONOMY" 2>/dev/null || echo 0)"
  echo "  taxonomy: ${TAXONOMY} (${RULE_COUNT} rules)"
  if classify "$TAXONOMY" "${TMPD}/tracked.txt" > "${TMPD}/classified.txt" 2>"${TMPD}/classify.err"; then
    TOTAL="$(wc -l < "${TMPD}/tracked.txt" | tr -d ' ')"
    MATCHED="$(grep -c '^rule' "${TMPD}/classified.txt" || true)"
    UNCLASSIFIED=$((TOTAL - MATCHED))
    PCT="$(awk -v m="$MATCHED" -v t="$TOTAL" 'BEGIN { if (t == 0) print "0.0"; else printf "%.1f", (m * 100.0) / t }')"
    echo "  tracked paths: ${TOTAL}; rule-classified: ${MATCHED} (${PCT}%)"
    if [[ "$UNCLASSIFIED" -gt 0 ]]; then
      echo "  unclassified (fail-closed default: private): ${UNCLASSIFIED} — sample:"
      grep '^default' "${TMPD}/classified.txt" | cut -f3 | head -10 | sed 's/^/    - /'
    else
      echo "  unclassified: 0 — every tracked path has an explicit rule"
    fi
    # coverage delta vs previous run (state under .forge/state/, gitignored — Spec 520/COO)
    STATE_FILE="${STATE_DIR}/doctor-coverage.prev"
    if [[ -f "$STATE_FILE" ]]; then
      PREV_PCT="$(head -1 "$STATE_FILE" | tr -d ' \r')"
      DELTA="$(awk -v a="$PCT" -v b="${PREV_PCT:-0}" 'BEGIN { printf "%+.1f", a - b }')"
      echo "  coverage delta vs previous run: ${DELTA} (prev ${PREV_PCT}%) — negative deltas are reviewed at /evolve cadence (SIG candidate)"
    else
      echo "  coverage delta vs previous run: n/a (no previous run recorded — baseline written)"
    fi
    if mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s\n' "$PCT" > "$STATE_FILE" 2>/dev/null; then
      : # state persisted
    else
      echo "  note  could not persist coverage state under ${STATE_DIR} (advisory — delta unavailable next run)"
    fi
  else
    echo "  note  taxonomy classification failed — coverage skipped (advisory): $(head -1 "${TMPD}/classify.err" 2>/dev/null)"
  fi
fi
echo ""

# ======================= D-CONFIDENTIALITY-CONSISTENCY ==========================
echo "== D-CONFIDENTIALITY-CONSISTENCY =="
if [[ ! -f "$SYNC_SCRIPT" ]]; then
  echo "  note  scripts/sync-to-public.sh not present — consistency skipped (expected on consumer checkouts; publishing happens only in the dev repo)"
elif [[ ! -f "$TAXONOMY" ]]; then
  echo "  note  taxonomy map not present — consistency skipped (advisory)"
elif [[ -z "$PY" ]]; then
  echo "  note  python3 not available — consistency skipped (advisory)"
elif ! bash "$SYNC_SCRIPT" --print-public-set > "${TMPD}/pubset.txt" 2>"${TMPD}/pubset.err"; then
  echo "  note  sync-to-public.sh --print-public-set failed — consistency skipped (advisory): $(head -1 "${TMPD}/pubset.err" 2>/dev/null)"
else
  PUB_TOTAL="$(wc -l < "${TMPD}/pubset.txt" | tr -d ' ')"
  echo "  publish-reachable set: ${PUB_TOTAL} path(s) (single source: sync-to-public.sh --print-public-set)"
  if classify "$TAXONOMY" "${TMPD}/pubset.txt" > "${TMPD}/pubclass.txt" 2>/dev/null; then
    # explicit private/customer rule match inside the publish-reachable set -> HIGH
    while IFS=$'\t' read -r origin conf path; do
      if [[ "$origin" == "rule" && ( "$conf" == "private" || "$conf" == "customer" ) ]]; then
        echo "  HIGH  ${path} — classified ${conf} but publish-reachable"
        HIGH_COUNT=$((HIGH_COUNT + 1))
      fi
    done < "${TMPD}/pubclass.txt"
    # fail-closed default (no explicit rule) inside the publish set -> surfaced, lower grade
    DEF_COUNT="$(grep -c '^default' "${TMPD}/pubclass.txt" || true)"
    if [[ "$DEF_COUNT" -gt 0 ]]; then
      MEDIUM_COUNT=$((MEDIUM_COUNT + DEF_COUNT))
      echo "  MEDIUM  ${DEF_COUNT} publish-reachable path(s) have no explicit taxonomy rule (fail-closed default: private) — sample:"
      grep '^default' "${TMPD}/pubclass.txt" | cut -f3 | head -5 | sed 's/^/    - /'
    fi
    if [[ "$HIGH_COUNT" -eq 0 ]]; then
      echo "  OK    no private/customer-classified path is publish-reachable (HIGH findings: 0)"
    else
      echo "  HIGH findings: ${HIGH_COUNT} — a private/customer path would ship; fix the manifest disposition or the classification"
    fi
  else
    echo "  note  taxonomy classification failed — consistency skipped (advisory)"
  fi
fi
echo ""

# ============================== D-PUBLIC-CHECKOUT ===============================
echo "== D-PUBLIC-CHECKOUT =="
PUB_DIR="${ROOT}/../forge-public"
if [[ -d "$PUB_DIR" ]] && git -C "$PUB_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  PUB_BRANCH="$(git -C "$PUB_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(unknown)")"
  echo "  sibling checkout: ${PUB_DIR}"
  echo "  branch: ${PUB_BRANCH}"
  if [[ "$PUB_BRANCH" != "main" ]]; then
    echo "  WARN  public checkout is not on main (detached or feature branch) — sync targets main"
  fi
  PUB_COUNTS="$(git -C "$PUB_DIR" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || true)"
  if [[ -n "$PUB_COUNTS" ]]; then
    PUB_BEHIND="$(echo "$PUB_COUNTS" | awk '{print $1}')"
    PUB_AHEAD="$(echo "$PUB_COUNTS" | awk '{print $2}')"
    echo "  ahead: ${PUB_AHEAD} / behind: ${PUB_BEHIND} (vs its upstream, last-known refs)"
  else
    echo "  note  no upstream comparison available (best-effort check)"
  fi
else
  echo "  note  no sibling forge-public checkout — skipped (optional, best-effort check)"
fi
echo ""

# ============================ D-INSTALLED-VERSION ================================
# Spec 539 AC4 — a `claude plugin install` cache can retain a stale recorded version
# (SIG-520-01 sibling: consumer healthcheck found the installed cache at 0.1.0 while
# plugin.json declared 3.0.0). This is READ-ONLY: it inspects the user-level Claude
# Code plugin registry (known_marketplaces.json + installed_plugins.json) for a
# directory-source marketplace whose path resolves to THIS checkout, and compares its
# recorded installed version to the declared .claude-plugin/plugin.json version. It
# never runs `claude plugin install` itself — reinstall is an operator action.
echo "== D-INSTALLED-VERSION =="
DECLARED_PJ="${ROOT}/.claude-plugin/plugin.json"
MARKETPLACES_FILE="${FORGE_DOCTOR_MARKETPLACES_FILE:-${HOME:-}/.claude/plugins/known_marketplaces.json}"
INSTALLED_FILE="${FORGE_DOCTOR_INSTALLED_PLUGINS_FILE:-${HOME:-}/.claude/plugins/installed_plugins.json}"
if [[ ! -f "$DECLARED_PJ" ]]; then
  echo "  note  no .claude-plugin/plugin.json at repo root — installed-version check not applicable (not a plugin source repo)"
elif [[ -z "$PY" ]]; then
  echo "  note  python3 not available — installed-version check skipped (advisory)"
elif [[ ! -f "$MARKETPLACES_FILE" || ! -f "$INSTALLED_FILE" ]]; then
  DECLARED_V="$("$PY" -c "import json,sys;print(json.load(open(sys.argv[1])).get('version',''))" "$DECLARED_PJ" 2>/dev/null)"
  echo "  note  no local Claude Code plugin registry found (${MARKETPLACES_FILE} / ${INSTALLED_FILE}) — cannot verify an installed cache from this checkout"
  echo "  manual verification: after 'claude plugin install ./ --force' (or reinstall), confirm the entry's"
  echo "    recorded version in installed_plugins.json equals plugin.json's declared version (${DECLARED_V:-unknown})"
else
  MATCH_LINES="$("$PY" - "$MARKETPLACES_FILE" "$INSTALLED_FILE" "$ROOT" "$DECLARED_PJ" << 'PYVER'
import json, os, sys
mk_path, inst_path, root, pj_path = sys.argv[1:5]
root_n = os.path.normcase(os.path.normpath(root))
try:
    declared = json.load(open(pj_path, encoding="utf-8")).get("version", "")
    marketplaces = json.load(open(mk_path, encoding="utf-8"))
    installed = json.load(open(inst_path, encoding="utf-8")).get("plugins", {})
except Exception as e:
    print("ERROR " + str(e).replace("\n", " "))
    sys.exit(0)
matches = []
for name, entry in marketplaces.items():
    src = entry.get("source", {}) if isinstance(entry, dict) else {}
    if src.get("source") != "directory":
        continue
    if os.path.normcase(os.path.normpath(src.get("path", ""))) != root_n:
        continue
    for inst in installed.get("forge@" + name, []):
        matches.append((name, inst.get("version", "")))
if not matches:
    print("NOMATCH " + declared)
else:
    for name, v in matches:
        status = "OK" if v == declared else "STALE"
        print("%s %s %s %s" % (status, name, v, declared))
PYVER
)"
  if [[ "$MATCH_LINES" == ERROR* ]]; then
    echo "  note  could not parse plugin registry files — installed-version check skipped (advisory): ${MATCH_LINES#ERROR }"
  elif [[ "$MATCH_LINES" == NOMATCH* ]]; then
    DECLARED_V="${MATCH_LINES#NOMATCH }"
    echo "  note  no locally-scoped plugin install registered for this checkout (${ROOT})"
    echo "  manual verification: after 'claude plugin install ./ --force' (or reinstall), confirm the entry's"
    echo "    recorded version in installed_plugins.json equals plugin.json's declared version (${DECLARED_V:-unknown})"
  else
    while read -r status name v declared; do
      [[ -z "$status" ]] && continue
      if [[ "$status" == "OK" ]]; then
        echo "  OK    installed plugin 'forge@${name}' cache version (${v}) matches declared plugin.json (${declared})"
      else
        echo "  WARN  installed plugin 'forge@${name}' cache version (${v}) is STALE vs declared plugin.json (${declared}) — reinstall: claude plugin uninstall forge@${name} && claude plugin install ./ (or remove the stale cache dir under ~/.claude/plugins/cache/${name}/forge/ and reinstall)"
        INSTALLED_STALE_COUNT=$((INSTALLED_STALE_COUNT + 1))
      fi
    done <<< "$MATCH_LINES"
  fi
fi
echo ""

# ================================ D-PATHS (Spec 575) ============================
# Process-state path health: each forge.paths key (configured or defaulted) must
# exist and be writable, and no key may be in SPLIT-BRAIN state — process files
# present in BOTH the classic default location and a configured non-default
# location (the designed interim state between a /configure preset switch and the
# Spec 577 migration; detection is what makes it visible — Spec 565 carry-forward).
echo "== D-PATHS =="
_dp_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
declare -A _DP_CLASSIC=([specs]="docs/specs" [sessions]="docs/sessions" [decisions]="docs/decisions" [research]="docs/research" [process_kit]="docs/process-kit" [backlog]="docs/backlog.md")
if [[ -f "AGENTS.md" ]] && [[ -f "${_dp_lib}/config.sh" ]]; then
  # shellcheck source=/dev/null
  source "${_dp_lib}/config.sh"
  forge_config_load "AGENTS.md" >/dev/null 2>&1 || true
  _dp_fail=0
  for _k in specs sessions decisions research process_kit backlog; do
    _resolved="$(forge_path "$_k" 2>/dev/null)" || { echo "  HIGH  forge.paths.${_k}: invalid value (validator rejected)"; _dp_fail=1; continue; }
    _classic="${_DP_CLASSIC[$_k]}"
    if [[ "$_k" == "backlog" ]]; then
      _res_exists=0; [[ -f "$_resolved" ]] && _res_exists=1
      _cls_exists=0; [[ -f "$_classic" ]] && _cls_exists=1
    else
      _res_exists=0; [[ -d "$_resolved" ]] && _res_exists=1
      _cls_exists=0; [[ -d "$_classic" && -n "$(ls -A "$_classic" 2>/dev/null)" ]] && _cls_exists=1
    fi
    if [[ "$_res_exists" -eq 0 ]]; then
      if [[ "$_resolved" != "$_classic" && "$_cls_exists" -eq 1 ]]; then
        echo "  WARN  forge.paths.${_k}: configured '${_resolved}' absent while classic '${_classic}' holds data — pre-migration state; run the Spec 577 migration flow"
      fi
      # absent in BOTH locations: silent — optional dirs materialize on first use
    elif [[ "$_k" != "backlog" && ! -w "$_resolved" ]]; then
      echo "  HIGH  forge.paths.${_k}: '${_resolved}' not writable"; _dp_fail=1
    fi
    if [[ "$_resolved" != "$_classic" && "$_cls_exists" -eq 1 && "$_res_exists" -eq 1 ]]; then
      echo "  HIGH  forge.paths.${_k}: SPLIT-BRAIN — files present in BOTH '${_classic}' (classic) and configured '${_resolved}'. Run the Spec 577 migration flow (or consolidate manually) so one location owns the data."
      _dp_fail=1
      HIGH_COUNT=$(( ${HIGH_COUNT:-0} + 1 ))
    fi
  done
  [[ "$_dp_fail" -eq 0 ]] && echo "  OK    all process-state paths resolve, exist-or-flagged, writable; no split-brain"
else
  echo "  SKIP  no AGENTS.md/config.sh at cwd — path check applies to FORGE project roots"
fi
echo ""

# =============================== fixed footer ===================================
echo "advisory detector — enforcement is public-manifest.yaml + validate-public-docs.sh/check-outgoing-identity.sh gates"

# --- Spec 530: persist last-full state (read by --summary) + history record ------
if mkdir -p "$STATE_DIR" 2>/dev/null; then
  {
    echo "pct=${PCT:-}"
    echo "delta=${DELTA:-}"
    echo "high=${HIGH_COUNT:-0}"
    echo "medium=${MEDIUM_COUNT:-0}"
    echo "provenance=${PROV_STATUS:-}"
  } > "$LAST_FULL_FILE" 2>/dev/null || true
fi
history_append "full" "${CUR_AHEAD:-}" "${CUR_BEHIND:-}" "${PCT:-}" "${DELTA:-}" "${HIGH_COUNT:-0}" "${MEDIUM_COUNT:-0}" "${PROV_STATUS:-}" ""

if [[ "$STRICT" == "true" ]]; then
  if [[ "$HIGH_COUNT" -gt 0 || "${BEHIND_COUNT:-0}" -gt 0 ]]; then
    exit 1
  fi
fi
exit 0
