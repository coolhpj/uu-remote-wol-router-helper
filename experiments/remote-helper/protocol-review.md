# UU Remote helper protocol review — research and implementation gates

**Status (2026-11-12):** research notes and offline-only contracts, **not** a UU client, working login, registered helper or cloud listener. No user credential or network packet was used while building the registration/message parser. Existing PR #16 (official router `uuplugin` experiment) is unchanged.

## Evidence boundaries

[Keithin's Z4 report in Issue #15](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/15#issuecomment-6820635855) describes a non-gateway x86_64 NAS running a **third-party UU Remote Linux host identity**, not the router `uuplugin` identity. The reporter says it registered as a wake helper, received a cloud `wake_on_lan` command, emitted Magic Packet and survived a whole NAS reboot. These are third-party **device** observations; we have not independently reproduced their service protocol or live WOL.

Public protocol observations from [VallierDev/uu-remote-linux](https://github.com/VallierDev/uu-remote-linux) (GPL-3.0; **do not copy implementation code into this MIT repo**) and [its registration-field fix `fe052cdc`](https://github.com/VallierDev/uu-remote-linux/commit/fe052cdca7ad90d1ab7c27d031036b1071869070) suggest the following steps. These are reverse-engineered community observations, **not an official, stable vendor API specification**.

## External dependencies and stages not implemented

| Stage | Observed protocol clue | Required independent proof |
|---|---|---|
| Device enrollment | Device initialization before QR login (reported endpoint `/api/v1/device/windows/init`) | Explicit host identity, no unauthorized automatic registration |
| QR sign-in | QR generation, status polling and owner confirmation (reported `/api/v1/qrcode/gen/login`, `/api/v1/qrcode/login/status`, `/api/v1/login/by_qrcode`) | Owner actually scans/authorizes, retry/expiry safety, no token/QR logging |
| Room creation | Authenticated account creates a signaling room (reported `/api/v1/room/create`) | Live response, server identity/TLS, room token expiry and refresh |
| Helper registration | Report `mac`, `ip`, `inner_ip`, `subnet_mask` to a helper info endpoint (reported `/api/v1/device/wake_on_lan/info`) | Real account-accepted HTTP 200 + business code 0 and service-side helper enablement |
| Cloud command | Socket.IO / Engine.IO room push `bmsg_push` with `type=wake_on_lan` and `target_device` | Authenticated room and validated push, not merely a local JSON fixture |
| Real wake | MAC and LAN identity validated against local user-owned targets; one directed LAN Magic Packet | Real PC offline→online over mobile data, plus post-reboot identity reuse |

The reported REST API requires request authentication and vendor-specific request-signing parameters. **No embedded client secret, signing key, cookies or third-party source code should be copied into this MIT experiment.** API status, session identity, token rotation and actual field shapes must be verified with the owner's account before claiming compatibility. A normal `HTTP 200` or an established WebSocket is not proof that remote wake works.

## What is actually implemented

- `cloud-contract.mjs` (Node 22 development harness): deterministic, **network-free** registration-body validator, HTTP/business-result checker and Socket.IO `bmsg_push / wake_on_lan` frame validator. It requires a future caller to provide a *verified* account/room state, an accepted helper registration and explicit WOL enablement. It then enforces an **owner-configured exact MAC+IP allowlist**, LAN subnet/mask and produces **inert** wake instructions. Caller-supplied boolean state in an offline fixture **does not establish actual authentication**.
- `tests/test-remote-helper-cloud.mjs`: normal/invalid protocol, wrong account, unknown target, expired/unconnected room, wrong mask, illegal MAC/IP, malformed or oversized messages.
- `tests/test-remote-helper-cloud-bridge.mjs`: simulated accepted registration and an artificial cloud frame flowing to `wol-send.sh` with **fake `ip` and `socat`** in a temporary directory. This proves the two local modules' data shapes and 102-byte WoL format compose, **not actual cloud delivery**.
- There is **no** real QR authorization client, persistent credential store, TLS/WebSocket transport, push subscription, account registration request, scheduled renewal or real-cloud device discovery. The Node harness is not the final selected production runtime; routers with tight memory must not be forced to install a full general-purpose remote desktop or Node environment.

## Next acceptance gate (no community waiting required)

1. Build a separate minimal authentication/QR state machine and room protocol adapter with loopback-only fake server tests. Do not accept event content from an arbitrary socket as proof of cloud authentication.
2. Review token and helper identity persistence (private 0600 files, atomic writes and reboot/expiry behavior), plus target allowlist storage and container capabilities, **before** using the account.
3. Only then carry out owner-approved first QR login and official app helper registration; observe sanitized error category, not credentials. Verify cloud pushes and directed WOL on an isolated/test LAN, then a real user's controlled target and post-reboot mobile-data wake. **No auto-deployment** on router/NAS main networks.
4. Ship a second, explicitly opt-in Docker mode only after x86_64/ARM64 resource, license and security tests. Keep the existing official-router-plugin path and its data untouched.

**Source licensing:** our repository is MIT; third-party `VallierDev/uu-remote-linux` and `Keithin/uu-remote-nas-wol` are GPL-3.0. This file records protocol facts and independent research tasks; it does not authorize copying GPL implementation into MIT sources.
