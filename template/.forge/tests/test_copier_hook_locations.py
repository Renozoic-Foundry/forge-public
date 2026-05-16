"""Spec 446 — regression tests for copier-hooks reachability.

Asserts that:
- Hooks exist under BOTH scripts/copier-hooks/ (FORGE-internal) AND
  template/scripts/copier-hooks/ (consumer-shipped).
- The two copies are byte-identical (drift catches Spec 446 regression).
- copier.yml's _tasks: references the hook SCRIPT LOCATIONS via dst_path,
  not src_path (the original Spec 446 bug — src_path becomes a cleaned-up
  VCS clone before tasks fire).

Run:
    pytest .forge/tests/test_copier_hook_locations.py -v
"""
from __future__ import annotations

import hashlib
from pathlib import Path

import pytest


_THIS = Path(__file__).resolve()
for candidate in (_THIS.parents[2], _THIS.parents[1]):
    if (candidate / "copier.yml").is_file():
        REPO_ROOT = candidate
        break
else:
    pytest.skip("copier.yml not found in any expected layout", allow_module_level=True)

HOOKS = ("forge_consent_gate.py", "scrub_answers.py")


def _sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


@pytest.mark.parametrize("hook", HOOKS)
def test_hook_exists_at_both_locations(hook):
    """AC 1 + AC 2: hook present under scripts/copier-hooks/ AND template/scripts/copier-hooks/."""
    root_copy = REPO_ROOT / "scripts" / "copier-hooks" / hook
    template_copy = REPO_ROOT / "template" / "scripts" / "copier-hooks" / hook
    assert root_copy.is_file(), f"missing root copy: {root_copy}"
    assert template_copy.is_file(), f"missing template copy: {template_copy}"


@pytest.mark.parametrize("hook", HOOKS)
def test_hook_byte_identical(hook):
    """AC 1 + AC 2: the two copies match byte-for-byte. Drift would resurrect the bug."""
    root_copy = REPO_ROOT / "scripts" / "copier-hooks" / hook
    template_copy = REPO_ROOT / "template" / "scripts" / "copier-hooks" / hook
    assert _sha(root_copy) == _sha(template_copy), (
        f"DRIFT: {hook} differs between scripts/copier-hooks/ and "
        f"template/scripts/copier-hooks/. The template copy is what consumers "
        f"actually run at task time — keeping these in sync prevents Spec 446 regression."
    )


def test_copier_yml_uses_dst_path_for_hook_locations():
    """AC 3 (refined): copier.yml _tasks must reference hook SCRIPT LOCATIONS via
    dst_path, not src_path. Src_path becomes a cleaned-up VCS clone before tasks
    fire (the original Spec 446 bug). Note: src_path may legitimately appear as a
    SCRIPT ARGV (e.g., scrub_answers.py receives src_path as argv[2] for reading
    template defaults — gracefully no-ops if unreachable). This test specifically
    targets the `/scripts/copier-hooks/<hook>.py` script-location pattern.
    """
    text = (REPO_ROOT / "copier.yml").read_text(encoding="utf-8")
    for hook in HOOKS:
        bad_pattern = f"_copier_conf.src_path }}}}/scripts/copier-hooks/{hook}"
        good_pattern = f"_copier_conf.dst_path }}}}/scripts/copier-hooks/{hook}"
        assert bad_pattern not in text, (
            f"copier.yml references {hook} via src_path — this breaks when the "
            f"template is sourced from a VCS clone (Spec 446)."
        )
        assert good_pattern in text, (
            f"copier.yml must reference {hook} via dst_path so the rendered hook "
            f"in the destination is what runs at task time (Spec 446 Req 3)."
        )


def test_template_hook_path_renders_into_destination():
    """After rendering, the hook MUST be reachable at <dst>/scripts/copier-hooks/<hook>.
    This is enforced structurally: the template ships the hooks under
    template/scripts/copier-hooks/, so copier renders them into <dst>/scripts/copier-hooks/.
    """
    for hook in HOOKS:
        template_copy = REPO_ROOT / "template" / "scripts" / "copier-hooks" / hook
        # The path under template/ MUST be exactly scripts/copier-hooks/<hook>
        # for the dst_path reference in copier.yml to resolve correctly after render.
        relative = template_copy.relative_to(REPO_ROOT / "template")
        assert relative.as_posix() == f"scripts/copier-hooks/{hook}"
