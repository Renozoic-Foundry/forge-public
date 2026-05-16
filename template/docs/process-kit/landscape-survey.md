# Landscape Survey — Operator Guide (Spec 273)

This guide explains how to maintain the landscape-survey pipeline that scans the AI
development ecosystem and methodology updates on FORGE's behalf, routing results into
the existing digest + watchlist surfaces (`/brainstorm` consumes them as usual).

## Architecture in 3 sentences

Two scheduled remote agents (daily for AI dev, weekly for methodology) fetch from a
versioned source allowlist, apply a normalized novelty filter and FORGE-relevance keyword
filter, and emit digest files / watchlist entries / silence-log lines accordingly. The
agents are **producers only** — they never modify `/brainstorm`, `/evolve`, `/now`, or
the spec/backlog surfaces. The operator-in-the-loop via `/brainstorm` stays authoritative.

## Files in the pipeline

| Path | Purpose |
|------|---------|
| `.forge/config/landscape-sources.yaml` | Source allowlist (HTTPS-only; spec-gated edits) |
| `.forge/config/landscape-agent-prompts/daily.md` | Agent prompt for daily AI-dev cadence |
| `.forge/config/landscape-agent-prompts/weekly.md` | Agent prompt for weekly methodology cadence |
| `scripts/landscape-novelty-filter.sh` (`.ps1`) | Encoded matching algorithm + 6 unit tests |
| `scripts/landscape-validate-sources.sh` | Schema + HTTPS validator (run at /implement) |
| `scripts/landscape-validate-prompts.sh` | Prompt-scope guard (run at /implement) |
| `scripts/landscape-scan.sh` (`.ps1`) | Local dry-run entry point + production fallback |
| `docs/sessions/landscape-scan-log.md` | Append-only silence-with-trail log (every run) |
| `.forge/state/trigger-registration-landscape.log` | Reproducibility record of /schedule create calls |
| `tests/fixtures/landscape/` | Fixtures for AC tests |

## Maintaining the source list

Editing `landscape-sources.yaml`:

- **Adding a new source** is a spec-gated change (small-change lane is acceptable). Reason:
  the source list is an SSRF / exfiltration channel surface — every URL is one the agent
  will fetch and pipe through its prompt. Reviewer should sanity-check the URL belongs
  to a reputable origin and matches the relevance scope.
- **Removing or fixing a stale source** is a non-spec maintenance edit. Just edit the YAML.
- **All URLs must be `https://`** — validator (`landscape-validate-sources.sh`) rejects
  `http://`, `file://`, `git+ssh://`, etc.
- **Required fields per entry**: `name`, `url`, `type`, `relevance`, `added`.

After editing, re-run the validator:

```bash
bash scripts/landscape-validate-sources.sh
```

## Tuning the filters

### FORGE-relevance keyword set (relevance filter)

Lives in the agent prompt files (`daily.md`, `weekly.md`) — not a separate config — so it
travels with the prompt. Edit the keyword list directly when FORGE's scope shifts.

**When to edit**: if a new framework class (e.g., "graph-based agents") becomes scope-
relevant, add the canonical keyword. If a class drops from scope, remove the keyword
(items mentioning it will start being dropped as off-topic).

### Novelty filter

Encoded in `scripts/landscape-novelty-filter.sh`. The matching algorithm (R2 DA-mandated):

1. Normalize: lowercase, strip punctuation, collapse whitespace, strip trailing version suffix.
2. Tokenize: split on whitespace; tokens of length ≥ 3 are "significant".
3. Match rule: subject is a duplicate if (i) normalized subject is a substring of any
   reference, OR (ii) ≥ 2 significant tokens fall within a 5-word window in the same
   reference.
4. Version-bump path: if the subject had a trailing version suffix and matches an existing
   entry exactly via substring rule, return `version-bump:<entry>` so the agent appends a
   note rather than creating a new entry.

Tweak `WINDOW`, `MIN_TOKEN`, or `had_version_suffix` regex if false-positives or
false-negatives become a problem. Re-run the unit tests:

```bash
bash scripts/landscape-novelty-filter.sh --self-test
```

There are 6 cases. Add new fixtures alongside `tests/fixtures/landscape/` if you change
the algorithm.

## Operator spot-check (Spec 273 Req 18)

Quarterly: review the most recent `docs/digests/digest-*-daily.md` and `digest-*-weekly.md`
files. Sanity-check that recent novel entries reflect actual landscape activity. If you
notice a release you're aware of being silently absent (false-negative), the novelty
filter or relevance keywords likely need tuning.

The watchlist entry `landscape-survey signal review` (added at /implement) carries the
trigger `90 days since last manual landscape-survey verification`, so `/now` will surface
the reminder when due.

## Failure modes & remediation

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Same item digesting daily | Novelty filter not seeing prior digest in `reviewed.md` | Confirm `/brainstorm --digest` is updating `docs/digests/reviewed.md` after review |
| Real release missing from digest | Source feed not in allowlist, or relevance keywords too strict | Add source via spec; expand keywords in agent prompts |
| `source-unreachable` recurring | Feed defunct | Remove source from `landscape-sources.yaml` |
| Empty digests appearing | Bug — agent ignored silence-with-trail rule | File a hotfix; agent prompt must be amended |
| Cost-visibility tokens always "unknown" | Remote runtime not surfacing token data | Acceptable; backfill manually if cost reporting needed |

## Live trigger registration

After /close on Spec 273 the triggers are registered manually:

```bash
/schedule create forge-landscape-daily \
  --cron "0 8 * * 1-5" \
  --prompt-file .forge/config/landscape-agent-prompts/daily.md

/schedule create forge-landscape-weekly \
  --cron "0 18 * * 0" \
  --prompt-file .forge/config/landscape-agent-prompts/weekly.md
```

Verify with `/schedule list`. Append the registration command and timestamp to
`.forge/state/trigger-registration-landscape.log` for reproducibility.

## Why daily for AI-dev and weekly for methodology

AI tooling release pace is on the order of days (Claude Code, Cursor, Cline ship rapidly).
Methodology updates (Scrum, IEC 61508 revisions) are on the order of months. Cadence
matches signal arrival rate. If 90 days of operation show < 1 novel daily-cadence item per
week, file a follow-up spec to downgrade daily → weekly (Spec 273 R2 MT measurement-gated
fallback).
