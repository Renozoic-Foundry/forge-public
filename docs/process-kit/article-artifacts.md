# Article Artifact Convention

**Spec: 269**

This document defines the naming convention, format routing rules, and build process
for FORGE articles that produce multiple output formats.

## Overview

Each FORGE article exists in up to four formats:

| Format | Extension | Audience | Pipeline |
|--------|-----------|----------|----------|
| Markdown article | `.md` | Public (forge-public) | `sync-to-public.sh` |
| HTML presentation | `-executive-summary.html` | Public (forge-public) | `sync-to-public.sh` |
| Word document | `.docx` | internal-distribution only | `<internal-builder>` |
| PowerPoint deck | `-executive-summary.pptx` | internal-distribution only | `<internal-builder>` |

**Key routing rule**: `.md` and `.html` go to `forge-public` (open source audience).
`.docx` and `.pptx` go to internal-distribution only (offline/editable formats for internal or
customer-facing use). The `.pptx` does NOT include a "Read the full article" link
(operator decision — it stands alone). The HTML DOES include the link.

## File naming

```
docs/articles/<slug>.md                          # the article
docs/articles/<slug>.docx                        # Word version
docs/articles/<slug>-executive-summary.pptx      # PowerPoint deck
docs/articles/<slug>-executive-summary.html      # HTML presentation
```

Where `<slug>` is a kebab-case identifier for the article, e.g. `debugging-in-forge`.

## Content architecture

Slide content (used by both the pptx and html builders) is defined once in a
shared Python module:

```
scripts/articles/<slug>.py
```

This module exports a `SLIDES` list — one dict per slide — consumed by:

- `scripts/build-article-pptx.py` — renders to PowerPoint
- `scripts/build-article-html.py` — renders to self-contained HTML

The `.docx` builder (`scripts/build-article-docx.py`) builds a narrative document
from article content; it does NOT consume the slides module.

## How to add a new article

### 1. Write the markdown article

Create `docs/articles/<slug>.md` as the authoritative source article.

### 2. Define slide content (shared module)

Create `scripts/articles/<slug>.py`. Copy `scripts/articles/debugging-in-forge.py`
as a template. Define:

```python
ARTICLE_SLUG = "<slug>"
ARTICLE_TITLE = "..."
ARTICLE_MD_PATH = "<slug>.md"

SLIDES = [
    { "type": "title",   "title": "...", "body": { ... } },
    { "type": "content", "title": "...", "kicker": "...", "body": { ... } },
    # ... up to N slides
    { "type": "closing", "title": "...", "body": { "paragraphs": [...], "full_article_md": "<slug>.md" } },
]
```

Supported slide types: `title`, `content`, `flow`, `cards`, `rows`, `stages`,
`metrics`, `two_col`, `dark`, `closing`.

### 3. Build the artifacts

```bash
# HTML presentation (goes to forge-public)
python scripts/build-article-html.py <slug>
# Output: docs/articles/<slug>-executive-summary.html

# PowerPoint (goes to internal-distribution only)
python scripts/build-article-pptx.py <slug>
# Output: docs/articles/<slug>-executive-summary.pptx

# Word document (goes to internal-distribution only)
python scripts/build-article-docx.py <slug>
# Output: docs/articles/<slug>.docx
```

### 4. Verify routing

```bash
# Confirm .md and .html appear in public sync, .docx and .pptx do not:
FORGE_PUBLIC=/tmp/test-sync bash scripts/sync-to-public.sh | grep <slug>

# Confirm .docx and .pptx are routed to your internal builder (project-specific).
```

### 5. Verify idempotency

```bash
python scripts/build-article-html.py <slug> --stdout > /tmp/run1.html
python scripts/build-article-html.py <slug> --stdout > /tmp/run2.html
diff /tmp/run1.html /tmp/run2.html  # should be empty
```

## Build dependencies

- `python-pptx` — required for `build-article-pptx.py`
- `python-docx` — required for `build-article-docx.py`
- `build-article-html.py` — stdlib only (no external dependencies)

```bash
pip install python-pptx python-docx
```

## The full-article link

The HTML presentation includes a "Read the full article" link on the closing slide.
The link path is the `.md` filename (relative, same directory) — e.g. `debugging-in-forge.md`.

This relative path resolves correctly in two contexts:
- **GitHub**: GitHub renders both files in the same directory; the relative link works.
- **Local file open**: `file:///path/to/docs/articles/foo-executive-summary.html` →
  `file:///path/to/docs/articles/foo.md` (same directory, relative link resolves).

The PowerPoint does NOT include this link. It is a standalone deck intended for
distribution outside of the repository context.

## Where builders live

All article build scripts live under `scripts/` (not `docs/articles/`):

```
scripts/
  build-article-html.py      # HTML presentation builder (stdlib only)
  build-article-pptx.py      # PowerPoint builder (python-pptx)
  build-article-docx.py      # Word document builder (python-docx)
  articles/
    debugging-in-forge.py    # Shared slide content module
    <slug>.py                # Add one per new article
```

Ad-hoc build scripts (`_build_*.py`, `_fix_header.py`) in `docs/articles/` are
deprecated and removed (Spec 269). All build logic lives under `scripts/`.

## Notes on the pptx vs. html design decision

The pptx builder is the canonical "slide design" authority — spacing, colors, and
layout are fine-tuned for PowerPoint rendering. The HTML builder replicates slide
content (via the shared module) but uses its own CSS layout. Minor visual differences
between the two formats are acceptable; content divergence is not.

If slide content needs to change, update `scripts/articles/<slug>.py` and rebuild
both the pptx and html. The docx is rebuilt independently (it is a narrative document,
not a slide deck).
