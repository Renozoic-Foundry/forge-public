#!/usr/bin/env bash
#
# probe-runtime-usage.sh — Spec 496 feasibility probe (read-only).
#
# Question (Spec 496 AC1/AC2): can a FORGE-side tool durably read the per-session
# token/cost usage that the Claude Code runtime exposes? This probe attempts to
# read a real usage signal and prints it, or demonstrates that none is reachable.
# Its stdout IS the evidence captured into docs/decisions/ADR-496-*.md.
#
# It reads ONLY (no writes, no network). It reports raw TOKEN counts — the durable
# signal — and deliberately does NOT compute or emit a cost figure (Spec 496 AC4:
# no cost field/key/ceiling is introduced by this spike).
#
# Usage:
#   probe-runtime-usage.sh [--json] [TRANSCRIPT_PATH]
#     --json           emit a machine-readable JSON object instead of prose
#     TRANSCRIPT_PATH  parse this transcript (e.g. a hook's stdin `transcript_path`);
#                      otherwise auto-discover the most-recent transcript on disk.
#   Env overrides: CLAUDE_PROJECTS_DIR (default: $HOME/.claude/projects)
#
set -euo pipefail

emit_json=0
explicit_path=""
for arg in "$@"; do
  case "$arg" in
    --json) emit_json=1 ;;
    -*) echo "probe-runtime-usage.sh: unknown flag '$arg'" >&2; exit 64 ;;
    *) explicit_path="$arg" ;;
  esac
done

# A python interpreter is the FORGE stdlib baseline (ADR-359) — more portable than
# jq across consumer boxes, and keeps a single JSONL-parsing implementation.
PY=""
for cand in python3 python; do
  if command -v "$cand" >/dev/null 2>&1; then PY="$cand"; break; fi
done

projects_dir="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

# Channel 1 — transcript JSONL discovery.
transcript=""
if [ -n "$explicit_path" ] && [ -f "$explicit_path" ]; then
  transcript="$explicit_path"
elif [ -d "$projects_dir" ]; then
  transcript=$(find "$projects_dir" -maxdepth 2 -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -1 | cut -d' ' -f2- || true)
fi

# Channel 2 — OpenTelemetry export env (alternate, opt-in capture path).
otel_enabled="${CLAUDE_CODE_ENABLE_TELEMETRY:-unset}"
otel_exporter="${OTEL_METRICS_EXPORTER:-unset}"
otel_endpoint="${OTEL_EXPORTER_OTLP_ENDPOINT:-unset}"

print_otel() {
  echo "OpenTelemetry channel (alternate):"
  echo "  CLAUDE_CODE_ENABLE_TELEMETRY = ${otel_enabled}"
  echo "  OTEL_METRICS_EXPORTER        = ${otel_exporter}"
  echo "  OTEL_EXPORTER_OTLP_ENDPOINT  = ${otel_endpoint}"
  echo "  (metrics claude_code.token.usage / claude_code.cost.usage export here when enabled)"
}

# --- No transcript reachable: the absence is itself the evidence. ---
if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
  if [ "$emit_json" -eq 1 ]; then
    printf '{"signal":"none","reason":"no transcript found","projects_dir":"%s","otel_enabled":"%s"}\n' \
      "$projects_dir" "$otel_enabled"
  else
    echo "PROBE VERDICT: NO USAGE SIGNAL REACHABLE"
    echo "  Searched: ${projects_dir} (and any TRANSCRIPT_PATH argument)"
    echo "  No transcript JSONL found. Transcript-parsing channel is unavailable here."
    print_otel
  fi
  exit 0
fi

if [ -z "$PY" ]; then
  echo "probe-runtime-usage.sh: no python interpreter found (need python3/python to parse JSONL)" >&2
  exit 69
fi

# --- Sum usage across assistant-message records in the transcript. ---
summary=$("$PY" - "$transcript" <<'PYEOF'
import json, sys
path = sys.argv[1]
tot = {"messages_with_usage": 0, "input_tokens": 0, "output_tokens": 0,
       "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0,
       "web_search_requests": 0, "web_fetch_requests": 0}
with open(path, "r", encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if not isinstance(obj, dict):
            continue
        usage = None
        msg = obj.get("message")
        if isinstance(msg, dict):
            usage = msg.get("usage")
        if usage is None:
            usage = obj.get("usage")
        if not isinstance(usage, dict):
            continue
        tot["messages_with_usage"] += 1
        for k in ("input_tokens", "output_tokens",
                  "cache_creation_input_tokens", "cache_read_input_tokens"):
            v = usage.get(k)
            if isinstance(v, (int, float)):
                tot[k] += int(v)
        stu = usage.get("server_tool_use")
        if isinstance(stu, dict):
            for k in ("web_search_requests", "web_fetch_requests"):
                v = stu.get(k)
                if isinstance(v, (int, float)):
                    tot[k] += int(v)
tot["total_tokens"] = (tot["input_tokens"] + tot["output_tokens"]
                       + tot["cache_creation_input_tokens"] + tot["cache_read_input_tokens"])
print(json.dumps(tot))
PYEOF
)

size_bytes=$(wc -c < "$transcript" | tr -d ' ')

if [ "$emit_json" -eq 1 ]; then
  # Splice transcript provenance into the python-emitted token object.
  "$PY" - "$transcript" "$size_bytes" "$otel_enabled" "$summary" <<'PYEOF'
import json, sys
path, size, otel, summary = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
out = {"signal": "tokens", "transcript_path": path, "transcript_bytes": size,
       "otel_enabled": otel, "usage": json.loads(summary)}
print(json.dumps(out))
PYEOF
else
  echo "PROBE VERDICT: USAGE SIGNAL REACHABLE (transcript channel)"
  echo "  Transcript: ${transcript}"
  echo "  Size:       ${size_bytes} bytes"
  echo "Per-session token usage summed from assistant-message 'usage' objects:"
  "$PY" - "$summary" <<'PYEOF'
import json, sys
u = json.loads(sys.argv[1])
print(f"  messages with usage         : {u['messages_with_usage']}")
print(f"  input_tokens                : {u['input_tokens']}")
print(f"  output_tokens               : {u['output_tokens']}")
print(f"  cache_creation_input_tokens : {u['cache_creation_input_tokens']}")
print(f"  cache_read_input_tokens     : {u['cache_read_input_tokens']}")
print(f"  TOTAL tokens                : {u['total_tokens']}")
print(f"  server web_search_requests  : {u['web_search_requests']}")
print(f"  server web_fetch_requests   : {u['web_fetch_requests']}")
PYEOF
  print_otel
  echo "Note: token counts are the durable raw signal (on-disk, append-only)."
  echo "      This probe does NOT compute or emit a cost figure (Spec 496 AC4)."
fi
