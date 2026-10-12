#!/usr/bin/env python3
"""Build deterministic, platform-scoped *source* archives; never bundle NetEase binaries."""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import stat
import zipfile

ROOT = Path(__file__).resolve().parent.parent
ARCHIVES = {
    "openwrt-x86_64": ("openwrt", "x86_64", "any", "iStoreOS x86_64 reference sample verified; other routers require validation."),
    "openwrt-aarch64": ("openwrt", "aarch64", "any", "Candidate only; real device compatibility is not automatic."),
    "openwrt-mipsel-y1-beta": ("openwrt", "mipsel_24kc", "lenovo-y1", "Experimental Lenovo Y1 / Newifi Mini R6830 only; no generic MIPS installer."),
    "xiaoqiang-aarch64": ("xiaoqiang", "aarch64", "any", "XiaoQiang/Redmi reference tested; new models require validation."),
    "asuswrt": ("asuswrt", "any", "any", "Official ASUS / NetEase integration preferred; diagnostics only, no replacement installer."),
}
DOCS = {
    "openwrt": "docs/OPENWRT.md",
    "xiaoqiang": "docs/XIAOQIANG.md",
    "asuswrt": "docs/ASUSWRT.md",
}


def source_files(platform: str) -> list[Path]:
    names = {
        "uu-helper.sh", "start-windows.cmd", "tools/windows-launcher.ps1",
        "LICENSE", "SECURITY.md", "docs/COMPATIBILITY.md",
        "docs/MANUAL-SETUP.md", DOCS[platform],
    }
    for sub in ("lib", "scripts"):
        names.update(p.relative_to(ROOT).as_posix() for p in (ROOT / sub).glob("*.sh"))
    for adapter in ("openwrt", "xiaoqiang", "asuswrt"):
        for fn in ("detect.sh", "health.sh"):
            names.add(f"platforms/{adapter}/{fn}")
    names.update(
        p.relative_to(ROOT).as_posix()
        for p in (ROOT / "platforms" / platform).rglob("*")
        if p.is_file()
    )
    files = [Path(name) for name in sorted(names)]
    for relative in files:
        src = ROOT / relative
        if not src.is_file() or src.is_symlink() or not src.resolve().is_relative_to(ROOT):
            raise RuntimeError(f"Unsafe or missing package input: {relative}")
        if src.name in {"uuplugin", "xuplugin-guardian", "xtables-nft-multi"}:
            raise RuntimeError(f"Proprietary executable may not be redistributed: {relative}")
    return files


def make_archive(name: str, dest: Path) -> None:
    platform, architecture, model, notice = ARCHIVES[name]
    metadata = f"platform={platform}\narchitecture={architecture}\nmodel={model}\n".encode()
    intro = (
        "UU Remote WOL Router Helper | platform-scoped package\n"
        f"Package: {name}\n"
        f"Compatibility: {notice}\n\n"
        "This is community software, not a NetEase official release.\n"
        "ZIP contents contain source scripts only; the official proprietary plugin\n"
        "is downloaded and integrity-checked from NetEase at runtime.\n"
        "Check the router's platform, architecture and firmware before using it.\n"
        "Wrong-platform operations stop with a safety error.\n"
        "Windows: extract ZIP, then run start-windows.cmd to upload the scripts.\n"
        "Other systems: upload extracted sources and run sh uu-helper.sh start.\n"
        "The installer does not automatically authorize experimental deployment.\n"
        "Read docs/COMPATIBILITY.md and the included platform-specific guide.\n"
        "Lenovo Y1 beta: see docs/OPENWRT.md for the separate opt-in path.\n"
    ).encode()
    files = source_files(platform)
    entries: dict[str, bytes] = {
        "START-HERE.txt": intro,
        "lib/package-profile": metadata,
    }
    for relative in files:
        entries[relative.as_posix()] = (ROOT / relative).read_bytes()
    dest.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9, strict_timestamps=True) as zf:
        for rel in sorted(entries):
            zi = zipfile.ZipInfo(rel, date_time=(2026, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.create_system = 3
            mode = stat.S_IFREG | (0o755 if rel.endswith(".sh") else 0o644)
            zi.external_attr = mode << 16
            zf.writestr(zi, entries[rel], compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    output = args.output.resolve()
    if output == ROOT or output == ROOT.parent:
        raise SystemExit("Refusing to create ZIPs directly at the source root")
    output.mkdir(parents=True, exist_ok=True)
    hashes = []
    for name in ARCHIVES:
        path = output / f"uu-helper-{name}.zip"
        make_archive(name, path)
        sha = hashlib.sha256(path.read_bytes()).hexdigest()
        hashes.append(f"{sha}  {path.name}")
        print(f"built: {path.name} ({path.stat().st_size} bytes)")
    (output / "SHA256SUMS.txt").write_text("\n".join(hashes) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
