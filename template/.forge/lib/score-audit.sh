#!/usr/bin/env bash
# FORGE score-audit helper — predicted/observed score calibration log (Spec 368).
# Time-blindness mitigation: timestamps and durations from shell, not from model.
#
# Usage:
#   score-audit.sh record-predicted <spec_id> <bv> <e> <r> <sr> <tc> <lane> <kind_tag> <revise_round> [predicted_by]
#   score-audit.sh record-observed <spec_id>
#   score-audit.sh read-records [spec_id]
#   score-audit.sh bias-report [lean|verbose]
#
# Audit log path is $SCORE_AUDIT_FILE (default: .forge/state/score-audit.jsonl).
# Atomic-append bound: 4000 bytes (POSIX PIPE_BUF=4096 safety margin).
# This helper is advisory; failures emit WARN to stderr but always exit 0.

SCORE_AUDIT_FILE="${SCORE_AUDIT_FILE:-.forge/state/score-audit.jsonl}"
ATOMIC_BOUND_BYTES=4000

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
  for f in docs/specs/${spec_id}-*.md; do
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

  local session_count=0
  if compgen -G "docs/sessions/*.json" > /dev/null 2>&1; then
    session_count=$(grep -l "\"$spec_id\"" docs/sessions/*.json 2>/dev/null | wc -l | tr -d ' ')
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
  prev=$(grep "\"spec_id\":\"$spec_id\"" "$SCORE_AUDIT_FILE" 2>/dev/null \
    | grep '"kind"' \
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

main() {
  if [ "$#" -lt 1 ]; then
    echo "Usage: score-audit.sh {record-predicted|record-observed|read-records|bias-report} [args...]" >&2
    return 2
  fi
  local sub="$1"; shift
  case "$sub" in
    record-predicted)   cmd_record_predicted "$@" ;;
    record-observed)    cmd_record_observed "$@" ;;
    read-records)       cmd_read_records "$@" ;;
    next-revise-round)  cmd_next_revise_round "$@" ;;
    bias-report)        cmd_bias_report "$@" ;;
    *) echo "Unknown subcommand: $sub" >&2; return 2 ;;
  esac
}

if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
  main "$@"
fi
