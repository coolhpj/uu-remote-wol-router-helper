import test from "node:test";
import assert from "node:assert/strict";
import { createVendorHttpsClient, sanitizedVendorResult, VENDOR_ORIGIN }
  from "../experiments/remote-helper/vendor-https-client.mjs";

const options = {
  enabled: true, signingKey: "synthetic-ci-test-key", clock: () => 1763000000000,
  xParams: {
    "x-param-ts": "1763000000", "x-param-plat": "1",
  },
};
function result(payload, status = 200, contentType = "application/json") {
  return new Response(typeof payload === "string" ? payload : JSON.stringify(payload),
    { status, headers: { "content-type": contentType } });
}

test("defaults to no vendor network; does not call fetch", () => {
  let fetches = 0;
  assert.throws(() => createVendorHttpsClient({
    ...options, enabled: false, fetchImpl: () => { fetches++; },
  }), /VENDOR_NETWORK_DISABLED/);
  assert.equal(fetches, 0);
});

test("TLS verification disabled environment is fail closed", () => {
  const old = process.env.NODE_TLS_REJECT_UNAUTHORIZED;
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";
  try {
    assert.throws(() => createVendorHttpsClient(options),
      /VENDOR_TLS_VERIFICATION_DISABLED/);
  } finally {
    if (old === undefined) delete process.env.NODE_TLS_REJECT_UNAUTHORIZED;
    else process.env.NODE_TLS_REJECT_UNAUTHORIZED = old;
  }
});

test("fixed official host, signed empty POST, no redirect and no credentials", async () => {
  let count = 0;
  const client = createVendorHttpsClient({
    ...options,
    fetchImpl: async (url, init) => {
      count++;
      assert.equal(url, VENDOR_ORIGIN + "/api/v1/qrcode/gen/login");
      assert.equal(init.method, "POST");
      assert.equal(init.body, "");
      assert.equal(init.redirect, "error");
      assert.equal(init.credentials, "omit");
      assert.equal(init.cache, "no-store");
      assert.ok(/^[a-f0-9]{64}$/.test(init.headers["x-param-sign"]));
      assert.equal(init.headers["x-param-ts"], "1763000000");
      assert.ok(!Object.values(init.headers).includes(options.signingKey));
      return result({ code: 0, data: {
        status_query_ticket: "synthetic-ticket-value",
        qrcode_jump_url: "https://example.invalid/only-for-test",
      } });
    },
  });
  const issued = await client.issueQr();
  assert.equal(count, 1);
  assert.equal(issued.sensitive, true);
  assert.equal(issued.displayOnlyToOwner, true);
  assert.equal(issued.statusQueryTicket, "synthetic-ticket-value");
  assert.equal(issued.qrcodeJumpUrl, "https://example.invalid/only-for-test");
});

test("unknown API path fails before fetch", async () => {
  let count = 0;
  const client = createVendorHttpsClient({ ...options,
    fetchImpl: async () => { count++; return result({ code: 0, data: {} }); },
  });
  await assert.rejects(client.request("/unexpected/admin", null), /UNLISTED_VENDOR_API_PATH/);
  assert.equal(count, 0);
});

test("request does not log tokens, QR URL or server raw errors", async () => {
  const privateText = "hidden-secret-ticket";
  const client = createVendorHttpsClient({ ...options,
    fetchImpl: async () => result({ code: 401, data: { token: privateText } }, 401),
  });
  const response = await client.request("/api/v1/qrcode/gen/login", null);
  assert.equal(response.httpStatus, 401);
  assert.deepEqual(sanitizedVendorResult(response), {
    httpStatus: 401, businessCode: 401,
    qrUrlPrinted: false, credentialsPrinted: false,
  });
  assert.equal(JSON.stringify(sanitizedVendorResult(response)).includes(privateText), false);
});

test("redirects, HTML, invalid JSON, oversized replies are rejected", async () => {
  for (const [response, error] of [
    [new Response(null, { status: 302, headers: { location: "/login" } }),
      "VENDOR_HTTP_STATUS_REJECTED"],
    [result("<html>login</html>", 200, "text/html"), "VENDOR_NON_JSON_REPLY"],
    [result("{bad json", 200), "VENDOR_INVALID_JSON"],
    [result({ code: 0, data: { text: "A".repeat(17000) } }),
      "VENDOR_REPLY_TOO_LARGE"],
  ]) {
    const client = createVendorHttpsClient({ ...options, fetchImpl: async () => response });
    await assert.rejects(client.request("/api/v1/qrcode/gen/login"), new RegExp(error));
  }
});

test("network exception and timeout bounds do not reveal request details", async () => {
  assert.throws(() => createVendorHttpsClient({ ...options, timeoutMs: 20000 }),
    /VENDOR_TIMEOUT_INVALID/);
  const client = createVendorHttpsClient({ ...options,
    fetchImpl: async () => { throw new Error("sensitive-qr-url"); },
  });
  await assert.rejects(client.issueQr(), e => {
    assert.equal(e.message, "VENDOR_HTTPS_REQUEST_FAILED");
    assert.ok(!e.message.includes("sensitive-qr-url"));
    return true;
  });
});

test("a synthetic 200 response without QR ticket is not valid authentication", async () => {
  const client = createVendorHttpsClient({ ...options,
    fetchImpl: async () => result({ code: 0, data: {
      token: "legacy-token-only", qrcode_jump_url: "https://example.invalid/qr",
    } }),
  });
  await assert.rejects(client.issueQr(), /INVALID_PROTOCOL_TICKET/);
});

test("no signing key means zero network attempts", async () => {
  let count = 0;
  const client = createVendorHttpsClient({
    ...options, signingKey: undefined,
    fetchImpl: async () => { count++; return result({ code: 0, data: {} }); },
  });
  await assert.rejects(client.request("/api/v1/device/windows/init", {
    name: "synthetic-test-device",
  }), /SIGNING_KEY_REQUIRED/);
  assert.equal(count, 0);
});

test("stale signing timestamp prevents any network attempt", async () => {
  let sent = 0;
  const client = createVendorHttpsClient({
    ...options, clock: () => 1763000300000,
    fetchImpl: async () => { sent++; return result({ code: 0, data: {} }); },
  });
  await assert.rejects(client.request("/api/v1/device/windows/init", {
    name: "virtual-fixture",
  }), /VENDOR_SIGNING_TIMESTAMP_STALE/);
  assert.equal(sent, 0);
});

test("dynamic timestamp and device identity are refreshed on each signed request", async () => {
  let now = 1763000000000;
  let deviceId = "";
  const headers = [];
  const client = createVendorHttpsClient({
    ...options, clock: () => now,
    xParams: ({ nowSeconds }) => ({
      "x-param-ts": String(nowSeconds), "x-param-plat": "1",
      ...(deviceId ? { "x-param-device-id": deviceId } : {}),
    }),
    fetchImpl: async (_url, init) => {
      headers.push(init.headers);
      return result({ code: 0, data: {} });
    },
  });
  await client.request("/api/v1/device/windows/init", {});
  now += 200000;
  deviceId = "synthetic-fixture-device";
  await client.request("/api/v1/qrcode/gen/login", null);
  assert.equal(headers.length, 2);
  assert.equal(headers[0]["x-param-device-id"], undefined);
  assert.equal(headers[1]["x-param-device-id"], deviceId);
  assert.equal(headers[0]["x-param-ts"], "1763000000");
  assert.equal(headers[1]["x-param-ts"], "1763000200");
  assert.notEqual(headers[0]["x-param-sign"], headers[1]["x-param-sign"]);
});

test("signing parameter provider failure is redacted and sends no HTTP", async () => {
  let sent = 0;
  const client = createVendorHttpsClient({
    ...options, xParams: () => { throw Error("sensitive-local-secret"); },
    fetchImpl: async () => { sent++; return result({ code: 0, data: {} }); },
  });
  await assert.rejects(client.request("/api/v1/qrcode/gen/login", null), e => {
    assert.equal(e.message, "VENDOR_SIGNING_PARAMS_UNAVAILABLE");
    assert.equal(e.message.includes("sensitive-local-secret"), false);
    return true;
  });
  assert.equal(sent, 0);
});
