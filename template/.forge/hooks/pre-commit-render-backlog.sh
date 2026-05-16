#!/usr/bin/env bash
# FORGE Spec 440 — Pre-commit hook: keep docs/backlog.md current with per-spec frontmatter.
#
# Behavior: if any staged file is a spec body (docs/specs/NNN-*.md), re-render
# docs/backlog.md from frontmatter and re-stage it. Bypassed commits (--no-verify,
# CI bots, GitHub web UI) skip this hook; recovery is automatic on the next operator
# commit that touches a spec, or explicit via `/forge stoke`.
#
# Exit semantics: 0 on success or skip (no spec files staged); non-zero on render failure.
#
# See: docs/decisions/ADR-440-generated-backlog-storage-model.md
# See: docs/process-kit/backlog-render-triggers.md

set -e

# Locate repo root (hook may be invoked from a subdirectory)
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$repo_root"

# Short-circuit if FORGE's render pipeline is absent (consumer hasn't migrated)
if [ ! -f .forge/lib/render_backlog.py ] || [ ! -f .forge/bin/forge-py ]; then
  exit 0
fi

# Detect staged spec body changes — anything that could affect backlog state
staged_spec_files=$(git diff --cached --name-only --diff-filter=ACMR | grep -E '^docs/specs/[0-9]+-[^/]*\.md$' || true)

if [ -z "$staged_spec_files" ]; then
  # No spec body changes — skip render
  exit 0
fi

# Render. Use the same path /matrix uses.
.forge/bin/forge-py .forge/lib/render_backlog.py --output docs/backlog.md >/dev/null

# Split-file mode (Spec 398) — assemble after render
if [ -d docs/.generated ]; then
  .forge/bin/forge-py .forge/lib/assemble_view.py docs/backlog.md >/dev/null
fi

# Re-stage the rendered view so it lands in this commit
if [ -f docs/backlog.md ]; then
  git add docs/backlog.md
fi

exit 0
