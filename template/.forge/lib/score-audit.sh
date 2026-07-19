#!/usr/bin/env bash
# FORGE score-audit helper — predicted/observed score calibration log (Spec 368).
# Time-blindness mitigation: timestamps and durations from shell, not from model.
#
# Usage:
#   score-audit.sh record-predicted <spec_id> <bv> <e> <r> <sr> <tc> <lane> <kind_tag> <revise_round> [predicted_by]
#   score-audit.sh record-observed <spec_id>
#   score-audit.sh read-records [spec_id]
#   score-audit.sh bias-report [lean|verbose]
#   score-audit.sh record-dispatch <spec_id> <stage> <role> <recommendation> [confidence] [key_concern]   (Spec 305)
#   score-audit.sh record-acceptance <spec_id> <role> <accepted:true|false|null> [partial_note]            (Spec 305)
#   score-audit.sh role-audit [--json]                                                                      (Spec 305)
#
# Spec 305 adds two additive record kinds to this shared sink: "role-dispatch" and
# "role-acceptance" (per Spec 368 Req 20 — adjacent instrumentation streams share storage,
# extend additively). They reuse the same _atomic_append / _json_escape primitives and the
# same SCORE_AUDIT_FILE. role-audit reads + filters those two kinds for a per-role rollup.
#
# Audit log path is $SCORE_AUDIT_FILE (default: .forge/state/score-audit.jsonl).
# Atomic-append bound: 4000 bytes (POSIX PIPE_BUF=4096 safety margin).
# This helper is advisory; failures emit WARN to stderr but always exit 0.

SCORE_AUDIT_FILE="${SCORE_AUDIT_FILE:-.forge/state/score-audit.jsonl}"
ATOMIC_BOUND_BYTES=4000

# Resolve a forge.paths.<key> value via config.sh's forge_path (Spec 564), falling back
# to the classic default when bash lacks associative-array support or config load fails.
# Runs relative to cwd (this helper has no repo-root parameter of its own).
_score_audit_paths_key() {
  local key="$1" default="$2"
  if declare -A __score_audit_probe 2>/dev/null; then
    unset __score_audit_probe
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=/dev/null
    if source "${lib_dir}/config.sh" 2>/dev/null; then
      PROJECT_DIR="." forge_config_load "./AGENTS.md" >/dev/null 2>&1 || true
      local resolved
      if resolved="$(PROJECT_DIR="." forge_path "$key" 2>/dev/null)"; then
        printf '%s\n' "$resolved"
        return
      fi
    fi
  fi
  printf '%s\n' "$default"
}

_iso_ts_utc() { date -u +%FT%TZ; }

_git_sha_or_unknown() {
  git rev-parse HEAD 2>/dev/null || printf 'unknown'
}

_ensure_log_dir() {
  local dir
  dir="$(dirname "$SCORE_AUDIT_FILE")"
  if ! mkdir -p "$dir" 2>/dev/null; then
    return 1
  fi
  if [ ! -f "$SCORE_AUDIT_FILE" ]; then
    if ! ( : > "$SCORE_AUDIT_FILE" ) 2>/dev/null; then
      return 1
    fi
    chmod 0644 "$SCORE_AUDIT_FILE" 2>/dev/null || true
  fi
  if [ ! -w "$SCORE_AUDIT_FILE" ]; then
    return 1
  fi
  return 0
}

_atomic_append() {
  local record="$1"
  local len=${#record}
  if [ "$len" -ge "$ATOMIC_BOUND_BYTES" ]; then
    printf 'WARN: record exceeds atomic-append bound; truncating discretionary fields\n' >&2
    record=$(printf '%s' "$record" | sed -E 's/"kind_tag":"[^"]*"/"kind_tag":""/')
  fi
  if ! printf '%s\n' "$record" >> "$SCORE_AUDIT_FILE" 2>/dev/null; then
    printf 'WARN: score-audit append failed (advisory; close continues)\n' >&2
    return 0
  fi
  return 0
}

_json_escape() {
  local s="${1-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

cmd_record_predicted() {
  if [ "$#" -lt 9 ]; then
    printf 'WARN: record-predicted needs 9+ args (spec bv e r sr tc lane kind_tag revise_round); got %d\n' "$#" >&2
    return 0
  fi
  if ! _ensure_log_dir; then
    printf 'WARN: score-audit append failed (advisory; close continues)\n' >&2
    return 0
  fi
  local spec_id="$1" bv="$2" e="$3" r="$4" sr="$5" tc="$6" lane="$7" kind_tag="$8" revise_round="$9"
  local predicted_by="${10:-operator}"
  local iso_ts git_sha rec
  iso_ts="$(_iso_ts_utc)"
  git_sha="$(_git_sha_or_unknown)"
  rec=$(printf '{"schema_version":1,"kind":"predicted","spec_id":"%s","git_sha":"%s","iso_ts":"%s","bv":%s,"e":%s,"r":%s,"sr":%s,"tc":"%s","lane":"%s","kind_tag":"%s","revise_round":%s,"predicted_by":"%s"}' \
    "$(_json_escape "$spec_id")" "$(_json_escape "$git_sha")" "$(_json_escape "$iso_ts")" \
    "$bv" "$e" "$r" "$sr" \
    "$(_json_escape "$tc")" "$(_json_escape "$lane")" "$(_json_escape "$kind_tag")" \
    "$revise_round" "$(_json_escape "$predicted_by")")
  _atomic_append "$rec"
}

cmd_record_observed() {
  if [ "$#" -lt 1 ]; then
    printf 'WARN: record-observed needs <spec_id>\n' >&2
    return 0
  fi
  if ! _ensure_log_dir; then
    printf 'WARN: score-audit append failed (advisory; close continues)\n' >&2
    return 0
  fi
  local spec_id="$1" spec_file=""
  local specs_dir
  specs_dir="$(_score_audit_paths_key specs docs/specs)"
  for f in "${specs_dir}"/${spec_id}-*.md; do
    [ -f "$f" ] && spec_file="$f" && break
  done

  local creation_iso_ts="" creation_ts_source="git-log" creation_epoch=0
  if [ -n "$spec_file" ]; then
    creation_iso_ts=$(git log --diff-filter=A --format=%cI -- "$spec_file" 2>/dev/null | tail -1)
    if [ -n "$creation_iso_ts" ]; then
      creation_ts_source="git-log"
    else
      creation_iso_ts=$(grep -m1 -E '^- Last updated:' "$spec_file" 2>/dev/null | sed -E 's/^- Last updated:[[:space:]]+//; s/[[:space:]]*$//')
      if [ -z "$creation_iso_ts" ]; then
        creation_iso_ts="$(_iso_ts_utc)"
      else
        case "$creation_iso_ts" in
          *T*) ;;
          *) creation_iso_ts="${creation_iso_ts}T00:00:00Z" ;;
        esac
      fi
      creation_ts_source="frontmatter"
    fi
  else
    creation_iso_ts="$(_iso_ts_utc)"
    creation_ts_source="frontmatter"
  fi
  creation_epoch=$(date -d "$creation_iso_ts" +%s 2>/dev/null || printf 0)

  local close_iso_ts close_epoch wallclock_days
  close_iso_ts="$(_iso_ts_utc)"
  close_epoch=$(date -u +%s)
  if [ "$creation_epoch" -gt 0 ] && [ "$close_epoch" -ge "$creation_epoch" ]; then
    wallclock_days=$(awk -v c="$close_epoch" -v s="$creation_epoch" 'BEGIN{ printf "%.2f", (c-s)/86400 }')
  else
    wallclock_days="0.00"
  fi

  local sessions_dir
  sessions_dir="$(_score_audit_paths_key sessions docs/sessions)"
  local session_count=0
  if compgen -G "${sessions_dir}/*.json" > /dev/null 2>&1; then
    session_count=$(grep -l "\"$spec_id\"" "${sessions_dir}"/*.json 2>/dev/null | wc -l | tr -d ' ')
  fi
  [ -z "$session_count" ] && session_count=0

  local revise_rounds=0
  if [ -n "$spec_file" ]; then
    revise_rounds=$(awk '/^## Revision Log/{flag=1;next} /^## /{flag=0} flag && /\/revise/{c++} END{print c+0}' "$spec_file")
  fi

  local validator_outcome="SKIP" da_outcome="SKIP"
  if [ -n "$spec_file" ]; then
    if grep -qE 'GATE \[validator(-coverage)?\]: PASS' "$spec_file"; then validator_outcome="PASS"
    elif grep -qE 'GATE \[validator(-coverage)?\]: PARTIAL' "$spec_file"; then validator_outcome="PARTIAL"
    elif grep -qE 'GATE \[validator(-coverage)?\]: FAIL' "$spec_file"; then validator_outcome="FAIL"
    fi
    if grep -qE 'DA-Decision:[[:space:]]+PASS' "$spec_file"; then da_outcome="PASS"
    elif grep -qE 'DA-Decision:[[:space:]]+CONDITIONAL_PASS' "$spec_file"; then da_outcome="CONDITIONAL_PASS"
    elif grep -qE 'DA-Decision:[[:space:]]+FAIL' "$spec_file"; then da_outcome="FAIL"
    fi
  fi

  local last_predicted_kind_tag="" last_predicted_tc=""
  if [ -f "$SCORE_AUDIT_FILE" ]; then
    last_predicted_kind_tag=$(grep "\"spec_id\":\"$spec_id\"" "$SCORE_AUDIT_FILE" 2>/dev/null | grep '"kind":"predicted"' | tail -1 | sed -nE 's/.*"kind_tag":"([^"]*)".*/\1/p')
    last_predicted_tc=$(grep "\"spec_id\":\"$spec_id\"" "$SCORE_AUDIT_FILE" 2>/dev/null | grep '"kind":"predicted"' | tail -1 | sed -nE 's/.*"tc":"([^"]*)".*/\1/p')
  fi
  [ -z "$last_predicted_kind_tag" ] && last_predicted_kind_tag="other"
  [ -z "$last_predicted_tc" ] && last_predicted_tc='$$'

  local tc_overrun_derived="false"
  case "$last_predicted_tc" in
    '$')
      if awk -v w="$wallclock_days" 'BEGIN{exit !(w >= 1)}' || [ "$session_count" -gt 1 ]; then
        tc_overrun_derived="true"
      fi
      ;;
    '$$')
      if awk -v w="$wallclock_days" 'BEGIN{exit !(w > 5)}' && [ "$session_count" -gt 4 ]; then
        tc_overrun_derived="true"
      fi
      ;;
  esac

  local git_sha rec
  git_sha="$(_git_sha_or_unknown)"
  rec=$(printf '{"schema_version":1,"kind":"observed","spec_id":"%s","git_sha":"%s","iso_ts":"%s","creation_iso_ts":"%s","close_iso_ts":"%s","wallclock_days":%s,"session_count":%s,"revise_rounds":%s,"validator_outcome":"%s","da_outcome":"%s","tc_overrun_derived":%s,"kind_tag":"%s","creation_ts_source":"%s"}' \
    "$(_json_escape "$spec_id")" "$(_json_escape "$git_sha")" "$(_json_escape "$close_iso_ts")" \
    "$(_json_escape "$creation_iso_ts")" "$(_json_escape "$close_iso_ts")" \
    "$wallclock_days" "$session_count" "$revise_rounds" \
    "$validator_outcome" "$da_outcome" "$tc_overrun_derived" \
    "$(_json_escape "$last_predicted_kind_tag")" "$creation_ts_source")
  _atomic_append "$rec"
}

cmd_next_revise_round() {
  if [ "$#" -lt 1 ]; then
    printf '0\n'
    return 0
  fi
  local spec_id="$1"
  if [ ! -f "$SCORE_AUDIT_FILE" ]; then
    printf '1\n'
    return 0
  fi
  local prev
  # Spec 305 DA Pass-2 finding 2: require "kind":"predicted" before extracting revise_round,
  # so role-dispatch/role-acceptance records (which share spec_id but carry no revise_round —
  # and whose escaped key_concern could otherwise false-match the regex) are excluded.
  prev=$(grep "\"spec_id\":\"$spec_id\"" "$SCORE_AUDIT_FILE" 2>/dev/null \
    | grep '"kind":"predicted"' \
    | sed -nE 's/.*"revise_round":([0-9]+).*/\1/p' \
    | sort -n | tail -1)
  if [ -z "$prev" ]; then
    printf '1\n'
  else
    printf '%s\n' $((prev + 1))
  fi
}

cmd_read_records() {
  if [ ! -f "$SCORE_AUDIT_FILE" ]; then return 0; fi
  if [ "$#" -ge 1 ] && [ -n "$1" ]; then
    grep "\"spec_id\":\"$1\"" "$SCORE_AUDIT_FILE" 2>/dev/null || true
  else
    cat "$SCORE_AUDIT_FILE"
  fi
}

cmd_bias_report() {
  local mode="${1:-lean}"
  if [ ! -f "$SCORE_AUDIT_FILE" ]; then
    printf '0 records — calibration deferred until data accumulates\n'
    return 0
  fi
  python3 - "$SCORE_AUDIT_FILE" "$mode" << 'PY'
import json, sys, collections
path, mode = sys.argv[1], sys.argv[2]
predicted = {}
observed = []
try:
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get('kind') == 'predicted':
                predicted[r['spec_id']] = r
            elif r.get('kind') == 'observed':
                observed.append(r)
except OSError:
    print('0 records — calibration deferred until data accumulates')
    sys.exit(0)

cells = collections.defaultdict(lambda: collections.defaultdict(list))
for o in observed:
    p = predicted.get(o['spec_id'])
    if not p:
        continue
    lane = p.get('lane', 'unknown')
    kind_tag = o.get('kind_tag') or p.get('kind_tag', 'other')
    pe = int(p.get('e', 3))
    wd = float(o.get('wallclock_days', 0) or 0)
    sc = int(o.get('session_count', 0) or 0)
    if pe >= 4 and wd < 1 and sc <= 1:
        cells[(lane, kind_tag)]['E'].append('over')
    if pe <= 2 and (wd > 3 or sc > 3):
        cells[(lane, kind_tag)]['E'].append('under')
    psr = int(p.get('sr', 3))
    rr = int(o.get('revise_rounds', 0) or 0)
    vo = o.get('validator_outcome', 'SKIP')
    if psr >= 4 and (rr >= 2 or vo in ('FAIL', 'PARTIAL')):
        cells[(lane, kind_tag)]['SR'].append('over')

emitted = False
for (lane, kt), dims in cells.items():
    for dim, dirs in dims.items():
        over = dirs.count('over')
        under = dirs.count('under')
        majority = max(over, under)
        if majority < 3:
            if mode == 'verbose':
                print(f"insufficient data (N={len(dirs)}) — {dim} trend in lane={lane} kind_tag={kt}")
            continue
        if over > under:
            direction = 'over'
        elif under > over:
            direction = 'under'
        else:
            continue
        emitted = True
        print(f"{dim} {direction}-prediction in lane={lane} kind_tag={kt} (based on N={majority} closed specs since first record) (direction-only; magnitude not measured)")

if not emitted and mode == 'verbose' and not cells:
    print("0 records — calibration deferred until data accumulates")
PY
}

# --- Spec 305: role-dispatch instrumentation (additive record kind) ---
cmd_record_dispatch() {
  if [ "$#" -lt 4 ]; then
    printf 'WARN: record-dispatch needs 4+ args (spec_id stage role recommendation [confidence] [key_concern]); got %d\n' "$#" >&2
    return 0
  fi
  if ! _ensure_log_dir; then
    printf 'WARN: score-audit append failed (advisory; continues)\n' >&2
    return 0
  fi
  local spec_id="$1" stage="$2" role="$3" recommendation="$4"
  local confidence="${5:-}" key_concern="${6:-}"
  local iso_ts git_sha rec
  iso_ts="$(_iso_ts_utc)"
  git_sha="$(_git_sha_or_unknown)"
  rec=$(printf '{"schema_version":1,"kind":"role-dispatch","spec_id":"%s","git_sha":"%s","iso_ts":"%s","stage":"%s","role":"%s","recommendation":"%s","confidence":"%s","key_concern":"%s"}' \
    "$(_json_escape "$spec_id")" "$(_json_escape "$git_sha")" "$(_json_escape "$iso_ts")" \
    "$(_json_escape "$stage")" "$(_json_escape "$role")" "$(_json_escape "$recommendation")" \
    "$(_json_escape "$confidence")" "$(_json_escape "$key_concern")")
  _atomic_append "$rec"
}

# --- Spec 305: operator-acceptance capture (additive record kind; single-shot, latest-wins per R7) ---
cmd_record_acceptance() {
  if [ "$#" -lt 3 ]; then
    printf 'WARN: record-acceptance needs 3+ args (spec_id role accepted:true|false|null [partial_note]); got %d\n' "$#" >&2
    return 0
  fi
  if ! _ensure_log_dir; then
    printf 'WARN: score-audit append failed (advisory; continues)\n' >&2
    return 0
  fi
  local spec_id="$1" role="$2" accepted_raw="$3" partial_note="${4:-}"
  local accepted note_json
  case "$accepted_raw" in
    true|false|null) accepted="$accepted_raw" ;;
    *) accepted="null" ;;
  esac
  if [ -z "$partial_note" ]; then
    note_json="null"
  else
    note_json="\"$(_json_escape "$partial_note")\""
  fi
  local iso_ts git_sha rec
  iso_ts="$(_iso_ts_utc)"
  git_sha="$(_git_sha_or_unknown)"
  rec=$(printf '{"schema_version":1,"kind":"role-acceptance","spec_id":"%s","git_sha":"%s","iso_ts":"%s","role":"%s","accepted":%s,"partial_note":%s}' \
    "$(_json_escape "$spec_id")" "$(_json_escape "$git_sha")" "$(_json_escape "$iso_ts")" \
    "$(_json_escape "$role")" "$accepted" "$note_json")
  _atomic_append "$rec"
}

# --- Spec 305: per-role rollup over role-dispatch/role-acceptance records (read-only; python3, matching bias-report) ---
cmd_role_audit() {
  local fmt="table"
  if [ "${1:-}" = "--json" ]; then fmt="json"; fi
  if [ ! -f "$SCORE_AUDIT_FILE" ]; then
    if [ "$fmt" = "json" ]; then printf '{"roles":[]}\n'; else printf 'No role-dispatch records yet (%s absent).\n' "$SCORE_AUDIT_FILE"; fi
    return 0
  fi
  python3 - "$SCORE_AUDIT_FILE" "$fmt" << 'PY'
import json, sys, collections
path, fmt = sys.argv[1], sys.argv[2]
dispatch = collections.defaultdict(list)
accept = collections.defaultdict(list)
try:
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            k = r.get('kind')
            if k == 'role-dispatch':
                dispatch[r.get('role', '?')].append(r)
            elif k == 'role-acceptance':
                accept[r.get('role', '?')].append(r)
except OSError:
    print('{"roles":[]}' if fmt == 'json' else 'No role-dispatch records.')
    sys.exit(0)

roles = sorted(set(dispatch) | set(accept))
stats = []
for role in roles:
    ds = dispatch[role]
    n = len(ds)
    acc = [a for a in accept[role] if a.get('accepted') is not None]
    acc_true = sum(1 for a in acc if a.get('accepted') is True)
    acc_pct = (100.0 * acc_true / len(acc)) if acc else None
    concerns = [d.get('key_concern', '') for d in ds if d.get('key_concern', '')]
    avg_concern = (len(concerns) / n) if n else 0.0
    stagedist = collections.Counter(d.get('stage', '?') for d in ds)
    common = collections.Counter(concerns).most_common(1)
    stats.append({
        'role': role, 'dispatches': n,
        'acceptance_pct': acc_pct,
        'avg_concerns': round(avg_concern, 2),
        'stage_distribution': dict(stagedist),
        'most_common_concern': common[0][0] if common else '',
    })

if fmt == 'json':
    print(json.dumps({'roles': stats}, indent=2))
else:
    print('| Role | Dispatches | Acceptance% | Avg Concerns | Stage Distribution | Most Common Concern |')
    print('|------|-----------|-------------|--------------|--------------------|---------------------|')
    if not stats:
        print('| (none) | 0 | — | 0 | — | — |')
    for s in stats:
        ap = '—' if s['acceptance_pct'] is None else f"{s['acceptance_pct']:.0f}%"
        sd = ' '.join(f"{k}:{v}" for k, v in sorted(s['stage_distribution'].items())) or '—'
        mc = s['most_common_concern']
        mc = (mc[:40] + '…') if len(mc) > 40 else (mc or '—')
        print(f"| {s['role']} | {s['dispatches']} | {ap} | {s['avg_concerns']} | {sd} | {mc} |")
PY
}

main() {
  if [ "$#" -lt 1 ]; then
    echo "Usage: score-audit.sh {record-predicted|record-observed|read-records|bias-report|record-dispatch|record-acceptance|role-audit} [args...]" >&2
    return 2
  fi
  local sub="$1"; shift
  case "$sub" in
    record-predicted)   cmd_record_predicted "$@" ;;
    record-observed)    cmd_record_observed "$@" ;;
    read-records)       cmd_read_records "$@" ;;
    next-revise-round)  cmd_next_revise_round "$@" ;;
    bias-report)        cmd_bias_report "$@" ;;
    record-dispatch)    cmd_record_dispatch "$@" ;;
    record-acceptance)  cmd_record_acceptance "$@" ;;
    role-audit)         cmd_role_audit "$@" ;;
    *) echo "Unknown subcommand: $sub" >&2; return 2 ;;
  esac
}

if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
  main "$@"
fi
