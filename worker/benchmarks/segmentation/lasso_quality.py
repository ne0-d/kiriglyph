from __future__ import annotations

import argparse
import json
import math
import resource
import statistics
import tempfile
from dataclasses import dataclass
from itertools import combinations
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from worker.efficient_sam_adapter import EfficientSamTiAdapter
from worker.segmentation_contract import (
    EmbedImageRequest,
    PointPrompt,
    PolygonPrompt,
    SegmentationPrompt,
)


CANVAS_SIZE = (640, 480)
LOOP_VARIANTS = (
    (24, 3, 11),
    (32, 7, 23),
    (16, 5, 37),
    (8, 4, 53),
    (-3, 2, 71),
)
BOX_FILL_THRESHOLD = 0.88
CLICK_OFFSETS = ((0, 0), (2, 0), (-2, 0), (0, 2), (0, -2))


@dataclass(frozen=True)
class PlacedObject:
    image: Image.Image
    mask: np.ndarray


@dataclass(frozen=True)
class Scene:
    name: str
    image: Image.Image
    ground_truth: np.ndarray
    objects: tuple[PlacedObject, ...]


def _background(kind: str) -> Image.Image:
    width, height = CANVAS_SIZE
    if kind == "white":
        return Image.new("RGB", CANVAS_SIZE, (246, 246, 243))
    if kind == "gradient":
        y, x = np.mgrid[:height, :width]
        value = np.clip(225 - 45 * x / width + 18 * y / height, 0, 255)
        rgb = np.stack((value, value + 3, value + 7), axis=2).astype(np.uint8)
        return Image.fromarray(rgb, mode="RGB")
    if kind == "wood":
        y, x = np.mgrid[:height, :width]
        grain = 18 * np.sin(x / 13) + 8 * np.sin((x + y) / 31)
        plank = ((y // 72) % 2) * 14
        rgb = np.stack(
            (174 + grain + plank, 127 + grain * 0.65 + plank, 83 + grain * 0.4 + plank),
            axis=2,
        )
        image = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), mode="RGB")
        draw = ImageDraw.Draw(image)
        for row in range(72, height, 72):
            draw.line((0, row, width, row), fill=(91, 61, 43), width=3)
        return image
    if kind == "cards":
        image = Image.new("RGB", CANVAS_SIZE, (225, 229, 234))
        draw = ImageDraw.Draw(image)
        for y in range(18, height, 118):
            for x in range(18, width, 150):
                draw.rounded_rectangle(
                    (x, y, min(x + 130, width - 1), min(y + 96, height - 1)),
                    radius=9,
                    fill=(250, 250, 249),
                    outline=(185, 190, 198),
                    width=2,
                )
                draw.rectangle((x + 12, y + 14, x + 92, y + 23), fill=(124, 132, 145))
                draw.rectangle((x + 12, y + 34, x + 112, y + 40), fill=(193, 198, 205))
        return image
    rng = np.random.default_rng(9127)
    noise = rng.normal(0, 18, (height, width, 3))
    base = np.zeros((height, width, 3), dtype=np.float32)
    base[:] = (109, 137, 115)
    base += noise
    image = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), mode="RGB")
    image = image.filter(ImageFilter.GaussianBlur(2))
    draw = ImageDraw.Draw(image)
    for index in range(28):
        x = int(rng.integers(-40, width))
        y = int(rng.integers(-40, height))
        radius = int(rng.integers(18, 75))
        color = tuple(int(value) for value in rng.integers(45, 205, 3))
        draw.ellipse((x, y, x + radius * 2, y + radius), fill=color)
    return image


def _prepare_cutout(path: Path, longest_edge: int) -> Image.Image:
    source = Image.open(path).convert("RGBA")
    alpha = np.asarray(source)[..., 3]
    ys, xs = np.nonzero(alpha > 8)
    if len(xs) == 0:
        raise ValueError(f"cutout has no visible alpha: {path}")
    source = source.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    scale = longest_edge / max(source.size)
    size = (max(1, round(source.width * scale)), max(1, round(source.height * scale)))
    return source.resize(size, Image.Resampling.LANCZOS)


def _make_scene(
    name: str,
    background: str,
    cutouts: list[Image.Image],
    placements: list[tuple[int, int]],
) -> Scene:
    image = _background(background).convert("RGBA")
    ground_truth = np.zeros((CANVAS_SIZE[1], CANVAS_SIZE[0]), dtype=bool)
    objects: list[PlacedObject] = []
    for cutout, (left, top) in zip(cutouts, placements, strict=True):
        image.alpha_composite(cutout, (left, top))
        alpha = np.asarray(cutout)[..., 3] > 127
        visible = np.zeros_like(ground_truth)
        bottom = min(top + cutout.height, CANVAS_SIZE[1])
        right = min(left + cutout.width, CANVAS_SIZE[0])
        visible[top:bottom, left:right] = alpha[: bottom - top, : right - left]
        ground_truth |= visible
        objects.append(PlacedObject(cutout, visible))
    return Scene(name, image.convert("RGB"), ground_truth, tuple(objects))


def make_scenes(paths: list[Path]) -> list[Scene]:
    if len(paths) < 6:
        raise ValueError("the lasso benchmark needs at least six RGBA cutouts")
    prepared = [
        _prepare_cutout(paths[0], 210),
        _prepare_cutout(paths[1], 205),
        _prepare_cutout(paths[2], 220),
        _prepare_cutout(paths[3], 190),
        _prepare_cutout(paths[4], 175),
        _prepare_cutout(paths[5], 150),
    ]
    return [
        _make_scene("single_white", "white", [prepared[0]], [(215, 130)]),
        _make_scene("single_gradient", "gradient", [prepared[2]], [(220, 125)]),
        _make_scene(
            "two_wood",
            "wood",
            [prepared[0], prepared[1]],
            [(105, 145), (330, 155)],
        ),
        _make_scene(
            "three_cards",
            "cards",
            [prepared[1], prepared[4], prepared[5]],
            [(70, 165), (270, 150), (440, 205)],
        ),
        _make_scene(
            "three_overlapping_clutter",
            "clutter",
            [prepared[3], prepared[4], prepared[0]],
            [(105, 170), (250, 115), (335, 175)],
        ),
    ]


def _rough_loop(mask: np.ndarray, margin: int, wobble: int, seed: int) -> PolygonPrompt:
    ys, xs = np.nonzero(mask)
    left = int(xs.min()) - margin
    right = int(xs.max()) + margin
    top = int(ys.min()) - margin
    bottom = int(ys.max()) + margin
    center_x = (left + right) / 2
    center_y = (top + bottom) / 2
    radius_x = max((right - left) / 2, 2)
    radius_y = max((bottom - top) / 2, 2)
    rng = np.random.default_rng(seed)
    points: list[PointPrompt] = []
    for index in range(16):
        angle = 2 * math.pi * index / 16
        radial = 1 + float(rng.uniform(-0.07, 0.07))
        x = center_x + math.cos(angle) * radius_x * radial + float(rng.uniform(-wobble, wobble))
        y = center_y + math.sin(angle) * radius_y * radial + float(rng.uniform(-wobble, wobble))
        points.append(
            PointPrompt(
                min(max(x, 0), CANVAS_SIZE[0] - 1),
                min(max(y, 0), CANVAS_SIZE[1] - 1),
            )
        )
    return PolygonPrompt(tuple(points))


def _load_result_mask(path: str) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"))[..., 3] > 127


def _iou(left: np.ndarray, right: np.ndarray) -> float:
    union = int(np.count_nonzero(left | right))
    if union == 0:
        return 1.0
    return float(np.count_nonzero(left & right) / union)


def _leakage(mask: np.ndarray, ground_truth: np.ndarray) -> float:
    area = int(np.count_nonzero(mask))
    if area == 0:
        return 0.0
    return float(np.count_nonzero(mask & ~ground_truth) / area)


def _bbox_fill(mask: np.ndarray) -> float:
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return 0.0
    bounds_area = (int(xs.max()) - int(xs.min()) + 1) * (int(ys.max()) - int(ys.min()) + 1)
    return float(np.count_nonzero(mask) / bounds_area)


def _interior_point(mask: np.ndarray) -> PointPrompt:
    ys, xs = np.nonzero(mask)
    center_x = float(np.mean(xs))
    center_y = float(np.mean(ys))
    nearest = int(np.argmin((xs - center_x) ** 2 + (ys - center_y) ** 2))
    return PointPrompt(float(xs[nearest]), float(ys[nearest]))


def _mean(values: list[float]) -> float:
    return float(statistics.mean(values)) if values else math.nan


def run_benchmark(paths: list[Path], models_dir: Path, threads: int) -> dict[str, object]:
    scenes = make_scenes(paths)
    lasso_ious: list[float] = []
    lasso_leakage: list[float] = []
    lasso_latencies: list[float] = []
    lasso_fills: list[float] = []
    stability: list[float] = []
    click_ious: list[float] = []
    click_leakage: list[float] = []
    click_latencies: list[float] = []
    click_fills: list[float] = []
    click_stability: list[float] = []
    scene_rows: list[dict[str, object]] = []
    with tempfile.TemporaryDirectory(prefix="kiriglyph-lasso-quality-") as temporary:
        root = Path(temporary)
        adapter = EfficientSamTiAdapter(models_root=models_dir, threads=threads)
        try:
            for scene in scenes:
                scene_path = root / f"{scene.name}.png"
                scene.image.save(scene_path)
                handle = adapter.embed_image(EmbedImageRequest.from_path(scene_path))
                masks: list[np.ndarray] = []
                for margin, wobble, seed in LOOP_VARIANTS:
                    result = adapter.prompt(
                        handle,
                        SegmentationPrompt(
                            polygon=_rough_loop(scene.ground_truth, margin, wobble, seed)
                        ),
                    )
                    predicted = _load_result_mask(result.mask.path)
                    masks.append(predicted)
                    lasso_ious.append(_iou(predicted, scene.ground_truth))
                    lasso_leakage.append(_leakage(predicted, scene.ground_truth))
                    lasso_fills.append(_bbox_fill(predicted))
                    assert result.timings.prompt_ms is not None
                    lasso_latencies.append(result.timings.prompt_ms)
                scene_stability = [_iou(left, right) for left, right in combinations(masks, 2)]
                stability.extend(scene_stability)
                scene_rows.append(
                    {
                        "scene": scene.name,
                        "objects": len(scene.objects),
                        "iou": _mean([_iou(mask, scene.ground_truth) for mask in masks]),
                        "leakage": _mean([_leakage(mask, scene.ground_truth) for mask in masks]),
                        "stability": _mean(scene_stability),
                        "box_fills": sum(_bbox_fill(mask) >= BOX_FILL_THRESHOLD for mask in masks),
                    }
                )
                if len(scene.objects) == 1:
                    point = _interior_point(scene.ground_truth)
                    click_masks: list[np.ndarray] = []
                    for offset_x, offset_y in CLICK_OFFSETS:
                        result = adapter.prompt(
                            handle,
                            SegmentationPrompt(
                                points=(
                                    PointPrompt(
                                        point.x + offset_x,
                                        point.y + offset_y,
                                    ),
                                )
                            ),
                        )
                        predicted = _load_result_mask(result.mask.path)
                        click_masks.append(predicted)
                        click_ious.append(_iou(predicted, scene.ground_truth))
                        click_leakage.append(_leakage(predicted, scene.ground_truth))
                        click_fills.append(_bbox_fill(predicted))
                        assert result.timings.prompt_ms is not None
                        click_latencies.append(result.timings.prompt_ms)
                    click_stability.extend(
                        _iou(left, right)
                        for left, right in combinations(click_masks, 2)
                    )
        finally:
            adapter.close_session()
    return {
        "click": {
            "mean_iou": _mean(click_ious),
            "box_fill_count": sum(fill >= BOX_FILL_THRESHOLD for fill in click_fills),
            "mean_leakage": _mean(click_leakage),
            "stability": _mean(click_stability),
            "median_latency_ms": float(statistics.median(click_latencies)),
        },
        "lasso": {
            "mean_iou": _mean(lasso_ious),
            "box_fill_count": sum(fill >= BOX_FILL_THRESHOLD for fill in lasso_fills),
            "mean_leakage": _mean(lasso_leakage),
            "stability": _mean(stability),
            "median_latency_ms": float(statistics.median(lasso_latencies)),
        },
        "peak_rss_mib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024,
        "scenes": scene_rows,
    }


def _print_summary(label: str, results: dict[str, object]) -> None:
    print(f"{label}:")
    print("mode   mean IoU  box-fill  leakage  stability  latency ms  RSS MiB")
    for mode in ("click", "lasso"):
        row = results[mode]
        assert isinstance(row, dict)
        stability = row["stability"]
        stability_text = "-" if stability is None else f"{stability:.3f}"
        print(
            f"{mode:<6} {row['mean_iou']:>8.3f} {row['box_fill_count']:>9} "
            f"{row['mean_leakage']:>8.3f} {stability_text:>10} "
            f"{row['median_latency_ms']:>11.1f} {results['peak_rss_mib']:>8.1f}"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cutout", action="append", type=Path, required=True)
    parser.add_argument("--models-dir", type=Path, default=Path(".models/segmentation"))
    parser.add_argument("--threads", type=int, default=2)
    parser.add_argument("--label", default="lasso")
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()
    results = run_benchmark(args.cutout, args.models_dir, args.threads)
    _print_summary(args.label, results)
    if args.json_output is not None:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
