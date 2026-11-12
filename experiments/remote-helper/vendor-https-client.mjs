// Optional, owner-authorized HTTPS transport for the experimental UU WOL helper.
// This is not a UU login client: no key, credentials or requests are bundled.
// Default is OFFLINE. A genuine scan requires separate owner authorization.
// No GPL implementation was copied into this independently authored transport.
import { prepareSignedRequest, parseQrIssued } from "./vendor-wire-contract.mjs";

export const VENDOR_ORIGIN = "https://api.nrd.nie.163.com";
const MAX_REPLY_BYTES = 16 * 1024;
const QR_STATUS_PATH = "/api/v1/qrcode/login/status";
function reject(code) { throw new Error(code); }

// QR status may be a 60-second long poll; other endpoints remain short-lived.
export function resolveVendorTimeout(path, normalMs = 10000, qrPollMs = 65000) {
  if (!Number.isInteger(normalMs) || normalMs < 1000 || normalMs > 15000 ||
      !Number.isInteger(qrPollMs) || qrPollMs < 60000 || qrPollMs > 70000)
    reject("VENDOR_TIMEOUT_INVALID");
  return path === QR_STATUS_PATH ? qrPollMs : normalMs;
}

async function readJsonBounded(response) {
  const contentType = response.headers?.get?.("content-type") ?? "";
  if (!/^application\/json(?:;|$)/i.test(contentType.trim())) reject("VENDOR_NON_JSON_REPLY");
  const reader = response.body?.getReader?.();
  if (!reader) reject("VENDOR_EMPTY_REPLY");
  let bytes = 0;
  const parts = [];
  try {
    while (true) {
      const item = await reader.read();
      if (item.done) break;
      bytes += item.value.byteLength;
      if (bytes > MAX_REPLY_BYTES) {
        await reader.cancel().catch(() => {});
        reject("VENDOR_REPLY_TOO_LARGE");
      }
      parts.push(item.value);
    }
  } finally {
    reader.releaseLock();
  }
  let parsed;
  try {
    const combined = new Uint8Array(bytes);
    let offset = 0;
    for (const part of parts) { combined.set(part, offset); offset += part.byteLength; }
    parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(combined));
  } catch { reject("VENDOR_INVALID_JSON"); }
  if (!parsed || Array.isArray(parsed) || typeof parsed !== "object")
    reject("VENDOR_INVALID_JSON");
  return parsed;
}

export function createVendorHttpsClient({
  enabled = false, signingKey, xParams, fetchImpl = globalThis.fetch,
  timeoutMs = 10000, qrPollTimeoutMs = 65000, clock = Date.now,
} = {}) {
  if (enabled !== true) reject("VENDOR_NETWORK_DISABLED");
  if (process.env.NODE_TLS_REJECT_UNAUTHORIZED === "0")
    reject("VENDOR_TLS_VERIFICATION_DISABLED");
  if (typeof fetchImpl !== "function") reject("VENDOR_FETCH_UNAVAILABLE");
  if (typeof clock !== "function") reject("VENDOR_CLOCK_UNAVAILABLE");
  resolveVendorTimeout(QR_STATUS_PATH, timeoutMs, qrPollTimeoutMs);

  async function request(path, body = null, method = "POST") {
    // Resolve fresh headers for every request: a static timestamp or device ID
    // from before registration cannot authenticate a later QR poll.
    let params;
    let now;
    try { now = clock(); }
    catch { reject("VENDOR_CLOCK_UNAVAILABLE"); }
    if (!Number.isSafeInteger(now) || now < 0) reject("VENDOR_CLOCK_INVALID");
    try { params = typeof xParams === "function" ? xParams({ path, method, nowSeconds: Math.floor(now / 1000) }) : xParams; }
    catch { reject("VENDOR_SIGNING_PARAMS_UNAVAILABLE"); }
    const signed = prepareSignedRequest({ method, path, xParams: params, body, signingKey });
    if (Math.abs(Number(signed.headers["x-param-ts"]) * 1000 - now) > 120000)
      reject("VENDOR_SIGNING_TIMESTAMP_STALE");
    const url = new URL(path, VENDOR_ORIGIN);
    if (url.origin !== VENDOR_ORIGIN || url.pathname !== path || url.search || url.hash)
      reject("VENDOR_URL_REJECTED");
    let response;
    try {
      response = await fetchImpl(url.href, {
        method: signed.method,
        headers: { ...signed.headers, "accept": "application/json",
          ...(method === "POST" ? { "content-type": "application/json" } : {}) },
        body: method === "POST" ? signed.bodyText : undefined,
        redirect: "error", credentials: "omit", cache: "no-store",
        signal: AbortSignal.timeout(resolveVendorTimeout(path, timeoutMs, qrPollTimeoutMs)),
      });
    } catch {
      // No URLs, requests, signatures, keys, tickets or response bodies in errors.
      reject("VENDOR_HTTPS_REQUEST_FAILED");
    }
    if (!Number.isInteger(response?.status) || response.status < 100 ||
        response.status > 599 || (response.status >= 300 && response.status < 400))
      reject("VENDOR_HTTP_STATUS_REJECTED");
    const payload = await readJsonBounded(response);
    const businessCode = Number.isInteger(payload.code) ? payload.code : null;
    return Object.freeze({
      httpStatus: response.status, businessCode,
      // Private: never write this payload to console, Git, artifacts or Progress.
      privatePayload: payload,
    });
  }

  async function issueQr() {
    const result = await request("/api/v1/qrcode/gen/login", null);
    const issued = parseQrIssued(result.httpStatus, result.privatePayload);
    // QR URL and ticket are sensitive. In-memory only; caller must not log.
    return Object.freeze({ ...issued, sensitive: true });
  }

  return Object.freeze({ request, issueQr });
}

export function sanitizedVendorResult(result) {
  if (!result || !Number.isInteger(result.httpStatus)) reject("VENDOR_RESULT_INVALID");
  return Object.freeze({ httpStatus: result.httpStatus,
    businessCode: Number.isInteger(result.businessCode) ? result.businessCode : null,
    qrUrlPrinted: false, credentialsPrinted: false });
}
