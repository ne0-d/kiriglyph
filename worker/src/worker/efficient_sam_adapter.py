from __future__ import annotations

import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw

from worker.segmentation_contract import (
    BoxPrompt,
    EmbedImageRequest,
    EmbeddedImageHandle,
    PointPrompt,
    PolygonPrompt,
    SegmentationAdapter,
    SegmentationContractError,
    SegmentationFailureKind,
    SegmentationPrompt,
    SegmentationResult,
    SegmentationTimings,
)
from worker.segmentation_mask import (
    MaskFileStore,
    analyse_mask,
    component_stats,
    connected_components,
    filter_components,
)
from worker.segmentation_models import FETCH_COMMAND, model_paths, missing_assets

POINT_SCORE_DELTA = 0.02
POINT_OBJECT_SCORE_DELTA = 0.10
REFINEMENT_PADDING_FRACTION = 0.25
REFINEMENT_MAX_BASE_FRACTION = 0.06
MIN_SPECK_AREA = 24
SMALL_HOLE_AREA = 96
BACKGROUND_DISTANCE = 34
LASSO_MIN_PREDICTED_IOU = 0.50
LASSO_MIN_STABILITY = 0.78
LASSO_MIN_INSIDE_FRACTION = 0.55
LASSO_DUPLICATE_OVERLAP = 0.82
# A plain click that lands on empty space makes the model return the backdrop
# (wallpaper, a window body, a wall). Such a mask is not an object.
CLICK_BACKGROUND_MAX_FRACTION = 0.35
CLICK_BACKGROUND_EDGE_FRACTION = 0.12
CLICK_BACKGROUND_MIN_EDGES = 3


@dataclass
class _Embedding:
    tensor: np.ndarray
    width: int
    height: int
    image: np.ndarray
    timings: SegmentationTimings


@dataclass(frozen=True)
class _LassoCandidate:
    mask: np.ndarray
    predicted_iou: float
    stability: float


def _select_lasso_candidates(
    candidates: list[_LassoCandidate],
    roi_mask: np.ndarray,
    image: np.ndarray | None = None,
) -> list[_LassoCandidate]:
    roi_area = int(np.count_nonzero(roi_mask))
    if roi_area == 0:
        return []
    roi_boundary = _inner_boundary(roi_mask)
    minimum_area = max(MIN_SPECK_AREA, int(roi_area * 0.001))
    plausible: list[_LassoCandidate] = []
    for candidate in candidates:
        mask = candidate.mask.astype(bool)
        area = int(np.count_nonzero(mask))
        if area < minimum_area:
            continue
        inside = int(np.count_nonzero(mask & roi_mask))
        inside_fraction = inside / area
        roi_fraction = inside / roi_area
        if (
            candidate.predicted_iou < LASSO_MIN_PREDICTED_IOU
            or candidate.stability < LASSO_MIN_STABILITY
            or inside_fraction < LASSO_MIN_INSIDE_FRACTION
            or (_is_container_like(mask) and roi_fraction >= 0.15)
        ):
            continue
        boundary_size = max(int(np.count_nonzero(_inner_boundary(mask))), 1)
        border_contact = int(np.count_nonzero(mask & roi_boundary)) / boundary_size
        if roi_fraction >= 0.72 or (
            roi_fraction >= 0.35 and inside_fraction < 0.92 and border_contact >= 0.20
        ):
            continue
        if image is not None and roi_fraction >= 0.25:
            pixels = image[mask]
            if len(pixels) and float(np.mean(np.std(pixels.astype(np.float32), axis=0))) < 10:
                continue
        plausible.append(
            _LassoCandidate(mask, candidate.predicted_iou, candidate.stability)
        )

    plausible.sort(
        key=lambda candidate: (
            int(np.count_nonzero(candidate.mask)),
            candidate.predicted_iou,
            candidate.stability,
        ),
        reverse=True,
    )
    selected: list[_LassoCandidate] = []
    for candidate in plausible:
        candidate_area = int(np.count_nonzero(candidate.mask))
        duplicate = False
        for kept in selected:
            kept_area = int(np.count_nonzero(kept.mask))
            intersection = int(np.count_nonzero(candidate.mask & kept.mask))
            if intersection / max(min(candidate_area, kept_area), 1) >= LASSO_DUPLICATE_OVERLAP:
                duplicate = True
                break
        if not duplicate:
            selected.append(candidate)
    return selected


class EfficientSamTiAdapter(SegmentationAdapter):
    def __init__(
        self,
        *,
        models_root: Path | None = None,
        mask_store: MaskFileStore | None = None,
        threads: int | None = None,
    ) -> None:
        missing = missing_assets(models_root)
        if missing:
            raise SegmentationContractError(
                SegmentationFailureKind.MODEL_MISSING,
                "EfficientSAM-Ti model files are not installed",
                details={"command": FETCH_COMMAND},
            )
        paths = model_paths(models_root)
        options = ort.SessionOptions()
        if threads is not None:
            options.intra_op_num_threads = threads
            options.inter_op_num_threads = 1
        start = time.perf_counter()
        try:
            self._encoder = ort.InferenceSession(
                str(paths["efficientsam_ti_encoder.onnx"]),
                sess_options=options,
                providers=["CPUExecutionProvider"],
            )
            self._decoder = ort.InferenceSession(
                str(paths["efficientsam_ti_decoder.onnx"]),
                sess_options=options,
                providers=["CPUExecutionProvider"],
            )
        except Exception as exc:  # noqa: BLE001 - ORT exposes provider-specific errors.
            raise SegmentationContractError(
                SegmentationFailureKind.MODEL_LOAD_FAILED,
                "local segmentation model could not be loaded",
            ) from exc
        self._load_ms = _elapsed_ms(start)
        self._embeddings: dict[str, _Embedding] = {}
        self._mask_store = mask_store or MaskFileStore()
        self._first_prompt = True
        self._closed = False

    def embed_image(self, request: EmbedImageRequest) -> EmbeddedImageHandle:
        self._ensure_open()
        start = time.perf_counter()
        image = _load_image(request)
        width, height = image.size
        source = np.asarray(image, dtype=np.uint8)
        arr = (
            np.asarray(image.resize((1024, 1024), Image.Resampling.BILINEAR))
            .astype(np.float32)
            / 255.0
        )
        batch = np.transpose(arr, (2, 0, 1))[None]
        embedding = self._encoder.run(None, {"batched_images": batch})[0]
        timings = SegmentationTimings(load_ms=self._load_ms, embed_ms=_elapsed_ms(start))
        handle = uuid.uuid4().hex
        self._embeddings[handle] = _Embedding(
            tensor=embedding,
            width=width,
            height=height,
            image=source,
            timings=timings,
        )
        return EmbeddedImageHandle(
            handle=handle,
            image_width=width,
            image_height=height,
            timings=timings,
        )

    def prompt(
        self,
        handle: EmbeddedImageHandle,
        prompt: SegmentationPrompt,
    ) -> SegmentationResult:
        self._ensure_open()
        embedding = self._embeddings.get(handle.handle)
        if embedding is None:
            raise SegmentationContractError(
                SegmentationFailureKind.SESSION_CLOSED,
                "embedding handle is not available in this session",
            )
        start = time.perf_counter()
        if prompt.polygon is not None:
            cleaned_mask, confidence = self._prompt_lasso_roi(embedding, prompt)
        else:
            masks, scores = self._decode(embedding, prompt)
            index = _select_candidate(masks, scores, prompt, embedding.width, embedding.height)
            mask = masks[index] > 0
            cleaned_mask: np.ndarray | None = None
            confidence = float(scores[index])
            if (
                _should_refine_point_prompt(prompt)
                and mask.mean() <= REFINEMENT_MAX_BASE_FRACTION
                and component_stats(mask).count > 1
            ):
                refined = _refine_point_prompt(mask, prompt, embedding.width, embedding.height)
                if refined is not None:
                    refined_masks, refined_scores = self._decode(embedding, refined)
                    refined_index = _select_candidate(
                        refined_masks,
                        refined_scores,
                        refined,
                        embedding.width,
                        embedding.height,
                    )
                    refined_mask = refined_masks[refined_index] > 0
                    refined_cleaned = postprocess_mask(refined_mask, prompt, embedding.image)
                    if cleaned_mask is None and _should_need_original_clean_mask(mask, refined_cleaned):
                        cleaned_mask = postprocess_mask(mask, prompt, embedding.image)
                    if _should_accept_refinement(mask, refined_mask, prompt) and (
                        cleaned_mask is None
                        or _should_accept_refined_clean_mask(cleaned_mask, refined_cleaned)
                    ):
                        cleaned_mask = refined_cleaned
                        confidence = float(refined_scores[refined_index])
            if cleaned_mask is None:
                cleaned_mask = postprocess_mask(mask, prompt, embedding.image)
            if _should_refine_point_prompt(prompt) and _is_background_like(cleaned_mask):
                # Report "nothing here" instead of selecting a random region.
                cleaned_mask = np.zeros_like(cleaned_mask, dtype=bool)
                confidence = 0.0
        stats = analyse_mask(cleaned_mask)
        mask_ref = self._mask_store.write(cleaned_mask)
        prompt_ms = _elapsed_ms(start)
        timings = SegmentationTimings(
            load_ms=embedding.timings.load_ms,
            embed_ms=embedding.timings.embed_ms,
            first_mask_ms=prompt_ms if self._first_prompt else None,
            prompt_ms=prompt_ms,
        )
        self._first_prompt = False
        return SegmentationResult(
            image_width=embedding.width,
            image_height=embedding.height,
            mask=mask_ref,
            bounds=stats.bounds,
            mask_stats=stats,
            confidence=confidence,
            stability_score=None,
            timings=timings,
        )

    def _prompt_lasso_roi(
        self,
        embedding: _Embedding,
        prompt: SegmentationPrompt,
    ) -> tuple[np.ndarray, float]:
        assert prompt.polygon is not None
        polygon_box, _ = prompt.polygon.to_box_and_points()
        roi_mask = _polygon_constraint(prompt.polygon, (embedding.height, embedding.width))
        seeds = _polygon_seed_points(prompt.polygon)
        candidates: list[_LassoCandidate] = []
        box_masks, box_scores = self._decode(
            embedding,
            SegmentationPrompt(box=polygon_box),
        )
        for index, score in enumerate(box_scores):
            logits = box_masks[index]
            candidates.append(
                _LassoCandidate(
                    mask=logits > 0,
                    predicted_iou=float(score),
                    stability=_mask_stability(logits),
                )
            )
        for seed in seeds:
            seed_prompt = SegmentationPrompt(points=(seed,))
            masks, scores = self._decode(embedding, seed_prompt)
            for index, score in enumerate(scores):
                logits = masks[index]
                candidate = logits > 0
                if not _contains_point(candidate, seed, embedding.width, embedding.height):
                    continue
                candidates.append(
                    _LassoCandidate(
                        mask=candidate,
                        predicted_iou=float(score),
                        stability=_mask_stability(logits),
                    )
                )
        kept = _select_lasso_candidates(candidates, roi_mask, embedding.image)
        if kept:
            cleaned_candidates = [
                _trim_uniform_background(candidate.mask, embedding.image)
                for candidate in kept
            ]
            union = np.logical_or.reduce(cleaned_candidates)
            union = _remove_small_specks(union)
            confidence = max(candidate.predicted_iou for candidate in kept)
        else:
            union = np.zeros((embedding.height, embedding.width), dtype=bool)
            confidence = 0
        return union, confidence

    def _decode(
        self,
        embedding: _Embedding,
        prompt: SegmentationPrompt,
    ) -> tuple[np.ndarray, np.ndarray]:
        coords, labels = _encode_prompt(prompt)
        outputs = self._decoder.run(
            None,
            {
                "image_embeddings": embedding.tensor,
                "batched_point_coords": coords,
                "batched_point_labels": labels,
                "orig_im_size": np.array([embedding.height, embedding.width], dtype=np.int64),
            },
        )
        return outputs[0][0, 0], outputs[1][0, 0]

    def close_session(self) -> None:
        self._closed = True
        self._embeddings.clear()
        self._mask_store.cleanup()

    def _ensure_open(self) -> None:
        if self._closed:
            raise SegmentationContractError(
                SegmentationFailureKind.SESSION_CLOSED,
                "segmentation session is closed",
            )


def _load_image(request: EmbedImageRequest) -> Image.Image:
    try:
        if request.source == "path":
            assert request.image_path is not None
            return Image.open(request.image_path).convert("RGB")
        assert request.png_bytes is not None
        from io import BytesIO

        return Image.open(BytesIO(request.png_bytes.data)).convert("RGB")
    except OSError as exc:
        raise SegmentationContractError(
            SegmentationFailureKind.MALFORMED_OUTPUT,
            "image file is missing or not readable",
        ) from exc


def _encode_prompt(prompt: SegmentationPrompt) -> tuple[np.ndarray, np.ndarray]:
    points = list(prompt.points)
    box = prompt.box
    if prompt.polygon is not None:
        polygon_box, polygon_points = prompt.polygon.to_box_and_points()
        box = box or polygon_box
        points.extend(polygon_points)
    coords: list[list[float]] = []
    labels: list[float] = []
    for point in points:
        coords.append([point.x, point.y])
        labels.append(1.0 if point.label == "foreground" else 0.0)
    if box is not None:
        coords.append([box.x, box.y])
        labels.append(2.0)
        coords.append([box.x + box.width, box.y + box.height])
        labels.append(3.0)
    if not coords:
        raise SegmentationContractError(
            SegmentationFailureKind.MALFORMED_OUTPUT,
            "prompt requires at least one point, box, or polygon",
        )
    return (
        np.array([[coords]], dtype=np.float32),
        np.array([[labels]], dtype=np.float32),
    )


def _select_candidate(
    masks: np.ndarray,
    scores: np.ndarray,
    prompt: SegmentationPrompt,
    width: int,
    height: int,
) -> int:
    candidates: list[tuple[float, int, int]] = []
    best_score = float(np.max(scores))
    prompt_points = _foreground_points(prompt)
    for index, score in enumerate(scores):
        mask = masks[index] > 0
        if prompt_points and not any(_contains_point(mask, point, width, height) for point in prompt_points):
            continue
        candidates.append((float(score), int(np.count_nonzero(mask)), index))
    if not candidates:
        return int(np.argmax(scores))
    if _should_refine_point_prompt(prompt):
        best_candidate_score = max(item[0] for item in candidates)
        broad = [
            item
            for item in candidates
            if item[0] >= best_candidate_score - POINT_OBJECT_SCORE_DELTA
            and not _is_container_like(masks[item[2]] > 0)
        ]
        if broad:
            return max(broad, key=lambda item: (item[1], item[0]))[2]
        close = [item for item in candidates if item[0] >= best_candidate_score - POINT_SCORE_DELTA]
        return max(close or candidates, key=lambda item: (item[1], item[0]))[2]
    return max(candidates, key=lambda item: item[0])[2]


def _should_refine_point_prompt(prompt: SegmentationPrompt) -> bool:
    return prompt.box is None and prompt.polygon is None and any(
        point.label == "foreground" for point in prompt.points
    )


def _foreground_points(prompt: SegmentationPrompt) -> list[PointPrompt]:
    points = [point for point in prompt.points if point.label == "foreground"]
    if prompt.polygon is not None:
        points.extend(prompt.polygon.to_box_and_points()[1])
    return points


def _polygon_seed_points(polygon: PolygonPrompt) -> list[PointPrompt]:
    box, _ = polygon.to_box_and_points()
    seeds: list[PointPrompt] = []
    rows = cols = 4
    for row in range(rows):
        y = box.y + box.height * (row + 0.5) / rows
        for col in range(cols):
            x = box.x + box.width * (col + 0.5) / cols
            if _point_in_polygon(x, y, polygon):
                seeds.append(PointPrompt(x, y))
    return seeds


def _point_in_polygon(x: float, y: float, polygon: PolygonPrompt) -> bool:
    inside = False
    points = polygon.points
    previous = points[-1]
    for current in points:
        if (current.y > y) != (previous.y > y):
            slope_x = (previous.x - current.x) * (y - current.y) / (previous.y - current.y) + current.x
            if x < slope_x:
                inside = not inside
        previous = current
    return inside


def _contains_point(mask: np.ndarray, point: PointPrompt, width: int, height: int) -> bool:
    x = int(round(point.x))
    y = int(round(point.y))
    return 0 <= x < width and 0 <= y < height and bool(mask[y, x])


def _refine_point_prompt(
    mask: np.ndarray,
    prompt: SegmentationPrompt,
    width: int,
    height: int,
) -> SegmentationPrompt | None:
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None
    left = int(xs.min())
    top = int(ys.min())
    right = int(xs.max()) + 1
    bottom = int(ys.max()) + 1
    pad = int(max(right - left, bottom - top) * REFINEMENT_PADDING_FRACTION)
    left = max(0, left - pad)
    top = max(0, top - pad)
    right = min(width, right + pad)
    bottom = min(height, bottom + pad)
    if right <= left or bottom <= top:
        return None
    return SegmentationPrompt(
        points=prompt.points,
        box=BoxPrompt(x=left, y=top, width=right - left, height=bottom - top),
    )


def _should_accept_refinement(
    original: np.ndarray,
    refined: np.ndarray,
    prompt: SegmentationPrompt,
) -> bool:
    if not refined.any():
        return False
    original_area = int(np.count_nonzero(original))
    refined_area = int(np.count_nonzero(refined))
    if refined_area <= original_area:
        return False
    if refined_area > refined.size * 0.35:
        return False
    return all(
        point.label != "foreground"
        or _contains_point(refined, point, refined.shape[1], refined.shape[0])
        for point in prompt.points
    )


def _should_accept_refined_clean_mask(original: np.ndarray, refined: np.ndarray) -> bool:
    if not refined.any():
        return False
    if _is_container_like(refined) and not _is_container_like(original):
        return False
    return int(np.count_nonzero(refined)) >= int(np.count_nonzero(original)) * 0.75


def _should_need_original_clean_mask(original_raw: np.ndarray, refined_cleaned: np.ndarray) -> bool:
    return _is_container_like(refined_cleaned) and not _is_container_like(original_raw)


def _is_background_like(mask: np.ndarray) -> bool:
    """True when a click mask is the backdrop rather than an object.

    Backdrops are large, or they wrap around the screen edges. A real object
    can still be lifted by drawing a rectangle or a loop around it.
    """
    height, width = mask.shape
    area_fraction = float(np.count_nonzero(mask)) / max(width * height, 1)
    if area_fraction > CLICK_BACKGROUND_MAX_FRACTION:
        return True
    edges = sum(
        (
            bool(np.any(mask[:, 0])),
            bool(np.any(mask[0, :])),
            bool(np.any(mask[:, width - 1])),
            bool(np.any(mask[height - 1, :])),
        )
    )
    return edges >= CLICK_BACKGROUND_MIN_EDGES and area_fraction > CLICK_BACKGROUND_EDGE_FRACTION


def _is_container_like(mask: np.ndarray) -> bool:
    return _mask_fill_ratio(mask) >= 0.88


def _mask_fill_ratio(mask: np.ndarray) -> float:
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return 0
    width = int(xs.max() - xs.min() + 1)
    height = int(ys.max() - ys.min() + 1)
    if width * height < 400:
        return 0
    return float(np.count_nonzero(mask) / (width * height))


def _mask_stability(logits: np.ndarray) -> float:
    low = logits > -0.05
    high = logits > 0.05
    union = int(np.count_nonzero(low))
    if union == 0:
        return 0
    return float(np.count_nonzero(high) / union)


def postprocess_mask(
    mask: np.ndarray,
    prompt: SegmentationPrompt,
    image: np.ndarray | None = None,
) -> np.ndarray:
    cleaned = mask.astype(bool)
    if image is not None and cleaned.any():
        cleaned = _trim_uniform_background(cleaned, image)
    cleaned = _keep_prompt_components(cleaned, prompt)
    cleaned = _close_tiny_gaps(cleaned)
    cleaned = _fill_small_holes(cleaned)
    cleaned = _remove_small_specks(cleaned)
    return cleaned


def _polygon_constraint(polygon: PolygonPrompt, shape: tuple[int, int]) -> np.ndarray:
    height, width = shape
    image = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(image)
    points = [(point.x, point.y) for point in polygon.points]
    draw.polygon(points, fill=255)
    draw.line(points + [points[0]], fill=255, width=9, joint="curve")
    return np.asarray(image, dtype=np.uint8) > 0


def _trim_uniform_background(mask: np.ndarray, image: np.ndarray) -> np.ndarray:
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return mask
    top = max(0, int(ys.min()) - 1)
    bottom = min(mask.shape[0], int(ys.max()) + 2)
    left = max(0, int(xs.min()) - 1)
    right = min(mask.shape[1], int(xs.max()) + 2)
    local_mask = mask[top:bottom, left:right]
    local_image = image[top:bottom, left:right]
    boundary = _inner_boundary(local_mask)
    frame = np.zeros_like(local_mask)
    frame[:5, :] = True
    frame[-5:, :] = True
    frame[:, :5] = True
    frame[:, -5:] = True
    sample_mask = local_mask & (boundary | frame)
    samples = local_image[sample_mask]
    if len(samples) < 32:
        return mask
    median = np.median(samples.astype(np.int16), axis=0)
    distances = np.max(np.abs(samples.astype(np.int16) - median), axis=1)
    close_ratio = float(np.mean(distances <= BACKGROUND_DISTANCE))
    brightness = float(np.mean(median))
    saturation = float(np.max(median) - np.min(median))
    local_fill = float(np.count_nonzero(local_mask) / local_mask.size)
    neutral_backdrop = saturation <= 35 and (
        brightness >= 170 or (brightness <= 70 and local_fill >= 0.85)
    )
    if close_ratio < 0.62 or not neutral_backdrop:
        return mask
    all_distances = np.max(np.abs(local_image.astype(np.int16) - median), axis=2)
    close_background = local_mask & (all_distances <= BACKGROUND_DISTANCE)
    background = _connected_from_seeds(close_background, close_background & sample_mask)
    if not background.any():
        return mask
    trimmed = mask.copy()
    trimmed[top:bottom, left:right] &= ~background
    return trimmed if trimmed.any() else mask


def _trim_lasso_seed_foreground(
    mask: np.ndarray,
    polygon: PolygonPrompt,
    image: np.ndarray,
) -> np.ndarray:
    _, points = polygon.to_box_and_points()
    seed = points[0]
    x = int(round(seed.x))
    y = int(round(seed.y))
    if not (0 <= y < mask.shape[0] and 0 <= x < mask.shape[1]) or not mask[y, x]:
        return mask
    xs = [point.x for point in polygon.points]
    ys = [point.y for point in polygon.points]
    if max(ys) - min(ys) < 60:
        return _trim_lasso_text_foreground(mask, image)
    if _mask_fill_ratio(mask) < 0.78:
        return mask
    sample = image[max(0, y - 2) : y + 3, max(0, x - 2) : x + 3]
    if sample.size == 0:
        return mask
    color = np.median(sample.reshape(-1, 3).astype(np.int16), axis=0)
    brightness = float(np.mean(color))
    saturation = float(np.max(color) - np.min(color))
    distances = np.max(np.abs(image.astype(np.int16) - color), axis=2)
    if saturation >= 35:
        selected = mask & (distances <= 80)
    elif brightness <= 90:
        selected = mask & (image.mean(axis=2) <= 115)
    else:
        return mask
    components, labels = connected_components(selected, label_map=True)
    if labels is None or not components:
        return mask
    label = int(labels[y, x])
    if label == 0:
        return mask
    trimmed = labels == label
    area = int(np.count_nonzero(trimmed))
    original_area = int(np.count_nonzero(mask))
    if area < original_area * 0.15 or area > original_area * 0.95:
        return mask
    return trimmed


def _trim_lasso_text_foreground(mask: np.ndarray, image: np.ndarray) -> np.ndarray:
    gray = image.mean(axis=2)
    saturation = image.max(axis=2) - image.min(axis=2)
    selected = mask & (gray >= 130) & (saturation <= 100)
    area = int(np.count_nonzero(selected))
    original_area = int(np.count_nonzero(mask))
    if area < original_area * 0.05 or area > original_area * 0.8:
        return mask
    return selected


def _inner_boundary(mask: np.ndarray) -> np.ndarray:
    up = np.zeros_like(mask)
    up[1:] = mask[:-1]
    down = np.zeros_like(mask)
    down[:-1] = mask[1:]
    left = np.zeros_like(mask)
    left[:, 1:] = mask[:, :-1]
    right = np.zeros_like(mask)
    right[:, :-1] = mask[:, 1:]
    return mask & ~(up & down & left & right)


def _connected_from_seeds(mask: np.ndarray, seeds: np.ndarray) -> np.ndarray:
    connected = seeds & mask
    if not connected.any():
        return connected
    while True:
        expanded = connected.copy()
        expanded[1:] |= connected[:-1]
        expanded[:-1] |= connected[1:]
        expanded[:, 1:] |= connected[:, :-1]
        expanded[:, :-1] |= connected[:, 1:]
        expanded &= mask
        if np.array_equal(expanded, connected):
            return connected
        connected = expanded


def _keep_prompt_components(mask: np.ndarray, prompt: SegmentationPrompt) -> np.ndarray:
    components, labels = connected_components(mask, label_map=True)
    if labels is None or not components:
        return mask
    keep: set[int] = set()
    for point in _foreground_points(prompt):
        x = int(round(point.x))
        y = int(round(point.y))
        if 0 <= y < labels.shape[0] and 0 <= x < labels.shape[1] and labels[y, x] > 0:
            keep.add(int(labels[y, x]))
    largest = max(components, key=lambda component: component.area)
    if not keep:
        keep.add(largest.label)
    min_fraction = 0.12 if prompt.polygon is not None else 0.25
    return filter_components(
        mask,
        keep_labels=keep,
        min_area=max(MIN_SPECK_AREA, int(largest.area * min_fraction)),
        min_area_fraction_of_largest=min_fraction,
    )


def _close_tiny_gaps(mask: np.ndarray) -> np.ndarray:
    if not mask.any():
        return mask
    dilated = _dilate3(mask)
    closed = _erode3(dilated)
    return closed


def _dilate3(mask: np.ndarray) -> np.ndarray:
    padded = np.pad(mask, 1, constant_values=False)
    out = np.zeros_like(mask)
    for dy in range(3):
        for dx in range(3):
            out |= padded[dy : dy + mask.shape[0], dx : dx + mask.shape[1]]
    return out


def _erode3(mask: np.ndarray) -> np.ndarray:
    padded = np.pad(mask, 1, constant_values=False)
    out = np.ones_like(mask)
    for dy in range(3):
        for dx in range(3):
            out &= padded[dy : dy + mask.shape[0], dx : dx + mask.shape[1]]
    return out


def _fill_small_holes(mask: np.ndarray) -> np.ndarray:
    if not mask.any():
        return mask
    ys, xs = np.nonzero(mask)
    top = max(0, int(ys.min()) - 1)
    bottom = min(mask.shape[0], int(ys.max()) + 2)
    left = max(0, int(xs.min()) - 1)
    right = min(mask.shape[1], int(xs.max()) + 2)
    local = mask[top:bottom, left:right]
    components, labels = connected_components(~local, label_map=True)
    if labels is None:
        return mask
    filled = mask.copy()
    for component in components:
        if component.touches_edge:
            continue
        if component.area <= SMALL_HOLE_AREA:
            local_filled = filled[top:bottom, left:right]
            local_filled[labels == component.label] = True
    return filled


def _remove_small_specks(mask: np.ndarray) -> np.ndarray:
    components, labels = connected_components(mask, label_map=True)
    if labels is None or not components:
        return mask
    largest = max(components, key=lambda component: component.area)
    min_area = max(MIN_SPECK_AREA, int(largest.area * 0.001))
    kept = {component.label for component in components if component.area >= min_area}
    if not kept:
        kept.add(largest.label)
    return np.isin(labels, list(kept))


def _elapsed_ms(start: float) -> float:
    return (time.perf_counter() - start) * 1000
