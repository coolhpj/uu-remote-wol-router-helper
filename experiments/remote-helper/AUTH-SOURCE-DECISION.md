# UU Remote Helper: signing source and backend feasibility (2026-11-13)

This is **engineering evidence for an unpublished Draft PR**, not a NetEase
approval, API license, independent cloud login or production install guide.
**WOL-only** is the product requirement: remote shell, file transfer, remote
assistance, desktop control, LAN port mapping and broad host mounts are out
of scope. Do not present a working full remote host as a WOL-only helper.

## What the sources establish

1. NetEase's [public mobile integration guide](https://github.com/netease-uuyc/uuremote-integration-guide)
   (MIT) documents URL Scheme / Android Intent interactions: launch the
   installed official UU Remote app, bind a Windows/macOS **remote-control**
   target and request full-screen or picture-in-picture remote control.
   It **does not document a headless WOL-helper registration API**, an
   independent host account token, or a signing key. Such functions may
   exist privately, but this guide is not evidence of public authorization
   for the different headless server-side API.
2. Independent GPL-3.0 [VallierDev/uu-remote-linux](https://github.com/VallierDev/uu-remote-linux)
   documents experimental `UU_WOL_HELPER=1` and reports headless NAS/iOS
   real-cloud wake. Its separate [Docker deployment guide](https://github.com/VallierDev/uu-remote-linux/blob/main/docs/deploy-nas-docker.md)
   also advertises remote **terminal, file transfer and port mapping**.
   `UU_PORT_MAPPING=0` and `UU_REMOTE_ASSIST=0` mitigate *two* features,
   but the public guide does not establish a no-terminal/no-file-transfer
   mode. Host networking and port mapping may expose LAN services. A GPL
   sidecar therefore cannot pass our WOL-only release gate merely because
   WOL works. No GPL source or signing constants are included in MIT.
3. The local `vendor-wire-contract.mjs` / `vendor-https-client.mjs`
   implement a **candidate, unofficial** signed request format. CI validates
   byte-for-byte canonicalization and mock HTTPS, not a vendor-accepted
   request. A publicly visible client signing constant, even described as
   "public", is not automatically an official API grant or evidence that
   shipping or using it complies with terms.

## Independently authorized signer seam

`prepareExternallySignedRequest` accepts a caller-supplied signing callback
only after **explicit opt-in**. It restricts requests to the reviewed API
path allowlist, validates canonical HTTP method, headers and body, accepts
only a lowercase SHA-256-format signature and fails closed on provider
errors/timeouts. It does not bundle, discover, log or persist a key.

A signing challenge may contain sensitive account/device identifiers, so
it must go only to a provider whose use is explicitly authorized and whose
logging and access controls are separately reviewed. The callback runs in
the caller process; **this repository is not a signing service or a trust
anchor**.

`createVendorHttpsClient({ externalSigner, explicitlyAuthorizedSigner:true,
enabled:true, ... })` can use that callback via the existing hardened HTTPS
adapter. Network access still requires explicit opt-in, verified TLS, a
permitted signer, and the account owner's authorization. No NetEase signing
capability is obtained by implementing this interface. Current tests use
a synthetic HMAC callback and fake `fetch` only; a correct signature or an
HTTP 200 does not imply `authenticated`, `registrationVerified` or
`wakePermitted`.

## Decision matrix

| Route | Evidence | WOL-only release now? |
| --- | --- | --- |
| MIT standalone without authorized signing source | Offline contract and virtual LAN verified; live credential source absent | **No** |
| MIT standalone with future permitted signer | Integration interface tested only with synthetic callback | **No** until real account, registration and WOL evidence |
| Official mobile URL Scheme / Intent | Documents app launch and remote-control binding, not headless helper | **No** |
| Independent GPL full host / Docker sidecar | Upstream reports WOL, but terminal and file-transfer functionality also exist | **No** under current WOL-only policy; requires separate security/license review |

**Next genuine gate**: identify a permitted, independently maintainable
headless helper signing/API mechanism, or verify a supported independent
upstream mode that really disables all non-WOL remote tools. Then verify
actual vendor HTTP/business acceptance, authenticated Socket.IO room,
owner/device binding, registration, authorized wake push, scoped LAN packet
and restart persistence as separate facts. Existing owner Windows PC is
not needed for current CI.

Do not merge Draft PR #19, publish a production image, copy GPL source or
vendor signing constants, reuse a third party's real credentials, or
install a full remote host under a WOL-only label merely because CI is green.
