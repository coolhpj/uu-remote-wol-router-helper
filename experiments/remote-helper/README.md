# Remote WoL helper: isolated network-layer prototype

Status: **isolated, offline-only helper prototype**. Read-only discovery, safe-by-default sender, synthetic cloud command validation, and **test-only QR enrollment / room authentication over loopback** are implemented and tested. A real `socat` UDP loopback test also exists. **Real LAN transmission, vendor-issued QR login, server registration, real cloud push, reboot identity retention, and actual PC wake remain unverified**. This is not a usable UU client or a Docker release.

This directory explores a second, optional NetEase UU Remote wake-helper identity **without changing** the existing official router `uuplugin` Docker experiment (PR #16). The two identities, login credentials, cloud channels, persistent volumes and install/cleanup responsibilities must remain separate.

## Implemented in this isolated worktree

`lan-preflight.sh` accepts four explicit values: candidate LAN interface name, local IPv4 address, netmask and target IPv4 address. It validates subnet membership, rejects WAN/loopback/tunnel/Docker names, and calculates the directed broadcast.

`lan-discover.sh` reads `ip -o -4 addr show scope global` and falls back to read-only multiline `ip -4 addr show` via `lan-normalize.awk` on BusyBox-style variants. It chooses an unambiguous LAN-bridge address (`br-lan`, `br0`, `lanN`) or a specific interface explicitly selected by the operator, then reuses `lan-preflight.sh` to verify the target. **It never guesses that the default route is LAN**. Ambiguity and unsupported `ip` variants fail closed. For a NAS with `eth0`, explicitly select the known LAN interface. The test suite uses a fake `ip` executable; actual OpenWrt/iStoreOS LAN discovery is not yet validated.

`magic-packet-hex.sh` emits an offline, exactly 102-byte WoL packet as ASCII hex. `wol-send.sh` defaults to a **non-sending preview**, validates the MAC and target, and has an explicit one-shot `--send` path requiring `UU_WOL_SEND_CONFIRM=SEND_ONE_WOL_PACKET`. Before any actual socket operation, it checks the broadcast route maps to the chosen LAN/source and does not go via a gateway. Only a compatible `socat` with `SO_BINDTODEVICE` and source-IP binding is accepted; no unconstrained fallback is allowed. The sender includes `shut-none` to prevent recent socat versions from emitting an extra zero-length UDP datagram when closing. A separate Linux loopback test with socat 1.8.0.3 successfully delivered exactly **one** 102-byte UDP datagram; a non-root UID 65534 repetition also succeeded. This was **not** a live LAN test of the full sender, and a successful socket write is not proof a target PC booted.

`cloud-contract.mjs` (Node.js standard library, **test-only**) defines the expected helper registration fields (`mac`, `ip`, `inner_ip`, `subnet_mask`), treats HTTP 200/business code 0 only as **registration acceptance**, and validates a `42["bmsg_push", {type:"wake_on_lan", ...}]` Socket.IO event against the configured account, explicitly enabled helper, registration state, and a local allowlist of target MAC/IP pairs. It emits an **inert** wake plan; it cannot log in, connect to the cloud or send a network packet. A future live adapter must prove the account and room's authentication cryptographically through its transport; caller-provided boolean flags in this offline contract are **not** evidence of a real authenticated connection.

`test-remote-helper-cloud-bridge.mjs` runs a fully synthetic registration→message→wake-plan→shell-sender path using a **fake** `ip` and `socat`; no host network is touched. This is the bridge contract, **not** a live end-to-end UU test. Node.js is currently a development harness only; the eventual production implementation and runtime for low-memory router hardware are undecided.

`credential-session.mjs` adds a test-only credential lifecycle: restores an existing account, checks token expiry with a safety margin, coalesces concurrent refreshes into one callback, atomically saves fresh credentials using the private vault, rejects cross-account changes and requires owner reauthorization on expiry or failed refresh. Refresh is **injected from a test fixture**, not a real vendor API; it does not schedule background jobs or connect externally. Stored tokens remain plaintext and require a private trusted volume.

`enrollment-state.mjs` is a deterministic QR state machine with five-minute maximum QR lifetime, distinct pending/scanned/approved/exchanging states, replay rejection and redacted public status. `fixture-qr-client.mjs` uses **only** loopback HTTP to exercise a synthetic QR server; external API URLs are rejected. `private-credentials.mjs` implements opt-in local token persistence under a private 0700 directory with atomic 0600 file writes, no-follow and restrictive ownership checks. **Tokens are stored in plaintext, not encrypted**; never mount shared folders or put real tokens into CI tests. `fixture-room-client.mjs` connects only to a local mock WebSocket server, requires the correct room token and account acknowledgement before interpreting synthetic `bmsg_push` frames, and closes on disconnect/expiry. It never connects to UU or sends WOL packets. The mock requires **separate registration evidence** showing both successful helper registration and enabled WoL before a room may accept events; room connection alone is insufficient. This fixture evidence is still synthetic. The mock uses a test-defined handshake, **not verified Socket.IO/Engine.IO vendor authentication**.

Offline verification:

```sh
sh tests/test-remote-helper-lan.sh
sh tests/test-remote-helper-magic.sh
sh tests/test-remote-helper-discovery.sh
sh tests/test-remote-helper-sender.sh
node --test tests/test-remote-helper-cloud.mjs tests/test-remote-helper-cloud-bridge.mjs
node --test tests/test-remote-helper-enrollment.mjs tests/test-remote-helper-credentials.mjs tests/test-remote-helper-qr-loopback.mjs tests/test-remote-helper-room-loopback.mjs tests/test-remote-helper-credential-session.mjs
sh tests/run-all.sh
# Where python3 and socat are installed, test real socket behavior on 127.0.0.1 only:
python3 tests/test-remote-helper-loopback.py
```

The project adds **71 shell offline cases**: 19 LAN input checks, 10 Magic Packet encoding cases, 27 synthetic interface-discovery cases (including BusyBox multiline parsing) and 15 mock socket-sender cases. It also adds **87 Node offline and loopback-auth cases** (53 original protocol/bridge cases plus 26 QR, credential and room cases and 8 credential lifecycle cases), for **158 new cases** across the project. Fixtures use RFC 5737 example IPs and a fake `socat`; no tests use a real UU account. The optional real-UDP loopback test runs only where both Python 3 and socat are available; on the existing DNAS workspace they are absent and the full suite explicitly prints `REMOTE_HELPER_LOOPBACK_SKIPPED`, rather than claiming a live UDP pass.

## Why this is separate

A NAS's default IPv4 route may identify its only LAN interface, but an OpenWrt router's default route normally points out of WAN. Copying a generic Linux default-route algorithm could register WAN identity instead of the target PC's LAN bridge. The future live adapter must positively resolve LAN role, handle multiple VLAN/subnets and verify a configured WOL target is reachable in that LAN. Do not infer the physical LAN interface from this synthetic check.

The upstream `VallierDev/uu-remote-linux` is GPL-3.0 while this project is MIT. Only public protocol observations and generic engineering concepts are being studied; no upstream source is copied into this experiment. It is not an assertion of protocol compatibility, user account authorization or licensing for a complete implementation.

See [protocol-review.md](protocol-review.md) for the exact publicly observed QR enrollment, room creation, helper registration and cloud event stages, the separate security/credential gates, and the remaining real-world verification requirements.

## Next isolated gates

1. Verify live read-only LAN interface discovery on representative OpenWrt, iStoreOS and NAS systems, including the new BusyBox multiline fallback. Distinguish default WAN, VLAN and LAN membership and confirm alias ambiguity handling.
2. Complete the isolated full-sender integration: exercise the actual `wol-send.sh` route preflight and socat on a dedicated virtual LAN in an environment with appropriate capabilities, then verify one 102-byte UDP broadcast and fail-closed behavior. The separate raw socat loopback test has passed, but the full sender's real socket branch is not yet exercised. Do not send to the user's real LAN without explicit approval.
3. Independently implement and verify a **real vendor-authenticated** UU remote enrollment/room transport (vendor request signing, TLS server verification, token rotation/refresh, helper registration and genuine Socket.IO/Engine.IO handshake), then exercise it against a controlled mock and user-authorized account. The current HTTP and WebSocket tests connect to a **loopback fixture only** and do not prove the real service protocol. Never add remote desktop, terminal, file transfer or port forwarding.
4. Only then build x86_64 and ARM64 experimental containers without touching PR #16. Actual offsite wake and post-reboot binding validation remain separate acceptance gates.

This prototype is not published, installed, or connected to any NetEase account.
