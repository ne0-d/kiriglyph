from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from worker.efficient_sam_adapter import (
    EfficientSamTiAdapter,
    _LassoCandidate,
    _refine_point_prompt,
    _select_candidate,
    _select_lasso_candidates,
    postprocess_mask,
)
from worker.segmentation_contract import (
    EmbedImageRequest,
    PointPrompt,
    PolygonPrompt,
    SegmentationPrompt,
)
from worker.segmentation_models import model_paths


def test_point_candidate_selection_prefers_larger_near_tied_mask_containing_prompt():
    masks = np.zeros((3, 20, 20), dtype=np.float32)
    masks[0, 0:20, 0:20] = 1
    masks[1, 8:13, 8:13] = 1
    masks[2, 6:15, 6:15] = 1
    scores = np.array([0.2, 0.7566, 0.7562], dtype=np.float32)

    index = _select_candidate(
        masks,
        scores,
        SegmentationPrompt(points=(PointPrompt(10, 10),)),
        width=20,
        height=20,
    )

    assert index == 2


def test_point_candidate_selection_ignores_masks_missing_prompt():
    masks = np.zeros((2, 12, 12), dtype=np.float32)
    masks[0, 0:5, 0:5] = 1
    masks[1, 5:11, 5:11] = 1
    scores = np.array([0.99, 0.7], dtype=np.float32)

    index = _select_candidate(
        masks,
        scores,
        SegmentationPrompt(points=(PointPrompt(7, 7),)),
        width=12,
        height=12,
    )

    assert index == 1


def test_point_candidate_selection_rejects_container_candidate():
    masks = np.zeros((2, 40, 40), dtype=np.float32)
    masks[0, 4:36, 4:36] = 1
    masks[1, 11:30, 12:29] = 1
    scores = np.array([0.95, 0.90], dtype=np.float32)

    index = _select_candidate(
        masks,
        scores,
        SegmentationPrompt(points=(PointPrompt(20, 20),)),
        width=40,
        height=40,
    )

    assert index == 1


def test_refinement_prompt_pads_candidate_bounds():
    mask = np.zeros((100, 120), dtype=bool)
    mask[40:60, 50:80] = True

    refined = _refine_point_prompt(
        mask,
        SegmentationPrompt(points=(PointPrompt(60, 50),)),
        width=120,
        height=100,
    )

    assert refined is not None
    assert refined.box is not None
    assert refined.box.x < 50
    assert refined.box.y < 40
    assert refined.box.width > 30
    assert refined.box.height > 20


def test_postprocess_removes_specks_and_fills_only_small_holes():
    mask = np.zeros((80, 80), dtype=bool)
    mask[10:70, 10:70] = True
    mask[20:23, 20:23] = False
    mask[35:55, 35:55] = False
    mask[2, 2] = True

    cleaned = postprocess_mask(mask, SegmentationPrompt(points=(PointPrompt(15, 15),)))

    assert bool(cleaned[21, 21]) is True
    assert bool(cleaned[40, 40]) is False
    assert bool(cleaned[2, 2]) is False


def test_postprocess_click_keeps_prompt_component_and_drops_slivers():
    mask = np.zeros((90, 90), dtype=bool)
    mask[20:70, 20:70] = True
    mask[75:78, 10:16] = True
    mask[10:25, 72:88] = True

    cleaned = postprocess_mask(mask, SegmentationPrompt(points=(PointPrompt(40, 40),)))

    assert bool(cleaned[40, 40]) is True
    assert cleaned[75:78, 10:16].sum() == 0
    assert cleaned[10:25, 72:88].sum() == 0


def test_postprocess_trims_uniform_backdrop_without_growing_mask():
    image = np.full((80, 100, 3), 255, dtype=np.uint8)
    image[25:60, 35:75] = np.array([210, 30, 20], dtype=np.uint8)
    mask = np.zeros((80, 100), dtype=bool)
    mask[20:65, 25:85] = True

    cleaned = postprocess_mask(mask, SegmentationPrompt(points=(PointPrompt(50, 40),)), image)

    assert cleaned.sum() < mask.sum()
    assert cleaned[40, 50]
    assert not cleaned[22, 27]
    assert not np.any(cleaned & ~mask)


def test_postprocess_no_longer_hard_clips_polygon_masks():
    mask = np.zeros((80, 140), dtype=bool)
    mask[20:65, 5:130] = True
    prompt = SegmentationPrompt(
        polygon=PolygonPrompt(
            tuple(
                PointPrompt(x, y)
                for x, y in [(30, 30), (95, 30), (100, 48), (28, 50)]
            )
        )
    )

    cleaned = postprocess_mask(mask, prompt)

    assert np.array_equal(cleaned, mask)


def test_lasso_seed_foreground_rejects_card_background():
    image = np.full((100, 120, 3), 225, dtype=np.uint8)
    image[32:78, 40:86] = np.array([190, 35, 25], dtype=np.uint8)
    mask = np.zeros((100, 120), dtype=bool)
    mask[20:90, 20:105] = True
    prompt = SegmentationPrompt(
        polygon=PolygonPrompt(
            tuple(
                PointPrompt(x, y)
                for x, y in [(32, 26), (92, 26), (98, 82), (30, 86)]
            )
        )
    )

    cleaned = postprocess_mask(mask, prompt, image)

    assert cleaned.sum() < mask.sum() * 0.6
    assert bool(cleaned[50, 60]) is True
    assert bool(cleaned[24, 24]) is False


def test_lasso_candidate_selection_rejects_rectangular_box_fill():
    roi = np.zeros((120, 160), dtype=bool)
    roi[10:110, 15:145] = True
    rectangle = roi.copy()
    left_object = np.zeros_like(roi)
    left_object[35:85, 30:70] = True
    left_object[25:95, 40:60] = True
    right_object = np.zeros_like(roi)
    right_object[30:90, 92:132] = True
    right_object[20:100, 102:122] = True

    selected = _select_lasso_candidates(
        [
            _LassoCandidate(rectangle, 0.97, 0.99),
            _LassoCandidate(left_object, 0.91, 0.98),
            _LassoCandidate(right_object, 0.89, 0.97),
        ],
        roi,
    )
    union = np.logical_or.reduce([candidate.mask for candidate in selected])

    assert not np.array_equal(union, rectangle)
    assert union[50, 50]
    assert union[50, 110]
    assert not union[15, 20]


def test_lasso_candidate_selection_keeps_multi_object_union():
    roi = np.ones((100, 180), dtype=bool)
    objects = []
    for left in (15, 70, 125):
        mask = np.zeros_like(roi)
        mask[25:75, left : left + 35] = True
        objects.append(mask)

    selected = _select_lasso_candidates(
        [_LassoCandidate(mask, 0.82, 0.96) for mask in objects],
        roi,
    )
    union = np.logical_or.reduce([candidate.mask for candidate in selected])

    assert all(np.any(union & mask) for mask in objects)
    assert len(selected) == 3


def test_lasso_candidate_selection_is_stable_across_loop_jitter():
    first_roi = np.zeros((120, 180), dtype=bool)
    first_roi[10:110, 10:170] = True
    second_roi = np.zeros_like(first_roi)
    second_roi[13:107, 7:173] = True
    subject = np.zeros_like(first_roi)
    subject[30:95, 38:143] = True
    subject[50:72, 20:160] = True
    background = first_roi.copy()
    candidates = [
        _LassoCandidate(subject, 0.88, 0.98),
        _LassoCandidate(background, 0.95, 0.99),
    ]

    first = np.logical_or.reduce(
        [candidate.mask for candidate in _select_lasso_candidates(candidates, first_roi)]
    )
    second = np.logical_or.reduce(
        [candidate.mask for candidate in _select_lasso_candidates(candidates, second_roi)]
    )
    intersection = np.count_nonzero(first & second)
    union = np.count_nonzero(first | second)

    assert intersection / union >= 0.98


def _real_fixture_path() -> Path:
    return (
        Path(__file__).resolve().parents[1]
        / "benchmarks"
        / "segmentation"
        / "fixtures"
        / "real"
        / "google-images-apple-user-regression.jpg"
    )


def _real_models_available() -> bool:
    return all(path.exists() for path in model_paths().values())


@pytest.mark.skipif(not _real_models_available(), reason="EfficientSAM-Ti files are not installed")
@pytest.mark.skipif(not _real_fixture_path().exists(), reason="real user regression fixture is local-only")
def test_real_google_images_apple_click_matches_lasso(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    adapter = EfficientSamTiAdapter(threads=2)
    try:
        handle = adapter.embed_image(EmbedImageRequest.from_path(_real_fixture_path()))
        click = adapter.prompt(
            handle,
            SegmentationPrompt(points=(PointPrompt(812, 340),)),
        )
        lasso = adapter.prompt(
            handle,
            SegmentationPrompt(
                polygon=PolygonPrompt(
                    tuple(
                        PointPrompt(x, y)
                        for x, y in [
                            (715, 255),
                            (796, 236),
                            (884, 247),
                            (933, 313),
                            (913, 414),
                            (816, 445),
                            (724, 402),
                            (690, 321),
                        ]
                    )
                )
            ),
        )
        google = adapter.prompt(
            handle,
            SegmentationPrompt(
                polygon=PolygonPrompt(
                    tuple(PointPrompt(x, y) for x, y in [(31, 77), (118, 76), (122, 105), (28, 106)])
                )
            ),
        )
        grid = adapter.prompt(
            handle,
            SegmentationPrompt(points=(PointPrompt(386, 400),)),
        )
        click_mask = np.asarray(Image.open(click.mask.path))[..., 3] > 127
        lasso_mask = np.asarray(Image.open(lasso.mask.path))[..., 3] > 127
    finally:
        adapter.close_session()

    union = np.logical_or(click_mask, lasso_mask).sum()
    assert np.logical_and(click_mask, lasso_mask).sum() / union >= 0.9
    assert click.mask_stats.components.count == 1
    assert google.mask_stats.area_fraction < 0.007
    assert grid.mask_stats.bounds is not None
    assert grid.mask_stats.bounds.width < 120
    assert grid.mask_stats.bounds.height < 120
    assert click.timings.prompt_ms is not None
    assert click.timings.prompt_ms < 450
