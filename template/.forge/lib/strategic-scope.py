#!/usr/bin/env python3
"""Spec 382 — yaml-aware reader/writer for forge.strategic_scope in AGENTS.md.

Subcommands:
  read <agents-md-path>
      Print the value of forge.strategic_scope (trim-normalized) to stdout.
      Exit 0 if value found and printed. Exit 1 if block missing or value absent.

  write <agents-md-path> <value>
      Update forge.strategic_scope to <value>. If <value> is "-", read from stdin.
      Exit 0 on success.

  is-sentinel <agents-md-path>
      Exit 0 if value equals literal "SKIP-FOR-NOW" (after trim). Exit 1 otherwise.
      Used by /matrix Step 8 to skip scope-fit eval cleanly.

Mechanism (Spec 382 AC6, AC9):
  Reader uses yaml.safe_load on the YAML fenced block containing
  forge.strategic_scope. Writer uses yaml.safe_load + targeted update +
  yaml.safe_dump round-trip. NEITHER reader nor writer uses regex on raw
  text — fragile against block-scalar variants (|, >, indentation) and
  produces false-positives on substring "SKIP-FOR-NOW" mid-paragraph.

Reader/writer mechanism parity (Spec 382 AC10): both read and write paths
use the same yaml.safe_load primitive — eliminates writer/reader coupling
drift between /onboarding (writer) and /matrix Step 8 (reader).
"""
import sys
import re

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Install via: python -m pip install pyyaml", file=sys.stderr)
    sys.exit(3)


SENTINEL = "SKIP-FOR-NOW"


def _find_yaml_block(content):
    """Find the YAML fenced block containing forge.strategic_scope.

    Returns (block_start, block_end, body) where block_start/end are byte
    offsets of the body content (between the fence markers), and body is
    the inner YAML string. Returns None if no matching block is found.

    The fence regex is intentionally narrow — we look for ```yaml ... ```
    blocks that contain the literal key forge.strategic_scope. We do NOT
    parse the whole file as YAML because AGENTS.md is markdown with multiple
    embedded YAML blocks.
    """
    pattern = re.compile(
        r'```yaml\s*\n'
        r'(?P<body>.*?\bforge\.strategic_scope:.*?)'
        r'\n```',
        re.MULTILINE | re.DOTALL,
    )
    m = pattern.search(content)
    if not m:
        return None
    return (m.start('body'), m.end('body'), m.group('body'))


def read_scope(path):
    """Return the value of forge.strategic_scope (trim-normalized), or None."""
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    found = _find_yaml_block(content)
    if not found:
        return None
    _, _, body = found
    try:
        parsed = yaml.safe_load(body)
    except yaml.YAMLError:
        return None
    if not isinstance(parsed, dict):
        return None
    value = parsed.get('forge.strategic_scope')
    if value is None:
        return None
    if isinstance(value, str):
        return value.strip()
    return None


def write_scope(path, new_value):
    """Update forge.strategic_scope to new_value via yaml round-trip."""
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    found = _find_yaml_block(content)
    new_value_str = str(new_value).strip()

    if not found:
        block = (
            '\n```yaml\n'
            '# Strategic scope — used by /matrix to evaluate spec fit (Spec 110)\n'
            f'forge.strategic_scope: |\n'
        )
        for line in new_value_str.splitlines() or ['']:
            block += f'  {line}\n'
        block += '```\n'
        with open(path, 'a', encoding='utf-8') as f:
            f.write(block)
        return

    start, end, body = found
    # Preserve leading comment lines (between ```yaml and first key)
    leading_comments = []
    for line in body.split('\n'):
        if line.strip().startswith('#') or line.strip() == '':
            leading_comments.append(line)
        else:
            break

    try:
        parsed = yaml.safe_load(body)
    except yaml.YAMLError:
        parsed = {}
    if not isinstance(parsed, dict):
        parsed = {}
    parsed['forge.strategic_scope'] = new_value_str

    # Reserialize: leading comments + scope-block-scalar + remaining keys
    new_lines = list(leading_comments)
    # forge.strategic_scope as block scalar
    if new_value_str == SENTINEL or '\n' not in new_value_str:
        # Single-line value — emit as plain scalar for cleanliness
        new_lines.append(f'forge.strategic_scope: {new_value_str}')
    else:
        new_lines.append('forge.strategic_scope: |')
        for vline in new_value_str.splitlines():
            new_lines.append(f'  {vline}')
    # Other keys (uncommon in the strategic_scope block but preserve if present)
    for key, val in parsed.items():
        if key == 'forge.strategic_scope':
            continue
        dumped = yaml.safe_dump({key: val}, default_flow_style=False).strip()
        new_lines.append(dumped)

    new_body = '\n'.join(new_lines)
    new_content = content[:start] + new_body + content[end:]
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_content)


def is_sentinel(path):
    value = read_scope(path)
    return value == SENTINEL


def main():
    if len(sys.argv) < 3:
        print("Usage: strategic-scope.py <read|write|is-sentinel> <agents-md-path> [value]", file=sys.stderr)
        sys.exit(2)

    cmd = sys.argv[1]
    path = sys.argv[2]

    if cmd == 'read':
        value = read_scope(path)
        if value is None:
            sys.exit(1)
        print(value)
        sys.exit(0)
    elif cmd == 'write':
        if len(sys.argv) < 4:
            print("Usage: strategic-scope.py write <path> <value-or-->", file=sys.stderr)
            sys.exit(2)
        value_arg = sys.argv[3]
        if value_arg == '-':
            value = sys.stdin.read()
        else:
            value = value_arg
        write_scope(path, value)
        sys.exit(0)
    elif cmd == 'is-sentinel':
        sys.exit(0 if is_sentinel(path) else 1)
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(2)


if __name__ == '__main__':
    main()
