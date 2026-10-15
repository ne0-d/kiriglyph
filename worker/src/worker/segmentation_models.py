from __future__ import annotations

import hashlib
import os
import tempfile
import urllib.request
from pathlib import Path


MODEL_NAME = "efficientsam-ti"
FETCH_COMMAND = "kiriglyph-fetch-models"
ASSETS = {
    "efficientsam_ti_encoder.onnx": {
        "url": "https://huggingface.co/yunyangx/EfficientSAM/resolve/main/efficientsam_ti_encoder.onnx",
        "sha256": "84ed466ffcc5c1f8d08409bc34a23bb364ab2c15e402cb12d4335a42be0e0951",
    },
    "efficientsam_ti_decoder.onnx": {
        "url": "https://huggingface.co/yunyangx/EfficientSAM/resolve/main/efficientsam_ti_decoder.onnx",
        "sha256": "a62f8fa5ea080447c0689418d69e58f1e83e0b7adf9c142e2bd9bcc8045c0b11",
    },
}


def default_models_root() -> Path:
    override = os.environ.get("KIRIGLYPH_MODELS_DIR")
    if override:
        return Path(override).expanduser()
    data_home = Path(os.environ.get("XDG_DATA_HOME", "~/.local/share")).expanduser()
    return data_home / "kiriglyph" / "models"


def efficient_sam_dir(root: Path | None = None) -> Path:
    base = root or default_models_root()
    if all((base / name).exists() for name in ASSETS):
        return base
    return base / MODEL_NAME


def model_paths(root: Path | None = None) -> dict[str, Path]:
    directory = efficient_sam_dir(root)
    return {name: directory / name for name in ASSETS}


def missing_assets(root: Path | None = None) -> list[Path]:
    return [path for path in model_paths(root).values() if not path.exists()]


def verify_assets(root: Path | None = None) -> None:
    for name, path in model_paths(root).items():
        expected = ASSETS[name]["sha256"]
        if not path.exists():
            raise FileNotFoundError(path)
        actual = sha256_file(path)
        if actual != expected:
            raise ValueError(f"sha256 mismatch for {name}: {actual}")


def fetch_models(root: Path | None = None) -> list[Path]:
    directory = efficient_sam_dir(root)
    directory.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for name, meta in ASSETS.items():
        path = directory / name
        if path.exists() and sha256_file(path) == meta["sha256"]:
            written.append(path)
            continue
        _download_atomic(meta["url"], path, meta["sha256"])
        written.append(path)
    return written


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _download_atomic(url: str, path: Path, expected_sha256: str) -> None:
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temp_path = Path(temp_name)
    try:
        with os.fdopen(fd, "wb") as out, urllib.request.urlopen(url, timeout=120) as response:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                out.write(chunk)
            out.flush()
            os.fsync(out.fileno())
        actual = sha256_file(temp_path)
        if actual != expected_sha256:
            raise RuntimeError(f"sha256 mismatch for {path.name}: {actual}")
        os.replace(temp_path, path)
    finally:
        temp_path.unlink(missing_ok=True)


def main() -> None:
    paths = fetch_models()
    for path in paths:
        print(f"{path.name} {sha256_file(path)} {path}")


if __name__ == "__main__":
    main()
