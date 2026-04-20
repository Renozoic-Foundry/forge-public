# Prompt Caching — Consumer API Integration Guide

<!-- Last verified: 2026-04-16 against https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching -->

> Applies to: projects that call the Anthropic API directly (Python `anthropic` SDK or TypeScript `@anthropic-ai/sdk`).
>
> If you use Claude Code exclusively, prompt caching is handled automatically — no action needed. This guide is for **direct API integrations only**.

## What is prompt caching?

Anthropic's prompt caching lets you mark content blocks as cacheable with `cache_control: {"type": "ephemeral"}`. When the API sees the same cached block again within 5 minutes, it charges ~10% of the normal input token rate instead of the full rate — up to a 90% reduction on repeated static content.

Cache blocks must be at least **1024 tokens**. Smaller blocks are accepted but do not benefit from caching.

The cache TTL resets to 5 minutes on every cache **read** (not just writes). Keep sessions active and you can sustain cache hits across a long conversation.

### Extended TTL tier (1 hour)

Anthropic also offers a **1-hour cache tier** for workloads where the default 5-minute window is too short. Opt in by setting `"ttl": "1h"` on the `cache_control` block:

```json
{
  "type": "ephemeral",
  "ttl": "1h"
}
```

The 1-hour tier carries a higher cache-write cost than the 5-minute tier but extends the period during which reads qualify for the ~10% discount. Use it when sessions naturally exceed 5 minutes of idle time (e.g., review workflows, batch pipelines with human-in-the-loop gaps). Check the [Anthropic prompt caching docs](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching) for the authoritative TTL list and current pricing — tier availability and rates evolve.

---

## When to cache

Use the following heuristic before adding `cache_control` to a content block:

| Signal | Cache? | Reason |
|--------|--------|--------|
| Static system prompt > 1024 tokens | Yes | High reuse, never changes between requests |
| Long static document (spec, schema, codebase context) | Yes | Same content sent every turn |
| Short system prompt < 1024 tokens | No | Below minimum cacheable size |
| Per-turn user message | No | Changes every request |
| Tool definitions (if large and static) | Yes | Reused across all turns in a session |
| Session state / dynamic context | No | Changes every request |
| File content loaded once per session | Yes (if > 1024 tokens) | Same bytes every turn |

**Rule of thumb**: _static + reused + long = cache it. Dynamic or short = don't._

---

## Multi-turn pattern

Cache the system prompt once at the start of the conversation. Keep user messages and tool results uncached.

```
Turn 1: [SYSTEM: cached] + [USER: not cached] → cache WRITE (full price)
Turn 2: [SYSTEM: cached] + [USER: not cached] → cache READ (~10% price)
Turn 3: [SYSTEM: cached] + [USER: not cached] → cache READ (~10% price)
...
```

The first turn always pays the full system-prompt cost (cache write). All subsequent turns within 5 minutes pay ~10%.

---

## Monitoring cache efficiency

Every API response includes a `usage` object with three fields relevant to caching:

| Field | Meaning |
|-------|---------|
| `cache_creation_input_tokens` | Tokens written to cache (first time; full price) |
| `cache_read_input_tokens` | Tokens read from cache (subsequent turns; ~10% price) |
| `input_tokens` | Tokens processed outside the cache (full price) |

A healthy multi-turn session shows `cache_read_input_tokens` growing and `cache_creation_input_tokens` stable after the first turn.

Log these fields per request to track cache efficiency over time. A `cache_read_input_tokens / (cache_creation_input_tokens + cache_read_input_tokens)` ratio above ~0.8 indicates good cache utilization in a typical session.

---

## Model support

Prompt caching requires a current Sonnet or Opus model. Haiku-tier models may or may not support caching — check the [Anthropic model documentation](https://docs.anthropic.com/en/docs/about-claude/models) for the definitive list at time of deployment. Never hard-code model IDs in long-lived scripts; use a configuration variable so you can update without changing application code.

---

## Common mistakes

1. **Caching content that changes per-turn** — the cache key is the full content hash; mutating content invalidates the cache entry and forces a re-write on every turn.
2. **Caching content under 1024 tokens** — accepted by the API but produces no savings; adds a small overhead instead.
3. **Letting the session go idle > 5 minutes** — the cache entry expires; the next request pays full write price again. For long-running workflows, design for periodic keep-alive calls or accept re-write cost.
4. **Marking multiple overlapping blocks as cached** — each `cache_control` boundary is a separate cache entry. Minimize the number of boundaries (typically one, at the end of your static system content).

---

## References

- [Anthropic prompt caching documentation](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
- [Anthropic model list](https://docs.anthropic.com/en/docs/about-claude/models)
- FORGE Spec 055 — Anthropic Prompt Caching (FORGE-internal session caching)
- FORGE Spec 271 — Prompt Caching Guidance for Consumer API Integrations (this guide)
