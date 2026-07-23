#!/usr/bin/env bash
# enumerate-classic-consumers.sh — Spec 560 Req 1: best-effort external
# classic-mode (Copier-managed) FORGE consumer census.
#
# NOT telemetry. This script makes ZERO calls back to any FORGE-owned
# endpoint — it only queries the public GitHub code-search API (via `gh
# search code`) for the Copier fingerprint (`.copier-answers.yml` containing
# `_src_path`/`_commit` pointing at a FORGE source), and prints an explicit
# operator-maintained known-consumers list. FORGE collects no consumer usage
# data by design (ADR-316 Finding M2 "paper telemetry"; ADR-496 confirms the
# only durable usage signal FORGE can reach is the operator's own local
# transcript — this script does not even do that).
#
# Requires network access + the `gh` CLI (GitHub CLI). FORGE's default
# runtime isolation is `network: none` (AGENTS.md `isolation.network`), so
# this script is inherently operator-run-with-network-enabled — it is NOT a
# sandboxed-agent default action.
#
# Usage: enumerate-classic-consumers.sh [--query "<github code search query>"]
#
# Output (stdout): one JSON object per matching repo (best-effort — GitHub
# code search does not index private repos, has indexing lag, and has
# syntax/coverage gaps), OR the literal line "search unavailable: <reason>"
# if `gh` or network access is absent. Exit code is always 0 — this is a
# report generator, never a hard gate.
set -uo pipefail

QUERY='forge-public filename:.copier-answers.yml'
while [ $# -gt 0 ]; do
  case "$1" in
    --query)
      QUERY="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "search unavailable: gh CLI not found in PATH"
  exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "search unavailable: gh CLI not authenticated (run 'gh auth login')"
  exit 0
fi

OUTPUT="$(gh search code "$QUERY" --json repository,path,url --limit 100 2>&1)"
RC=$?
if [ $RC -ne 0 ]; then
  echo "search unavailable: gh search code failed (network or API error): $OUTPUT"
  exit 0
fi

if [ -z "$OUTPUT" ] || [ "$OUTPUT" = "[]" ]; then
  echo "search returned zero matches for query: $QUERY"
  exit 0
fi

echo "$OUTPUT"
exit 0
