# FORGE Spec 440 — Pre-commit hook (PowerShell parity): keep docs/backlog.md current with per-spec frontmatter.
#
# Behavior: if any staged file is a spec body (docs/specs/NNN-*.md), re-render
# docs/backlog.md from frontmatter and re-stage it. Bypassed commits (--no-verify,
# CI bots, GitHub web UI) skip this hook; recovery is automatic on the next operator
# commit that touches a spec, or explicit via `/forge stoke`.
#
# See: docs/decisions/ADR-440-generated-backlog-storage-model.md
# See: docs/process-kit/backlog-render-triggers.md

$ErrorActionPreference = 'Stop'

# Locate repo root
$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) { exit 0 }
Set-Location $repoRoot

# Short-circuit if FORGE's render pipeline is absent
if (-not (Test-Path '.forge/lib/render_backlog.py') -or -not (Test-Path '.forge/bin/forge-py')) {
  exit 0
}

# Detect staged spec body changes
$staged = git diff --cached --name-only --diff-filter=ACMR | Where-Object { $_ -match '^docs/specs/[0-9]+-[^/]*\.md$' }
if (-not $staged) { exit 0 }

# Render. Same path /matrix uses.
& .forge/bin/forge-py .forge/lib/render_backlog.py --output docs/backlog.md | Out-Null

# Split-file mode (Spec 398) — assemble after render
if (Test-Path 'docs/.generated') {
  & .forge/bin/forge-py .forge/lib/assemble_view.py docs/backlog.md | Out-Null
}

# Re-stage the rendered view
if (Test-Path 'docs/backlog.md') {
  git add docs/backlog.md
}

exit 0
