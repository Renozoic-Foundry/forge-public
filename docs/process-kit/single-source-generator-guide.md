# Single-source generator guide (NC-1a)

> Spec 480. Establishes one canonical source for FORGE's behavioral payload, with every other surface generated from it and a parity gate that fails on drift.

## Plugin-root-relative helper resolution in commands/skills (Spec 538)

Command and skill **bodies** invoke FORGE's helper binaries/libraries
(`.forge/bin/*`, `.forge/lib/*`) as literal prose the agent reads and then types into
a shell. This is a **different resolution context** from the `resolve-root.{sh,ps1}`
dual-mode contract (Spec 487, documented in `plugin-architecture.md`): that helper is
*sourced by other .sh/.ps1 scripts* and resolves `FORGE_ASSET_ROOT` /
`FORGE_PROJECT_ROOT` robustly (git rev-parse, fail-closed). Command/skill prose can't
assume a prior step's shell variables survive — each instruction may be typed as its
own, independent shell invocation — so it needs a **self-contained, per-invocation**
idiom instead of a sourced script or a variable declared once and reused later.

**The idiom**: prefix every helper path with `${CLAUDE_PLUGIN_ROOT:-.}/` inline, at
the point of use:

```bash
# Bash — resolves from the plugin install root when running as a plugin,
# falls back to the project-relative .forge/ tree for classic vendored consumers.
bash "${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py" "${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/derived_state.py" --get-backlog --format=json
```

```powershell
# PowerShell — same fallback semantics via the environment variable.
& "$(if ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else { '.' })/.forge/bin/forge-status.ps1"
```

When `CLAUDE_PLUGIN_ROOT` is set (plugin-installed consumer), the helper resolves
under the plugin root — no vendored `.forge/bin|lib` copy required. When unset
(classic Copier-rendered/vendored consumer), it degrades to the current
project-relative behavior unchanged. `CLAUDE_PLUGIN_ROOT` is inherited by every
subprocess the agent spawns for the session, so the inline form needs no prior
sourcing step and survives across separate tool invocations.

**Scope**: applies to helper **invocations** — paths the agent actually runs or
checks for existence. It does **not** apply to:
- Project-scoped data paths (`docs/specs/`, `docs/sessions/`, `.forge/state/`) —
  consumer-project data, never plugin payload.
- FORGE's own self-referential authoring paths (e.g. `template/.forge/lib/stoke/gates.py`
  compared against its repo-root mirror in `/close`'s gate-mediation check) — these
  reference the FORGE framework repository's own file layout, not a runtime helper
  resolution for a consumer session.
- Status/report message templates that name a destination file just written into a
  *new* project during `/forge init` (e.g. `Updated: .forge/lib/logging.sh
  (framework)`) — always project-relative by definition, since they describe what
  landed in the target project's own tree.
- Fixture-naming conventions with an unfilled `NNN` placeholder (e.g.
  `.forge/bin/tests/test-spec-NNN-<behavior>.sh` in `/spec`'s behavioral-AC scan) —
  documentation of a naming pattern for a file the operator will author later into
  their own project tree, not an invocation of an existing helper.

**Authoring guidance**: when writing or editing a command/skill body that invokes a
`.forge/bin/*` or `.forge/lib/*` helper, use the idiom above at the point of
invocation. See `docs/process-kit/plugin-architecture.md` for the companion
`resolve-root.{sh,ps1}` contract used inside `.sh`/`.ps1` scripts themselves.
