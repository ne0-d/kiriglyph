#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
except ImportError as exc:  # pragma: no cover - runtime dependency check.
    raise SystemExit("Pillow is required; run with worker/.venv/bin/python") from exc

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "scripts" / "acceptance" / "corpus" / "manifest.json"
GENERATED = ROOT / "scripts" / "acceptance" / "corpus" / "generated"
OUTPUT = ROOT / "scripts" / "acceptance" / "output" / "ocr-corpus"
EVIDENCE = ROOT / ".scratch" / "ubuntu-live-text-v0" / "evidence" / "ocr-corpus-results.md"


@dataclass
class OcrCase:
    case_id: str
    image_path: Path
    expected_lines: list[str]
    paragraphs: list[list[int]]
    font_paths: list[str]
    notes: list[str]


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a small screenshot-like OCR corpus and evaluate the real worker.")
    parser.add_argument("--worker-python", default=str(ROOT / "worker" / ".venv" / "bin" / "python"))
    parser.add_argument("--skip-dart", action="store_true", help="Do not run the paragraph grouping Flutter test")
    args = parser.parse_args()
    cases = generate_corpus()
    results = run_worker(cases, args.worker_python)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    results_json = OUTPUT / "ocr-results.json"
    results_json.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    paragraph = None
    if not args.skip_dart:
        paragraph = run_paragraph_eval(results_json)
    write_report(results, paragraph)
    print(f"Wrote {EVIDENCE}")
    print(aggregate_line(results, paragraph))
    return 0


def font(*names: str, size: int) -> tuple[ImageFont.FreeTypeFont, str]:
    candidates = [
        Path("/usr/share/fonts/truetype/dejavu") / name for name in names
    ] + [Path("/usr/share/fonts/truetype/ubuntu") / name for name in names]
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size=size), str(path)
    return ImageFont.load_default(size=size), "Pillow default bitmap font"


def generate_corpus() -> list[OcrCase]:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    GENERATED.mkdir(parents=True, exist_ok=True)
    cases = []
    for item in manifest["cases"]:
        image, fonts, notes = render_case(item)
        path = GENERATED / f"{item['id']}.png"
        image.save(path)
        cases.append(
            OcrCase(
                case_id=item["id"],
                image_path=path,
                expected_lines=item["expected_lines"],
                paragraphs=item["paragraphs"],
                font_paths=sorted(set(fonts)),
                notes=notes,
            )
        )
    return cases


def render_case(item: dict[str, Any]) -> tuple[Image.Image, list[str], list[str]]:
    kind = item["kind"]
    lines = item["expected_lines"]
    fonts: list[str] = []
    notes: list[str] = []
    regular, regular_path = font("DejaVuSans.ttf", "Ubuntu-R.ttf", size=28)
    small, small_path = font("DejaVuSans.ttf", "Ubuntu-R.ttf", size=18)
    mono, mono_path = font("DejaVuSansMono.ttf", "UbuntuMono-R.ttf", size=24)
    fonts.extend([regular_path, small_path, mono_path])
    image = Image.new("RGB", (1000, 620), (246, 244, 238))
    draw = ImageDraw.Draw(image)
    if kind == "light_article":
        draw.rectangle((80, 60, 920, 540), fill=(255, 255, 255), outline=(210, 210, 210))
        y = 130
        for line in lines:
            draw.text((130, y), line, font=regular, fill=(28, 28, 28))
            y += 54
    elif kind == "dark_code":
        image = Image.new("RGB", (1000, 620), (34, 39, 46))
        draw = ImageDraw.Draw(image)
        y = 150
        for line in lines:
            draw.text((120, y), line, font=mono, fill=(220, 232, 242))
            y += 46
    elif kind == "two_columns":
        draw.rectangle((70, 70, 930, 550), fill=(255, 255, 255))
        positions = [(120, 150), (120, 205), (560, 150), (560, 205)]
        for line, pos in zip(lines, positions, strict=True):
            draw.text(pos, line, font=regular, fill=(24, 24, 24))
    elif kind == "ui_buttons":
        image = Image.new("RGB", (1000, 620), (238, 240, 244))
        draw = ImageDraw.Draw(image)
        draw.rounded_rectangle((190, 110, 810, 500), radius=28, fill=(255, 255, 255))
        draw.text((250, 180), lines[0], font=regular, fill=(20, 20, 20))
        x = 250
        for label in lines[1:]:
            draw.rounded_rectangle((x, 300, x + 160, 365), radius=12, fill=(55, 118, 208))
            draw.text((x + 20, 318), label, font=small, fill=(255, 255, 255))
            x += 180
    elif kind == "low_contrast_small":
        image = Image.new("RGB", (1000, 620), (196, 196, 190))
        draw = ImageDraw.Draw(image)
        y = 250
        for line in lines:
            draw.text((160, y), line, font=small, fill=(118, 118, 112))
            y += 34
    elif kind == "video_subtitle":
        image = Image.linear_gradient("L").resize((1000, 620)).convert("RGB")
        image = Image.blend(image, Image.new("RGB", image.size, (40, 55, 90)), 0.55)
        draw = ImageDraw.Draw(image)
        draw.rectangle((0, 470, 1000, 620), fill=(20, 20, 24))
        draw.text((250, 520), lines[0], font=regular, fill=(255, 255, 255))
    elif kind == "tilted":
        image = Image.new("RGB", (1000, 620), (250, 245, 225))
        layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        ld.text((260, 280), lines[0], font=regular, fill=(25, 25, 25, 255))
        rotated = layer.rotate(-7, resample=Image.Resampling.BICUBIC, center=(500, 310))
        image = Image.alpha_composite(image.convert("RGBA"), rotated).convert("RGB").filter(ImageFilter.SHARPEN)
        notes.append("tilted text is diagnostic and expected to be harder")
    else:
        raise ValueError(kind)
    notes.append("mixed Devanagari/Japanese not covered unless future host fonts are pinned")
    return image, fonts, notes


def run_worker(cases: list[OcrCase], worker_python: str) -> dict[str, Any]:
    env = {**os.environ, "PYTHONPATH": str(ROOT / "worker" / "src")}
    proc = subprocess.Popen(
        [worker_python, "-m", "worker"],
        cwd=ROOT / "worker",
        env=env,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert proc.stdin and proc.stdout
    results = {"cases": [], "aggregate": {}, "generated_dir": str(GENERATED), "fonts": {}}
    try:
        for index, case in enumerate(cases, start=1):
            request = {
                "version": 1,
                "id": f"ocr-{index}",
                "method": "recognize",
                "params": {"image_path": str(case.image_path)},
            }
            start = time.perf_counter()
            proc.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
            proc.stdin.flush()
            response = json.loads(proc.stdout.readline())
            elapsed_ms = (time.perf_counter() - start) * 1000
            result = score_case(case, response, elapsed_ms)
            results["cases"].append(result)
            for path in case.font_paths:
                results["fonts"][path] = True
    finally:
        if proc.stdin:
            proc.stdin.close()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
    results["aggregate"] = aggregate(results["cases"])
    return results


def score_case(case: OcrCase, response: dict[str, Any], elapsed_ms: float) -> dict[str, Any]:
    if not response.get("ok"):
        return {
            "id": case.case_id,
            "image": str(case.image_path),
            "ok": False,
            "error": response.get("error", {}).get("code", "unknown"),
            "expected_lines": case.expected_lines,
            "paragraphs": case.paragraphs,
            "elapsed_ms": elapsed_ms,
            "notes": case.notes,
        }
    ocr = response["result"]
    recognized = [region["text"] for region in ocr["regions"]]
    matched = greedy_match(case.expected_lines, recognized)
    cer_values = [cer(expected, actual) for expected, actual in matched]
    line_recall = len(matched) / max(len(case.expected_lines), 1)
    line_precision = len(matched) / max(len(recognized), 1)
    geometry = geometry_sanity(ocr)
    order_errors = reading_order_errors(ocr["regions"])
    return {
        "id": case.case_id,
        "image": str(case.image_path),
        "ok": True,
        "expected_lines": case.expected_lines,
        "recognized_lines": recognized,
        "ocr_result": ocr,
        "paragraphs": case.paragraphs,
        "cer": statistics.mean(cer_values) if cer_values else 1.0,
        "line_recall": line_recall,
        "line_precision": line_precision,
        "geometry": geometry,
        "reading_order_errors": order_errors,
        "worker_total_ms": ocr["timings_ms"]["total"],
        "elapsed_ms": elapsed_ms,
        "notes": case.notes,
    }


def greedy_match(expected: list[str], actual: list[str]) -> list[tuple[str, str]]:
    remaining = actual[:]
    pairs = []
    for exp in expected:
        if not remaining:
            break
        best_index, best = min(enumerate(remaining), key=lambda item: cer(exp, item[1]))
        pairs.append((exp, best))
        remaining.pop(best_index)
    return pairs


def cer(expected: str, actual: str) -> float:
    if not expected:
        return 0.0 if not actual else 1.0
    prev = list(range(len(actual) + 1))
    for i, ec in enumerate(expected, start=1):
        curr = [i]
        for j, ac in enumerate(actual, start=1):
            curr.append(min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + (ec != ac)))
        prev = curr
    return prev[-1] / len(expected)


def geometry_sanity(ocr: dict[str, Any]) -> dict[str, int]:
    bad_bounds = bad_counts = bad_order = 0
    width = ocr["image"]["width"]
    height = ocr["image"]["height"]
    for region in ocr["regions"]:
        ranges = region.get("ranges", [])
        if ranges and len(ranges) != len(region["text"]):
            bad_counts += 1
        last = -1
        for item in ranges:
            if item["start"] <= last:
                bad_order += 1
            last = item["start"]
            for x, y in item["polygon"]:
                if x < 0 or y < 0 or x > width or y > height:
                    bad_bounds += 1
    return {"bad_bounds": bad_bounds, "bad_counts": bad_counts, "bad_order": bad_order}


def reading_order_errors(regions: list[dict[str, Any]]) -> int:
    errors = 0
    previous_y = -1.0
    for region in sorted(regions, key=lambda r: r["reading_order"]):
        y = sum(point[1] for point in region["polygon"]) / 4
        if y + 5 < previous_y:
            errors += 1
        previous_y = max(previous_y, y)
    return errors


def aggregate(cases: list[dict[str, Any]]) -> dict[str, Any]:
    ok = [case for case in cases if case.get("ok")]
    return {
        "case_count": len(cases),
        "ok_count": len(ok),
        "mean_cer": statistics.mean(case["cer"] for case in ok) if ok else 1.0,
        "mean_line_recall": statistics.mean(case["line_recall"] for case in ok) if ok else 0.0,
        "mean_line_precision": statistics.mean(case["line_precision"] for case in ok) if ok else 0.0,
        "geometry_failures": sum(sum(case["geometry"].values()) for case in ok),
        "reading_order_errors": sum(case["reading_order_errors"] for case in ok),
        "mean_worker_ms": statistics.mean(case["worker_total_ms"] for case in ok) if ok else 0.0,
    }


def run_paragraph_eval(results_json: Path) -> dict[str, Any]:
    env = {**os.environ, "OCR_CORPUS_RESULTS": str(results_json)}
    proc = subprocess.run(
        [str(ROOT / ".tools" / "flutter" / "bin" / "flutter"), "test", "test/tool/paragraph_corpus_eval_test.dart", "--reporter", "compact"],
        cwd=ROOT / "app",
        env=env,
        text=True,
        capture_output=True,
        check=False,
        timeout=60,
    )
    return {"returncode": proc.returncode, "stdout": proc.stdout, "stderr": proc.stderr}


def write_report(results: dict[str, Any], paragraph: dict[str, Any] | None) -> None:
    EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# OCR Corpus Results",
        "",
        f"Generated images: `{Path(results['generated_dir']).relative_to(ROOT)}`",
        f"Result JSON: `{(OUTPUT / 'ocr-results.json').relative_to(ROOT)}`",
        "",
        "## Aggregate",
        "",
        f"- Cases recognized: {results['aggregate']['ok_count']}/{results['aggregate']['case_count']}",
        f"- Mean CER: {results['aggregate']['mean_cer']:.3f}",
        f"- Mean line recall/precision: {results['aggregate']['mean_line_recall']:.3f}/{results['aggregate']['mean_line_precision']:.3f}",
        f"- Geometry failures: {results['aggregate']['geometry_failures']}",
        f"- Reading-order errors: {results['aggregate']['reading_order_errors']}",
        f"- Mean worker OCR time: {results['aggregate']['mean_worker_ms']:.1f} ms",
        "",
        "## Per Image",
        "",
        "| Image | CER | Recall | Precision | Geometry failures | Reading-order errors | Notes |",
        "|---|---:|---:|---:|---:|---:|---|",
    ]
    for case in results["cases"]:
        if not case.get("ok"):
            lines.append(f"| {case['id']} | n/a | 0.000 | 0.000 | n/a | n/a | error: {case['error']} |")
            continue
        geom = sum(case["geometry"].values())
        notes = "; ".join(case.get("notes", []))
        lines.append(
            f"| {case['id']} | {case['cer']:.3f} | {case['line_recall']:.3f} | {case['line_precision']:.3f} | {geom} | {case['reading_order_errors']} | {notes} |"
        )
    lines.extend(["", "## Paragraph Grouping", ""])
    if paragraph is None:
        lines.append("- Not run (`--skip-dart`).")
    else:
        status = "PASS" if paragraph["returncode"] == 0 else "FAIL"
        paragraph_cases = parse_paragraph_cases(paragraph["stdout"])
        exact = sum(1 for item in paragraph_cases if item["classification"] == "exact")
        lines.append(f"- Dart paragraph corpus test: {status}")
        lines.append(f"- Exact paragraph matches: {exact}/{len(paragraph_cases)}")
        lines.append("- Command: `cd app && OCR_CORPUS_RESULTS=../scripts/acceptance/output/ocr-corpus/ocr-results.json ../.tools/flutter/bin/flutter test test/tool/paragraph_corpus_eval_test.dart`")
        lines.extend([
            "",
            "| Image | Classification | Expected groups | Actual groups | Interpretation |",
            "|---|---|---|---|---|",
        ])
        for item in paragraph_cases:
            if item["classification"] == "exact":
                continue
            interpretation = paragraph_interpretation(item["id"], item["classification"])
            lines.append(
                f"| {item['id']} | {item['classification']} | {_groups_cell(item['expected'])} | {_groups_cell(item['actual'])} | {interpretation} |"
            )
    lines.extend(["", "## Fonts", ""])
    lines.extend(f"- `{path}`" for path in sorted(results["fonts"]))
    lines.extend([
        "",
        "## Failures And Limitations",
        "",
        "- The corpus is synthetic and non-sensitive; it does not replace manual tests on real web pages, video frames, and image viewers.",
        "- Tilted, low-contrast, and small text cases are diagnostic. This ticket reports failures instead of changing OCR thresholds.",
        "- Mixed Devanagari/Japanese is not covered until a suitable font is pinned on the acceptance host.",
    ])
    EVIDENCE.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_paragraph_cases(stdout: str) -> list[dict[str, Any]]:
    cases = []
    for line in stdout.splitlines():
        if not line.startswith("paragraph_case "):
            continue
        cases.append(json.loads(line.removeprefix("paragraph_case ")))
    return cases


def _groups_cell(groups: list[list[str]]) -> str:
    return "<br>".join("[" + "; ".join(group) + "]" for group in groups)


def paragraph_interpretation(case_id: str, classification: str) -> str:
    if case_id == "dark_code":
        return (
            "Acceptable by design for code-like text: keeping the final assert "
            "separate is better than forcing prose paragraph behavior."
        )
    if case_id == "two_columns":
        return (
            "Follow-up defect/risk: OCR ordered the synthetic columns row-wise, "
            "so paragraph grouping cannot recover column paragraphs."
        )
    if case_id == "ui_buttons":
        return (
            "Acceptable by design for toolbar/button clusters: per-control or "
            "per-line selection is a better UX than one paragraph."
        )
    return f"Follow-up review needed for {classification} mismatch."


def aggregate_line(results: dict[str, Any], paragraph: dict[str, Any] | None) -> str:
    para = "not-run" if paragraph is None else ("pass" if paragraph["returncode"] == 0 else "fail")
    aggregate_result = results["aggregate"]
    return (
        f"OCR mean CER={aggregate_result['mean_cer']:.3f}, "
        f"line recall={aggregate_result['mean_line_recall']:.3f}, "
        f"paragraph={para}"
    )


if __name__ == "__main__":
    raise SystemExit(main())
