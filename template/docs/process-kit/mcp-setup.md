# MCP Documentation Server Setup Guide

This guide covers setup and configuration for the MCP servers declared in `.mcp.json`.

FORGE bootstraps two MCP servers for all projects.

---

## Included Servers

### Context7 (versioned library docs)

**Purpose:** Resolves versioned documentation for any third-party library. Use this before writing code against any library to get current API docs, not stale training data.

**Install:** No separate install required — runs via `npx`.

**Usage in Claude:**
```
Use context7 to look up the current API for <library>.
```

**How it works:**
1. Call `resolve-library-id` with the library name to get the Context7 library ID.
2. Call `get-library-docs` with the library ID and a topic to get current docs.

**Configuration:** No environment variables required. Declared in `.mcp.json` — no edits needed.

---

### Fetch (URL to markdown)

**Purpose:** Fetches any URL and returns content as markdown. Use for one-off lookups not covered by Context7 — RFCs, GitHub READMEs, blog posts, raw documentation pages.

**Install:** Requires `uv` / `uvx`:
```bash
# macOS / Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

**Usage in Claude:**
```
Use the fetch tool to retrieve https://example.com/docs/api.
```

**Configuration:** No environment variables required.


---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `npx: command not found` | Install Node.js: https://nodejs.org |
| `uvx: command not found` | Install uv: `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| Context7 returns stale docs | Run `/resolve-library-id` first to get the canonical library ID |
| Grounded Docs returns no results | Re-index: `uvx mcp-server-grounded-docs index docs/compliance/standards/` |
| Ansvar returns 401 | Check `ANSVAR_PROFILE` env var matches your registered profile |
