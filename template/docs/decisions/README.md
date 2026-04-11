# Decisions

Architecture Decision Records (ADRs) capture important design choices that affect implementation. Based on the Nygard/Fowler ADR format.

## Creating a new ADR

Use the `/decision` slash command:
```
/decision <short title or description>
```

This scans existing ADRs for the next number, fills the template, and writes the file.

Alternatively, copy `_template.md` manually and fill in the sections.

## Conventions

- Template: `_template.md`
- Filename format: `ADR-NNN-short-title.md`
- Status values: `proposed`, `accepted`, `deprecated`, `superseded`
- New ADRs start as `proposed` and move to `accepted` after team agreement

## ADRs
