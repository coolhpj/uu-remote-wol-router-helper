// Experimental independent wire-format adapter. NO networking, no static keys.
// Publicly observed, UNOFFICIAL NRD-style contract; subject to protocol changes.
// Authentication must use a key supplied by the authorized host at runtime.
// Never place real tokens/signature keys in tests, Git history or logs.
import { createHmac } from "node:crypto";

const ROUTES = Object.freeze(new Set([
  "/api/v1/device/windows/init",
  "/api/v1/qrcode/gen/login",
  "/api/v1/qrcode/login/status",
  "/api/v1/login/by_qrcode",
  "/api/v1/room/create",
  "/api/v1/device/wake_on_lan/info",
]));
function reject(code) { throw new Error(code); }
function requireValue(ok, code) { if (!ok) reject(code); }
function tokenString(value, code = "INVALID_PROTOCOL_TICKET") {
  requireValue(typeof value === "string" && value.length >= 8 && value.length <= 4096 &&
    !/[\x00-\x1f\x7f]/.test(value), code);
  return value;
}
function response(httpStatus, payload) {
  requireValue(httpStatus === 200 && payload && typeof payload === "object" &&
    !Array.isArray(payload) && payload.code === 0 &&
    payload.data && typeof payload.data === "object" && !Array.isArray(payload.data),
    "VENDOR_RESPONSE_NOT_ACCEPTED");
  return payload.data;
}
function qrURL(value) {
  tokenString(value, "INVALID_QR_URL");
  let url;
  try { url = new URL(value); } catch { reject("INVALID_QR_URL"); }
  requireValue(url.protocol === "https:" && !url.username && !url.password &&
    !url.hash && url.hostname.length > 0, "INVALID_QR_URL");
  return value;
}
export function prepareSignedRequest({ method = "POST", path, xParams, body = null, signingKey }) {
  requireValue(method === "POST" || method === "GET", "UNSUPPORTED_REQUEST_METHOD");
  requireValue(typeof path === "string" && ROUTES.has(path), "UNLISTED_VENDOR_API_PATH");
  requireValue(typeof signingKey === "string" && signingKey.length >= 8 &&
    signingKey.length <= 4096, "SIGNING_KEY_REQUIRED");
  requireValue(xParams && typeof xParams === "object" && !Array.isArray(xParams),
    "INVALID_SIGNING_PARAMS");
  const pairs = [];
  const seen = new Set();
  for (const [rawKey, rawValue] of Object.entries(xParams)) {
    const key = rawKey.toLowerCase();
    requireValue(/^x-param-[a-z0-9-]+$/.test(key) && key !== "x-param-sign" &&
      !seen.has(key) && typeof rawValue === "string" && rawValue.length <= 1024 &&
      !/[\r\n\x00]/.test(rawValue), "INVALID_SIGNING_PARAMS");
    seen.add(key);
    pairs.push([key, rawValue]);
  }
  requireValue(pairs.length >= 1 && pairs.length <= 32 && seen.has("x-param-ts"),
    "MISSING_SIGNING_TIMESTAMP");
  const timestamp = pairs.find(([key]) => key === "x-param-ts")?.[1];
  requireValue(typeof timestamp === "string" && /^[0-9]{10}$/.test(timestamp),
    "INVALID_SIGNING_TIMESTAMP");
  pairs.sort((a, b) => a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0);
  requireValue(method !== "GET" || body === null, "GET_BODY_FORBIDDEN");
  const bodyText = body === null ? "" : JSON.stringify(body);
  requireValue(typeof bodyText === "string" && bodyText.length <= 65536,
    "INVALID_SIGNED_BODY");
  const canonical = method + path + pairs.map(([key, value]) => key + "=" + value).join("&") + bodyText;
  const signature = createHmac("sha256", signingKey).update(canonical, "utf8").digest("hex");
  const headers = Object.fromEntries(pairs);
  headers["x-param-sign"] = signature;
  // Do not expose signingKey or canonical to the caller, to reduce accidental logging.
  return Object.freeze({ method, path, bodyText, headers: Object.freeze(headers),
    publicSummary: Object.freeze({ method, path, hasSignature: true,
      bodyBytes: Buffer.byteLength(bodyText), headerCount: pairs.length + 1 }) });
}

export function parseQrIssued(httpStatus, payload) {
  const data = response(httpStatus, payload);
  // Never substitute the older gen.login "token": recent hosts require the
  // explicit status-query ticket. QR URL is a bearer-like credential.
  const statusQueryTicket = tokenString(data.status_query_ticket);
  const qrcodeJumpUrl = qrURL(data.qrcode_jump_url);
  return Object.freeze({ statusQueryTicket, qrcodeJumpUrl,
    displayOnlyToOwner: true });
}
export function makeQrStatusBody(issued, lastStatus) {
  requireValue(issued && typeof issued === "object", "QR_NOT_ISSUED");
  requireValue([1, 2].includes(lastStatus), "INVALID_LAST_QR_STATUS");
  return Object.freeze({
    token: tokenString(issued.statusQueryTicket),
    qrcode_jump_url: qrURL(issued.qrcodeJumpUrl),
    login_status: lastStatus,
  });
}
export function interpretQrStatus(httpStatus, payload) {
  const data = response(httpStatus, payload);
  const code = data.status;
  requireValue(Number.isInteger(code), "INVALID_QR_STATUS");
  if (code === 1) return Object.freeze({ state: "pending", nextLastStatus: 1 });
  if (code === 2) return Object.freeze({ state: "scanned", nextLastStatus: 2 });
  if (code === 4) return Object.freeze({ state: "approved", mayExchange: true });
  if (code === 3 || code === 0)
    return Object.freeze({ state: "refresh_required", mayExchange: false });
  reject("INVALID_QR_STATUS");
}
export function makeQrExchangeBody(issued) {
  requireValue(issued && typeof issued === "object", "QR_NOT_ISSUED");
  return Object.freeze({ token: tokenString(issued.statusQueryTicket),
    qrcode_jump_url: qrURL(issued.qrcodeJumpUrl) });
}
