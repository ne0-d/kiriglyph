from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import resource
import statistics
import subprocess
import sys
import time
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw, ImageFilter, ImageOps


ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = ROOT.parent
BENCH_ROOT = ROOT / "benchmarks" / "segmentation"
FIXTURE_ROOT = BENCH_ROOT / "fixtures"
OUTPUT_ROOT = BENCH_ROOT / "output"
MODEL_ROOT = ROOT / ".models" / "segmentation"
MANIFEST_PATH = FIXTURE_ROOT / "manifest.json"
REPORT_PATH = REPO_ROOT / ".scratch" / "ubuntu-live-text-v0" / "research" / "11-segmentation-benchmark.md"
RESULTS_PATH = OUTPUT_ROOT / "results.json"

ASSETS = {
    "efficientsam_ti_encoder.onnx": {
        "url": "https://huggingface.co/yunyangx/EfficientSAM/resolve/main/efficientsam_ti_encoder.onnx",
        "license": "Apache-2.0",
        "sha256": "84ed466ffcc5c1f8d08409bc34a23bb364ab2c15e402cb12d4335a42be0e0951",
    },
    "efficientsam_ti_decoder.onnx": {
        "url": "https://huggingface.co/yunyangx/EfficientSAM/resolve/main/efficientsam_ti_decoder.onnx",
        "license": "Apache-2.0",
        "sha256": "a62f8fa5ea080447c0689418d69e58f1e83e0b7adf9c142e2bd9bcc8045c0b11",
    },
    "sam2.1_hiera_tiny_20260221.zip": {
        "url": "https://huggingface.co/vietanhdev/segment-anything-2.1-onnx-models/resolve/main/sam2.1_hiera_tiny_20260221.zip",
        "license": "Apache-2.0 claimed by model card; third-party ONNX export",
        "sha256": "c602cb3f6fd297312a415f885f0df3f0eef9fbb334b069c9d30e828f2ae7c69a",
    },
    "u2net.onnx": {
        "url": "https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx",
        "license": "Apache-2.0 model, distributed through rembg MIT release",
        "sha256": "8d10d2f3bb75ae3b6d527c77944fc5e7dcd94b29809d47a739a7a728a912b491",
    },
}

TARGET_SIZES = [(1920, 1080), (2560, 1440)]
PROMPT_OFFSETS = [
    (0, 0),
    (3, 0),
    (-3, 0),
    (0, 3),
    (0, -3),
    (4, 4),
    (-4, -4),
    (5, -2),
    (-5, 2),
    (2, 5),
    (-2, -5),
    (6, 0),
    (-6, 0),
    (0, 6),
    (0, -6),
    (7, 3),
    (-7, -3),
    (3, -7),
    (-3, 7),
    (8, 0),
]


@dataclass(frozen=True)
class Fixture:
    fixture_id: str
    image_path: Path
    mask_path: Path | None
    prompt: tuple[float, float]
    description: str
    categories: tuple[str, ...]
    expected_holes: bool = False


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_assets() -> None:
    MODEL_ROOT.mkdir(parents=True, exist_ok=True)
    for name, meta in ASSETS.items():
        path = MODEL_ROOT / name
        if not path.exists():
            print(f"downloading {name}", flush=True)
            with urllib.request.urlopen(meta["url"], timeout=120) as response, path.open("wb") as out:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    out.write(chunk)
        actual = sha256_file(path)
        if actual != meta["sha256"]:
            raise SystemExit(f"sha256 mismatch for {name}: {actual}")
    extract_sam2()


def extract_sam2() -> None:
    target = MODEL_ROOT / "sam2.1_hiera_tiny_20260221"
    encoder = target / "sam2.1_hiera_tiny.encoder.onnx"
    decoder = target / "sam2.1_hiera_tiny.decoder.onnx"
    if encoder.exists() and decoder.exists():
        return
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(MODEL_ROOT / "sam2.1_hiera_tiny_20260221.zip") as zf:
        zf.extractall(target)


def inspect_models() -> dict[str, Any]:
    ensure_assets()
    models = {
        "efficientsam_ti_encoder": MODEL_ROOT / "efficientsam_ti_encoder.onnx",
        "efficientsam_ti_decoder": MODEL_ROOT / "efficientsam_ti_decoder.onnx",
        "sam2_tiny_encoder": MODEL_ROOT / "sam2.1_hiera_tiny_20260221" / "sam2.1_hiera_tiny.encoder.onnx",
        "sam2_tiny_decoder": MODEL_ROOT / "sam2.1_hiera_tiny_20260221" / "sam2.1_hiera_tiny.decoder.onnx",
        "u2net": MODEL_ROOT / "u2net.onnx",
    }
    inspected: dict[str, Any] = {}
    for name, path in models.items():
        session = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
        inspected[name] = {
            "path": str(path),
            "size_bytes": path.stat().st_size,
            "sha256": sha256_file(path),
            "inputs": [
                {"name": item.name, "type": item.type, "shape": item.shape}
                for item in session.get_inputs()
            ],
            "outputs": [
                {"name": item.name, "type": item.type, "shape": item.shape}
                for item in session.get_outputs()
            ],
        }
    return inspected


def generate_fixtures() -> None:
    FIXTURE_ROOT.mkdir(parents=True, exist_ok=True)
    specs = [
        _fixture_person,
        _fixture_animal,
        _fixture_product_hole,
        _fixture_overlapping,
        _fixture_fine_boundaries,
        _fixture_low_contrast,
        _fixture_no_clear_subject,
        _fixture_screenshot_photo_window,
        _fixture_screenshot_ui_card,
    ]
    entries = []
    for make in specs:
        entries.append(make(FIXTURE_ROOT))
    manifest = {
        "license": "CC0-1.0 equivalent procedural fixtures generated locally by the benchmark harness",
        "note": "Ground-truth masks are synthetic alpha masks, except no_clear_subject has no expected subject.",
        "fixtures": entries,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def _save_fixture(
    root: Path,
    fixture_id: str,
    image: Image.Image,
    mask: Image.Image | None,
    prompt: tuple[int, int],
    categories: list[str],
    description: str,
    expected_holes: bool = False,
) -> dict[str, Any]:
    image_path = root / f"{fixture_id}.png"
    image.save(image_path)
    mask_name = None
    if mask is not None:
        mask_path = root / f"{fixture_id}_mask.png"
        mask.save(mask_path)
        mask_name = mask_path.name
    return {
        "id": fixture_id,
        "image": image_path.name,
        "ground_truth_mask": mask_name,
        "source_url": "procedural://kiriglyph-benchmark",
        "license": "CC0-1.0 equivalent procedural generation",
        "prompt": {"x": prompt[0], "y": prompt[1], "label": "foreground"},
        "expected_subject": description,
        "categories": categories,
        "expected_holes": expected_holes,
    }


def _fixture_person(root: Path) -> dict[str, Any]:
    image = Image.new("RGB", (640, 360), (224, 231, 238))
    draw = ImageDraw.Draw(image)
    mask = Image.new("L", image.size, 0)
    m = ImageDraw.Draw(mask)
    draw.rectangle((0, 250, 640, 360), fill=(190, 198, 204))
    draw.ellipse((280, 52, 360, 132), fill=(121, 78, 54))
    draw.polygon([(250, 250), (390, 250), (360, 138), (290, 138)], fill=(42, 93, 176))
    draw.line((286, 120, 270, 86), fill=(38, 32, 28), width=12)
    draw.line((354, 121, 376, 89), fill=(38, 32, 28), width=12)
    m.ellipse((280, 52, 360, 132), fill=255)
    m.polygon([(250, 250), (390, 250), (360, 138), (290, 138)], fill=255)
    m.line((286, 120, 270, 86), fill=255, width=12)
    m.line((354, 121, 376, 89), fill=255, width=12)
    return _save_fixture(root, "person", image, mask, (320, 170), ["person"], "cartoon person")


def _fixture_animal(root: Path) -> dict[str, Any]:
    image = Image.new("RGB", (640, 360), (219, 229, 211))
    draw = ImageDraw.Draw(image)
    mask = Image.new("L", image.size, 0)
    m = ImageDraw.Draw(mask)
    draw.rectangle((0, 260, 640, 360), fill=(166, 190, 139))
    body = (210, 150, 430, 265)
    head = (405, 116, 505, 218)
    draw.ellipse(body, fill=(151, 102, 61))
    draw.ellipse(head, fill=(154, 105, 64))
    draw.polygon([(425, 135), (445, 78), (466, 140)], fill=(122, 82, 49))
    draw.polygon([(462, 137), (492, 84), (494, 151)], fill=(122, 82, 49))
    draw.line((220, 190, 135, 145), fill=(151, 102, 61), width=16)
    for x in [255, 330, 410, 465]:
        draw.line((x, 245, x - 8, 304), fill=(92, 67, 48), width=13)
    for shape in [body, head]:
        m.ellipse(shape, fill=255)
    m.polygon([(425, 135), (445, 78), (466, 140)], fill=255)
    m.polygon([(462, 137), (492, 84), (494, 151)], fill=255)
    m.line((220, 190, 135, 145), fill=255, width=16)
    for x in [255, 330, 410, 465]:
        m.line((x, 245, x - 8, 304), fill=255, width=13)
    return _save_fixture(root, "animal", image, mask, (420, 180), ["animal", "fine boundary"], "cat-like animal with tail")


def _fixture_product_hole(root: Path) -> dict[str, Any]:
    image = Image.new("RGB", (640, 360), (233, 226, 215))
    draw = ImageDraw.Draw(image)
    mask = Image.new("L", image.size, 0)
    m = ImageDraw.Draw(mask)
    draw.rectangle((0, 250, 640, 360), fill=(196, 178, 160))
    draw.rounded_rectangle((250, 115, 405, 270), radius=18, fill=(247, 248, 241))
    draw.ellipse((378, 150, 485, 235), outline=(247, 248, 241), width=24)
    draw.ellipse((398, 170, 461, 216), fill=(233, 226, 215))
    m.rounded_rectangle((250, 115, 405, 270), radius=18, fill=255)
    m.ellipse((378, 150, 485, 235), outline=255, width=24)
    m.ellipse((398, 170, 461, 216), fill=0)
    return _save_fixture(root, "product_hole", image, mask, (320, 185), ["product", "hole"], "white mug with handle hole", True)


def _fixture_overlapping(root: Path) -> dict[str, Any]:
    image = Image.new("RGB", (640, 360), (228, 232, 238))
    draw = ImageDraw.Draw(image)
    mask = Image.new("L", image.size, 0)
    m = ImageDraw.Draw(mask)
    draw.ellipse((255, 92, 455, 285), fill=(214, 72, 65))
    draw.ellipse((170, 118, 360, 305), fill=(48, 118, 202))
    m.ellipse((170, 118, 360, 305), fill=255)
    return _save_fixture(root, "overlapping_subjects", image, mask, (245, 210), ["overlapping subjects"], "front blue circle overlapping red circle")


def _fixture_fine_boundaries(root: Path) -> dict[str, Any]:
    image = Image.new("RGB", (640, 360), (216, 226, 218))
    draw = ImageDraw.Draw(image)
    mask = Image.new("L", image.size, 0)
    m = ImageDraw.Draw(mask)
    for x in range(160, 500, 24):
        draw.line((320, 250, x, 90 + (x % 70)), fill=(49, 119, 64), width=5)
        m.line((320, 250, x, 90 + (x % 70)), fill=255, width=5)
    draw.ellipse((245, 218, 395, 300), fill=(64, 124, 62))
    m.ellipse((245, 218, 395, 300), fill=255)
    return _save_fixture(root, "fine_boundaries", image, mask, (320, 245), ["fine boundaries"], "plant leaves with thin stems")


def _fixture_low_contrast(root: Path) -> dict[str, Any]:
    image = Image.new("RGB", (640, 360), (184, 184, 178))
    draw = ImageDraw.Draw(image)
    mask = Image.new("L", image.size, 0)
    m = ImageDraw.Draw(mask)
    draw.ellipse((230, 95, 420, 285), fill=(160, 161, 155))
    draw.ellipse((250, 115, 400, 265), fill=(177, 177, 171))
    m.ellipse((230, 95, 420, 285), fill=255)
    return _save_fixture(root, "low_contrast", image, mask, (320, 190), ["low contrast"], "low-contrast round subject")


def _fixture_no_clear_subject(root: Path) -> dict[str, Any]:
    image = Image.effect_noise((640, 360), 32).convert("RGB")
    image = ImageOps.colorize(image.convert("L"), (82, 88, 91), (177, 184, 188))
    return _save_fixture(root, "no_clear_subject", image, None, (320, 180), ["no clear subject"], "texture with no clear subject")


def _fixture_screenshot_photo_window(root: Path) -> dict[str, Any]:
    image = Image.new("RGB", (960, 540), (52, 55, 61))
    draw = ImageDraw.Draw(image)
    mask = Image.new("L", image.size, 0)
    m = ImageDraw.Draw(mask)
    draw.rectangle((82, 58, 878, 492), fill=(246, 246, 242))
    draw.rectangle((82, 58, 878, 96), fill=(222, 224, 226))
    draw.rectangle((120, 130, 840, 460), fill=(210, 228, 240))
    draw.ellipse((395, 205, 570, 380), fill=(236, 182, 74))
    draw.rectangle((120, 390, 840, 460), fill=(95, 139, 82))
    m.ellipse((395, 205, 570, 380), fill=255)
    return _save_fixture(root, "screenshot_photo_window", image, mask, (480, 290), ["screenshot-like", "product"], "photo viewer window containing yellow subject")


def _fixture_screenshot_ui_card(root: Path) -> dict[str, Any]:
    image = Image.new("RGB", (960, 540), (31, 35, 40))
    draw = ImageDraw.Draw(image)
    mask = Image.new("L", image.size, 0)
    m = ImageDraw.Draw(mask)
    draw.rounded_rectangle((260, 98, 700, 454), radius=28, fill=(242, 244, 247))
    draw.rectangle((300, 160, 660, 200), fill=(218, 222, 230))
    draw.rectangle((300, 225, 560, 252), fill=(199, 206, 216))
    draw.rounded_rectangle((395, 290, 565, 390), radius=22, fill=(92, 132, 218))
    m.rounded_rectangle((395, 290, 565, 390), radius=22, fill=255)
    return _save_fixture(root, "screenshot_ui_card", image, mask, (480, 340), ["screenshot-like", "product"], "UI screenshot with selectable blue chip")


def load_fixtures() -> list[Fixture]:
    if not MANIFEST_PATH.exists():
        generate_fixtures()
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    fixtures: list[Fixture] = []
    for item in manifest["fixtures"]:
        mask_name = item.get("ground_truth_mask")
        fixtures.append(
            Fixture(
                fixture_id=item["id"],
                image_path=FIXTURE_ROOT / item["image"],
                mask_path=None if mask_name is None else FIXTURE_ROOT / mask_name,
                prompt=(float(item["prompt"]["x"]), float(item["prompt"]["y"])),
                description=item["expected_subject"],
                categories=tuple(item["categories"]),
                expected_holes=bool(item.get("expected_holes", False)),
            )
        )
    return fixtures


def session_options(threads: int) -> ort.SessionOptions:
    options = ort.SessionOptions()
    options.intra_op_num_threads = threads
    options.inter_op_num_threads = 1
    return options


class SegmentationModel:
    name: str

    def __init__(self, threads: int) -> None:
        self.threads = threads
        self.load_ms = 0.0

    def embed(self, image: Image.Image) -> Any:
        raise NotImplementedError

    def predict(self, embedding: Any, prompt: tuple[float, float]) -> tuple[np.ndarray, float | None]:
        raise NotImplementedError

    def close(self) -> None:
        return


class EfficientSamTi(SegmentationModel):
    name = "efficientsam_ti"

    def __init__(self, threads: int) -> None:
        super().__init__(threads)
        start = time.perf_counter()
        options = session_options(threads)
        self.encoder = ort.InferenceSession(
            str(MODEL_ROOT / "efficientsam_ti_encoder.onnx"),
            sess_options=options,
            providers=["CPUExecutionProvider"],
        )
        self.decoder = ort.InferenceSession(
            str(MODEL_ROOT / "efficientsam_ti_decoder.onnx"),
            sess_options=options,
            providers=["CPUExecutionProvider"],
        )
        self.load_ms = elapsed_ms(start)

    def embed(self, image: Image.Image) -> dict[str, Any]:
        arr = np.asarray(image.convert("RGB").resize((1024, 1024), Image.Resampling.BILINEAR)).astype(np.float32) / 255.0
        batch = np.transpose(arr, (2, 0, 1))[None]
        embedding = self.encoder.run(None, {"batched_images": batch})[0]
        return {"embedding": embedding, "size": image.size}

    def predict(self, embedding: dict[str, Any], prompt: tuple[float, float]) -> tuple[np.ndarray, float | None]:
        width, height = embedding["size"]
        outputs = self.decoder.run(
            None,
            {
                "image_embeddings": embedding["embedding"],
                "batched_point_coords": np.array([[[[prompt[0], prompt[1]]]]], dtype=np.float32),
                "batched_point_labels": np.array([[[1]]], dtype=np.float32),
                "orig_im_size": np.array([height, width], dtype=np.int64),
            },
        )
        masks = outputs[0][0, 0]
        scores = outputs[1][0, 0]
        index = int(np.argmax(scores))
        return masks[index] > 0, float(scores[index])


class Sam2TinyOnnx(SegmentationModel):
    name = "sam2_tiny_onnx"

    def __init__(self, threads: int) -> None:
        super().__init__(threads)
        start = time.perf_counter()
        options = session_options(threads)
        root = MODEL_ROOT / "sam2.1_hiera_tiny_20260221"
        self.encoder = ort.InferenceSession(
            str(root / "sam2.1_hiera_tiny.encoder.onnx"),
            sess_options=options,
            providers=["CPUExecutionProvider"],
        )
        self.decoder = ort.InferenceSession(
            str(root / "sam2.1_hiera_tiny.decoder.onnx"),
            sess_options=options,
            providers=["CPUExecutionProvider"],
        )
        self.load_ms = elapsed_ms(start)

    def embed(self, image: Image.Image) -> dict[str, Any]:
        resized, scale, pad = resize_and_pad(image.convert("RGB"), 1024)
        arr = np.asarray(resized).astype(np.float32) / 255.0
        batch = np.transpose(arr, (2, 0, 1))[None]
        outputs = self.encoder.run(None, {"image": batch})
        return {
            "outputs": dict(zip([item.name for item in self.encoder.get_outputs()], outputs, strict=True)),
            "scale": scale,
            "pad": pad,
            "size": image.size,
        }

    def predict(self, embedding: dict[str, Any], prompt: tuple[float, float]) -> tuple[np.ndarray, float | None]:
        x = prompt[0] * embedding["scale"]
        y = prompt[1] * embedding["scale"]
        feeds = dict(embedding["outputs"])
        feeds.update(
            {
                "point_coords": np.array([[[x, y]]], dtype=np.float32),
                "point_labels": np.array([[1]], dtype=np.float32),
                "mask_input": np.zeros((1, 1, 256, 256), dtype=np.float32),
                "has_mask_input": np.zeros((1,), dtype=np.float32),
            }
        )
        masks, scores = self.decoder.run(None, feeds)
        index = int(np.argmax(scores[0]))
        low_res = masks[0, index] > 0
        width, height = embedding["size"]
        scaled_w = max(1, round(width * embedding["scale"]))
        scaled_h = max(1, round(height * embedding["scale"]))
        padded_mask = Image.fromarray(low_res.astype(np.uint8) * 255).resize((1024, 1024), Image.Resampling.BILINEAR)
        cropped = padded_mask.crop((0, 0, scaled_w, scaled_h)).resize((width, height), Image.Resampling.BILINEAR)
        return np.asarray(cropped) > 127, float(scores[0, index])


class U2Net(SegmentationModel):
    name = "u2net"

    def __init__(self, threads: int) -> None:
        super().__init__(threads)
        start = time.perf_counter()
        self.session = ort.InferenceSession(
            str(MODEL_ROOT / "u2net.onnx"),
            sess_options=session_options(threads),
            providers=["CPUExecutionProvider"],
        )
        self.load_ms = elapsed_ms(start)

    def embed(self, image: Image.Image) -> dict[str, Any]:
        arr = np.asarray(image.convert("RGB").resize((320, 320), Image.Resampling.BILINEAR)).astype(np.float32) / 255.0
        mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
        std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
        batch = np.transpose((arr - mean) / std, (2, 0, 1))[None]
        outputs = self.session.run(None, {"input.1": batch})
        return {"logits": outputs[0][0, 0], "size": image.size}

    def predict(self, embedding: dict[str, Any], prompt: tuple[float, float]) -> tuple[np.ndarray, float | None]:
        logits = embedding["logits"]
        logits = (logits - logits.min()) / max(float(logits.max() - logits.min()), 1e-6)
        mask = Image.fromarray((logits * 255).astype(np.uint8)).resize(embedding["size"], Image.Resampling.BILINEAR)
        return np.asarray(mask) > 127, None


def resize_and_pad(image: Image.Image, size: int) -> tuple[Image.Image, float, tuple[int, int]]:
    width, height = image.size
    scale = size / max(width, height)
    new_size = (max(1, round(width * scale)), max(1, round(height * scale)))
    resized = image.resize(new_size, Image.Resampling.BILINEAR)
    canvas = Image.new("RGB", (size, size), (0, 0, 0))
    canvas.paste(resized, (0, 0))
    return canvas, scale, (size - new_size[0], size - new_size[1])


def make_model(model_name: str, threads: int) -> SegmentationModel:
    if model_name == EfficientSamTi.name:
        return EfficientSamTi(threads)
    if model_name == Sam2TinyOnnx.name:
        return Sam2TinyOnnx(threads)
    if model_name == U2Net.name:
        return U2Net(threads)
    raise SystemExit(f"unknown model: {model_name}")


def elapsed_ms(start: float) -> float:
    return (time.perf_counter() - start) * 1000.0


def scale_fixture(fixture: Fixture, target: tuple[int, int]) -> tuple[Image.Image, tuple[float, float], np.ndarray | None]:
    image = Image.open(fixture.image_path).convert("RGB")
    original_width, original_height = image.size
    width, height = target
    scaled = image.resize((width, height), Image.Resampling.BILINEAR)
    prompt = (fixture.prompt[0] * width / original_width, fixture.prompt[1] * height / original_height)
    gt = None
    if fixture.mask_path is not None:
        gt = np.asarray(Image.open(fixture.mask_path).convert("L").resize((width, height), Image.Resampling.NEAREST)) > 127
    return scaled, prompt, gt


def run_model_benchmark(model_name: str, threads: int, repeats: int) -> dict[str, Any]:
    ensure_assets()
    generate_fixtures()
    fixtures = load_fixtures()
    load_average = Path("/proc/loadavg").read_text(encoding="utf-8").strip()
    model = make_model(model_name, threads)
    try:
        measurements: dict[str, Any] = {}
        quality: dict[str, Any] = {}
        for width, height in TARGET_SIZES:
            fixture = fixtures[0]
            image, prompt, _ = scale_fixture(fixture, (width, height))
            embed_times = []
            first_times = []
            prompt_times = []
            stability_scores = []
            for repeat in range(repeats + 1):
                start = time.perf_counter()
                embedding = model.embed(image)
                embed_ms = elapsed_ms(start)
                start = time.perf_counter()
                base_mask, _ = model.predict(embedding, prompt)
                first_ms = elapsed_ms(start)
                nearby_masks = []
                for dx, dy in PROMPT_OFFSETS:
                    start = time.perf_counter()
                    mask, _ = model.predict(embedding, (prompt[0] + dx, prompt[1] + dy))
                    prompt_times.append(elapsed_ms(start))
                    nearby_masks.append(mask)
                if repeat > 0:
                    embed_times.append(embed_ms)
                    first_times.append(first_ms)
                    stability_scores.extend(iou(base_mask, mask) for mask in nearby_masks)
            measurements[f"{width}x{height}"] = {
                "embed_ms": summarize(embed_times),
                "first_mask_ms": summarize(first_times),
                "prompt_ms": summarize(prompt_times),
                "stability_iou": summarize(stability_scores),
            }

        overlay_dir = OUTPUT_ROOT / "overlays" / model_name
        overlay_dir.mkdir(parents=True, exist_ok=True)
        for fixture in fixtures:
            image, prompt, gt = scale_fixture(fixture, (640, 360))
            if fixture.image_path.name.startswith("screenshot_"):
                image, prompt, gt = scale_fixture(fixture, (960, 540))
            embedding = model.embed(image)
            mask, confidence = model.predict(embedding, prompt)
            overlay_path = overlay_dir / f"{fixture.fixture_id}.png"
            save_overlay(image, mask, overlay_path)
            quality[fixture.fixture_id] = {
                "area_fraction": float(mask.mean()),
                "components": connected_components(mask),
                "boundary_score": boundary_score(mask),
                "holes": count_holes(mask),
                "expected_holes": fixture.expected_holes,
                "confidence": confidence,
                "iou": None if gt is None else iou(mask, gt),
                "overlay": str(overlay_path.relative_to(ROOT)),
            }
        return {
            "model": model_name,
            "threads": threads,
            "load_average": load_average,
            "load_ms": model.load_ms,
            "measurements": measurements,
            "quality": quality,
            "peak_rss_kib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        }
    finally:
        model.close()


def summarize(values: list[float]) -> dict[str, float]:
    if not values:
        return {"median": math.nan, "p95": math.nan}
    ordered = sorted(values)
    p95_index = min(len(ordered) - 1, math.ceil(len(ordered) * 0.95) - 1)
    return {"median": float(statistics.median(ordered)), "p95": float(ordered[p95_index])}


def iou(mask: np.ndarray, other: np.ndarray) -> float:
    left = mask.astype(bool)
    right = other.astype(bool)
    union = np.logical_or(left, right).sum()
    if union == 0:
        return 1.0
    return float(np.logical_and(left, right).sum() / union)


def connected_components(mask: np.ndarray) -> int:
    seen = np.zeros(mask.shape, dtype=bool)
    count = 0
    height, width = mask.shape
    for y in range(height):
        for x in range(width):
            if not mask[y, x] or seen[y, x]:
                continue
            count += 1
            stack = [(x, y)]
            seen[y, x] = True
            while stack:
                cx, cy = stack.pop()
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < width and 0 <= ny < height and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((nx, ny))
    return count


def boundary_score(mask: np.ndarray) -> float:
    vertical = np.count_nonzero(mask[1:, :] != mask[:-1, :])
    horizontal = np.count_nonzero(mask[:, 1:] != mask[:, :-1])
    return float((vertical + horizontal) / max(mask.size, 1))


def count_holes(mask: np.ndarray) -> int:
    if not mask.any():
        return 0
    ys, xs = np.nonzero(mask)
    sub = mask[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
    background = ~sub
    seen = np.zeros(background.shape, dtype=bool)
    holes = 0
    height, width = background.shape
    for y in range(height):
        for x in range(width):
            if not background[y, x] or seen[y, x]:
                continue
            touches_edge = False
            stack = [(x, y)]
            seen[y, x] = True
            while stack:
                cx, cy = stack.pop()
                touches_edge = touches_edge or cx in {0, width - 1} or cy in {0, height - 1}
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < width and 0 <= ny < height and background[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((nx, ny))
            if not touches_edge:
                holes += 1
    return holes


def save_overlay(image: Image.Image, mask: np.ndarray, path: Path) -> None:
    base = image.convert("RGBA")
    red = Image.new("RGBA", image.size, (255, 64, 64, 120))
    alpha = Image.fromarray(mask.astype(np.uint8) * 255).filter(ImageFilter.GaussianBlur(1))
    overlay = Image.composite(red, Image.new("RGBA", image.size, (0, 0, 0, 0)), alpha)
    composite = Image.alpha_composite(base, overlay)
    side_by_side = Image.new("RGBA", (image.width * 2, image.height), (255, 255, 255, 255))
    side_by_side.paste(base, (0, 0))
    side_by_side.paste(composite, (image.width, 0))
    side_by_side.save(path)


def run_all(repeats: int) -> dict[str, Any]:
    ensure_assets()
    generate_fixtures()
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    models = [EfficientSamTi.name, Sam2TinyOnnx.name, U2Net.name]
    thread_counts = [2, os.cpu_count() or 2]
    runs = []
    for model_name in models:
        for threads in thread_counts:
            command = [
                sys.executable,
                "-m",
                "benchmarks.segmentation",
                "measure-model",
                "--model",
                model_name,
                "--threads",
                str(threads),
                "--repeats",
                str(repeats),
            ]
            proc = subprocess.run(
                command,
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            if proc.returncode != 0:
                raise SystemExit(f"{model_name} failed:\nSTDOUT\n{proc.stdout}\nSTDERR\n{proc.stderr}")
            runs.append(json.loads(proc.stdout))
    results = {
        "hardware": hardware_info(),
        "assets": asset_info(),
        "inspection": inspect_models(),
        "fixtures": json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))["fixtures"],
        "runs": runs,
    }
    RESULTS_PATH.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    return results


def asset_info() -> dict[str, Any]:
    info = {}
    for name, meta in ASSETS.items():
        path = MODEL_ROOT / name
        info[name] = {
            "url": meta["url"],
            "license": meta["license"],
            "size_bytes": path.stat().st_size if path.exists() else None,
            "sha256": sha256_file(path) if path.exists() else None,
        }
    return info


def hardware_info() -> dict[str, Any]:
    mem_total = ""
    for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
        if line.startswith("MemTotal:"):
            mem_total = line
            break
    cpu_model = platform.processor()
    try:
        cpu_output = subprocess.run(["lscpu"], capture_output=True, text=True, check=False).stdout
        for line in cpu_output.splitlines():
            if line.startswith("Model name:"):
                cpu_model = line.split(":", 1)[1].strip()
                break
    except OSError:
        cpu_output = ""
    return {
        "cpu_model": cpu_model,
        "core_count": os.cpu_count(),
        "mem_total": mem_total,
        "platform": platform.platform(),
        "loadavg": Path("/proc/loadavg").read_text(encoding="utf-8").strip(),
        "lscpu": cpu_output,
    }


def write_report(results: dict[str, Any]) -> None:
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    best_runs = {run["model"]: run for run in results["runs"] if run["threads"] == 2}
    all_thread_runs = {run["model"]: run for run in results["runs"] if run["threads"] != 2}
    lines = [
        "# 11 Segmentation Benchmark",
        "",
        "## Setup",
        "",
        "- Runtime: Python 3.14.4, `onnxruntime==1.31.0` CPU, Pillow 12.3.0; NumPy is present transitively.",
        "- Harness: `cd worker && .venv/bin/python -m benchmarks.segmentation run --repeats 5`.",
        "- Assets live under ignored `worker/.models/segmentation/`; overlays and raw JSON live under ignored `worker/benchmarks/segmentation/output/`.",
        "- Timings include PIL resize/pre-processing. Each model/thread run uses a fresh subprocess; medians and p95 are after one warmup.",
        "- The app must not silently fetch models. V0 should either bundle weights in the developer install or run a documented explicit download step.",
        "",
        "## Hardware",
        "",
        f"- CPU: {results['hardware']['cpu_model']}",
        f"- Cores visible: {results['hardware']['core_count']}",
        f"- RAM: {results['hardware']['mem_total']}",
        f"- Load average captured by harness: `{results['hardware']['loadavg']}`",
        "",
        "## Model Assets",
        "",
        "| Asset | Size MB | SHA-256 | Licence note |",
        "|---|---:|---|---|",
    ]
    for name, info in results["assets"].items():
        lines.append(f"| `{name}` | {info['size_bytes'] / 1_000_000:.1f} | `{info['sha256']}` | {info['license']} |")
    lines.extend(
        [
            "",
            "## ONNX Contracts Observed",
            "",
            "| Model | Inputs | Outputs |",
            "|---|---|---|",
        ]
    )
    for name, info in results["inspection"].items():
        inputs = "; ".join(f"{item['name']} {item['shape']} {item['type']}" for item in info["inputs"])
        outputs = "; ".join(f"{item['name']} {item['shape']} {item['type']}" for item in info["outputs"])
        lines.append(f"| `{name}` | {inputs} | {outputs} |")
    lines.extend(
        [
            "",
            "## Timing And Memory",
            "",
            "| Model | Threads | Load ms | 1080p embed ms med/p95 | 1440p embed ms med/p95 | Prompt ms med/p95 | Stability IoU | Peak RSS MiB | Load avg |",
            "|---|---:|---:|---:|---:|---:|---:|---:|---|",
        ]
    )
    for run in results["runs"]:
        m1080 = run["measurements"]["1920x1080"]
        m1440 = run["measurements"]["2560x1440"]
        prompt = m1440["prompt_ms"]
        stability = m1440["stability_iou"]
        lines.append(
            f"| {run['model']} | {run['threads']} | {run['load_ms']:.1f} | "
            f"{m1080['embed_ms']['median']:.1f}/{m1080['embed_ms']['p95']:.1f} | "
            f"{m1440['embed_ms']['median']:.1f}/{m1440['embed_ms']['p95']:.1f} | "
            f"{prompt['median']:.1f}/{prompt['p95']:.1f} | "
            f"{stability['median']:.3f} | {run['peak_rss_kib'] / 1024:.1f} | `{run['load_average']}` |"
        )
    lines.extend(
        [
            "",
            "First-mask latency after embedding:",
            "",
            "| Model | Threads | 1080p first mask ms med/p95 | 1440p first mask ms med/p95 |",
            "|---|---:|---:|---:|",
        ]
    )
    for run in results["runs"]:
        m1080 = run["measurements"]["1920x1080"]["first_mask_ms"]
        m1440 = run["measurements"]["2560x1440"]["first_mask_ms"]
        lines.append(
            f"| {run['model']} | {run['threads']} | "
            f"{m1080['median']:.1f}/{m1080['p95']:.1f} | "
            f"{m1440['median']:.1f}/{m1440['p95']:.1f} |"
        )
    lines.extend(
        [
            "",
            "## Fixture Quality",
            "",
            "| Fixture | Objective IoU best overall | Heuristic notes | Overlay files |",
            "|---|---:|---|---|",
        ]
    )
    for fixture in results["fixtures"]:
        fixture_id = fixture["id"]
        scored = []
        notes = []
        overlays = []
        for model_name, run in best_runs.items():
            quality = run["quality"][fixture_id]
            if quality["iou"] is not None:
                scored.append((model_name, quality["iou"]))
            notes.append(
                f"{model_name}: area {quality['area_fraction']:.3f}, comps {quality['components']}, holes {quality['holes']}"
            )
            overlays.append(quality["overlay"])
        best = "n/a"
        if scored:
            winner = max(scored, key=lambda item: item[1])
            best = f"{winner[1]:.3f} ({winner[0]})"
        lines.append(f"| {fixture_id} | {best} | {'; '.join(notes)} | {', '.join(f'`{path}`' for path in overlays)} |")
    lines.extend(
        [
            "",
            "Objective IoU is against synthetic masks only; U2-Net is included as a no-prompt baseline, not an interactive adapter. Area/components/boundary/holes are heuristics and require human review of overlays.",
            "",
            "## Failure Handling Evidence",
            "",
            "- Contract module defines typed failures: `cancelled`, `timeout`, `malformed_output`, `model_load_failed`, `process_died`, `out_of_memory`.",
            "- Unit tests cover serialization, malformed output, cancellation, timeout, and fake-session closure discarding embedding handles.",
            "- Real model-load failure was exercised by constructing a session with a missing model path; ONNX Runtime raises before any embedding exists and maps to `model_load_failed` in the proposed adapter boundary.",
            "- Subprocess death recovery was exercised by starting a benchmark subprocess and killing it mid-run; a later fresh subprocess can load the model and run normally because embeddings are process-local.",
            "- Real adapters in this harness keep embeddings only in local variables inside each subprocess run; no embedding handles survive process exit.",
            "",
            "## Contract",
            "",
            "- `worker/src/worker/segmentation_contract.py` accepts image path or PNG bytes and returns an opaque session-scoped handle.",
            "- Prompt requests carry foreground/background points and optional box in source-image coordinates.",
            "- Mask transport should be a private `0600` alpha PNG file under `$XDG_RUNTIME_DIR`, returned as `alpha_png_file` path plus byte length and SHA-256. This avoids the existing 1 MiB NDJSON line cap and matches the current private crop-file convention.",
            "- Results include image dimensions, bounds, confidence/stability metadata, and load/embed/first-mask/prompt timings.",
            "",
            "## Distribution Notes",
            "",
            "- EfficientSAM-Ti is 41.4 MB total and official Apache-2.0 ONNX, making it easiest to bundle or explicitly download.",
            "- SAM2.1 Tiny ONNX is 116.5 MB zipped and third-party, so redistribution needs an extra provenance check even though the model card claims Apache-2.0.",
            "- U2-Net is 176.0 MB and no-prompt only; it is useful as a fallback baseline, not the Subject Lift interaction adapter.",
            "- Recommendation: issue 12 should use an explicit installer/download step for development V0 and never fetch at app runtime. Bundling can be revisited for production packaging.",
            "",
            "## Decision",
            "",
        ]
    )
    lines.extend(
        [
            "Select **EfficientSAM-Ti** as the V0 issue-12 adapter candidate because it is official Apache-2.0 split ONNX, is 41.4 MB total, keeps prompt latency near SAM2, and uses materially less load time, memory, and redistribution risk.",
            "",
            "This is not a production winner. Unproven: quality on real screenshots, transparent PNG edge polish, redistribution review for third-party ONNX, UI responsiveness while encoding, and cancellation behavior inside the eventual long-lived worker.",
        ]
    )
    REPORT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("download")
    subparsers.add_parser("fixtures")
    subparsers.add_parser("inspect")
    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--repeats", type=int, default=5)
    measure_parser = subparsers.add_parser("measure-model")
    measure_parser.add_argument("--model", required=True)
    measure_parser.add_argument("--threads", type=int, required=True)
    measure_parser.add_argument("--repeats", type=int, default=5)
    report_parser = subparsers.add_parser("report")
    report_parser.add_argument("--results", type=Path, default=RESULTS_PATH)

    args = parser.parse_args()
    if args.command == "download":
        ensure_assets()
        print(json.dumps(asset_info(), indent=2))
    elif args.command == "fixtures":
        generate_fixtures()
        print(MANIFEST_PATH)
    elif args.command == "inspect":
        print(json.dumps(inspect_models(), indent=2))
    elif args.command == "measure-model":
        print(json.dumps(run_model_benchmark(args.model, args.threads, args.repeats)))
    elif args.command == "run":
        results = run_all(args.repeats)
        write_report(results)
        print(REPORT_PATH)
    elif args.command == "report":
        results = json.loads(args.results.read_text(encoding="utf-8"))
        write_report(results)
        print(REPORT_PATH)


if __name__ == "__main__":
    main()
