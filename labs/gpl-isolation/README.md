# GPL WOL-only isolation laboratory — NOT INSTALLABLE

This is **not** part of the MIT helper implementation or a Docker package.
The separate GPL-3.0-or-later upstream is fetched into the temporary GitHub
Runner directory from a pinned official tag and commit. The original GPL
source and license remain with that temporary checkout. No GPL Rust source
is copied into the MIT repository. No credentials, real UU API request,
real network broadcast or production hardware is used by this workflow.

The patch prototype adds a *default-off*, explicitly configured
`UU_WOL_ONLY=1` mode which:

- requires `UU_WOL_HELPER=1`, `UU_REMOTE_ASSIST=0`,
  `UU_PORT_MAPPING=0` and an explicit `UU_WOL_ALLOWED_MAC`;
- rejects WebRTC/remote-control, file, terminal, port mapping and desktop
  signaling events **before** constructing a peer session;
- keeps only the room lifecycle and `wake_on_lan` push;
- validates exact allowed target MAC, local LAN subnet and contiguous mask;
- sends at most **one directed UDP/9 packet** in WOL-only mode, rather
  than the upstream's general-broadcast UDP/7 and UDP/9 fan-out.

The compile/test CI gate additionally creates **two ephemeral isolated Linux
network namespaces** and runs only the patched Rust unit-test binary inside
one namespace, capturing the actual UDP packet in the other. It must verify
**exactly one 102-byte UDP/9** frame and **no UDP/7**, without any host NIC,
Internet route, UU login or production service. This proves the synthetic
single-packet path, not that a real NAS network interface or post-reboot
identity has been safely configured. The container is not started by CI. There is no published binary artifact,
Docker image, GitHub Release or end-user installation guide.

## Remaining gates before recruiting Docker volunteers

1. Verify real account sign-in and device listing without personal PC WOL
   on an isolated virtual test identity.
2. Verify no remote terminal, file-transfer, desktop/WebRTC or port-mapping
   capability is reachable at runtime, and no unintended background services
   use sensitive host privileges.
3. Prove interface-bound UDP/9 sends exactly one packet only to an explicitly
   approved LAN target in an independent virtual network. Fail closed when
   the Docker bridge has the wrong subnet.
4. Provide clear, reviewed GPL source distribution/attribution, signed
   or digest-pinned artifacts, isolated nonprivileged container deployment,
   opt-in enrollment and rollback.
5. Only then invite opt-in real NAS/OpenWrt/Linux users with a redacted
   test checklist. Do **not** ask for UU account tokens, QR ticket values,
   public IP/MAC, complete raw logs, or full network configuration.

The existing OpenWrt/router beta and its community feedback are separate
from this still-unreleased Docker helper.

## Vendor/licensing boundary

The GPL client is independent of the MIT original project and unofficial
with respect to NetEase. Source inspection and virtual CI do not confer
NetEase API authorization. Do not relicense GPL material as MIT or ship
a full-featured remote host while labeling it WOL-only.

Original upstream: https://github.com/VallierDev/uu-remote-linux
Pinned tag: v0.2.58, commit 0e1e935fb41c2aac2bdd5eebdd4b38a7476d14bc
