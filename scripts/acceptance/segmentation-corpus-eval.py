#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "worker" / "benchmarks" / "segmentation" / "fixtures"
MANIFEST = FIXTURES / "manifest.json"
EVIDENCE = ROOT / ".scratch" / "ubuntu-live-text-v0" / "evidence" / "subject-corpus-results.md"
OUTPUT = ROOT / "scripts" / "acceptance" / "output" / "segmentation-corpus"


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the real segmentation worker over benchmark fixtures.")
    parser.add_argument("--worker-python", default=str(ROOT / "worker" / ".venv" / "bin" / "python"))
    parser.add_argument("--models-dir", default=os.environ.get("KIRIGLYPH_MODELS_DIR", str(default_models_dir())))
    parser.add_argument("--sessions", type=int, default=20, help="Sequential boundedness sessions")
    args = parser.parse_args()
    fixtures = json.loads(MANIFEST.read_text(encoding="utf-8"))["fixtures"]
    results = []
    with tempfile.TemporaryDirectory(prefix="kiriglyph-seg-") as runtime:
        for fixture in fixtures:
            results.append(run_session(args, fixture, Path(runtime)))
        bounded = [run_session(args, fixtures[0], Path(runtime), label=f"bounded-{i + 1}") for i in range(args.sessions)]
    payload = {"fixtures": results, "bounded": bounded, "aggregate": aggregate(results, bounded)}
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "segmentation-results.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    write_report(payload)
    print(f"Wrote {EVIDENCE}")
    agg = payload["aggregate"]
    print(
        f"Segmentation outcomes={agg['outcomes']}, median embed={agg['median_embed_ms']:.1f} ms, "
        f"median prompt={agg['median_prompt_ms']:.1f} ms, peak RSS={agg['peak_rss_mib']:.1f} MiB, "
        f"bounded_sessions={agg['bounded_sessions']}"
    )
    return 0 if agg["closed_cleanly"] else 1


def default_models_dir() -> Path:
    benchmark_dir = ROOT / "worker" / ".models" / "segmentation"
    if benchmark_dir.exists():
        return benchmark_dir
    return ROOT / "worker" / ".models"


def run_session(args: argparse.Namespace, fixture: dict[str, Any], runtime_dir: Path, label: str | None = None) -> dict[str, Any]:
    env = {
        **os.environ,
        "PYTHONPATH": str(ROOT / "worker" / "src"),
        "XDG_RUNTIME_DIR": str(runtime_dir),
        "KIRIGLYPH_MODELS_DIR": args.models_dir,
    }
    proc = subprocess.Popen(
        [args.worker_python, "-m", "worker.segmentation_worker"],
        cwd=ROOT / "worker",
        env=env,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert proc.stdin and proc.stdout
    peak_rss = 0
    mask_path: Path | None = None
    started = time.perf_counter()
    try:
        image_path = FIXTURES / fixture["image"]
        prompt = fixture["prompt"]
        embed_response, peak_rss = request(
            proc,
            {
                "version": 1,
                "id": "embed-1",
                "method": "embed",
                "params": {"source": "path", "image_path": str(image_path)},
            },
            peak_rss,
        )
        if not embed_response.get("ok"):
            close_response = close(proc, peak_rss)
            return session_result(fixture, label, embed_response, None, close_response, peak_rss, started, runtime_dir, None)
        prompt_response, peak_rss = request(
            proc,
            {
                "version": 1,
                "id": "prompt-1",
                "method": "prompt",
                "params": {
                    "handle": embed_response["result"],
                    "prompt": {
                        "points": [{"x": prompt["x"], "y": prompt["y"], "label": "foreground"}],
                        "box": None,
                        "polygon": None,
                    },
                },
            },
            peak_rss,
        )
        if prompt_response.get("ok"):
            mask_path = Path(prompt_response["result"]["mask"]["path"])
        close_response = close(proc, peak_rss)
        return session_result(fixture, label, embed_response, prompt_response, close_response, peak_rss, started, runtime_dir, mask_path)
    finally:
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)
        shutil.rmtree(runtime_dir, ignore_errors=True)
        runtime_dir.mkdir(parents=True, exist_ok=True)


def request(proc: subprocess.Popen[str], payload: dict[str, Any], peak_rss: int) -> tuple[dict[str, Any], int]:
    assert proc.stdin and proc.stdout
    proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
    proc.stdin.flush()
    while True:
        peak_rss = max(peak_rss, rss_kib(proc.pid))
        line = proc.stdout.readline()
        if line:
            return json.loads(line), peak_rss
        if proc.poll() is not None:
            return {"ok": False, "error": {"code": "process_died"}}, peak_rss
        time.sleep(0.05)


def close(proc: subprocess.Popen[str], peak_rss: int) -> dict[str, Any]:
    response, _ = request(proc, {"version": 1, "id": "close", "method": "close", "params": {}}, peak_rss)
    if proc.stdin:
        proc.stdin.close()
    return response


def rss_kib(pid: int) -> int:
    try:
        for line in (Path("/proc") / str(pid) / "status").read_text(encoding="utf-8").splitlines():
            if line.startswith("VmRSS:"):
                return int(line.split()[1])
    except OSError:
        return 0
    return 0


def session_result(
    fixture: dict[str, Any],
    label: str | None,
    embed: dict[str, Any],
    prompt: dict[str, Any] | None,
    close_response: dict[str, Any],
    peak_rss: int,
    started: float,
    runtime_dir: Path,
    mask_path: Path | None,
) -> dict[str, Any]:
    leftover = list(runtime_dir.rglob("*"))
    prompt_result = prompt.get("result") if prompt and prompt.get("ok") else {}
    stats = prompt_result.get("mask_stats", {})
    timings = {
        **(embed.get("result", {}).get("timings_ms", {}) if embed.get("ok") else {}),
        **(prompt_result.get("timings_ms", {}) if prompt_result else {}),
    }
    return {
        "id": label or fixture["id"],
        "fixture": fixture["id"],
        "ok": bool(embed.get("ok")) and bool(prompt and prompt.get("ok")) and bool(close_response.get("ok")),
        "error": None if embed.get("ok") and (prompt is None or prompt.get("ok")) else (embed.get("error") or (prompt or {}).get("error")),
        "outcome": stats.get("outcome", "error"),
        "area_fraction": stats.get("area_fraction"),
        "timings_ms": timings,
        "peak_rss_kib": peak_rss,
        "elapsed_ms": (time.perf_counter() - started) * 1000,
        "mask_deleted_after_close": False if mask_path and mask_path.exists() else True,
        "runtime_leftovers": [str(path) for path in leftover],
    }


def aggregate(fixtures: list[dict[str, Any]], bounded: list[dict[str, Any]]) -> dict[str, Any]:
    all_rows = fixtures + bounded
    outcomes: dict[str, int] = {}
    for row in all_rows:
        outcomes[row["outcome"]] = outcomes.get(row["outcome"], 0) + 1
    embed = [row["timings_ms"].get("embed_ms") for row in all_rows if row["timings_ms"].get("embed_ms") is not None]
    prompt = [row["timings_ms"].get("prompt_ms") for row in all_rows if row["timings_ms"].get("prompt_ms") is not None]
    return {
        "outcomes": outcomes,
        "median_embed_ms": statistics.median(embed) if embed else 0,
        "median_prompt_ms": statistics.median(prompt) if prompt else 0,
        "peak_rss_mib": max((row["peak_rss_kib"] for row in all_rows), default=0) / 1024,
        "bounded_sessions": len(bounded),
        "closed_cleanly": all(row["mask_deleted_after_close"] and not row["runtime_leftovers"] for row in all_rows),
    }


def write_report(payload: dict[str, Any]) -> None:
    EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
    agg = payload["aggregate"]
    lines = [
        "# Subject Corpus Results",
        "",
        "Command: `worker/.venv/bin/python scripts/acceptance/segmentation-corpus-eval.py`",
        "",
        "## Aggregate",
        "",
        f"- Outcomes: `{agg['outcomes']}`",
        f"- Median embed/prompt: {agg['median_embed_ms']:.1f} ms / {agg['median_prompt_ms']:.1f} ms",
        f"- Peak segmentation RSS: {agg['peak_rss_mib']:.1f} MiB",
        f"- Sequential bounded sessions: {agg['bounded_sessions']}",
        f"- Mask/runtime cleanup after close: {'PASS' if agg['closed_cleanly'] else 'FAIL'}",
        "",
        "## Per Fixture",
        "",
        "| Fixture | Outcome | Embed ms | Prompt ms | Peak RSS MiB | Mask cleanup | Runtime leftovers |",
        "|---|---|---:|---:|---:|---|---:|",
    ]
    for row in payload["fixtures"]:
        lines.append(
            f"| {row['fixture']} | {row['outcome']} | {row['timings_ms'].get('embed_ms', 0):.1f} | "
            f"{row['timings_ms'].get('prompt_ms', 0):.1f} | {row['peak_rss_kib'] / 1024:.1f} | "
            f"{'yes' if row['mask_deleted_after_close'] else 'no'} | {len(row['runtime_leftovers'])} |"
        )
    lines.extend([
        "",
        "## Boundedness",
        "",
        f"- Ran {len(payload['bounded'])} sequential spawn/embed/prompt/close sessions on `{payload['bounded'][0]['fixture']}`.",
        f"- All sessions cleaned mask files: {'yes' if all(row['mask_deleted_after_close'] for row in payload['bounded']) else 'no'}.",
        f"- All sessions left zero runtime files: {'yes' if all(not row['runtime_leftovers'] for row in payload['bounded']) else 'no'}.",
        "",
        "## Limitations",
        "",
        "- Fixtures are synthetic and do not represent real screenshots, camera photos, or every edge case.",
        "- This harness measures the real worker protocol and cleanup; it does not judge visual mask quality beyond worker outcomes.",
    ])
    EVIDENCE.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
