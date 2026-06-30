#!/usr/bin/env bash
# FORGE root resolution (Spec 487) — splits framework-asset root from project root so a
# plugin-installed runtime and a Copier-rendered runtime resolve identically.
#
#   FORGE_PROJECT_ROOT  Always the consumer working-tree (git repo root). Holds project
#                       artifacts + .forge/state/*. Reads/writes of project state target
#                       this root in BOTH modes.
#   FORGE_ASSET_ROOT    Framework assets (.forge/{bin,lib,templates,...}). The plugin root
#                       when CLAUDE_PLUGIN_ROOT points at a dir containing
#                       .claude-plugin/plugin.json; otherwise the repo root (rendered
#                       mode). Never resolved to a bogus path — fails closed.
#
# Usage:
#   source resolve-root.sh && forge_resolve_roots   # exports both vars
#   bash   resolve-root.sh [asset|project|both]      # prints the requested root(s)
#
# Fail-closed (Spec 487 R1/R10): if a required root cannot resolve (not a git work-tree
# AND no valid CLAUDE_PLUGIN_ROOT/override), the function returns non-zero with a clear
# stderr message and never emits a silent-allow path. A set-but-invalid CLAUDE_PLUGIN_ROOT
# degrades to repo-root (rendered mode), it does not error on its own.

forge_resolve_roots() {
  local repo_root plugin_root="" cpr
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$repo_root" ]; then
    repo_root=$(printf '%s' "$repo_root" | tr '\\' '/')
  fi

  # Project root: always the working-tree repo root (override honored if not a repo).
  if [ -n "$repo_root" ]; then
    FORGE_PROJECT_ROOT="$repo_root"
  elif [ -n "${FORGE_PROJECT_ROOT:-}" ]; then
    : # honor explicit override
  else
    echo "resolve-root: cannot resolve FORGE_PROJECT_ROOT (not a git work-tree, no override)" >&2
    return 1
  fi

  # Asset root: a valid CLAUDE_PLUGIN_ROOT (manifest present) wins; else repo root.
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    cpr=$(printf '%s' "$CLAUDE_PLUGIN_ROOT" | tr '\\' '/')
    if [ -f "$cpr/.claude-plugin/plugin.json" ]; then
      plugin_root="$cpr"
    fi
  fi
  if [ -n "$plugin_root" ]; then
    FORGE_ASSET_ROOT="$plugin_root"
  elif [ -n "$repo_root" ]; then
    FORGE_ASSET_ROOT="$repo_root"
  elif [ -n "${FORGE_ASSET_ROOT:-}" ]; then
    : # honor explicit override
  else
    echo "resolve-root: cannot resolve FORGE_ASSET_ROOT (no valid CLAUDE_PLUGIN_ROOT, not a git work-tree)" >&2
    return 1
  fi

  export FORGE_ASSET_ROOT FORGE_PROJECT_ROOT
  return 0
}

# Executed directly (not sourced): resolve and print the requested root(s).
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  if ! forge_resolve_roots; then exit 1; fi
  case "${1:-both}" in
    asset)   printf '%s\n' "$FORGE_ASSET_ROOT" ;;
    project) printf '%s\n' "$FORGE_PROJECT_ROOT" ;;
    *)       printf 'ASSET=%s\nPROJECT=%s\n' "$FORGE_ASSET_ROOT" "$FORGE_PROJECT_ROOT" ;;
  esac
fi
