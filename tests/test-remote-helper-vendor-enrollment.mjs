import test from "node:test";
import assert from "node:assert/strict";
import { VendorQrEnrollment } from "../experiments/remote-helper/vendor-enrollment-flow.mjs";
import { createVendorHttpsClient, resolveVendorTimeout }
  from "../experiments/remote-helper/vendor-https-client.mjs";

const device = Object.freeze({
  name: "Synthetic Virtual Device",
  client_id: "synthetic-client-1234",
  system_id: "synthetic-system-5678",
  machine_guid: "synthetic-guid-5678",
  os: "Virtual Linux",
  base_board: "Fixture",
  cpu: "Synthetic CPU",
  video: [], mac: ["02", "11", "22", "33", "44", "55"].join(":"), memory: 2048, screen: [],
});
const qr = Object.freeze({
  statusQueryTicket: "private-fixture-status-ticket",
  qrcodeJumpUrl: "https://example.invalid/private-fixture-qr",
});
function ok(data) {
  return { httpStatus: 200, businessCode: 0, privatePayload: { code: 0, data } };
}
function fixture({
  replies = [1, 2, 4], initReply = ok({ device_id: "synthetic-device-id-1234" }),
  issueReply = qr, exchangeReply = ok({
    user_id: "synthetic-account-1234", token: "private-test-token-never-log",
  }), failPoll = false, onCredentials = async () => {},
  onDeviceInitialized = async () => {},
  clock = () => 1800000000000,
} = {}) {
  let idx = 0;
  const calls = [];
  const transport = {
    async request(path, body) {
      calls.push({ path, body });
      if (path.endsWith("/windows/init")) return initReply;
      if (path.endsWith("/qrcode/login/status")) {
        if (failPoll) throw Error("private-network-error");
        return ok({ status: replies[Math.min(idx++, replies.length - 1)] });
      }
      if (path.endsWith("/login/by_qrcode")) return exchangeReply;
      throw Error("unexpected-fixture-path");
    },
    async issueQr() { calls.push({ path: "issueQr" }); return issueReply; },
  };
  const flow = new VendorQrEnrollment({
    enabled: true, transport, virtualDevice: device,
    onDeviceInitialized, onCredentials, clock,
  });
  return { flow, calls };
}

test("enrollment defaults disabled and refuses actual physical MAC or injected fields", () => {
  const transport = { request() {}, issueQr() {} };
  assert.throws(() => new VendorQrEnrollment({
    transport, virtualDevice: device, onDeviceInitialized() {},
    onCredentials() {},
  }), /VENDOR_ENROLLMENT_DISABLED/);
  assert.throws(() => new VendorQrEnrollment({
    enabled: true, transport, virtualDevice: { ...device, mac: ["00", "11", "22", "33", "44", "55"].join(":") },
    onDeviceInitialized() {}, onCredentials() {},
  }), /VIRTUAL_MAC_NOT_LOCALLY_ADMINISTERED/);
  assert.throws(() => new VendorQrEnrollment({
    enabled: true, transport,
    virtualDevice: { ...device, cookie: "secret-cookie" },
    onDeviceInitialized() {}, onCredentials() {},
  }), /VIRTUAL_IDENTITY_FIELDS_INVALID/);
});

test("device initialization, owner-only QR, polling and single approved exchange", async () => {
  let deviceId = "";
  let saved;
  const { flow, calls } = fixture({
    onDeviceInitialized: async id => { deviceId = id; },
    onCredentials: async data => { saved = data; },
  });
  await assert.rejects(flow.issueQr(), /VENDOR_QR_ISSUE_NOT_ALLOWED/);
  assert.equal((await flow.initialize()).deviceInitialized, true);
  assert.equal(deviceId, "synthetic-device-id-1234");
  await flow.issueQr();
  assert.throws(() => flow.ownerQr(), /QR_PRIVATE_DISPLAY_NOT_CONFIRMED/);
  assert.equal(flow.ownerQr({ confirmPrivateDisplay: true }), qr.qrcodeJumpUrl);
  assert.equal((await flow.pollOnce()).state, "pending");
  assert.equal((await flow.pollOnce()).state, "scanned");
  assert.equal((await flow.pollOnce()).state, "approved");
  assert.equal((await flow.exchange()).state, "ready");
  assert.equal(saved.accountId, "synthetic-account-1234");
  assert.equal(saved.accessToken, "private-test-token-never-log");
  assert.deepEqual(calls.map(x => x.path), [
    "/api/v1/device/windows/init", "issueQr", "/api/v1/qrcode/login/status",
    "/api/v1/qrcode/login/status", "/api/v1/qrcode/login/status",
    "/api/v1/login/by_qrcode",
  ]);
  assert.deepEqual(calls.filter(x => x.path.endsWith("/status")).map(x => x.body.login_status),
    [1, 1, 2]);
  for (const forbidden of [
    qr.statusQueryTicket, qr.qrcodeJumpUrl, saved.accessToken, saved.accountId, deviceId,
  ]) assert.equal(JSON.stringify(flow.publicStatus()).includes(forbidden), false);
  await assert.rejects(flow.exchange(), /VENDOR_QR_NOT_APPROVED/);
  assert.throws(() => flow.ownerQr({ confirmPrivateDisplay: true }), /QR_NOT_AVAILABLE/);
});

test("pending after scanned does not roll back scan, retains prior status code", async () => {
  const { flow, calls } = fixture({ replies: [2, 1, 4] });
  await flow.initialize(); await flow.issueQr();
  assert.equal((await flow.pollOnce()).state, "scanned");
  assert.equal((await flow.pollOnce()).state, "scanned");
  assert.equal((await flow.pollOnce()).state, "approved");
  assert.deepEqual(calls.filter(x => x.path.endsWith("/status")).map(x => x.body.login_status),
    [1, 2, 2]);
});

test("invalid initialization response fails closed and cannot reinit", async () => {
  const { flow, calls } = fixture({ initReply: ok({ unrelated: "missing-id" }) });
  await assert.rejects(flow.initialize(), /VENDOR_DEVICE_INIT_FAILED/);
  assert.equal(flow.publicStatus().state, "failed");
  await assert.rejects(flow.initialize(), /VENDOR_DEVICE_INIT_ALREADY_ATTEMPTED/);
  assert.equal(calls.length, 1);
});

test("invalid QR issue fails closed without retry or leaking ticket", async () => {
  const { flow } = fixture({ issueReply: { statusQueryTicket: "short", qrcodeJumpUrl: "http://example.invalid" } });
  await flow.initialize();
  await assert.rejects(flow.issueQr(), /VENDOR_QR_ISSUE_FAILED/);
  assert.equal(flow.publicStatus().hasQr, false);
  await assert.rejects(flow.issueQr(), /VENDOR_QR_ISSUE_NOT_ALLOWED/);
});

test("poll errors suspend; only explicit owner retry permits one more request", async () => {
  const { flow, calls } = fixture({ failPoll: true });
  await flow.initialize(); await flow.issueQr();
  await assert.rejects(flow.pollOnce(), /VENDOR_QR_POLL_FAILED_NOT_EXPIRED/);
  assert.equal(flow.publicStatus().state, "poll_paused");
  assert.throws(() => flow.resumePoll(), /VENDOR_QR_RETRY_NOT_APPROVED/);
  assert.equal(flow.resumePoll({ ownerConfirmed: true }).state, "pending");
  assert.equal(calls.filter(x => x.path.endsWith("/status")).length, 1);
});

test("local QR expiry refuses further status requests and owner QR", async () => {
  let now = 1800000000000;
  const { flow, calls } = fixture({ clock: () => now });
  await flow.initialize(); await flow.issueQr();
  now += 300000;
  assert.equal(flow.publicStatus().state, "expired");
  await assert.rejects(flow.pollOnce(), /VENDOR_QR_POLL_NOT_ALLOWED/);
  assert.throws(() => flow.ownerQr({ confirmPrivateDisplay: true }), /QR_NOT_AVAILABLE/);
  assert.equal(calls.filter(x => x.path.endsWith("/status")).length, 0);
});

test("vendor refresh-required code cannot auto issue another QR", async () => {
  const { flow, calls } = fixture({ replies: [3] });
  await flow.initialize(); await flow.issueQr();
  assert.equal((await flow.pollOnce()).state, "expired");
  await assert.rejects(flow.issueQr(), /VENDOR_QR_ISSUE_NOT_ALLOWED/);
  assert.equal(calls.filter(x => x.path === "issueQr").length, 1);
});

test("concurrent polling rejects the second call and cannot duplicate request", async () => {
  let resolve;
  const pending = new Promise(r => { resolve = r; });
  let polls = 0;
  const { flow } = fixture();
  const original = flow; // No dynamic monkeypatching of private transport.
  assert.ok(original);
  const transport = {
    async request(path) {
      if (path.endsWith("/windows/init")) return ok({ device_id: "synthetic-device-id-1234" });
      if (path.endsWith("/status")) { polls++; return pending; }
      throw Error("unexpected");
    },
    async issueQr() { return qr; },
  };
  const f = new VendorQrEnrollment({
    enabled: true, transport, virtualDevice: device,
    onDeviceInitialized() {}, onCredentials() {},
  });
  await f.initialize(); await f.issueQr();
  const first = f.pollOnce();
  await assert.rejects(f.pollOnce(), /VENDOR_ENROLLMENT_BUSY/);
  resolve(ok({ status: 2 }));
  assert.equal((await first).state, "scanned");
  assert.equal(polls, 1);
});

test("cancellation while long poll is pending cannot revive an enrollment", async () => {
  let resolve;
  const pending = new Promise(r => { resolve = r; });
  const transport = {
    async request(path) {
      if (path.endsWith("/windows/init")) return ok({ device_id: "synthetic-device-id-1234" });
      if (path.endsWith("/status")) return pending;
      throw Error("unexpected");
    },
    async issueQr() { return qr; },
  };
  const flow = new VendorQrEnrollment({
    enabled: true, transport, virtualDevice: device,
    onDeviceInitialized() {}, onCredentials() {},
  });
  await flow.initialize(); await flow.issueQr();
  const active = flow.pollOnce();
  assert.equal(flow.cancel().state, "cancelled");
  resolve(ok({ status: 4 }));
  await assert.rejects(active, /VENDOR_ENROLLMENT_CANCELLED/);
  assert.equal(flow.publicStatus().state, "cancelled");
  await assert.rejects(flow.exchange(), /VENDOR_QR_NOT_APPROVED/);
});

test("exchange fails once on invalid business result, never returns a token", async () => {
  const { flow, calls } = fixture({ replies: [4],
    exchangeReply: { httpStatus: 401, businessCode: 1001, privatePayload: {
      code: 1001, data: { token: "should-not-leak" },
    } },
  });
  await flow.initialize(); await flow.issueQr(); await flow.pollOnce();
  await assert.rejects(flow.exchange(), e => {
    assert.equal(e.message, "VENDOR_QR_EXCHANGE_FAILED_REAUTH_REQUIRED");
    assert.ok(!e.message.includes("should-not-leak"));
    return true;
  });
  assert.equal(flow.publicStatus().state, "failed");
  assert.equal(calls.filter(x => x.path.endsWith("by_qrcode")).length, 1);
});

test("failure to store a real token cannot be silently treated as login success", async () => {
  const { flow } = fixture({ replies: [4], onCredentials: async () => {
    throw new Error("private-secret-do-not-echo");
  } });
  await flow.initialize(); await flow.issueQr(); await flow.pollOnce();
  await assert.rejects(flow.exchange(), e => {
    assert.equal(e.message, "VENDOR_QR_EXCHANGE_FAILED_REAUTH_REQUIRED");
    assert.equal(e.message.includes("private-secret"), false);
    return true;
  });
  assert.equal(flow.publicStatus().state, "failed");
});

test("only QR-status requests receive 65s long-poll budget; bad settings rejected", () => {
  assert.equal(resolveVendorTimeout("/api/v1/qrcode/login/status"), 65000);
  assert.equal(resolveVendorTimeout("/api/v1/qrcode/gen/login"), 10000);
  assert.equal(resolveVendorTimeout("/api/v1/device/windows/init"), 10000);
  assert.throws(() => resolveVendorTimeout("/api/v1/qrcode/login/status", 1000, 71000),
    /VENDOR_TIMEOUT_INVALID/);
});

test("the actual signed HTTPS adapter can traverse synthetic init->QR->poll->exchange", async () => {
  const paths = [];
  let liveDeviceId = "";
  let count = 0;
  const signingKey = "fixture-only-hmac-key";
  const requests = [
    { code: 0, data: { device_id: "device-id-from-fixture" } },
    { code: 0, data: { status_query_ticket: qr.statusQueryTicket,
      qrcode_jump_url: qr.qrcodeJumpUrl } },
    { code: 0, data: { status: 4 } },
    { code: 0, data: { user_id: "synthetic-account-1234",
      token: "private-test-token-never-log" } },
  ];
  const client = createVendorHttpsClient({
    enabled: true, signingKey, clock: () => 1800000000000,
    xParams: ({ path, nowSeconds }) => ({
      "x-param-ts": String(nowSeconds), "x-param-plat": "1",
      ...(liveDeviceId ? { "x-param-device-id": liveDeviceId } : {}),
    }),
    fetchImpl: async (url, options) => {
      const path = new URL(url).pathname;
      paths.push(path);
      assert.equal(options.method, "POST");
      assert.ok(/^[a-f0-9]{64}$/.test(options.headers["x-param-sign"]));
      assert.equal(Object.hasOwn(options.headers, "x-param-device-id"),
        count > 0);
      if (path.endsWith("/qrcode/gen/login")) assert.equal(options.body, "");
      else assert.ok(options.body?.startsWith("{"));
      return new Response(JSON.stringify(requests[count++]), {
        status: 200, headers: { "content-type": "application/json" },
      });
    },
  });
  let acceptedCredentials = false;
  const flow = new VendorQrEnrollment({
    enabled: true, transport: client, virtualDevice: device,
    onDeviceInitialized: id => { liveDeviceId = id; },
    onCredentials: data => {
      acceptedCredentials = data.accountId === "synthetic-account-1234" &&
        data.accessToken === "private-test-token-never-log";
    },
  });
  await flow.initialize(); await flow.issueQr(); await flow.pollOnce();
  assert.equal((await flow.exchange()).state, "ready");
  assert.equal(acceptedCredentials, true);
  assert.deepEqual(paths, [
    "/api/v1/device/windows/init", "/api/v1/qrcode/gen/login",
    "/api/v1/qrcode/login/status", "/api/v1/login/by_qrcode",
  ]);
  assert.equal(JSON.stringify(flow.publicStatus()).includes("private-test-token"), false);
});

test("QR URL with embedded username/password is rejected even by a mocked transport", async () => {
  const { flow } = fixture({ issueReply: {
    statusQueryTicket: "synthetic-ticket-12345",
    qrcodeJumpUrl: "https://user:secret@example.invalid/private",
  } });
  await flow.initialize();
  await assert.rejects(flow.issueQr(), /VENDOR_QR_ISSUE_FAILED/);
  assert.equal(flow.publicStatus().hasQr, false);
});

test("cancellation before device-init response prevents persisting the server identity", async () => {
  let resolve;
  const pending = new Promise(r => { resolve = r; });
  let stored = 0;
  const transport = {
    async request() { return pending; },
    async issueQr() { throw Error("QR should not be reached"); },
  };
  const flow = new VendorQrEnrollment({
    enabled: true, transport, virtualDevice: device,
    onDeviceInitialized: () => { stored++; },
    onCredentials() {},
  });
  const active = flow.initialize();
  flow.cancel();
  resolve(ok({ device_id: "private-device-identity" }));
  await assert.rejects(active, /VENDOR_DEVICE_INIT_FAILED/);
  assert.equal(stored, 0);
  assert.equal(flow.publicStatus().deviceInitialized, false);
  assert.equal(flow.publicStatus().state, "cancelled");
});

test("cancel before exchange response blocks credential persistence", async () => {
  let resolve;
  const pending = new Promise(r => { resolve = r; });
  let stored = 0;
  const transport = {
    async request(path) {
      if (path.endsWith("/windows/init")) return ok({ device_id: "synthetic-device-id-1234" });
      if (path.endsWith("/status")) return ok({ status: 4 });
      if (path.endsWith("/login/by_qrcode")) return pending;
      throw Error("unexpected");
    },
    async issueQr() { return qr; },
  };
  const flow = new VendorQrEnrollment({
    enabled: true, transport, virtualDevice: device,
    onDeviceInitialized() {}, onCredentials() { stored++; },
  });
  await flow.initialize(); await flow.issueQr(); await flow.pollOnce();
  const active = flow.exchange();
  flow.cancel();
  resolve(ok({ user_id: "synthetic-account", token: "should-not-be-saved" }));
  await assert.rejects(active, /VENDOR_QR_EXCHANGE_FAILED_REAUTH_REQUIRED/);
  assert.equal(stored, 0);
  assert.equal(flow.publicStatus().state, "cancelled");
});

test("QR status polling has a hard attempt cap and cannot run forever", async () => {
  const { flow, calls } = fixture({ replies: [1] });
  await flow.initialize(); await flow.issueQr();
  for (let i = 0; i < 16; i++) assert.equal((await flow.pollOnce()).state, "pending");
  await assert.rejects(flow.pollOnce(), /VENDOR_QR_POLL_BUDGET_EXHAUSTED/);
  assert.equal(flow.publicStatus().state, "poll_paused");
  assert.throws(() => flow.resumePoll({ ownerConfirmed: true }),
    /VENDOR_QR_POLL_BUDGET_EXHAUSTED/);
  assert.equal(calls.filter(x => x.path.endsWith("/status")).length, 16);
});

