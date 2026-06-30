# Hook Coverage — FORGE gate enforcement inventory (NC-2)

> **Scope of enforcement, stated honestly:** This inventory reflects **FORGE-self** (this repo). The hooks below are activated in FORGE's own `.claude/settings.json` (Spec 457 slice 1). **Consumer projects are NOT yet auto-activated** — they receive the (fixed) hook scripts + a `settings.json.template`, but activation is deferred. **The ADR-046 autonomy self-escalation invariant is enforced only at the `hooks-only` tier (Spec 469) — bypassable at L3** until the operator installs the OS-level managed-settings trust root. It is NOT closed at the trust-root tier on FORGE-self. Do not read "hooks active" as "the autonomy invariant is closed."

This document maps FORGE's load-bearing gates to *how* they are enforced (prose the agent may route around vs. a harness hook the agent cannot) and *how autonomy-critical* each is. It is the scaffold for ADR-449's prompt-rule→hook parity report and the planning surface for subsequent NC-2 slices.

Enforcement levels:
- **prose** — an instruction in a command/AGENTS.md body. An autonomous agent can rationalize past it (the gap NC-2 closes).
- **script-hook** — a `PreToolUse` hook (bash, invoked via `bash`) that the harness runs deterministically; blocks via the documented `hookSpecificOutput.permissionDecision:"deny"` schema (Spec 499; see § Hook output schema below).
- **native-deny** — a Claude Code `permissions.deny` rule (absolute, mode-independent).
- **managed-settings-required** — can only be made agent-immutable via OS-level `managed-settings.json` (project `.claude/settings.json` is agent-editable; `bypassPermissions` auto-allows `.claude` writes).
- **state-snapshot** — a lifecycle hook that surfaces repo state to the operator (stdout); observability, not enforcement. Never blocks.
- **advisory** — a lifecycle hook that soft-warns (stderr) when a prose rule appears violated; the prose rule remains authoritative. Never blocks.

## Gate inventory

| Gate | Enforces | Enforcement (FORGE-self) | Autonomy-criticality | Status |
|------|----------|--------------------------|----------------------|--------|
| Edit-gate (spec-gate) | No Write/Edit to `template/`,`scripts/`,`copier.yml` without an active `/implement` | **script-hook** (`check-edit-gate.sh`) — *fixed + activated, Spec 457* | High | ✅ active (firing-test verified: `test-spec-457-hooks-fire`) |
| Commit guard | No `git commit` without active `/implement` or `/close` | **script-hook** (`check-commit-guard.sh`) — activated, Spec 457 | High | ✅ active (firing-test verified) |
| Role read-only | Validator/DA roles cannot Write/Edit while active | **script-hook** (`check-role-permissions.sh`) — activated, Spec 457 | Medium | ✅ active (firing-test verified) |
| Final-draft consensus (Spec 395) | High-value drafts vetted before `/implement` | prose (`/implement` Step 0d) | Medium | prose — future NC-2 slice |
| Spec-integrity SHA (Spec 089) | Spec body unchanged since approval (Lane B) | prose (`/close` Step 2) | Medium | prose — future NC-2 slice |
| DA gate (Spec 078) | Adversarial review before code | prose (`/implement` Step 2b) | Medium | prose — future NC-2 slice |
| Status-verification (`/close`) | Only `implemented` specs close | prose (`/close` Step 2) | Medium | prose — future NC-2 slice |
| Gate-holding / evidence (the HALT) | A spec failing an AC must not self-close | prose | **High** (Spec 455 probe measures it) | prose — semantic; partly irreducible |
| **Autonomy self-escalation (ADR-046)** | The agent may improve its *process* but never expand its own *authority* (autonomy/budget) without human sign-off | **script-hook** (`check-authority-guard.sh`, Spec 469) at **hooks-only tier**; **managed-settings-required** for the trust root | **Critical** | ⚠ hooks-only active (Spec 469) — **bypassable at L3** until the operator installs managed-settings; see `authority-constitution-guide.md` |

## Slice 1 (Spec 457) — what is now enforced for FORGE-self

The three PreToolUse hooks above are wired into FORGE's own `.claude/settings.json` and verified by `test-spec-457-hooks-fire.{sh,ps1}` (block/allow **decisions**, not mere presence). A dedicated parity fixture (`test-spec-457-settings-parity.{sh,ps1}`) keeps the three hook entries in sync with `template/.claude/settings.json.template`.

**EA-143 fixed in this slice**: the edit-gate previously shipped as an inline command that read a non-existent `$CLAUDE_FILE_PATH` env var and blocked via `exit 1` (non-blocking) — it was inert in every consumer that activated it. It is now the script `check-edit-gate.sh` (reads `.tool_input.file_path` from stdin; blocks via the documented `permissionDecision:"deny"` schema — Spec 499), and the fix ships to consumers via `template/`.

## Slice 2 (Spec 469) — managed-settings autonomy self-escalation guard

**Status (2026-06-15): implemented at the hooks-only tier.** Spec 469 ships:
- `.forge/config/authority.yaml` — the enforcement-ceiling config (max autonomy level + budget envelope).
- `check-authority-guard.sh` — a PreToolUse guard (Edit/Write/NotebookEdit + Bash matchers) denying agent writes to `authority.yaml`, `.claude/settings.json[.local]`, and the guard scripts (self-protecting set).
- `docs/process-kit/managed-settings-template.json` + `authority-constitution-guide.md` — the admin-installable trust root + install runbook (3 OS paths, verification, config-reader enumeration).
- `/now` Step 0f — the `Authority: <tier>` posture line.

**Tier honesty (unchanged, load-bearing): the hooks-only tier is bypassable at L3** — an agent at
`bypassPermissions` can edit `.claude/settings.json` to remove the guard, because `bypassPermissions`
auto-allows `.claude` writes. The ADR-046 invariant is enforced at the **trust-root** tier ONLY after
the operator installs `managed-settings.json` at the OS path. On FORGE-self today the posture is
`hooks-only`. **Do not read "guard active" as "ADR-046 enforced."**

### Original slice-2 design (records the settled plan)

Two `/consensus 457` rounds established that the ADR-046 invariant **cannot be enforced by repo-shipped config**:
- A `permissions.deny` rule protecting an autonomy-config file lives in `.claude/settings.json`, which is **itself agent-editable**; `bypassPermissions` (the mode L3/L4 sets) explicitly auto-allows `.claude` writes. An agent deletes the deny rule (or edits the guard script) in one step — the protection is circular.

**Slice-2 design (records the settled plan):**
1. Relocate the machine-read autonomy/budget config (`default_autonomy`, `auto_progression`, budget/swarm ceilings) out of `AGENTS.md` into a dedicated file (e.g. `.forge/config/autonomy.yml`); reconcile with **Spec 453** (AGENTS.md keeps a human-readable pointer/summary).
2. Protect it with an **OS-level managed-settings** layer (`managed-settings.json` — `/etc/claude-code/` or `C:\Program Files\ClaudeCode\` — admin/IT-installed, agent-immutable) carrying the `deny` rule + `disableBypassPermissionsMode` + `allowManagedPermissionRulesOnly`.
3. Close the Bash channel with a companion Bash-matcher guard (`check-commit-guard.sh`-style, single-target).
4. Protect `settings.json` and the guard scripts from agent edits.
5. Enumerate the ~30 config-reader files (sweep) before migration.

This **sharpens ADR-451**: the autonomy gate specifically needs an immutable (managed-settings) trust root, not just project hooks — an ADR-451 addendum candidate when slice 2 is specced. See `docs/research/explore-nc-2-hooks-as-enforcement.md` and the scratchpad spec candidate.

## Slice 3 (Spec 460) — SessionStart + Stop lifecycle observability hooks

Two lifecycle hooks machine-surface CLAUDE.md's two hard rules at the moments of highest operator attention. Per the /consensus 460 R1 hybrid decision, this slice ships ONLY these two events: UserPromptSubmit was dropped (its nudge folds into the SessionStart hint, which fires solely on the absence of `.forge/state/implementing.json` and never scans prompt text), and PreCompact / SubagentStop are deferred.

**Neither hook is enforcement.** Both exit 0 in all paths. They are labeled `state-snapshot` and `advisory` — NOT `script-hook` — and no existing row's enforcement label is downgraded by this slice.

> Honesty statement (unchanged by this slice): FORGE-self only; consumers not activated; ADR-046 invariant NOT yet enforced. **This slice does NOT enforce the ADR-046 autonomy self-escalation invariant** — that remains deferred to slice 2 (managed settings).

<!-- FORGE-HOOK-COVERAGE-ROW-START: SessionStart -->
| Gate | Surfaces | Enforcement (FORGE-self) | Autonomy-criticality | Status |
|------|----------|--------------------------|----------------------|--------|
| SessionStart snapshot | Hard rule #1 (spec-before-code): active spec, active tab, unreviewed digests, last evolve at session open; emits a `/spec`-or-`/explore` hint when no `implementing.json` exists | **state-snapshot** (`check-session-start.sh`) — activated, Spec 460 | Low (observability; never blocks) | ✅ active (firing-test verified: `test-spec-460-lifecycle-hooks`) |
<!-- FORGE-HOOK-COVERAGE-ROW-END: SessionStart -->

<!-- FORGE-HOOK-COVERAGE-ROW-START: Stop -->
| Gate | Surfaces | Enforcement (FORGE-self) | Autonomy-criticality | Status |
|------|----------|--------------------------|----------------------|--------|
| Stop session-log advisory | Hard rule #2 (session-log-required): stderr soft-warn at turn end when spec/code paths changed without a `docs/sessions/` update | **advisory** (`check-stop.sh`) — activated, Spec 460 | Low (advisory; never blocks; prose rule stays authoritative) | ✅ active (firing-test verified: `test-spec-460-lifecycle-hooks`) |
<!-- FORGE-HOOK-COVERAGE-ROW-END: Stop -->

**Per-hook opt-out (consumer granularity)**: each event is a distinct entry in `settings.json` (`hooks.SessionStart`, `hooks.Stop`). Consumers can disable either hook by deleting its event block without affecting the other — or either independently of the three Spec 457 `PreToolUse` hooks. The anchor comments above let future hook specs extend this inventory row-by-row without rewriting existing rows; `test-spec-460-settings-parity` asserts the Spec 457 rows and honesty statement stay byte-preserved.

## Hook output schema (Spec 499)

All FORGE PreToolUse guards (`check-commit-guard.sh`, `check-edit-gate.sh`,
`check-authority-guard.sh`, `check-role-permissions.sh`) block via the **documented**
Claude Code PreToolUse schema:

```json
{ "hookSpecificOutput": { "hookEventName": "PreToolUse",
                          "permissionDecision": "deny",
                          "permissionDecisionReason": "<why>" } }
```

emitted at **exit 0**. Allow paths emit nothing (exit 0 = *defer* to normal permission flow).

**Why this matters (the Spec 499 finding).** The guards previously emitted the legacy
top-level `{"decision":"block"}`. Per current Claude Code docs
(https://code.claude.com/docs/en/hooks.md) that field is a **no-op for PreToolUse** —
it is the legacy schema for *other* events (Stop, UserPromptSubmit, …). A 2026-06-24
harness-execution probe (VS Code extension, Opus 4.8) found the legacy form was still
**honored via undocumented backward-compat** — so the guards enforced, but only by luck
the docs do not promise. A future Claude Code release dropping that backward-compat, or
any surface that already follows the docs strictly, would make every gate **silently
fail open**. Spec 499 migrated all four guards to the documented schema so enforcement
rests on the contract, not the backward-compat. This is load-bearing for the plugin
(`.claude-plugin/hooks/hooks.json` wires the same guards as the *sole* enforcer post-Spec-489).

**Framing correction (no in-session bypass for a blocked guard).**
`permissionDecision:"deny"` is a **hard block** — it does **not** raise a permission
dialog; the model simply sees the denial. (Per the docs, `"ask"` by contrast *does* force
a prompt **even under `bypassPermissions`** — but the FORGE guards use `deny`, not `ask`, so
no in-session approval surfaces for a blocked guard.) To proceed past a block, the operator
runs the action **manually in the terminal** (or lets `/implement`|`/close` set the marker
the guard checks). Any guard header or spec that claimed "the operator approves at the
permission prompt" was inaccurate and is corrected (Spec 499 Req 3). _Note: Spec 499's own
Scope said "`ask` does not prompt under bypassPermissions" — that was incorrect per the docs
(`ask` does prompt at L3); it does not affect the guards, which deny._

**Mechanism choice (`deny` vs `exit 2`).** `exit 2` also blocks a PreToolUse call (stderr →
model, stdout ignored) with no `jq` dependency. We chose `permissionDecision:"deny"` because
(a) it preserves a structured reason in the permission UI, and (b) the guards already parse
their stdin tool-input with `jq`, so `exit 2`'s "no-jq" advantage does not apply to this
guard family (jq is required either way; the `fail-open-without-jq` posture is unchanged).

## Parity & maintenance

Any change to the hook scripts (`.forge/bin/check-*.sh`), the settings files, or this doc must update BOTH the own-copy and the `template/` mirror in the same change. `test-spec-457-settings-parity.{sh,ps1}` guards the `.claude/settings.json` ↔ `template/.claude/settings.json.template` PreToolUse-hook fork; `forge-sync-cross-level.sh --check` guards the `.forge/bin/` + `docs/process-kit/` mirrors.
