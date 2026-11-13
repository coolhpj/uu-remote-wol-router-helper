// Experimental, offline-first room-create response and signaling endpoint gate.
// Independent implementation of publicly described fields, not licensed vendor
// protocol code or a verified NetEase transport. No I/O, WOL or client secrets.
// A response shape and bearer token alone NEVER authenticate a cloud room.
const MAX_TOKEN_BYTES = 4096;
const MAX_AGE_MS = 120000;
const MAX_SERVER_BYTES = 256;

function fail(code) { throw new Error(code); }
function requireRule(ok, code) { if (!ok) fail(code); }
function record(x) { return x !== null && typeof x === "object" && !Array.isArray(x); }

function approvedHostname(value) {
  requireRule(typeof value === "string" && value.length <= 253 &&
    value.length > 0 && value === value.toLowerCase() &&
    /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(value),
    "INVALID_APPROVED_SIGNAL_HOST");
  // The supplied hostname is an EXACT pin from a trusted operator policy;
  // no wildcard, suffix matching, .local, localhost, or IP literal is allowed.
  requireRule(!value.endsWith(".local") && !value.endsWith(".invalid") &&
    !value.endsWith(".test"), "UNTRUSTED_SIGNAL_HOST");
  return value;
}

export function inspectSignalingServer(server, approvedHost) {
  const expected = approvedHostname(approvedHost);
  requireRule(typeof server === "string" && Buffer.byteLength(server) <= MAX_SERVER_BYTES,
    "INVALID_SIGNALING_SERVER");
  let u;
  try { u = new URL(server); } catch { fail("INVALID_SIGNALING_SERVER"); }
  requireRule(u.protocol === "wss:" && u.hostname === expected && !u.username &&
    !u.password && !u.search && !u.hash && !u.port &&
    u.pathname === "/" && u.href === "wss://" + expected + "/",
    "SIGNALING_ENDPOINT_REJECTED");
  return Object.freeze({
    origin: u.origin,
    socketIOPath: u.origin + "/socket.io/?transport=websocket&EIO=4",
    exactHostMatched: true,
  });
}

export function parseRoomCandidate({
  httpStatus, payload, approvedSignalHost, receivedAtMs, clock = Date.now,
  maxAgeMs = 60000,
} = {}) {
  requireRule(typeof clock === "function" && Number.isSafeInteger(receivedAtMs) &&
    Number.isInteger(maxAgeMs) && maxAgeMs >= 1000 &&
    maxAgeMs <= MAX_AGE_MS, "ROOM_CLOCK_INVALID");
  const now = clock();
  requireRule(Number.isSafeInteger(now) && now >= receivedAtMs &&
    now - receivedAtMs < maxAgeMs, "ROOM_CREATE_STALE");
  requireRule(httpStatus === 200 && record(payload) && payload.code === 0 &&
    record(payload.data), "ROOM_CREATE_NOT_ACCEPTED");
  const data = payload.data;
  const host = inspectSignalingServer(data.signaling_server, approvedSignalHost);

  // Opaque bearer credential. The token must never appear in a URL or public
  // status, and a syntactically valid token is never proof of authentication.
  const token = data.token;
  requireRule(typeof token === "string" &&
    Buffer.byteLength(token, "utf8") >= 16 &&
    Buffer.byteLength(token, "utf8") <= MAX_TOKEN_BYTES &&
    /^[A-Za-z0-9._~-]+$/.test(token), "INVALID_ROOM_BEARER");
  if (data.signaling_list !== undefined) {
    requireRule(Array.isArray(data.signaling_list) &&
      data.signaling_list.length > 0 && data.signaling_list.length <= 8 &&
      data.signaling_list.every(v => {
        try { inspectSignalingServer(v, approvedSignalHost); return true; }
        catch { return false; }
      }), "UNAPPROVED_SIGNALING_FALLBACK");
  }
  if (data.ws_connect_timeout_ms !== undefined)
    requireRule(Number.isInteger(data.ws_connect_timeout_ms) &&
      data.ws_connect_timeout_ms >= 1000 &&
      data.ws_connect_timeout_ms <= 20000, "UNSAFE_SIGNAL_TIMEOUT");

  // An unverified JWT payload may be used only to DENY obviously expired
  // candidates. It cannot authorize a room or establish server identity.
  if (token.split(".").length === 3) {
    // A three-segment JWT-like value must have parseable expiry metadata or
    // be rejected. Unverified JWT claims are never used as positive identity.
    const part = token.split(".")[1];
    requireRule(part.length <= 8192 && /^[A-Za-z0-9_-]+$/.test(part),
      "INVALID_ROOM_BEARER");
    let decoded;
    try { decoded = JSON.parse(Buffer.from(part, "base64url").toString("utf8")); }
    catch { fail("INVALID_ROOM_BEARER"); }
    requireRule(record(decoded) && Number.isSafeInteger(decoded.exp) &&
      decoded.exp >= 0, "INVALID_ROOM_BEARER");
    requireRule(decoded.exp * 1000 > now + 5000, "ROOM_BEARER_EXPIRED");
  }

  const publicResult = Object.freeze({
    acceptedResponseShape: true, exactHostMatched: true,
    engineIOVersion: 4, socketIOPathValidated: true,
    authenticated: false, registrationVerified: false,
    wakePermitted: false, tokenExposed: false,
  });

  return Object.freeze({
    publicStatus: () => publicResult,
    // Only explicitly enabled, owner-authorized transport wiring may access
    // the private request. This does not perform WebSocket I/O and the caller
    // is still responsible for TLS certificate validation, token transport,
    // room-account binding, server ACK and authenticated registration proof.
    prepareUpgradeRequest({ enabled = false } = {}) {
      requireRule(enabled === true, "ROOM_TRANSPORT_DISABLED");
      requireRule(clock() - receivedAtMs < maxAgeMs, "ROOM_CREATE_STALE");
      return Object.freeze({
        url: host.socketIOPath,
        headers: Object.freeze({ "X-NRD-AUTH": token }),
        sensitive: true, authenticated: false, maySendWol: false,
      });
    },
    toJSON: () => publicResult,
  });
}
