# Agent Roles Guide — frontmatter hardening, tiering, isolation, overrides

This guide documents the hardened frontmatter posture FORGE ships on its 17 subagents
(`.claude/agents/` + the `template/.claude/agents/` mirror), introduced by Spec 462.
It is the reference for operators who want to understand, override, or roll back the
tool allowlists, model tiering, and isolation defaults.

**Honesty constraint**: this is *policy*, not *enforcement*. A `tools:` allowlist
restricts the subagent's available toolset, not the parent session's. A `model:`
assignment is a Claude Code hint the operator's model picker can override at session
level. None of the fields below open a global write path.

## 1. Tiering policy

Every agent file declares an explicit `model:` line. Review-only and CXO advisory
roles run on the cheapest tier that preserves quality; implementation roles stay on
the operator's default working tier.

| # | File | Role class | `tools:` | `model:` | CXO-rubric ref | `isolation:` |
|---|------|-----------|----------|----------|----------------|--------------|
| 1  | `devils-advocate.md`  | review (depth)      | `Read, Grep, Glob, WebSearch` | `sonnet` | —   | `worktree` (preserved) |
| 2  | `validator.md`        | review (shallow)    | `Read, Grep, Glob, WebSearch` | `haiku`  | —   | `worktree` (preserved) |
| 3  | `competitor.md`       | review (strategic)  | `Read, Grep, Glob, WebSearch` | `sonnet` | —   | — |
| 4  | `maverick-thinker.md` | review (strategic)  | `Read, Grep, Glob, WebSearch` | `sonnet` | —   | — |
| 5–15 | 11 CXO panel files | CXO advisory       | `Read, Grep, Glob, WebSearch` | `sonnet` | yes | — |
| 16 | `implementer.md`      | implementation      | full default (no `tools:` line) | `sonnet` | — | autonomy-conditional (see §2) |
| 17 | `spec-author.md`      | implementation      | full default (no `tools:` line) | `sonnet` | — | autonomy-conditional (see §2) |

The 11 CXO files are: `cto`, `cfo`, `ciso`, `coo`, `cmo`, `cefo`, `creso`, `cxo`,
`cqo`, `cco`, `cro`. Only `validator.md` runs on `haiku`; every other file runs on
`sonnet` (modulo operator `inherit` opt-out, §4).

### WebFetch is deliberately excluded

Review and CXO roles get `WebSearch` but NOT `WebFetch`. `WebFetch` lets a
subagent-controlled URL pull arbitrary content — a prompt-injection-to-exfiltration
vector (CISO finding, /consensus 462 R1). `WebSearch` queries are operator-attestable
and a fundamentally different surface, so it is retained.

## 2. Autonomy-conditional isolation (rows 16, 17)

`implementer` and `spec-author` carry `isolation: worktree` as a **default only when
the configured autonomy level is L3+**. This mirrors Spec 454: at L0–L2 the multi-tab
substrate is canonical and Agent-tool dispatch runs in-parent; at L3+ native worktree
isolation is canonical.

- **L3+** (FORGE's current level — see `Current autonomy level:` in AGENTS.md):
  `isolation: worktree` is present on rows 16/17.
- **L0–L2**: no `isolation:` line is set on rows 16/17. Agent-tool dispatch defaults
  to in-parent.

The autonomy level is read from AGENTS.md (`Current autonomy level: **L<N>**`). If
AGENTS.md is absent or malformed, the fixture treats the level as L0 (most
conservative — no isolation default required).

**Operator opt-in at L0–L2**: explicitly add `isolation: worktree` to the agent file
for a specific dispatch. The fixture treats this as a valid operator override and
PASSes (logging the override).

## 3. `forge.agents.model_tier_override` — the single knob

Editing 17 files to change tiers is friction. AGENTS.md exposes one optional config
key that documents a global tier override:

```yaml
forge:
  agents:
    model_tier_override: null   # null | haiku | sonnet | opus | inherit
```

Set `model_tier_override: haiku` to declare that all agent roles should drop to the
cheaper tier for cost-sensitive runs — one key instead of 17 file edits. This is
**operator policy, not mechanical enforcement**: Claude Code's model picker can still
override at session level, and the per-file `model:` lines remain the as-shipped
default. The override is the documented bulk-cost-revert path (COO single-knob
concern, /consensus 462 R1).

## 4. Opt-out paths

Three operator opt-outs are supported:

1. **`model: inherit`** — set on any agent row to use the operator's session-default
   model instead of the spec's assignment. The fixture accepts `inherit` as a valid
   `model:` value.
2. **`forge.agents.model_tier_override: <tier>`** in AGENTS.md — sets a single global
   override (see §3). The bulk-revert mechanism.
3. **Remove `isolation: worktree` from rows 16/17** — even at L3+, if the operator
   wants in-parent edits. Run the fixture with
   `AGENT_FIXTURE_ALLOW_ISOLATION_DEVIATION=1` so it accepts the deviation and PASSes
   (logging the operator override) instead of failing the L3-expects-isolation check.

## 5. `disallowedTools` vs `tools` precedence

Some files (`devils-advocate.md`, `cto.md`, `competitor.md`, and others) carry BOTH a
positive `tools:` allowlist AND a `disallowedTools: [Write, Edit, NotebookEdit]` line.

- The positive `tools:` allowlist is **authoritative** for this spec's assertions: it
  enumerates exactly what the subagent may use.
- The `disallowedTools:` line is preserved as **defense in depth** — it explicitly
  denies write tools even though they are already absent from the positive allowlist.
- Spec 462 never removes a `disallowedTools:` line. The positive allowlist is
  additive, not a replacement.

## 6. The `AGENT_FIXTURE_ALLOW_ISOLATION_DEVIATION` flag

The behavioral fixture
(`.forge/bin/tests/test-spec-462-agent-frontmatter.{sh,ps1}`) reads `forge.autonomy`
from AGENTS.md and asserts the correct isolation state on rows 16/17. To let an
operator deviate (opt-out #3 above) without the fixture failing:

```bash
AGENT_FIXTURE_ALLOW_ISOLATION_DEVIATION=1 bash "${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/tests/test-spec-462-agent-frontmatter.sh"
```

With the flag set, a row-16/17 isolation state that disagrees with the autonomy level
is logged as an operator override and PASSes instead of FAILing.

## 7. Rollback recipes

- **Revert tiering to operator default**: set `forge.agents.model_tier_override:
  inherit` in AGENTS.md (one key), or set `model: inherit` per file.
- **Revert isolation at L3+**: remove the `isolation: worktree` line from
  `implementer.md` / `spec-author.md` (both mirrors) and run the fixture with
  `AGENT_FIXTURE_ALLOW_ISOLATION_DEVIATION=1`.
- **Revert tool allowlists entirely**: delete the `tools:` line from the affected
  agent files (both mirrors). The subagent then inherits the full default toolset.
  The preserved `disallowedTools:` lines still deny write tools.
- **Full rollback**: `git revert` the Spec 462 implementation commit. All 34 agent
  files, `cxo-rubric.md`, this guide, the AGENTS.md key, and the fixtures revert
  together.

## 8. CXO rubric reference

The 11 CXO files no longer restate the shared review rubric inline. Each references
`docs/process-kit/cxo-rubric.md` (the single source for problem framing, output-block
convention, recommendation taxonomy, and confidence labels). Each CXO file keeps only
its role-specific Key Questions, Constraints, role-specific output lines, and
narrative. No new skill was created — the rubric is a markdown reference, not a
preloaded capability (MT finding, /consensus 462 R1).

## 9. Refusal fallback for security-flavored work (F5-5)

Benign security work — CISO dispatch, `/security-review` usage, dependency/CVE
analysis, incident-class work (Spec 519 territory) — can false-positive on
frontier-model cyber safety classifiers (`stop_reason: "refusal"`). Fable 5 enforces
these most strictly; Sonnet 5 ships with milder cyber safeguards on by default;
Opus 4.8 carries no such constraint.

Operating guidance:
- **Session-level**: if a security-flavored role refuses or stalls on legitimate
  review content, re-run it on Opus 4.8 (also cheaper — advisory roles don't need
  Fable 5). The CISO role file carries this note inline.
- **API-level**: anything FORGE ever builds against the API for security-flavored
  calls should pass server-side `fallbacks: [{model: "claude-opus-4-8"}]` by default
  (beta feature — verify the header at implementation time).
- **Prompt hygiene**: never instruct a role to "show your thinking" or transcribe
  chain-of-thought into response text — that can trip the `reasoning_extraction`
  refusal category. Structured rationale fields (the cxo-rubric output blocks) are
  the correct channel.

Provenance: F5-5 in `docs/digests/fable5-adaptation-recommendations.md` (v4).
Originally dispositioned 2026-07-02 as "folded into Spec 519 follow-up" but never
written (SIG-INTAKE-0706-01); landed 2026-07-06 via research-intake small-change.
