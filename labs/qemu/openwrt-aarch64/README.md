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

Stage 3 mounts the current repository read-only into the guest and runs the real `scripts/stage-package.sh openwrt-aarch64`, so API parsing, signed-download redaction, package download, official MD5 verification, archive validation, and extraction are tested using the project code itself.

The lab does **not** claim to emulate a MediaTek, Qualcomm, Broadcom, Xiaomi, ASUS, TP-Link, or GL.iNet hardware platform. Passing this lab means **Lab Tested**, not physical-device **Verified**.

## Why ARM64 first

AArch64 is the software ABI used by many current router SoCs across multiple vendors. Testing the OpenWrt userspace and official ARM64 UU package here can therefore catch a large class of architecture/runtime regressions without pretending that QEMU reproduces vendor-specific drivers, NAND/UBI layouts, switch hardware, Wi-Fi, or boot firmware.

## Pinned image

The initial CI baseline is OpenWrt `25.12.5`, target `armsr/armv8`, using:

`generic-initramfs-kernel.bin`

The image is not stored in this repository. CI downloads it from the official OpenWrt release server and checks the published SHA256 before booting it.

## Local prerequisites

A Linux host can run the same smoke-test when these commands are available:

- `qemu-system-aarch64`
- `expect`
- `sha256sum`
- `curl` or `wget`

Run:

```sh
sh labs/qemu/openwrt-aarch64/boot-smoke.sh
```

## Planned next stages

1. finish Stage 3 repository-driven staging verification;
2. run the real ARM64 `uuplugin` and check guardian + UU cloud connection;
3. move to a persistent rootfs and validate install → reboot → health → rollback;
4. add a XiaoQiang compatibility shim for the rewritten RB06 migration adapter;
5. later add a virtual LAN / packet-capture test for WOL Magic Packet emission.
