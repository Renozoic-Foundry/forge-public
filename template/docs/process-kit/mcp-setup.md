# MCP Documentation Server Setup Guide

This guide covers setup and configuration for the MCP servers declared in `.mcp.json`.

FORGE bootstraps two Lane A servers for all projects, and two optional Lane B servers for compliance-profile projects.

---

## Lane A — All Projects

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

## Lane B — Compliance-Profile Projects

These servers are only included when `compliance_profile` is set to a non-`none` value during `cruft create`.

### Ansvar EU Regulations

**Purpose:** Authoritative text lookup for EU regulations — Machinery Regulation (EU 2023/1230), Medical Device Regulation (MDR 2017/745), AI Act, and others. Required for any spec that touches EU compliance requirements.

**Install:**
```bash
npm install -g ansvar-mcp
```

**Environment variable:**
- `ANSVAR_PROFILE` — set to your compliance profile (e.g., `eu-machinery`, `iso-13485`). This is automatically set from the `compliance_profile` Copier variable.

**Usage rule (mandatory):**
> Before citing any EU regulation text, query Ansvar for the current article text. Never paraphrase from training data. Cite the article number, paragraph, and subparagraph in every spec or commit that touches a regulatory requirement.

**Verify setup:**
```bash
npx ansvar-mcp --version
```

---

### Grounded Docs (purchased IEC/ISO standards)

**Purpose:** Provides lookup capability over purchased IEC, ISO, and EN standards PDFs stored locally. Use for standards that cannot be served via public URLs (IEC 62443, ISO 13485, EN ISO 10218, etc.).

**Install:**
```bash
pip install mcp-server-grounded-docs
# or
uvx mcp-server-grounded-docs --help
```

**Setup steps:**

1. Create the standards directory:
   ```bash
   mkdir -p docs/compliance/standards
   ```

2. Copy your purchased PDFs into `docs/compliance/standards/`:
   ```
   docs/compliance/standards/
     IEC-62443-3-3-2013.pdf
     ISO-13485-2016.pdf
     EN-ISO-10218-1-2011.pdf
   ```

3. Add to `.gitignore` (PDFs are copyrighted — never commit them):
   ```
   docs/compliance/standards/*.pdf
   ```

4. Index the standards (run once, re-run when PDFs change):
   ```bash
   uvx mcp-server-grounded-docs index docs/compliance/standards/
   ```

**Environment variable:**
- `GROUNDED_DOCS_DIR` — automatically set to `${workspaceFolder}/docs/compliance/standards` in `.mcp.json`.

**Usage rule (mandatory):**
> Before citing any clause from a purchased standard, query Grounded Docs for the current section text. Cite the standard number, edition year, section, and clause in every spec or commit that touches a standards requirement.

**Verify setup:**
```bash
uvx mcp-server-grounded-docs list docs/compliance/standards/
```

---

## Enforcement Rule

For compliance-profile projects, the following rule applies to all agent sessions:

1. **Query first, cite precisely** — before implementing or reviewing any code that relates to a regulatory or standards requirement, query the relevant MCP server for the current text.
2. **Never paraphrase from training data** — training data may be outdated, abridged, or incorrect. Always verify against the live source.
3. **Include the citation** — every spec AC and commit message touching a compliance requirement must include the standard/article reference (e.g., `EU 2023/1230 Art. 10(1)(b)` or `IEC 62443-3-3 SR 2.1`).
4. **Profile verification check** — verify `docs/compliance/profile-verification.md` exists and is not expired before generating any compliance artifact. If missing or expired, halt and request human review.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `npx: command not found` | Install Node.js: https://nodejs.org |
| `uvx: command not found` | Install uv: `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| Context7 returns stale docs | Run `/resolve-library-id` first to get the canonical library ID |
| Grounded Docs returns no results | Re-index: `uvx mcp-server-grounded-docs index docs/compliance/standards/` |
| Ansvar returns 401 | Check `ANSVAR_PROFILE` env var matches your registered profile |
