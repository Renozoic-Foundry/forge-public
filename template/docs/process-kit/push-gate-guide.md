<!-- Last updated: 2026-06-25 -->
<!-- Last verified: 2026-06-25 against https://docs.claude.com/en/docs/claude-code/hooks and .../settings (managed-settings paths + PreToolUse permissionDecision schema) -->

# Push gate + deferred-close chaining guide (Spec 498)

This guide documents the `git push` authorization gate and the deferred-close chaining it
backstops. It is the operator-facing companion to `check-push-guard.sh`,
`lib/git-command-detect.sh`, and the `auto_progression` entry in `AGENTS.md`.

## Why a push gate exists

FORGE's close/push boundary is the human-authorization checkpoint: `/close` is the terminal
lifecycle state that commits, pushes, and writes gate evidence, and it requires **explicit operator
invocation every time** (the EA-025/026/027 self-authorization failures are why). Deferred-close
chaining (`implement -> implement_next`) deliberately removes the per-spec `/close` checkpoint so an
operator can run several specs in one session. That is a productivity win — and a risk: without the
per-spec checkpoint, nothing stops an agent from eventually pushing unreviewed work.

The **push gate** is the backstop. Once chaining is in play, the gate is the thing that keeps the
close/push boundary from re-opening.

## The mechanism — `ask`, not `deny`

`check-push-guard.sh` is a `PreToolUse` hook on the `Bash` matcher. When it detects a `git push` at
shell command position it emits the documented schema:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"PUSH GATE (Spec 498): git push requires your approval at this prompt. …"}}
```

`permissionDecision: "ask"` **forces the operator's approval prompt — even at L3/`bypassPermissions`**
(verified in Spec 499). This is the key distinction from the commit guard:

| Guard | Decision | Effect |
|-------|----------|--------|
| `check-commit-guard.sh` | `deny` | **Hard block, no prompt.** The operator re-runs after `/implement`/`/close`, or runs the commit manually. |
| `check-push-guard.sh` | `ask` | **Forces the approval prompt.** The operator approves the specific push in-session; that approval is the authorization. |

The push gate **wants** an in-session approval (so a legitimate `/close`-time push still completes —
the operator just approves at the prompt), which is why it uses `ask`. `deny` would block legitimate
pushes outright; the legacy top-level `{"decision":"block"}` is a **PreToolUse no-op** and must not be
used (Spec 499).

### Provenance: the prompt, not a marker

The push gate trusts **no on-disk state**. There is no sign-off file, no nonce, nothing forgeable. An
agent writing any file under `.forge/state/`, or placing a "sign-off" string in assistant-visible
content, does **not** authorize a push — the guard never reads such a thing. **Only the operator
approving at the harness-issued permission prompt authorizes the push.** The permission prompt *is* the
operator-provenance primitive. (This is what made the original Spec 497 `UserPromptSubmit`+nonce design
unsound: FORGE dropped `UserPromptSubmit` per Spec 460 R1, and a nonce "secret" has no agent-unreadable
home since only `managed-settings.json` is agent-immutable — ADR-453.)

### Shared detection helper (no copy-paste)

The command-position detection — heredoc/newline normalization, quote-stripping, git global-option
tolerance (`git -C <path> push`, `git -c k=v push`, …), and the `push`-vs-`push-tree` trailing anchor —
lives **once** in `.forge/bin/lib/git-command-detect.sh`, sourced by **both** the commit guard and the
push guard. The two guards differ only in matcher (`commit` vs `push`) and decision (`deny` vs `ask`).
The helper is in `check-authority-guard.sh`'s protected/deny set (CISO R2): both guards source it, so an
unprotected helper would be a tamper target whose *detection* an agent could neuter without touching the
protected guards. The security-bearing decision stays in each guard; only detection is shared.

## The L3/L4 ceiling split (ADR-453 §6.1) — designed, not enforced

> **This is the honesty constraint. Read it before relying on the gate at L3/L4.**

The push guard is registered in two places:

1. **`.claude/settings.json`** — defense-in-depth for **L0–L2 / unmanaged machines**. This file is
   **agent-editable**: at L3/L4 (`bypassPermissions` auto-allows `.claude` writes) an agent could remove
   the hook entry. So this registration is **NOT** the trust root.
2. **`managed-settings.json` trust root** (`docs/process-kit/managed-settings-template.json` + the
   `template/` mirror) — registers the push guard **and** sets `disableBypassPermissionsMode: "disable"`,
   so once installed the guard cannot be removed and the permission prompt cannot be bypassed at L3/L4.

The catch: **the only documented cross-surface (CLI + VS Code extension) enforcement of managed settings
is server-managed settings**, delivered via the **Claude.ai admin console** (Claude for Teams/Enterprise),
which is **InfoSec-gated** in this org. The per-user file path that ADR-453 §6.1 originally named as the
primary target **does not exist** — Claude Code documents only OS-level admin-installed managed-settings
paths (no `~/.claude/managed-settings.json`), and the VS Code extension's enforcement of file-based
managed settings is undocumented (the doc-backed finding in
`docs/research/explore-vscode-per-user-managed-settings-enforcement.md`, resolving Spec 469 Open Q2).

**Therefore, under the §6.1 kill-criterion (no server-managed settings installed):**

- The push gate is **enforced ≤L2** (the `.claude/settings.json` hook fires and `ask` is honored).
- At **L3/L4** the guarantee is **"designed, not enforced"** — the hook is bypassable.
- **Deferred-close chaining (`implement -> implement_next`) is therefore L1/L2-gated only.** The chain
  is intentionally **absent from the L3/L4 `auto_progression` rows** in `AGENTS.md`. A future operator
  reading only the YAML must not be able to run the chain at L3 where the push gate is unenforced. The
  L3/L4 rows gain the chain **only when the server-managed trust root lands**.

### The InfoSec ask (route to L3/L4 enforcement)

To make the L3/L4 guarantee real: obtain **server-managed settings** via the Claude.ai admin console
(Claude for Teams/Enterprise) and install the contents of `managed-settings-template.json`. Once active
cross-surface, drop the §6.1 kill-criterion and add `implement -> implement_next` to the L3/L4
`auto_progression` rows. Until then, run chaining at L2.

## The deferred-close fixability contract

When chaining is admitted (Step 9f of `/implement`) and the operator chooses `implement_next`:

1. The just-implemented spec stays at **`implemented`** — never auto-closed (deferred close ≠ auto-close).
2. **No `git push` during the chain.** The next push happens only at the human `/close` gate, which hits
   the push guard.
3. Per-spec commits stage **only the declared paths** (Spec 494 commit guard).
4. Per-spec evidence is persisted on disk (Spec 497) so each spec is independently bisectable.
5. A **security/quality gate FAIL halts the chain** — `implement -> implement_next` does not advance past
   a failing `authorization-rule-lint` (strict), `agents-md-drift` (strict), `lane-b/*`, `test-execution`,
   or `post-implementation` gate.

`/now` Step 1b surfaces the resulting pile-up: it lists implemented-but-unclosed specs (count + IDs),
warns past `forge.now.unclosed_spec_cap` (default 3), and **mechanically flags file-overlap** among
unclosed specs (where a later spec builds on an earlier spec's unreviewed output).

## Post-ship review (COO R1)

The push prompt fires on **every** `git push` for **all** operators — not just chained sessions. That is
a prompt-fatigue risk. `/evolve` should review push cadence after ship: if the prompt nags on routine
non-chain pushes, revisit (e.g., scope the gate to chained sessions, or accept the friction as the cost
of the boundary). Tracked as a Compatibility note on Spec 498.

## Files

- `.forge/bin/check-push-guard.sh` — the push guard (emits `ask`).
- `.forge/bin/lib/git-command-detect.sh` — shared command-position detection.
- `.forge/bin/check-commit-guard.sh` — the sibling commit guard (emits `deny`); sources the same helper.
- `.forge/bin/check-authority-guard.sh` — self-protection deny set (includes the push guard + helper).
- `docs/process-kit/managed-settings-template.json` — the trust-root template (server-managed install).
- `docs/decisions/ADR-498-permission-prompt-push-gate.md` — the decision record.
- `docs/process-kit/authority-constitution-guide.md` — the managed-settings trust-root install guide.
