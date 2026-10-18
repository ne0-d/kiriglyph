"""Checked-in protocol goldens must match a fresh encoder run."""

from __future__ import annotations

import importlib.util
from pathlib import Path

_GENERATOR_PATH = Path(__file__).with_name("regenerate_golden.py")
_SPEC = importlib.util.spec_from_file_location("regenerate_golden", _GENERATOR_PATH)
assert _SPEC is not None and _SPEC.loader is not None
_GENERATOR = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_GENERATOR)


def test_checked_in_goldens_match_fresh_worker_output():
    expected = _GENERATOR.golden_lines()
    golden_dir = _GENERATOR.GOLDEN_DIR
    checked_in = {
        path.name: path.read_text(encoding="utf-8")
        for path in golden_dir.glob("*.ndjson")
    }

    assert checked_in == expected
    mask = golden_dir / "masks" / _GENERATOR.MASK_PNG_NAME
    assert mask.read_bytes() == _GENERATOR.mask_png_bytes()
