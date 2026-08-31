# OpenWrt ARM64 QEMU Lab

This lab provides repeatable software-level validation for the ARM64 OpenWrt path without requiring a physical router for every code change.

## Scope

Stage 1 is cloud-verified in GitHub Actions and validates:

- an official OpenWrt `armsr/armv8` image boots under QEMU AArch64;
- the guest reports `aarch64`;
- the OpenWrt target is `armsr/armv8`;
- the pinned OpenWrt release matches the expected version;
- a virtio network interface is visible;
- the image is downloaded from OpenWrt at runtime and verified by SHA256 before execution.

Stage 2 is cloud-verified in GitHub Actions: an isolated second virtio WAN interface obtains DHCP, reaches the Internet over HTTPS, and validates the official NetEase `openwrt-aarch64` plugin API without printing signed package URLs into CI logs.

Stage 3 is cloud-verified in GitHub Actions: it mounts the current repository read-only into the guest and runs the real `scripts/stage-package.sh openwrt-aarch64`, so API parsing, signed-download redaction, package download, official MD5 verification, archive validation, and extraction are tested using the project code itself.

Stage 4 is cloud-verified in GitHub Actions: it runs the project's real guarded `platforms/openwrt/smoke-test.sh` against that staged official ARM64 package. The official `uuplugin` and `xuplugin-guardian` both came online, `:16000` reached ESTABLISHED in about 4 seconds, the temporary runtime was stopped, process/firewall residue checks passed, and the normal stage-MD5-bound smoke-pass evidence was written. No persistent install is performed in this stage.

Stage 5 is cloud-verified in GitHub Actions using the official writable `generic-ext4-combined-efi` image. The same disk completed install → reboot → automatic procd/cloud health → rollback → second reboot. The final boot confirmed the managed install directory, init script and startup link remained removed, no UU runtime reappeared, and rollback state persisted.

The lab does **not** claim to emulate a MediaTek, Qualcomm, Broadcom, Xiaomi, ASUS, TP-Link, or GL.iNet hardware platform. Passing this lab means **Lab Tested**, not physical-device **Verified**.

## Why ARM64 first

AArch64 is the software ABI used by many current router SoCs across multiple vendors. Testing the OpenWrt userspace and official ARM64 UU package here can therefore catch a large class of architecture/runtime regressions without pretending that QEMU reproduces vendor-specific drivers, NAND/UBI layouts, switch hardware, Wi-Fi, or boot firmware.

## Pinned image

The initial CI baseline is OpenWrt `25.12.5`, target `armsr/armv8`.

Stages 1-4 use `generic-initramfs-kernel.bin`. Stage 5 uses the official `generic-ext4-combined-efi.img.gz` so the same writable disk can survive multiple QEMU boots.

Images are not stored in this repository. CI downloads them from the official OpenWrt release server and checks the pinned published SHA256 before booting them.

## Local prerequisites

A Linux host can run the same smoke-test when these commands are available:

- `qemu-system-aarch64`
- `expect`
- `sha256sum`
- `curl` or `wget`
- AArch64 QEMU EFI firmware (`qemu-efi-aarch64` on Ubuntu/Debian)

Run:

```sh
sh labs/qemu/openwrt-aarch64/boot-smoke.sh
```

## Planned next stages

1. add a XiaoQiang compatibility shim for the rewritten RB06 migration adapter;
2. validate the rewritten XiaoQiang smoke-test / legacy-migration installer / rollback against that shim;
3. later add a virtual LAN / packet-capture test for WOL Magic Packet emission.
