# GPL WOL-only isolation laboratory — NOT INSTALLABLE

This work belongs to a **separate GPL-3.0-or-later experimental client**,
not the MIT UU Router Helper product and not the downloadable router-identity
Docker beta from PR #16. Each CI job clones the exact upstream
`VallierDev/uu-remote-linux v0.2.58` revision and applies the diagnostic
patch in the ephemeral GitHub Runner. No third-party Rust source or NetEase
signing material is copied into the MIT product.

## What the test-only patch changes

- **Startup gate first:** the isolated binary has no ordinary full-remote-host
  fallback, including when `UU_WOL_ONLY` is omitted. It allows only
  `login --no-gui` for account enrollment and a precisely configured
  `UU_WOL_ONLY=1` service. All other commands (including `assist`) fail
  before initializing the original desktop/audio/input/assist/WebRTC host.
- **Separate service:** the WOL-only route loads existing private credentials,
  creates a room, exchanges Engine.IO / Socket.IO signaling and accepts only
  a successful room-info acknowledgement before enabling any wake push.
  Non-wake remote-control, file, terminal, clipboard and WebRTC signaling
  events never construct peer sessions.
- **Strict egress:** requires `UU_WOL_HELPER=1`, `UU_REMOTE_ASSIST=0`,
  `UU_PORT_MAPPING=0`, one explicit `UU_WOL_ALLOWED_MAC` and a
  `UU_WOL_LAN_IFACE`. Sender/source IP must match the selected Linux
  interface and LAN subnet; the socket also uses Linux `SO_BINDTODEVICE`.
  Wrong subnet, mask, target, interface or binding fails closed. A permitted
  wake sends **one 102-byte directed UDP/9 packet** and no UDP/7.
- **QR timeout fix:** retains the same single-use login ticket across
  transient status-poll timeouts, with a bounded polling period, based on
  the separately tested GPL QR diagnostic. No login tokens are committed.

## CI coverage and limits

The isolated GitHub workflow compiles the patched upstream and checks
configuration guards, authentication-message gating and error cases. It
tests the real Linux kernel's UDP interface binding in two short-lived,
disconnected network namespaces: one sender, one independent receiver.
The receiver must see **exactly one 102-byte UDP/9 datagram** and **no UDP/7**.
The startup checks also execute the actual Linux binary in deliberately
invalid configurations to prove that assist and full-host fallback are
rejected before any cloud connection.

These gates **do not prove live NetEase authorization or a sustained
WOL-only runtime against genuine cloud messages**. The workflow never runs
the cloud-connected host with personal credentials, cannot prove complete
resource isolation under every NAS kernel, and does not verify power-on of
a real PC, device persistence after a NAS reboot or multi-NIC/VLAN behavior.
No ready-to-install GPL image or binary is published by this workflow.

## Remaining before an opt-in community WOL-only Docker release

1. A dedicated nonprivileged, read-only Docker image with no Docker socket,
   no privileged mode, no remote-tool host mounts, bounded resources, and
   a private persistent credential volume; verify ownership and rollback.
2. Runtime checks that no desktop, terminal, files, audio, WebRTC,
   local listener or port mapping is reachable when actual WOL-only room
   signaling is active; include unauthorized cloud-event negative tests.
3. An opt-in real account/room/registration trial in a segregated virtual
   device environment, followed by explicitly consenting volunteer NAS
   tests for real mobile-data wake and reboot persistence.
4. Published GPL attribution and complete corresponding patch/source,
   reproducible build and pinned SHA-256 for any distributed binaries.
   Do not relicense GPL code as MIT or repackage the original full remote
   host as a WOL-only image.

Never request volunteers' UU tokens, QR tickets, full raw logs, private IP,
MAC addresses, NAS credentials or identity volumes. The existing PR #16
router-identity NAS source beta and its Issue #15 feedback remain separate.

Upstream: https://github.com/VallierDev/uu-remote-linux

Pinned revision: `0e1e935fb41c2aac2bdd5eebdd4b38a7476d14bc`
