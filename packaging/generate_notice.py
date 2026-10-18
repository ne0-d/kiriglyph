#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from email.message import Message
from importlib import metadata
from pathlib import Path
from urllib.parse import unquote, urlparse


def license_name(meta: Message) -> str:
    value = (meta.get("License-Expression") or meta.get("License") or "").strip()
    if value and value.upper() not in {"UNKNOWN", "UNKNOWN LICENSE"}:
        return " ".join(value.split())
    classifiers = meta.get_all("Classifier") or []
    licenses = [
        item.rsplit(" :: ", 1)[-1]
        for item in classifiers
        if item.startswith("License ::")
    ]
    return ", ".join(sorted(set(licenses))) if licenses else "UNVERIFIED"


def find_site_packages(runtime: Path) -> list[Path]:
    candidates = sorted(runtime.glob("lib/python*/site-packages"))
    return [path for path in candidates if path.is_dir()]


def python_components(runtime: Path) -> list[tuple[str, str, str]]:
    rows: list[tuple[str, str, str]] = []
    for site in find_site_packages(runtime):
        for dist in metadata.distributions(path=[str(site)]):
            meta = dist.metadata
            rows.append(
                (
                    meta.get("Name", dist.metadata["Name"]),
                    meta.get("Version", "UNVERIFIED"),
                    license_name(meta),
                )
            )
    return sorted(set(rows), key=lambda row: row[0].lower())


def parse_pubspec_license(path: Path) -> str:
    if not path.exists():
        return "UNVERIFIED"
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"^\s*license:\s*(.+?)\s*$", line)
        if match:
            value = match.group(1).strip().strip("'\"")
            return value or "UNVERIFIED"
    return "UNVERIFIED"


def package_path(root: Path, uri: str) -> Path:
    parsed = urlparse(uri)
    if parsed.scheme == "file":
        return Path(unquote(parsed.path))
    return (root / uri).resolve()


def dart_components(root: Path) -> list[tuple[str, str, str]]:
    config_path = root / "app" / ".dart_tool" / "package_config.json"
    if not config_path.exists():
        return []
    config = json.loads(config_path.read_text(encoding="utf-8"))
    rows: list[tuple[str, str, str]] = []
    for package in config.get("packages", []):
        name = package.get("name", "")
        if not name or name == "kiriglyph":
            continue
        version = str(package.get("languageVersion", "UNVERIFIED"))
        root_uri = package.get("rootUri") or ""
        pubspec = package_path(config_path.parent, root_uri) / "pubspec.yaml"
        rows.append((name, version, parse_pubspec_license(pubspec)))
    return sorted(set(rows), key=lambda row: row[0].lower())


def write_table(out, title: str, rows: list[tuple[str, str, str]]) -> None:
    out.write(f"\n## {title}\n\n")
    out.write("| Component | Version | Licence |\n")
    out.write("| --- | --- | --- |\n")
    for name, version, licence in rows:
        out.write(f"| {name} | {version} | {licence} |\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--worker-runtime", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    output = args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    python_rows = python_components(args.worker_runtime)
    dart_rows = dart_components(args.repo_root)

    with output.open("w", encoding="utf-8") as out:
        out.write("# Kiriglyph bundled component notice\n")
        out.write("\nThis file inventories components bundled in the beta Debian package.\n")
        out.write("Licence values come from package metadata when available; `UNVERIFIED` means no reliable licence metadata was found locally.\n")
        out.write(f"\nPackage version: {args.version}\n")
        write_table(
            out,
            "Native and application components",
            [
                ("Kiriglyph application", args.version, "UNVERIFIED"),
                ("Flutter engine (libflutter_linux_gtk.so)", "bundled by Flutter build", "UNVERIFIED"),
                ("Dart SDK runtime artifacts", "bundled by Flutter build", "UNVERIFIED"),
                ("RapidOCR bundled PP-OCR models", "bundled in rapidocr wheel", "UNVERIFIED"),
                (
                    "EfficientSAM-Ti ONNX models",
                    "encoder sha256 84ed466ffcc5c1f8d08409bc34a23bb364ab2c15e402cb12d4335a42be0e0951; decoder sha256 a62f8fa5ea080447c0689418d69e58f1e83e0b7adf9c142e2bd9bcc8045c0b11",
                    "Apache-2.0",
                ),
            ],
        )
        write_table(out, "Python wheels", python_rows)
        write_table(out, "Dart packages", dart_rows)
        out.write("\n## EfficientSAM-Ti notice\n\n")
        out.write("EfficientSAM-Ti model files are downloaded at package build time from the published EfficientSAM repository and verified against the pinned SHA-256 digests above. The model notice is Apache-2.0.\n")


if __name__ == "__main__":
    main()
