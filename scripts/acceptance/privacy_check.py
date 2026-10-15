#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
JPEG_MAGIC = b"\xff\xd8\xff"
DEFAULT_PATTERN = r"dev\.kiriglyph\.Kiriglyph|kiriglyph|worker(\.|$| )"


@dataclass
class Check:
    name: str
    passed: bool
    detail: str


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Privacy acceptance scan for Kiriglyph logs, files, crash dumps, and sockets."
    )
    parser.add_argument("--canary", default="", help="Text to search for without printing file contents")
    parser.add_argument("--root", type=Path, default=Path.home(), help="Home root to scan")
    parser.add_argument("--runtime-dir", type=Path, default=Path(os.environ.get("XDG_RUNTIME_DIR", tempfile.gettempdir())))
    parser.add_argument("--pattern", default=DEFAULT_PATTERN, help="Process command-line regex")
    parser.add_argument("--magic-threshold", type=int, default=256, help="Minimum PNG/JPEG bytes to flag")
    parser.add_argument("--self-test", action="store_true", help="Run planted clean/fail synthetic checks")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    checks = run_checks(args)
    print_table(checks)
    return 0 if all(check.passed for check in checks) else 1


def self_test() -> int:
    with tempfile.TemporaryDirectory(prefix="kiriglyph-privacy-") as tmp:
        root = Path(tmp) / "home"
        runtime = Path(tmp) / "runtime"
        (root / ".config" / "kiriglyph").mkdir(parents=True)
        (root / "Pictures").mkdir(parents=True)
        runtime.mkdir()
        clean_args = argparse.Namespace(
            canary="CANARY_SECRET",
            root=root,
            runtime_dir=runtime,
            pattern=r"unlikely-kiriglyph-self-test-process",
            magic_threshold=8,
        )
        clean = run_checks(clean_args)
        planted = root / ".config" / "kiriglyph" / "leak.log"
        planted.write_text("CANARY_SECRET\nQ0FOQVJZX1NFQ1JFVA==\n", encoding="utf-8")
        (root / "Pictures" / "Screenshot.png").write_bytes(PNG_MAGIC + b"x" * 32)
        dirty = run_checks(clean_args)
        print("Clean synthetic state:")
        print_table(clean)
        print("\nPlanted synthetic leaks:")
        print_table(dirty)
        if all(check.passed for check in clean) and not all(check.passed for check in dirty):
            return 0
        return 1


def run_checks(args: argparse.Namespace) -> list[Check]:
    paths = scan_paths(args.root, args.runtime_dir)
    pids = matching_pids(args.pattern)
    checks = [
        check_canary(paths, args.canary),
        check_magic(paths, args.magic_threshold, args.runtime_dir),
        check_pictures(args.root),
        check_runtime_leftovers(args.runtime_dir),
        check_crash_dumps(args.root),
        check_journal(args.canary),
        check_sockets(pids),
    ]
    return checks


def scan_paths(root: Path, runtime_dir: Path) -> list[Path]:
    candidates: list[Path] = []
    for base in [
        root / ".config" / "kiriglyph",
        root / ".local" / "share" / "kiriglyph",
        root / ".local" / "state" / "kiriglyph",
        root / ".cache" / "kiriglyph",
        runtime_dir,
        root / "Pictures",
    ]:
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.is_file() and not path.is_symlink():
                candidates.append(path)
    return candidates


def check_canary(paths: list[Path], canary: str) -> Check:
    if not canary:
        return Check("canary text/base64", True, "not requested")
    needles = [canary.encode("utf-8"), base64.b64encode(canary.encode("utf-8"))]
    hits = []
    for path in paths:
        try:
            data = path.read_bytes()
        except OSError:
            continue
        if any(needle and needle in data for needle in needles):
            hits.append(redact_path(path))
    return Check("canary text/base64", not hits, f"{len(hits)} hit(s): {', '.join(hits[:5])}")


def check_magic(paths: list[Path], threshold: int, runtime_dir: Path) -> Check:
    hits = []
    for path in paths:
        try:
            size = path.stat().st_size
            if size < threshold:
                continue
            start = path.read_bytes()[:16]
        except OSError:
            continue
        if start.startswith(PNG_MAGIC) or start.startswith(JPEG_MAGIC):
            hits.append(redact_path(path))
    return Check("persistent PNG/JPEG bytes", not hits, f"{len(hits)} hit(s): {', '.join(hits[:5])}")


def check_pictures(root: Path) -> Check:
    pictures = root / "Pictures"
    hits = sorted(p.name for p in pictures.glob("Screenshot*.png")) if pictures.exists() else []
    return Check("~/Pictures screenshots", not hits, f"{len(hits)} file(s): {', '.join(hits[:5])}")


def check_runtime_leftovers(runtime_dir: Path) -> Check:
    hits = []
    if runtime_dir.exists():
        for path in runtime_dir.rglob("*"):
            if path.name.startswith("kiriglyph") or path.name.startswith("screen-capture-"):
                hits.append(redact_path(path))
    timing_only = [hit for hit in hits if hit.endswith("kiriglyph-timing.jsonl")]
    unexpected = [hit for hit in hits if hit not in timing_only]
    return Check("$XDG_RUNTIME_DIR session files", not unexpected, f"{len(unexpected)} unexpected; timing logs {len(timing_only)}")


def check_crash_dumps(root: Path) -> Check:
    hits = []
    for pattern in ("*.dmp", "core", "core.*"):
        hits.extend(redact_path(path) for path in root.rglob(pattern) if path.is_file())
    if shutil.which("coredumpctl"):
        proc = subprocess.run(
            ["coredumpctl", "list", "--no-pager", "kiriglyph"],
            text=True,
            capture_output=True,
            check=False,
            timeout=5,
        )
        if proc.returncode == 0 and "kiriglyph" in proc.stdout.lower():
            hits.append("coredumpctl:kiriglyph")
    return Check("crash dumps", not hits, f"{len(hits)} hit(s): {', '.join(hits[:5])}")


def check_journal(canary: str) -> Check:
    if not shutil.which("journalctl"):
        return Check("journal logs", True, "journalctl unavailable")
    proc = subprocess.run(
        ["journalctl", "--user", "-t", "kiriglyph", "--no-pager", "-n", "500"],
        text=True,
        capture_output=True,
        check=False,
        timeout=8,
    )
    if proc.returncode not in (0, 1):
        return Check("journal logs", True, "journal unavailable")
    if canary and (canary in proc.stdout or base64.b64encode(canary.encode()).decode() in proc.stdout):
        return Check("journal logs", False, "canary found")
    return Check("journal logs", True, "no canary in recent tagged logs")


def matching_pids(pattern: str) -> list[int]:
    regex = re.compile(pattern)
    pids = []
    proc = Path("/proc")
    for child in proc.iterdir():
        if not child.name.isdigit():
            continue
        try:
            cmdline = (child / "cmdline").read_bytes().replace(b"\x00", b" ").decode("utf-8", "replace")
        except OSError:
            continue
        if regex.search(cmdline):
            pids.append(int(child.name))
    return pids


def check_sockets(pids: list[int]) -> Check:
    offenders = []
    for pid in pids:
        inodes = socket_inodes(pid)
        if not inodes:
            continue
        inet = inet_socket_states(pid)
        for inode in inodes:
            state = inet.get(inode)
            if state is not None:
                offenders.append(f"pid {pid} inet state {state}")
    return Check("process TCP/UDP sockets", not offenders, f"{len(offenders)} inet socket(s)")


def socket_inodes(pid: int) -> set[str]:
    result = set()
    fd_dir = Path("/proc") / str(pid) / "fd"
    if not fd_dir.exists():
        return result
    for fd in fd_dir.iterdir():
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            result.add(match.group(1))
    return result


def inet_socket_states(pid: int) -> dict[str, str]:
    states: dict[str, str] = {}
    for name in ("tcp", "tcp6", "udp", "udp6"):
        path = Path("/proc") / str(pid) / "net" / name
        try:
            lines = path.read_text(encoding="ascii").splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            parts = line.split()
            if len(parts) >= 10:
                states[parts[9]] = f"{name}/{parts[3]}"
    return states


def redact_path(path: Path) -> str:
    return str(path).replace(str(Path.home()), "~")


def print_table(checks: list[Check]) -> None:
    print("Check | Result | Detail")
    print("--- | --- | ---")
    for check in checks:
        print(f"{check.name} | {'PASS' if check.passed else 'FAIL'} | {check.detail}")


if __name__ == "__main__":
    sys.exit(main())
