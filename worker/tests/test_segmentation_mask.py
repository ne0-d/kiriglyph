from __future__ import annotations

import stat
import time
from pathlib import Path

import numpy as np
from PIL import Image

from worker.segmentation_contract import MaskOutcome
from worker.segmentation_mask import MaskFileStore, analyse_mask


def test_empty_mask_is_typed_empty():
    stats = analyse_mask(np.zeros((10, 12), dtype=bool))

    assert stats.outcome is MaskOutcome.EMPTY
    assert stats.bounds is None
    assert stats.components.count == 0


def test_full_mask_is_suspect_and_touches_every_edge():
    stats = analyse_mask(np.ones((10, 12), dtype=bool))

    assert stats.outcome is MaskOutcome.SUSPECT_FULL_IMAGE
    assert stats.touches_edge.any is True
    assert stats.touches_edge.left is True
    assert stats.touches_edge.right is True
    assert stats.area_fraction == 1


def test_mask_stats_report_edge_touch_and_largest_component():
    mask = np.zeros((10, 12), dtype=bool)
    mask[0:3, 0:4] = True
    mask[6:8, 8:10] = True

    stats = analyse_mask(mask)

    assert stats.outcome is MaskOutcome.OK
    assert stats.touches_edge.left is True
    assert stats.touches_edge.top is True
    assert stats.multiple_components is True
    assert stats.components.count == 2
    assert stats.components.largest_bounds is not None
    assert stats.components.largest_bounds.to_json() == {
        "x": 0,
        "y": 0,
        "width": 4,
        "height": 3,
    }


def test_mask_store_writes_private_png_and_cleans_up(tmp_path: Path):
    store = MaskFileStore(tmp_path)
    mask = np.zeros((4, 5), dtype=bool)
    mask[1:3, 2:4] = True

    reference = store.write(mask)

    path = Path(reference.path)
    assert path.exists()
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    assert reference.byte_length == path.stat().st_size
    image = Image.open(path)
    assert image.mode == "RGBA"
    alpha = np.asarray(image)[..., 3]
    assert np.array_equal(alpha, mask.astype(np.uint8) * 255)
    assert np.all(np.asarray(image)[..., :3] == 255)

    store.cleanup()

    assert not path.exists()


def test_mask_stats_performance_on_large_mask():
    mask = np.zeros((1440, 2560), dtype=bool)
    mask[300:900, 700:1500] = True
    mask[50, 50] = True

    start = time.perf_counter()
    stats = analyse_mask(mask)
    elapsed_ms = (time.perf_counter() - start) * 1000

    assert stats.components.count == 2
    assert elapsed_ms < 300
