#!/usr/bin/env python3
"""Offline, deterministic, security-focused checks for per-platform archives."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("uu_build_platform_packages", ROOT / "scripts" / "build-platform-packages.py")
assert spec is not None and spec.loader is not None
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
ARCHIVES = builder.ARCHIVES
make_archive = builder.make_archive

PREFIX = "uu-helper-"
INSTALLERS = {"install.sh", "rollback.sh", "uninstall.sh", "mips-experimental-install.sh"}


def run(cmd: list[str], *, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=False, timeout=20)


def check() -> None:
    with tempfile.TemporaryDirectory(prefix="uu-platform-package-test-") as td:
        tmp = Path(td)
        for name, (platform, arch, model, _) in ARCHIVES.items():
            a = tmp / f"first-{name}.zip"
            b = tmp / f"second-{name}.zip"
            make_archive(name, a)
            make_archive(name, b)
            assert a.read_bytes() == b.read_bytes(), f"Non-deterministic ZIP: {name}"
            with zipfile.ZipFile(a) as zf:
                paths = zf.namelist()
                assert len(paths) == len(set(paths)), f"Duplicate entries: {name}"
                assert all(not p.startswith("/") and ".." not in Path(p).parts for p in paths)
                assert zf.testzip() is None
                assert "uu-helper.sh" in paths
                assert "scripts/wizard.sh" in paths
                assert "tools/windows-launcher.ps1" in paths
                assert "lib/package-guard.sh" in paths
                assert "lib/package-profile" in paths
                assert f"platforms/{platform}/detect.sh" in paths
                assert "START-HERE.txt" in paths
                profile = zf.read("lib/package-profile").decode()
                assert profile == f"platform={platform}\narchitecture={arch}\nmodel={model}\n"
                assert not any(
                    Path(p).name in {"uuplugin", "xuplugin-guardian", "xtables-nft-multi"}
                    for p in paths
                ), f"Proprietary file bundled: {name}"
                for other in {"openwrt", "xiaoqiang", "asuswrt"} - {platform}:
                    assert all(
                        not p.startswith(f"platforms/{other}/") or Path(p).name in {"detect.sh", "health.sh"}
                        for p in paths
                    ), f"Cross-platform installer bundled in {name}"
                if platform == "asuswrt":
                    assert not any(p.startswith("platforms/asuswrt/") and Path(p).name in INSTALLERS for p in paths)
                unpack = tmp / f"extract-{name}"
                zf.extractall(unpack)
            # A Linux CI runner is not any supported router; installed ZIPs must refuse it.
            denied = run(["sh", "uu-helper.sh", "preflight"], cwd=unpack)
            assert denied.returncode == 67, (name, denied.returncode, denied.stdout, denied.stderr)
            # Every distributed POSIX shell file is syntactically valid.
            for path in unpack.rglob("*.sh"):
                result = run(["sh", "-n", str(path)], cwd=unpack)
                assert result.returncode == 0, (name, path, result.stderr)

        # Simulate a correctly identified x86 OpenWrt for positive package gate testing.
        name = "openwrt-x86_64"
        unpack = tmp / f"extract-{name}"
        for adapter in ("xiaoqiang", "asuswrt"):
            (unpack / "platforms" / adapter / "detect.sh").write_text("#!/bin/sh\nexit 1\n")
        (unpack / "platforms/openwrt/detect.sh").write_text("#!/bin/sh\nexit 0\n")
        shell = '. ./lib/package-guard.sh; uu_openwrt_detect_arch() { printf "x86_64\\n"; }; uu_package_check "$PWD"'
        allowed = run(["sh", "-c", shell], cwd=unpack)
        assert allowed.returncode == 0, allowed.stderr
        shell = '. ./lib/package-guard.sh; uu_openwrt_detect_arch() { printf "aarch64\\n"; }; uu_package_check "$PWD"'
        wrong_arch = run(["sh", "-c", shell], cwd=unpack)
        assert wrong_arch.returncode == 67, wrong_arch.stderr

    print("PASS: 5 reproducible, platform-scoped source ZIPs; guards and exclusions verified")


if __name__ == "__main__":
    check()
