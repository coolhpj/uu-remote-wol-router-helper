// Optional, owner-authorized HTTPS transport for the experimental UU WOL helper.
// This is not a UU login client: no key, credentials or requests are bundled.
// Default is OFFLINE. A genuine scan requires separate owner authorization.
// No GPL implementation was copied into this independently authored transport.
import { prepareSignedRequest, parseQrIssued } from "./vendor-wire-contract.mjs";

export const VENDOR_ORIGIN = "https://api.nrd.nie.163.com";
const MAX_REPLY_BYTES = 16 * 1024;
function reject(code) { throw new Error(code); }

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
  timeoutMs = 10000,
} = {}) {
  if (enabled !== true) reject("VENDOR_NETWORK_DISABLED");
  if (process.env.NODE_TLS_REJECT_UNAUTHORIZED === "0")
    reject("VENDOR_TLS_VERIFICATION_DISABLED");
  if (typeof fetchImpl !== "function") reject("VENDOR_FETCH_UNAVAILABLE");
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1000 || timeoutMs > 15000)
    reject("VENDOR_TIMEOUT_INVALID");

  async function request(path, body = null, method = "POST") {
    const signed = prepareSignedRequest({ method, path, xParams, body, signingKey });
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
        signal: AbortSignal.timeout(timeoutMs),
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
