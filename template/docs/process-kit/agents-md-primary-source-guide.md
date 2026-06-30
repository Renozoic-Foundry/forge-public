# AGENTS.md Primary-Source Guide

<!-- Last verified: 2026-06-14 against https://agents.md and https://github.com/ETH-AGENTbench -->

Spec 453 / ADR-450 Phase 1 made **AGENTS.md the primary-source operator-facing context
document** for every agent runtime (Claude Code, Codex CLI, Cursor, Gemini CLI, Aider).
CLAUDE.md is now a thin Claude-specific addendum that imports AGENTS.md via the
`@AGENTS.md` syntax and carries only content that does not apply to other runtimes
(model-picker guidance, prompt caching, PDF/digest handling).

This guide documents the convention, the ETH six-section rubric mapping, the
authorization-prose carve-out checklist, the `@AGENTS.md` import pattern, and the
cross-tool verification workflow.

## Why AGENTS.md is the primary source

- **Cross-tool portability.** AGENTS.md is an open convention (agents.md) read natively
  by Codex CLI, Cursor, and Aider, and configurable in Gemini CLI. Claude Code imports
  it via `@AGENTS.md`. A single primary source removes per-tool drift.
- **One operating doctrine.** Everything an agent needs at session start — the spec
  gate, the Boundaries (authorization gates), autonomy levels, the runtime config — is
  in AGENTS.md. CLAUDE.md never restates it.

## ETH six-section rubric mapping

AGENTS.md is organized under the ETH AGENTbench six-section rubric. Each section is
identifiable by its heading. Rule sections use **concrete commands** (no vague
directives) and **numbered Priority ordering** where two rules could conflict.

| ETH rubric section | AGENTS.md heading | What it covers |
|--------------------|-------------------|----------------|
| **Setup** | `## Setup` | Onboarding gate, project context (strategic scope + config YAML), capabilities granted |
| **Test** | `## Test` | Validation commands (`validate-bash.sh`, `validate-authorization-rules.sh`, Copier render), the Delivery gate evidence requirement |
| **Project structure** | `## Project structure` | Repo layout, workflow-map doc pointers, command index, signal capture |
| **Code style** | `## Code style` | Two hard rules, Architectural Principles, Bash safety, Jinja2/Copier rules, spec gate, spec lifecycle, change lanes |
| **Git workflow** | `## Git workflow` | Non-destructive git latitude, delegation contract |
| **Boundaries** | `## Boundaries (authorization, safety)` | Requires-Confirmation, authorization-required commands, machine-readable auth-rules block, Prohibited list, autonomy levels, role separation, budget ceilings |

Verify section presence:

```bash
grep -nE "^## (Setup|Test|Project structure|Code style|Git workflow|Boundaries)" AGENTS.md
```

### Concrete-command rule

Operator-facing prose contains no vague directives. The following scan returns zero:

```bash
grep -nE "\b(should|consider|might|may|approximately|reasonable|as needed)\b" AGENTS.md
```

### Numbered-priority rule

Where two rules could conflict (e.g., "ship fast" vs. "tests pass" vs. "ask before
push"), AGENTS.md states explicit Priority ordering in **Agent Identity → Priority
ordering**:

1. **Priority 1 — Boundaries** (authorization gates) override everything.
2. **Priority 2 — Spec gate** (no implementation without a matching spec).
3. **Priority 3 — Delivery** (implement, test, ship).

## Authorization-prose carve-out checklist

Per Spec 453, load-bearing authorization prose is **preserved verbatim** until NC-2
(hooks-as-enforcement, ADR-450 Phase 2) ratifies these rules at the runtime layer. Each
anchor below must return ≥ 1 hit across AGENTS.md and/or CLAUDE.md:

- [x] **Two hard rules** — spec-before-code + session-log-mandatory (AGENTS.md Code style)
- [x] **Architectural Principles 1–5** (AGENTS.md Code style)
- [x] **EA-025 / EA-026 / EA-027** incident references (AGENTS.md Boundaries)
- [x] **Session summary authorization rule** (AGENTS.md Boundaries)
- [x] **Scope confirmation rule** (AGENTS.md Code style → spec gate)
- [x] **Context compaction rule** — post-compaction, treat auth-required commands as unissued (AGENTS.md Boundaries)
- [x] **Hotfix rule** — hotfix edits only within an already-open spec's scope (AGENTS.md Code style → change lanes)
- [x] **Prohibited list** — no `--no-verify`, no secret commits, no git-config edits, no destructive shell (AGENTS.md Boundaries)
- [x] **Requires Confirmation list** — destructive git, push, PR, out-of-scope, schema-breaking, deps (AGENTS.md Boundaries)
- [x] **Seven destructive-shell patterns** — `git reset --hard`, `git push --force`, `git checkout --`, `gh pr create`, `gh pr merge`, `rm -rf`, `branch -D` (AGENTS.md Boundaries)
- [x] **Methodology-annex pointer** — `docs/process-kit/methodology-mapping-annex.md` (forward-looking; NC-4 / Phase 3 populates it)
- [x] **Machine-readable `forge:auth-rules:start/end` block** — preserved exactly; consumed by `scripts/validate-authorization-rules.sh`

Verify the carve-out:

```bash
for a in "EA-025" "EA-026" "EA-027" "Two hard rules" \
         "Session summary authorization rule" "Scope confirmation rule" \
         "context compaction" "Architectural Principles"; do
    grep -Fq "$a" AGENTS.md CLAUDE.md && echo "OK: $a" || echo "MISSING: $a"
done
grep -F "hotfix" AGENTS.md | grep -F "open spec"   # hotfix-within-scope rule
bash scripts/validate-authorization-rules.sh         # auth-rules block intact
```

## The `@AGENTS.md` import pattern

CLAUDE.md's first non-comment, non-blank directive line is exactly `@AGENTS.md`:

```text
# Framework: FORGE
<!-- explanatory comment block -->

@AGENTS.md

## Claude-specific addenda
...
```

Verify:

```bash
awk '/^@AGENTS\.md/{print "import on line", NR; exit}' CLAUDE.md
```

## Cross-tool resolution by runtime

| Runtime | How `@AGENTS.md` / AGENTS.md resolves | Consumer config |
|---------|--------------------------------------|-----------------|
| **Claude Code** | `@AGENTS.md` import directive in CLAUDE.md | none (v2.0+) |
| **Codex CLI** | Autoloads repo-root AGENTS.md | Codex 2026.4+ |
| **Cursor** | Reads AGENTS.md natively (plus `.cursor/rules/`) | none |
| **Gemini CLI** | `.gemini/settings.json` → `{"context": {"fileName": "AGENTS.md"}}` | add the settings entry |
| **Aider** | Loads repo-level AGENTS.md as context | none |

## Cross-tool verification workflow

`scripts/verify-cross-tool-import.sh` (and `.ps1` parity) renders the FORGE template
into a scratch project and verifies that `@AGENTS.md` resolves to AGENTS.md under each
runtime:

```bash
# All four runtimes, with evidence artifacts
scripts/verify-cross-tool-import.sh --runtime=all \
  --evidence-dir=tmp/evidence/SPEC-453-$(date +%Y%m%d)

# A single runtime
scripts/verify-cross-tool-import.sh --runtime=gemini --evidence-dir=tmp/evidence/x

# Verify an already-rendered project (skip the Copier render)
scripts/verify-cross-tool-import.sh --runtime=all --project-dir /path/to/rendered
```

**Live vs. manual mode.** When a runtime CLI is installed, the helper invokes it and
records a live transcript. When the CLI is absent (the common CI / dev case), the check
runs in **manual mode**: it verifies the runtime's documented resolution artifact
(AGENTS.md presence, the `@AGENTS.md` import line, per-tool config) and records that the
operator must capture a live transcript. Manual mode still exits 0 — an unavailable
runtime defers to operator evidence per Spec 453 verification-scope (c).

## Maintenance

- Keep AGENTS.md ≤ 500 lines. Operational matrices (autonomy levels, budget ceilings,
  role separation, auto-progression, runtime config, dispatch rules) stay in-file and
  are **not** subject to the ETH prune.
- A future Phase 1.5 may relocate matrices to `docs/process-kit/runtime-config.md` —
  out of scope until NC-4 (Phase 3) ratifies the annex.
- The carve-out anchors stay verbatim until NC-2 (Phase 2) hook-coverage parity reaches
  100%. Do not delete them.
