# Framework: FORGE
# Signals Log — Unified Cross-Session Signal Record

Migrated from legacy EA-NNN (error) and CI-NNN (insight) formats. All new entries use SIG-NNN.

## Purpose

Capture errors, insights, decisions, corrections, and retrospective findings across all sessions. Signals are reviewed by `/matrix` to detect patterns, inform Evolve Loop re-scoring, and trigger process specs.

## Format

```
### SIG-NNN: <one-line summary>
- **Date**: YYYY-MM-DD
- **Session**: NNN
- **Spec**: NNN (or "session-wide")
- **Type**: error | insight | retro-content | retro-process | retro-architecture | bug | decision | feedback
- **Source**: chat | test | harness | review | retro | harvest
- **Details**: <2-3 sentences>
- **Action**: spec trigger NNN | process update | memory save | deferred | none
```

---

<!-- Signal entries will be appended here as they are captured -->
