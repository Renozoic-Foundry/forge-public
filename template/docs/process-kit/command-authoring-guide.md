# Command Authoring Guide — Default-Path-First Architecture

> **Spec 265** — established the default-path-first principle for FORGE command `.md` files.

## Why this matters

FORGE commands are monolithic prompt files. Unlike compiled code — where only the executed branch runs — a language model processes the entire document when it loads a command file. Every branch the file contains is loaded into context, whether that branch will execute or not.

This creates a specific failure mode: **negative output instructions are cognitively weaker than positive output instructions**. When branch A says "print X" and branch B says "do not mention X," the model has already loaded X into context and gravitates toward narrating it. Spec 155 tried to fix `/spec` narration with an explicit "Do not mention Spec Kit" instruction; the fix did not hold because the structure still exposed Spec Kit content on every read.

The fix is structural, not instructional. **Keep non-default content out of the model's reading path entirely.**

## The principle

1. **Main body = default path only.**
   The top of the file describes the common / most frequent execution path. No conditionals, no routing, no mention of alternative paths, no negative output instructions.

2. **Addenda for non-default paths.**
   Feature-gated or configuration-dependent behavior lives in a clearly separated `## Addendum: <name>` section **after** the main flow. The addendum opens with a positive gate that a model can honor by stopping reading:

   > Only execute this section if AGENTS.md has `<feature>.enabled: true` AND <precondition>. Otherwise, do not read further.

3. **Positive gates, not negative ones.**
   "Execute if X" halts cleanly when X is false. "Do not mention Y" requires the model to actively suppress content it has already loaded — structurally fragile.

4. **No negative output instructions inside default branches.**
   If content Y would trigger narration, remove Y from the path the model reads; do not add a "do not print Y" instruction next to it.

## What this replaces

Commands historically used a "route first, then branch" structure:

```
Step 0 — Detect configuration.
  If feature X enabled: run Guided Flow (Steps A–F).
  If feature X not configured: run Manual Flow (Steps 1–9). Do not mention X.
  If feature X enabled but dependency missing: run Fallback (print warning).
```

Under this structure, the model reads all three paths on every invocation. Spec Kit content, fallback warnings, and error messages all live in the model's context even on runs where feature X is not configured. Suppression instructions fail probabilistically.

Under default-path-first, the same command becomes:

```
(Main body — Manual Flow, Steps 1–9)
...

## Addendum: Guided Flow (feature X)

Only execute this section if AGENTS.md has `feature_x.enabled: true` AND <preconditions>. Otherwise, do not read further.

(Steps A–F, fallback logic, warnings)
```

On a project without feature X, the model reads the main body, hits the addendum gate, does not proceed. It never loads the Guided Flow, the fallback language, or the warnings. There is nothing to narrate.

## Authoring checklist

When writing or reviewing a command file:

- [ ] The main body describes only the default execution path.
- [ ] No conditionals in the main body that branch on optional features or configuration.
- [ ] No mention of alternative paths, flows, or feature names in the main body.
- [ ] No "do not print," "do not mention," "skip silently" instructions in the main body.
- [ ] Non-default content is relocated to `## Addendum: <name>` sections placed after the main flow.
- [ ] Each addendum opens with a positive gate phrased as "Only execute this section if … Otherwise, do not read further."
- [ ] Addendum gates key on observable preconditions (AGENTS.md settings, MCP tool availability, explicit flags) — not on the model's self-judgment.
- [ ] Global anti-narration rules in `CLAUDE.md` are relied upon for cross-command consistency, not restated inline.

## Reference implementation

`/spec` (see `template/.claude/commands/spec.md`) is the first command refactored to this pattern. Manual Flow is the main body; the Spec Kit Guided Flow is an addendum gated on `spec_kit.enabled: true` plus MCP availability. Consumers without Spec Kit configured see no Spec Kit content, no routing narration, and no mention of "manual flow" (there is no alternative to contrast against in the default path).

## Explicit user-facing errors for invalid flag combinations

> **Spec 282** — pattern for handling flags whose behavior lives in a gated addendum.

The default-path-first pattern (Spec 265) relocates non-default behavior into addenda guarded by positive gates. This keeps unused content out of the model's reading path — but it introduces a UX gap: **flags that invoke addendum behavior become silent no-ops when the addendum gate fails.** A user who typed `/cmd --feature` gets the default flow with no explanation, because the model stopped reading before it reached the code that would have explained the refusal.

The fix is a pre-addendum flag gate at the top of the main body:

```
## [mechanical] Step 0X — `--feature` flag gate

If $ARGUMENTS contains `--feature`: evaluate the same precondition the addendum gates on.

- If preconditions hold: proceed silently to the addendum.
- If preconditions fail: print exactly this one-line notice, then continue with the default flow:

  > `--feature` flag ignored: <feature> is not configured for this project. Running standard `/cmd` flow. See <config doc path> to enable <feature>.

If $ARGUMENTS does not contain `--feature`: continue with the default flow.
```

### Rules for this pattern

- **Positive instruction only.** Write "print X when condition Y" — never "do not print Z" or "skip silently". The anti-narration directive (Spec 265) permits explicit `print`/`report` output; it prohibits negative suppression instructions in the default branch.
- **Narrow condition.** Print the notice only for the exact flag-on-unconfigured combination. Silent pass-through on all other paths (flag absent, flag present and gate passes, different flag, etc.).
- **One line, positive framing.** The notice states what happened and what to do next — no internal vocabulary ("gate failed", "checking for flag"), no long paragraphs.
- **Link to setup docs.** The notice points at a concrete config document the user can act on.
- **Do not halt.** The notice is informational; the command continues through the default flow. Users get the behavior a bare `/cmd` would have produced, plus one line explaining why their flag was ignored.

### When to apply

Add this pattern whenever a command file both (a) uses default-path-first architecture with an addendum gate, and (b) accepts a flag whose intended behavior lives inside that addendum. Without the pre-addendum gate, the flag silently no-ops on projects where the addendum precondition fails.

## Related

- Global anti-narration directive — see `template/CLAUDE.md.jinja` § Command execution discipline
- Spec 155 (closed) — prior attempt at `/spec` narration suppression, superseded by structural relocation
- Spec 265 (this spec) — default-path-first principle and `/spec` refactor
- Spec 282 — explicit user-facing errors for invalid flag combinations (pattern above)
