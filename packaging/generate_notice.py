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


LICENCE_FILE_NAMES = ("LICENSE", "LICENCE", "COPYING")


def classify_licence(text: str) -> str:
    """Names a licence from its text; UNVERIFIED when it is not a known one."""
    flat = " ".join(text.split()).lower()
    if "apache license" in flat and "version 2.0" in flat:
        return "Apache-2.0"
    if "mozilla public license" in flat and "version 2.0" in flat:
        return "MPL-2.0"
    if "permission is hereby granted, free of charge" in flat:
        return "MIT"
    if "redistribution and use in source and binary forms" in flat:
        return "BSD-3-Clause" if "neither the name" in flat else "BSD-2-Clause"
    return "UNVERIFIED"


def find_licence_text(package_dir: Path) -> str | None:
    """Reads a package's licence file, or the SDK's when the package has none.

    Flutter SDK packages such as flutter_web_plugins share the SDK's licence
    file, which sits a directory or two above them.
    """
    directory = package_dir
    for _ in range(3):
        for name in LICENCE_FILE_NAMES:
            candidate = directory / name
            if candidate.is_file():
                return candidate.read_text(encoding="utf-8", errors="replace")
        if directory.parent == directory:
            break
        directory = directory.parent
    return None


def package_path(root: Path, uri: str) -> Path:
    parsed = urlparse(uri)
    if parsed.scheme == "file":
        return Path(unquote(parsed.path))
    return (root / uri).resolve()


def runtime_packages(graph: dict) -> dict[str, dict]:
    """Packages the app links, not the ones only tests and lints use.

    The graph lists runtime and development dependencies apart, so walking
    only `dependencies` from the roots leaves the development ones out.
    """
    packages = {package["name"]: package for package in graph.get("packages", [])}
    seen: set[str] = set()
    pending = list(graph.get("roots", []))
    while pending:
        name = pending.pop()
        if name in seen or name not in packages:
            continue
        seen.add(name)
        pending.extend(packages[name].get("dependencies", []))
    return {name: packages[name] for name in seen}


def dart_components(root: Path) -> list[tuple[str, str, str]]:
    dart_tool = root / "app" / ".dart_tool"
    config_path = dart_tool / "package_config.json"
    graph_path = dart_tool / "package_graph.json"
    if not config_path.exists() or not graph_path.exists():
        return []
    config = json.loads(config_path.read_text(encoding="utf-8"))
    graph = json.loads(graph_path.read_text(encoding="utf-8"))
    roots = set(graph.get("roots", []))
    linked = runtime_packages(graph)
    rows: list[tuple[str, str, str]] = []
    for package in config.get("packages", []):
        name = package.get("name", "")
        if name not in linked or name in roots:
            continue
        text = find_licence_text(package_path(dart_tool, package.get("rootUri") or ""))
        rows.append(
            (
                name,
                str(linked[name].get("version", "UNVERIFIED")),
                classify_licence(text) if text else "UNVERIFIED",
            )
        )
    return sorted(set(rows), key=lambda row: row[0].lower())


def python_runtime_name(runtime: Path) -> str:
    sites = find_site_packages(runtime)
    return sites[0].parent.name if sites else "python"


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
        out.write("\nKiriglyph is licensed under the Apache License, Version 2.0 (see /usr/share/common-licenses/Apache-2.0).\n")
        out.write("This file inventories the components bundled in the Debian package.\n")
        out.write("Licence values come from package metadata or the package's licence file; `UNVERIFIED` means no reliable licence information was found locally.\n")
        out.write(f"\nPackage version: {args.version}\n")
        write_table(
            out,
            "Native and application components",
            [
                ("Kiriglyph application", args.version, "Apache-2.0"),
                (
                    "Flutter engine (lib/libflutter_linux_gtk.so)",
                    "bundled by Flutter build",
                    "BSD-3-Clause; third-party licences it includes are in data/flutter_assets/NOTICES.Z",
                ),
                ("Dart runtime (compiled into the Flutter engine)", "bundled by Flutter build", "BSD-3-Clause"),
                (
                    f"CPython runtime, {python_runtime_name(args.worker_runtime)} (python-build-standalone)",
                    "bundled by uv",
                    "PSF-2.0; text in worker-runtime/python/lib/*/LICENSE.txt",
                ),
                (
                    "PP-OCR models (inside the rapidocr wheel)",
                    "bundled in rapidocr wheel",
                    "Apache-2.0; provenance in rapidocr's MODEL_LICENSES.md",
                ),
                (
                    "EfficientSAM-Ti ONNX models",
                    "encoder sha256 84ed466ffcc5c1f8d08409bc34a23bb364ab2c15e402cb12d4335a42be0e0951; decoder sha256 a62f8fa5ea080447c0689418d69e58f1e83e0b7adf9c142e2bd9bcc8045c0b11",
                    "Apache-2.0",
                ),
            ],
        )
        write_table(out, "Python wheels", python_rows)
        out.write("\nSome wheels carry their own third-party libraries, for example FFmpeg (LGPL-2.1, dynamically linked) inside OpenCV and the image codec libraries inside Pillow. Each wheel ships those licence texts in its own folder, such as cv2/LICENSE-3RD-PARTY.txt.\n")
        write_table(out, "Dart packages in the app's dependency tree", dart_rows)
        out.write("\nPackages under MPL-2.0 (the dbus, gtk, gsettings and yaru families) are used unmodified; their source is published on pub.dev. The Flutter framework and engine licences, and those of everything compiled into them, are in data/flutter_assets/NOTICES.Z.\n")
        out.write("\n## EfficientSAM-Ti notice\n\n")
        out.write("EfficientSAM-Ti model files are downloaded at package build time from the published EfficientSAM repository and verified against the pinned SHA-256 digests above. The model notice is Apache-2.0.\n")


if __name__ == "__main__":
    main()
