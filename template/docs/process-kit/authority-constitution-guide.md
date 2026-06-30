# Authority Constitution Guide — managed-settings autonomy/budget trust root (Spec 469, NC-2 slice 2)

> **Last verified:** 2026-06-15 (Claude Code managed-settings paths + keys confirmed against
> current docs: `disableBypassPermissionsMode`, `allowManagedPermissionRulesOnly`, `permissions.deny`).

This guide is the operator/admin runbook for installing the **Authority Constitution** — the
OS-level managed-settings trust root that makes the ADR-046 no-self-escalation invariant
*mechanically enforced* rather than prose. It implements the enforcement layer of the trust
boundary defined by **ADR-453** (declarative config in `AGENTS.md`; enforcement ceiling + deny
rule in `managed-settings.json`).

## What the invariant is

ADR-046: *the agent may improve its own **process** but may never expand its own **authority**
(autonomy level / budget) without human sign-off.* Concretely: an agent operating at L3+
(`bypassPermissions`) must be **structurally unable** to raise its own autonomy level or budget
ceiling. Self-escalation = editing `AGENTS.md` (or `.forge/config/authority.yaml`) to declare a
level/budget above the permitted ceiling.

## The honesty statement (load-bearing — do not strip)

The enforcement is **tiered**, and the active tier must always be stated plainly:

- **`managed-settings` tier** — OS-level managed-settings installed → the invariant is enforced at
  the trust-root tier; the ceiling is agent-immutable.
- **`hooks-only` tier** — PreToolUse guard active but no managed-settings install. The invariant is
  enforced for L0–L2 but **the hooks-only tier is bypassable at L3**: an agent at
  `bypassPermissions` can edit `.claude/settings.json` to remove the guard, because
  `bypassPermissions` auto-allows `.claude` writes. This tier is **defense-in-depth, not a trust
  root**.
- **`prose-only` tier** — neither installed → `AGENTS.md` prose only; no mechanical enforcement.

**The agent cannot install its own cage.** `managed-settings.json` is admin-installed at the OS
level — outside FORGE's write reach *by design*. FORGE ships the template + this runbook;
**enforcement is only real after the operator installs it.** No FORGE artifact claims unqualified
"ADR-046 enforced" — every such claim carries the tier qualifier. Until you complete the install
below, this repo is at the **hooks-only tier (bypassable at L3)**.

## Trust-boundary anchor (what anchors enforcement, and what is agent-writable)

| Artifact | Anchors what | Agent-writable? |
|----------|--------------|-----------------|
| OS `managed-settings.json` (admin-installed) | The real trust root: deny rule + `disableBypassPermissionsMode` + `allowManagedPermissionRulesOnly` | **No** — OS path outside the repo, admin-owned, immutable to the user/agent. This is the anchor. |
| `.forge/config/authority.yaml` | The *declared* enforcement ceiling (max_autonomy_level, budget_ceiling) | **Yes, when unmanaged** — repo-tracked. Becomes immutable only via the managed deny rule above. |
| `.claude/settings.json` (hook wiring) | hooks-only defense-in-depth | **Yes at L3** (`bypassPermissions` auto-allows `.claude` writes) — this is exactly why hooks-only is insufficient. |
| `.forge/bin/check-authority-guard.sh` | The PreToolUse guard (and self-protection) | **Yes at L3** unless the managed deny rule protects it. In its own protected set. |

The boundary is principled: an agent-editable file can never be the trust root for an invariant
whose purpose is to stop the agent from rewriting the rule (the `/consensus 457` R2 circular-trust-root
finding). Only the OS managed-settings layer breaks the circle.

## Install runbook (admin / operator)

### Step 1 — Locate the template

FORGE ships `docs/process-kit/managed-settings-template.json`. It carries the three control
surfaces:

1. `permissions.disableBypassPermissionsMode: "disable"` — blocks `--dangerously-skip-permissions`
   and `defaultMode: "bypassPermissions"`.
2. `permissions.allowManagedPermissionRulesOnly: true` — user/project permission rules are ignored;
   only managed rules apply (so a project-level un-deny cannot re-open the protected files).
3. `permissions.deny` — denies Edit/Write/Bash to `.forge/config/authority.yaml`,
   `.claude/settings.json[.local]`, and the guard scripts (self-protecting set).

### Step 2 — Install at the OS managed-settings path

Copy (or merge) the template to the platform path. **These paths are verified against current
Claude Code docs (2026-06-15); re-verify on Claude Code upgrades (OS-path drift is a tracked
residual risk).**

| OS | Managed-settings path |
|----|-----------------------|
| **macOS** | `/Library/Application Support/ClaudeCode/managed-settings.json` |
| **Linux / WSL** | `/etc/claude-code/managed-settings.json` |
| **Windows** | `C:\Program Files\ClaudeCode\managed-settings.json` |

A `managed-settings.d/` drop-in directory exists on each platform (merged alphabetically) if you
prefer modular policy files rather than a single merged file.

Admin privileges are required (system-level path). Under the PRD-001 §6.1 dependency gate, if an
enterprise admin install is not obtainable, a per-user / endpoint-managed deployment that the
operator controls still proves the mechanism. If *no* managed path is obtainable, the Constitution
is demoted to "designed, not enforced" and the repo stays at the hooks-only tier — surfaced by the
posture line, never silently.

### Step 3 — Verify the source is active

Claude Code does not document a single `claude config` introspection command that prints the
winning settings source. Verify by:

1. Confirming the file exists and is valid JSON at the platform path above
   (`jq -e . <path>` returns 0).
2. Starting a Claude Code session and confirming `bypassPermissions` mode is refused (the
   `--dangerously-skip-permissions` flag and `defaultMode: "bypassPermissions"` are blocked).
3. Attempting an edit to `.forge/config/authority.yaml` from an agent session → denied by the
   managed deny rule (not merely the hook).
4. Running `/now` → the posture line reads **`Authority: managed-settings`**.

If the posture line still reads `hooks-only` after install, the managed file is not being read
(wrong path, invalid JSON, or a Claude Code version that relocated the path) — re-verify Step 2.

## Posture surface (`/now` Step 0f)

`/now` emits one read-only line derived from filesystem checks — **observability, never
enforcement**:

```
Authority: <managed-settings | hooks-only | prose-only>
```

- `managed-settings` — OS managed-settings installed and denies `.forge/config/authority.yaml`.
- `hooks-only` — guard wired in `.claude/settings.json`, no managed install (**bypassable at L3**).
- `prose-only` — neither present.

On FORGE-self today the expected value is **`hooks-only`** (no operator has installed managed
settings into this repo's machine).

## Config-reader enumeration

Per ADR-453, autonomy/budget config splits into two classes. **Declarative** readers stay on
`AGENTS.md` (Spec 453 primary source, unchanged by Spec 469). The **enforcement-ceiling** concept
is *new* with this spec and lives in `.forge/config/authority.yaml`; there were no prior readers of
a machine-read *ceiling* (today's config is all declarative), so this table classifies the existing
autonomy/budget readers and records that the ceiling is additive — no declarative reader is
repointed.

| Reader | Reads | Class | Home | Repoint status |
|--------|-------|-------|------|----------------|
| `AGENTS.md` (Autonomy levels L0–L4 matrix, `auto_progression`) | Declared operating level + chain rules | declarative | `AGENTS.md` | unchanged (Spec 453 territory) |
| `AGENTS.md` (Budget ceilings per lane, swarm ceiling) | Per-lane budgets *within* the envelope | declarative | `AGENTS.md` | unchanged |
| `.forge/lib/config.sh` `forge_config_get_budget` | Per-lane cost ceilings | declarative | `AGENTS.md` (hard-coded mirror) | unchanged |
| `.forge/lib/config.sh` `forge_onboarding_get_autonomy_level` | Declared onboarding level | declarative | `.forge/onboarding.yaml` | unchanged |
| `.forge/commands/parallel.md`, `scheduler.md`, `close.md`, `config-change.md` | Declared autonomy / chain behavior | declarative | `AGENTS.md` | unchanged |
| `template/docs/sessions/swarm-budget.yaml` | Swarm budget config | declarative | consumer config | unchanged |
| **`.forge/config/authority.yaml`** (new) | **Max permitted autonomy level + budget ceiling (the envelope)** | **enforcement** | **`.forge/config/authority.yaml`** | **new — the enforcement-ceiling home this spec creates** |
| **OS `managed-settings.json`** (admin-installed) | **The immutable copy of the deny rule + ceiling controls** | **enforcement (trust root)** | **OS path** | **new — authoritative when installed** |

The discriminator (ADR-453): *declaration-within-an-envelope* (declarative, stays on `AGENTS.md`)
vs *the envelope itself* (enforcement, owned by the managed root, mirrored declared in
`authority.yaml`).

## Fixtures

`.forge/bin/tests/test-spec-469-authority-guard.{sh,ps1}` asserts the hook-layer denials: each
protected file × each write form (Edit, Bash append/redirect, `mv`) is denied, and the fixture
FAILs when the guard is removed (injected-drift sub-case). It does **not** assert the
managed-settings tier — that requires an admin install + a live L3 session (a natural follow-up to
Spec 470's runner).

## References

- ADR-046 — human-in-the-loop self-modification axiom (the invariant)
- ADR-451 — NC-2 hooks-enforcement / autonomy-progression principle
- ADR-453 — autonomy-config trust boundary (declarative vs enforcement split)
- Spec 457 — NC-2 slice 1 (the PreToolUse hook substrate this rides on)
- `docs/process-kit/hook-coverage.md` — gate enforcement inventory (slice-2 row updated by this spec)
