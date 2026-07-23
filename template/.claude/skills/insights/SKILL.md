---
name: insights
description: "[deprecated] Folded into /evolve --insights (Spec 587 — native Claude Code collision)"
disable-model-invocation: false
---

# Framework: FORGE
**Deprecated (Spec 587, S2 MINOR — not removed):** Claude Code ships a native built-in
`/insights` (30-day usage HTML report). The built-in owns the un-namespaced spelling, so this
name folded into `/evolve --insights` (the process-mining body, reachable and unaffected by the
native collision). Read `.forge/commands/evolve.md` and execute its `--insights` mode (Step
INSIGHTS), passing `$ARGUMENTS` through unchanged. Then stop.
