// Independent, offline-only UU Remote WOL protocol contract (Node.js 20+).
// No network, no credentials, no process spawn, no WOL transmissions.
// This is a boundary for future *authenticated* transport integration,
// not a working UU client and not copied from GPL implementations.

const MAX_PUSH_BYTES = 16 * 1024;

function plain(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function fail(code) { throw new Error(code); }

export function ipv4(value) {
  if (typeof value !== "string") fail("INVALID_IPV4");
  const parts = value.split(".");
  if (parts.length !== 4 || parts.some(p => !/^(0|[1-9][0-9]{0,2})$/.test(p))) fail("INVALID_IPV4");
  const nums = parts.map(Number);
  if (nums.some(n => n > 255)) fail("INVALID_IPV4");
  return nums.reduce((n, octet) => (n * 256 + octet) >>> 0, 0);
}

export function normalizeMAC(value) {
  if (typeof value !== "string") fail("INVALID_MAC");
  const normalized = value.toUpperCase().replace(/[:-]/g, "");
  if (!/^[0-9A-F]{12}$/.test(normalized)) fail("INVALID_MAC");
  if (normalized === "000000000000" || normalized === "FFFFFFFFFFFF") fail("INVALID_MAC");
  if ((Number.parseInt(normalized.slice(0, 2), 16) & 1) !== 0) fail("MULTICAST_MAC");
  return normalized.match(/../g).join(":");
}

function formatIPv4(n) {
  return [n >>> 24, (n >>> 16) & 255, (n >>> 8) & 255, n & 255].join(".");
}

export function subnet(helperIP, mask) {
  const ip = ipv4(helperIP);
  const m = ipv4(mask);
  const inverted = (~m) >>> 0;
  if (m === 0 || m === 0xffffffff || (inverted & (inverted + 1)) !== 0) fail("UNSUPPORTED_SUBNET_MASK");
  const prefix = 32 - Math.log2(inverted + 1);
  if (!Number.isInteger(prefix) || prefix < 8 || prefix > 30) fail("UNSUPPORTED_SUBNET_MASK");
  const network = (ip & m) >>> 0;
  const broadcast = (network | inverted) >>> 0;
  const first = ip >>> 24;
  if (ip === network || ip === broadcast || first === 0 || first === 127 || first >= 224
      || (ip >>> 16) === 0xa9fe) fail("INVALID_HELPER_HOST");
  return Object.freeze({ network, broadcast, mask: m, helper: ip,
    directedBroadcast: formatIPv4(broadcast), prefix });
}

function validateHost(value, net, reason = "TARGET_OUTSIDE_LAN") {
  const addr = ipv4(value);
  if ((addr & net.mask) >>> 0 !== net.network || addr === net.network || addr === net.broadcast
    || addr === net.helper || (addr >>> 24) === 0 || (addr >>> 24) >= 224) fail(reason);
  return addr;
}

export function registrationBody(helper) {
  if (!plain(helper) || !/^[A-Za-z0-9_.:-]{1,24}$/.test(helper.lanInterface ?? "")
    || /^(lo[0-9]*|wan[0-9]*|pppoe.*|tun.*|wg.*|docker.*|veth.*)$/i.test(helper.lanInterface)) fail("INVALID_LAN_INTERFACE");
  const net = subnet(helper.ip, helper.subnetMask);
  const mac = normalizeMAC(helper.mac);
  return Object.freeze({ mac, ip: formatIPv4(net.helper),
    inner_ip: formatIPv4(net.helper), subnet_mask: helper.subnetMask });
}

// An HTTP 200 response with business code 0 proves acceptance only,
// not that the cloud will deliver a wake push or that the PC can wake.
export function registrationResult(httpStatus, payload) {
  if (httpStatus !== 200 || !plain(payload) || payload.code !== 0) fail("REGISTRATION_NOT_ACCEPTED");
  const data = plain(payload.data) ? payload.data : {};
  const rawEnabled = Object.hasOwn(data, "turn_on_wol") ? data.turn_on_wol : payload.turn_on_wol;
  if (rawEnabled === false) return Object.freeze({ accepted: true, enabled: false, cloudPushVerified: false });
  return Object.freeze({ accepted: true, enabled: rawEnabled === true ? true : null, cloudPushVerified: false });
}

function parseFrame(frame) {
  if (typeof frame !== "string" || Buffer.byteLength(frame, "utf8") > MAX_PUSH_BYTES
      || !frame.startsWith("42")) fail("INVALID_SIGNALING_FRAME");
  let body;
  try { body = JSON.parse(frame.slice(2)); } catch { fail("INVALID_SIGNALING_JSON"); }
  if (!Array.isArray(body) || body.length !== 2 || typeof body[0] !== "string"
      || !plain(body[1])) fail("INVALID_SIGNALING_EVENT");
  return body;
}

// Caller MUST be a transport authenticating the account and room token;
// the shape alone cannot authenticate a cloud message.
// The returned plan is inert data. Sending is deliberately out of scope.
export function validateWakePush(frame, session, config) {
  if (!plain(session) || session.authenticated !== true || session.roomConnected !== true
    || session.registrationAccepted !== true || session.wolEnabled !== true || session.expired === true
    || typeof session.accountId !== "string" || session.accountId.trim() === "") {
    fail("AUTHENTICATED_ROOM_REQUIRED");
  }
  if (!plain(config) || session.accountId !== config.accountId) fail("ACCOUNT_MISMATCH");
  const [eventName, event] = parseFrame(frame);
  if (eventName !== "bmsg_push" || event.type !== "wake_on_lan")
    return Object.freeze({ kind: "ignored", packetSent: false });
  if (!plain(event.data) || !plain(event.data.target_device)) fail("MISSING_WAKE_TARGET");

  const helper = config.helper;
  const body = registrationBody(helper); // validates the LAN identity
  const net = subnet(body.ip, body.subnet_mask);
  const selectedInterface = helper.lanInterface;
  const target = event.data.target_device;
  if (normalizeMAC(target.mac) === body.mac) fail("HELPER_CANNOT_WAKE_ITSELF");

  const allowed = Array.isArray(config.allowedTargets) ? config.allowedTargets : [];
  if (!allowed.length || allowed.length > 32) fail("EMPTY_OR_OVERSIZED_ALLOWLIST");
  const localMacs = new Set();
  let authorizedTarget = null;
  for (const entry of allowed) {
    if (!plain(entry)) fail("INVALID_ALLOWLIST_ENTRY");
    const mac = normalizeMAC(entry.mac);
    if (localMacs.has(mac)) fail("DUPLICATE_ALLOWLIST_MAC");
    localMacs.add(mac);
    validateHost(entry.ip, net, "ALLOWLIST_TARGET_OUTSIDE_LAN");
    if (mac === normalizeMAC(target.mac)) authorizedTarget = entry;
  }
  if (!authorizedTarget) fail("WAKE_TARGET_NOT_ALLOWLISTED");
  if (ipv4(target.ip) !== ipv4(authorizedTarget.ip)) fail("WAKE_TARGET_IP_MISMATCH");
  if (target.subnet_mask !== body.subnet_mask) fail("WAKE_TARGET_SUBNET_MISMATCH");
  validateHost(target.ip, net);

  return Object.freeze({ kind: "authorized_wake_plan", packetSent: false,
    lanInterface: selectedInterface, sourceIP: body.ip,
    targetIP: authorizedTarget.ip, targetMAC: normalizeMAC(authorizedTarget.mac),
    directedBroadcast: net.directedBroadcast, port: 9,
    verification: "offline-only; cloud transport and host wake unverified" });
}
