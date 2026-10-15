from __future__ import annotations

import hashlib
import os
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

from worker.segmentation_contract import (
    ComponentStats,
    EdgeTouches,
    MaskEncoding,
    MaskOutcome,
    MaskReference,
    MaskStats,
    Rect,
)


@dataclass(frozen=True)
class MaskComponent:
    label: int
    area: int
    bounds: Rect
    touches_edge: bool


def analyse_mask(mask: np.ndarray) -> MaskStats:
    foreground = mask.astype(bool)
    height, width = foreground.shape
    area = int(np.count_nonzero(foreground))
    area_fraction = area / max(width * height, 1)
    if area == 0:
        return MaskStats(
            outcome=MaskOutcome.EMPTY,
            area_fraction=0,
            bounds=None,
            touches_edge=EdgeTouches(),
            components=ComponentStats(count=0, largest_bounds=None),
        )

    ys, xs = np.nonzero(foreground)
    bounds = Rect(
        x=int(xs.min()),
        y=int(ys.min()),
        width=int(xs.max() - xs.min() + 1),
        height=int(ys.max() - ys.min() + 1),
    )
    touches = EdgeTouches(
        left=bool(np.any(foreground[:, 0])),
        top=bool(np.any(foreground[0, :])),
        right=bool(np.any(foreground[:, width - 1])),
        bottom=bool(np.any(foreground[height - 1, :])),
    )
    components = component_stats(foreground)
    return MaskStats(
        outcome=MaskOutcome.SUSPECT_FULL_IMAGE
        if area_fraction > 0.90
        else MaskOutcome.OK,
        area_fraction=area_fraction,
        bounds=bounds,
        touches_edge=touches,
        components=components,
    )


def save_private_alpha_png(mask: np.ndarray, directory: Path, stem: str) -> MaskReference:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{stem}.png"
    alpha = mask.astype(np.uint8) * 255
    rgba = np.zeros((*alpha.shape, 4), dtype=np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = alpha
    Image.fromarray(rgba, mode="RGBA").save(path)
    os.chmod(path, 0o600)
    data = path.read_bytes()
    return MaskReference(
        encoding=MaskEncoding.ALPHA_PNG_FILE,
        path=str(path),
        byte_length=len(data),
        sha256=hashlib.sha256(data).hexdigest(),
    )


class MaskFileStore:
    def __init__(self, root: Path | None = None) -> None:
        parent = root
        if parent is None:
            runtime = os.environ.get("XDG_RUNTIME_DIR")
            parent = Path(runtime) if runtime else Path(tempfile.gettempdir())
        parent.mkdir(parents=True, exist_ok=True)
        self.path = Path(tempfile.mkdtemp(prefix="kiriglyph-segmentation-", dir=parent))
        os.chmod(self.path, 0o700)
        self._counter = 0

    def write(self, mask: np.ndarray) -> MaskReference:
        self._counter += 1
        return save_private_alpha_png(mask, self.path, f"mask-{self._counter}")

    def cleanup(self) -> None:
        shutil.rmtree(self.path, ignore_errors=True)


def component_stats(mask: np.ndarray) -> ComponentStats:
    components = _component_stats_rle(mask)
    if not components:
        return ComponentStats(count=0, largest_bounds=None)
    largest = max(components, key=lambda component: component.area)
    return ComponentStats(count=len(components), largest_bounds=largest.bounds)


def _component_stats_rle(mask: np.ndarray) -> list[MaskComponent]:
    foreground = mask.astype(bool)
    height, width = foreground.shape
    parent: dict[int, int] = {}
    area: dict[int, int] = {}
    min_x: dict[int, int] = {}
    max_x: dict[int, int] = {}
    min_y: dict[int, int] = {}
    max_y: dict[int, int] = {}
    touches: dict[int, bool] = {}
    next_label = 0
    previous: list[tuple[int, int, int]] = []

    def find(label: int) -> int:
        root = label
        while parent[root] != root:
            root = parent[root]
        while parent[label] != label:
            parent[label], label = root, parent[label]
        return root

    def union(left_label: int, right_label: int) -> int:
        left_root = find(left_label)
        right_root = find(right_label)
        if left_root == right_root:
            return left_root
        if area[left_root] < area[right_root]:
            left_root, right_root = right_root, left_root
        parent[right_root] = left_root
        area[left_root] += area[right_root]
        min_x[left_root] = min(min_x[left_root], min_x[right_root])
        max_x[left_root] = max(max_x[left_root], max_x[right_root])
        min_y[left_root] = min(min_y[left_root], min_y[right_root])
        max_y[left_root] = max(max_y[left_root], max_y[right_root])
        touches[left_root] = touches[left_root] or touches[right_root]
        return left_root

    for y in range(height):
        xs = np.flatnonzero(foreground[y])
        if len(xs) == 0:
            previous = []
            continue
        breaks = np.flatnonzero(np.diff(xs) > 1) + 1
        starts = np.concatenate(([0], breaks))
        ends = np.concatenate((breaks, [len(xs)]))
        current: list[tuple[int, int, int]] = []
        prev_index = 0
        for start_index, end_index in zip(starts, ends, strict=True):
            start = int(xs[start_index])
            end = int(xs[end_index - 1])
            overlapping: list[int] = []
            while prev_index < len(previous) and previous[prev_index][1] < start:
                prev_index += 1
            scan = prev_index
            while scan < len(previous) and previous[scan][0] <= end:
                overlapping.append(previous[scan][2])
                scan += 1
            if overlapping:
                label = find(overlapping[0])
                for other in overlapping[1:]:
                    label = union(label, other)
            else:
                next_label += 1
                label = next_label
                parent[label] = label
                area[label] = 0
                min_x[label] = start
                max_x[label] = end
                min_y[label] = y
                max_y[label] = y
                touches[label] = False
            root = find(label)
            run_area = end - start + 1
            area[root] += run_area
            min_x[root] = min(min_x[root], start)
            max_x[root] = max(max_x[root], end)
            min_y[root] = min(min_y[root], y)
            max_y[root] = max(max_y[root], y)
            touches[root] = (
                touches[root]
                or start == 0
                or end == width - 1
                or y == 0
                or y == height - 1
            )
            current.append((start, end, root))
        previous = current

    components: list[MaskComponent] = []
    for label in list(parent):
        if find(label) != label:
            continue
        components.append(
            MaskComponent(
                label=label,
                area=area[label],
                bounds=Rect(
                    x=min_x[label],
                    y=min_y[label],
                    width=max_x[label] - min_x[label] + 1,
                    height=max_y[label] - min_y[label] + 1,
                ),
                touches_edge=touches[label],
            )
        )
    return components


def filter_components(
    mask: np.ndarray,
    *,
    keep_labels: set[int] | None = None,
    min_area: int = 0,
    min_area_fraction_of_largest: float = 0,
) -> np.ndarray:
    components, labels = connected_components(mask, label_map=True)
    if labels is None or not components:
        return mask.astype(bool)
    largest_area = max(component.area for component in components)
    kept = set(keep_labels or set())
    for component in components:
        if component.area >= min_area and (
            min_area_fraction_of_largest <= 0
            or component.area >= largest_area * min_area_fraction_of_largest
        ):
            kept.add(component.label)
    if not kept:
        kept.add(max(components, key=lambda component: component.area).label)
    return np.isin(labels, list(kept))


def connected_components(
    mask: np.ndarray,
    *,
    label_map: bool = False,
) -> tuple[list[MaskComponent], np.ndarray | None]:
    foreground = mask.astype(bool)
    height, width = foreground.shape
    labels = np.zeros(foreground.shape, dtype=np.int32) if label_map else None
    seen = np.zeros(foreground.shape, dtype=bool)
    components: list[MaskComponent] = []
    label = 0
    for y in range(height):
        xs = np.flatnonzero(foreground[y] & ~seen[y])
        for raw_x in xs:
            x = int(raw_x)
            if seen[y, x] or not foreground[y, x]:
                continue
            label += 1
            area, bounds, touches_edge = _flood_component(
                foreground,
                seen,
                x,
                y,
                label,
                labels,
            )
            components.append(
                MaskComponent(
                    label=label,
                    area=area,
                    bounds=bounds,
                    touches_edge=touches_edge,
                )
            )
    return components, labels


def _flood_component(
    mask: np.ndarray,
    seen: np.ndarray,
    start_x: int,
    start_y: int,
    label: int,
    labels: np.ndarray | None,
) -> tuple[int, Rect, bool]:
    height, width = mask.shape
    stack = [(start_x, start_y)]
    seen[start_y, start_x] = True
    if labels is not None:
        labels[start_y, start_x] = label
    area = 0
    min_x = max_x = start_x
    min_y = max_y = start_y
    touches_edge = False
    while stack:
        x, y = stack.pop()
        area += 1
        min_x = min(min_x, x)
        max_x = max(max_x, x)
        min_y = min(min_y, y)
        max_y = max(max_y, y)
        touches_edge = touches_edge or x in {0, width - 1} or y in {0, height - 1}
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < width and 0 <= ny < height and mask[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                if labels is not None:
                    labels[ny, nx] = label
                stack.append((nx, ny))
    return (
        area,
        Rect(x=min_x, y=min_y, width=max_x - min_x + 1, height=max_y - min_y + 1),
        touches_edge,
    )
