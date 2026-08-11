<!-- Last updated: 2026-06-24 -->
# Framework: FORGE
# Positive-signal taxonomy (Spec 497)

FORGE's signal capture was historically ~54:1 failure-biased: error autopsies, chat
insights, and `[content|process|architecture|trust]` signals all record what went *wrong*
or what *needs changing*. There was no bucket for what went *right*. That asymmetry means
wins are never reinforced — a pattern, decision, gate, or tool that paid off is forgotten
instead of repeated. The `[positive]` signal category closes that gap.

This is the companion to `docs/process-kit/signal-quality-guide.md` (which governs the
failure-classification fields). It defines the positive bucket: when to capture, the entry
shape, and how `/evolve` reviews positives alongside negatives.

## When to capture a positive signal

At `/close` retro (Step 6), draft a `[positive]` SIG for each **genuine, repeatable win** this
cycle. Zero is acceptable — do not manufacture wins. A good positive signal is one where, if
you could make it happen again on the next spec, you would. Examples:

- A gate or check caught something early and cheaply (the gate earned its cost).
- A design decision made the implementation simpler than expected.
- A tool, helper, or workflow shortcut removed real friction.
- A spec was unusually clean to implement because of how it was written — worth copying.

Not positive signals: routine success ("tests passed"), restating the AC, or praise with no
repeatable mechanism behind it. The test is **"what made this work, and can we do it on
purpose next time?"**

## Entry shape

A `[positive]` entry replaces the three failure-classification fields (Root-cause category /
Wrong assumption / Evidence-gate coverage — which describe *failures*) with positive fields:

```
### SIG-NNN-XX — <title>
- Date: YYYY-MM-DD
- Type: [positive]
- Spec: NNN
- Impact: <low|medium|high>
- Observation: <the win — what worked well>
- Why it worked: <the enabling pattern, decision, gate, or tool>
- Keep/amplify: <how to repeat or institutionalize it>
```

`Why it worked` is the load-bearing field: it names the **reusable cause**, which is what
`/evolve` clusters on. `Keep/amplify` is the action — make-it-a-habit, add-to-a-checklist,
graduate-to-memory, or propose-a-spec.

## How `/evolve` reviews positives

`/evolve` F-loop signal analysis (Step 8j) clusters `[positive]` entries by their `Why it
worked` factor — the same ≥2-keyword-overlap rule used for problem clustering — and emits a
Positive-Signal Review table. A win recurring **≥2 times** is a durable, repeatable success:
`/evolve` recommends graduating it into project memory or a strategy/process-kit doc so the
pattern is reused deliberately rather than rediscovered.

If no positives were captured since the last review, `/evolve` emits a one-line nudge ("wins
may be going unrecorded") — advisory, never blocking. The goal is to bend the long-run
positive:negative ratio away from 54:1, measured over successive `/evolve` cycles (a
qualitative trend, not a hard target).

See also: `docs/process-kit/signal-quality-guide.md` (failure-side taxonomy),
`docs/process-kit/operator-summary-guide.md` (the four-part summary that surfaces wins),
`docs/sessions/signals.md` (the unified signal record).
