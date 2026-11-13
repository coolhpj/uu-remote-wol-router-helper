// Fixture-only local QR/room client. NEVER connects to vendor services.
// This client's HTTP requests are allowed ONLY to numeric IPv4 loopback.
// Actual UU Remote QR endpoint/signing/auth transport remains unimplemented.
const MAX_RESPONSE = 16 * 1024;
const LOOPBACK_HOST = [127, 0, 0, 1].join(".");
function check(value, code) { if (!value) throw new Error(code); }
function validChallenge(value) {
  check(typeof value === "string" && /^[a-zA-Z0-9_-]{8,128}$/.test(value), "INVALID_CHALLENGE");
  return value;
}
export class FixtureQRClient {
  #base;
  constructor(base) {
    let url;
    try { url = new URL(base); } catch { throw new Error("INVALID_FIXTURE_URL"); }
    check(url.protocol === "http:" && url.hostname === LOOPBACK_HOST &&
      /^[0-9]{1,5}$/.test(url.port) && !url.username && !url.password &&
      url.pathname === "/" && !url.hash && !url.search, "FIXTURE_LOOPBACK_ONLY");
    this.#base = url.href;
  }
  async #call(path, { method = "GET", json = null, accessToken = null } = {}) {
    check(path.startsWith("/fixture/"), "FIXTURE_PATH_REQUIRED");
    const headers = { "Accept": "application/json" };
    if (json !== null) headers["Content-Type"] = "application/json";
    if (accessToken) {
      check(typeof accessToken === "string" && accessToken.length >= 8,
        "INVALID_AUTH_TOKEN");
      headers.Authorization = "Bearer " + accessToken;
    }
    const res = await fetch(new URL(path.slice(1), this.#base), {
      method, headers, body: json === null ? undefined : JSON.stringify(json),
      redirect: "error", cache: "no-store", credentials: "omit",
      signal: AbortSignal.timeout(2000),
    });
    // No raw body/HTTP header included in errors: tokens must not be logged.
    check(res.status === 200 && res.headers.get("content-type")?.includes("application/json"),
      "FIXTURE_RESPONSE_REJECTED");
    let bytes = 0;
    const parts = [];
    for await (const part of res.body) {
      bytes += part.byteLength;
      if (bytes > MAX_RESPONSE) {
        await res.body.cancel().catch(() => {});
        throw new Error("FIXTURE_RESPONSE_TOO_LARGE");
      }
      parts.push(part);
    }
    let result;
    try {
      const merged = Buffer.concat(parts.map(x => Buffer.from(x))).toString("utf8");
      result = JSON.parse(merged);
    } catch { throw new Error("FIXTURE_BAD_JSON"); }
    check(result && typeof result === "object" && !Array.isArray(result), "FIXTURE_BAD_JSON");
    return result;
  }
  begin() { return this.#call("/fixture/qr/start", { method: "POST", json: {} }); }
  poll(challengeId) {
    return this.#call("/fixture/qr/status?id=" + encodeURIComponent(validChallenge(challengeId)));
  }
  exchange(challengeId) {
    return this.#call("/fixture/qr/exchange", { method: "POST",
      json: { challengeId: validChallenge(challengeId) } });
  }
  createRoom(accessToken) {
    return this.#call("/fixture/room/create", { method: "POST", json: {},
      accessToken });
  }
}
