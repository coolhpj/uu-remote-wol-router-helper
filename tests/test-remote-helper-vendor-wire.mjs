import test from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import {
  prepareSignedRequest, parseQrIssued, makeQrStatusBody,
  interpretQrStatus, makeQrExchangeBody
} from "../experiments/remote-helper/vendor-wire-contract.mjs";

const key = "SYNTHETIC-VENDOR-TEST-KEY-ONLY";
const params = {
  "x-param-vn": "fixture-version",
  "x-param-ts": "1794513600",
  "x-param-plat": "1",
};
const issuedBody = { code: 0, data: {
  status_query_ticket: "status-query-fixture-20261112",
  token: "OLD-TICKET-DO-NOT-USE",
  qrcode_jump_url: "https://example.invalid/qr/login?ticket=synthetic"
} };
const issued = () => parseQrIssued(200, issuedBody);

test("canonical HMAC SHA-256 signs sorted x-param fields, method, exact path and empty QR body", () => {
  const result = prepareSignedRequest({ path: "/api/v1/qrcode/gen/login", xParams: params,
    signingKey: key });
  const known = "POST/api/v1/qrcode/gen/login" +
    "x-param-plat=1&x-param-ts=1794513600&x-param-vn=fixture-version";
  const expected = createHmac("sha256", key).update(known).digest("hex");
  assert.equal(result.headers["x-param-sign"], expected);
  assert.equal(result.bodyText, "");
  assert.deepEqual(result.publicSummary, { method: "POST", path: "/api/v1/qrcode/gen/login",
    hasSignature: true, bodyBytes: 0, headerCount: 4 });
  assert.equal(JSON.stringify(result.publicSummary).includes(key), false);
  assert.equal(Object.isFrozen(result), true);
});
test("canonical signing is independent of input field insertion order and case", () => {
  const reordered = { "x-param-plat": "1", "x-param-vn": "fixture-version",
    "x-param-ts": "1794513600" };
  const a = prepareSignedRequest({ path: "/api/v1/qrcode/gen/login", xParams: params,
    signingKey: key });
  const b = prepareSignedRequest({ path: "/api/v1/qrcode/gen/login", xParams: reordered,
    signingKey: key });
  assert.equal(a.headers["x-param-sign"], b.headers["x-param-sign"]);
  const c = prepareSignedRequest({ path: "/api/v1/qrcode/gen/login",
    xParams: { "X-Param-Plat": "1", "X-Param-Vn": "fixture-version",
      "X-Param-Ts": "1794513600" }, signingKey: key });
  assert.equal(a.headers["x-param-sign"], c.headers["x-param-sign"]);
});
test("empty QR request and signed JSON '{}' must not share a signature", () => {
  const a = prepareSignedRequest({ path: "/api/v1/qrcode/gen/login", xParams: params,
    signingKey: key });
  const b = prepareSignedRequest({ path: "/api/v1/qrcode/gen/login", xParams: params,
    signingKey: key, body: {} });
  assert.notEqual(a.headers["x-param-sign"], b.headers["x-param-sign"]);
  assert.equal(b.bodyText, "{}");
});
test("HTTP and business success must be checked before QR can be issued", () => {
  for (const [code, body] of [[422, issuedBody], [200, { code: 1120, data: issuedBody.data }],
    [200, null], [204, { code: 0, data: issuedBody.data }]]) {
    assert.throws(() => parseQrIssued(code, body), /VENDOR_RESPONSE_NOT_ACCEPTED/);
  }
});
test("status_query_ticket is mandatory; legacy token alone cannot pass", () => {
  assert.throws(() => parseQrIssued(200, { code: 0, data: {
    token: "legacy-token-do-not-use", qrcode_jump_url: "https://example.invalid/qr"
  } }), /INVALID_PROTOCOL_TICKET/);
  assert.equal(issued().statusQueryTicket, "status-query-fixture-20261112");
});
test("QR URL must be HTTPS and not use embedded credentials", () => {
  for (const url of ["http://example.invalid/login",
    "https://user:pass@example.invalid/login", "file:///tmp/code",
    "https://example.invalid/login#secret", "ftp://example.invalid/login"]) {
    assert.throws(() => parseQrIssued(200, { code: 0, data: {
      status_query_ticket: "status-query-fixture",
      qrcode_jump_url: url
    } }), /INVALID_QR_URL/);
  }
});
test("QR status body uses the new ticket and preserves last scan state", () => {
  const data = makeQrStatusBody(issued(), 2);
  assert.deepEqual(data, { token: "status-query-fixture-20261112",
    qrcode_jump_url: issuedBody.data.qrcode_jump_url, login_status: 2 });
  assert.equal(data.token === issuedBody.data.token, false);
  assert.deepEqual(makeQrExchangeBody(issued()), { token: data.token,
    qrcode_jump_url: data.qrcode_jump_url });
  assert.throws(() => makeQrStatusBody(issued(), 4), /INVALID_LAST_QR_STATUS/);
});
test("QR poll transitions reflect observed numeric server states", () => {
  for (const [server, expected] of [[1,"pending"],[2,"scanned"],[4,"approved"],
    [3,"refresh_required"],[0,"refresh_required"]]) {
    const result = interpretQrStatus(200, { code: 0, data: { status: server } });
    assert.equal(result.state, expected);
    assert.equal(result.mayExchange === true, server === 4);
  }
});
test("QR malformed numeric states and failed business codes are refused", () => {
  for (const code of [null, "4", 5, -1, 4.3]) {
    assert.throws(() => interpretQrStatus(200, { code: 0, data: { status: code } }),
      /INVALID_QR_STATUS/);
  }
  assert.throws(() => interpretQrStatus(200, { code: 1001, data: { status: 4 } }),
    /VENDOR_RESPONSE_NOT_ACCEPTED/);
});
test("missing signing key, header spoofing and path injection fail closed", () => {
  const args = { path: "/api/v1/login/by_qrcode", xParams: params, signingKey: key };
  assert.throws(() => prepareSignedRequest({ ...args, signingKey: "" }), /SIGNING_KEY_REQUIRED/);
  assert.throws(() => prepareSignedRequest({ ...args, path: "https://example.invalid/foo" }),
    /UNLISTED_VENDOR_API_PATH/);
  assert.throws(() => prepareSignedRequest({ ...args,
    xParams: { ...params, "x-param-sign": "forged" } }), /INVALID_SIGNING_PARAMS/);
  assert.throws(() => prepareSignedRequest({ ...args,
    xParams: { ...params, "x-param-User-Id": "x\r\nAuthorization: forged" } }),
    /INVALID_SIGNING_PARAMS/);
});
