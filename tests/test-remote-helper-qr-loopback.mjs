import test from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { Enrollment } from "../experiments/remote-helper/enrollment-state.mjs";
import { PrivateCredentialVault } from "../experiments/remote-helper/private-credentials.mjs";
import { FixtureQRClient } from "../experiments/remote-helper/fixture-qr-client.mjs";

const challengeId = "qr-fixture-owned-01";
const accessToken = "fixture-access-token-private";
const refreshToken = "fixture-refresh-token-private";
function send(res, code, body) {
  res.writeHead(code, { "content-type": "application/json", "cache-control": "no-store" });
  res.end(JSON.stringify(body));
}
async function serverForTest(fn) {
  let phase = "pending";
  let exchanged = false;
  let roomCount = 0;
  const now = Date.now();
  const service = http.createServer((req, res) => {
    const pathname = new URL(req.url, "http://fixture.invalid").pathname;
    if (req.method === "POST" && pathname === "/fixture/qr/start") {
      return send(res, 200, { challengeId,
        qrUrl: "https://qr.example.invalid/owner-approval",
        expiresAt: now + 60_000 });
    }
    if (req.method === "GET" && pathname === "/fixture/qr/status") {
      if (new URL(req.url, "http://fixture.invalid").searchParams.get("id") !== challengeId)
        return send(res, 403, { error: "wrong challenge" });
      return send(res, 200, { challengeId, status: phase });
    }
    if (req.method === "POST" && pathname === "/fixture/qr/exchange") {
      if (phase !== "approved" || exchanged) return send(res, 403, { error: "not approved" });
      exchanged = true;
      return send(res, 200, { version: 1, provider: "uu-remote-helper",
        accountId: "fixture-account-01", accessToken, refreshToken,
        expiresAt: now + 3_600_000 });
    }
    if (req.method === "POST" && pathname === "/fixture/room/create") {
      if (req.headers.authorization !== "Bearer " + accessToken)
        return send(res, 401, { error: "not authenticated" });
      roomCount++;
      return send(res, 200, { roomId: "fixture-room-01", roomToken: "fixture-room-token",
        accountId: "fixture-account-01" });
    }
    if (pathname === "/fixture/big-response") return send(res, 200, { x: "x".repeat(18000) });
    if (pathname === "/fixture/redirect") {
      res.writeHead(302, { location: "https://example.invalid/" });
      return res.end();
    }
    return send(res, 404, { error: "unknown fixture" });
  });
  await new Promise(resolve => service.listen(0, "127.0.0.1", resolve));
  const port = service.address().port;
  const url = "http://127.0.0.1:" + port + "/";
  try {
    return await fn({ client: new FixtureQRClient(url),
      setPhase(v) { phase = v; }, getRoomCount() { return roomCount; } });
  } finally { await new Promise((resolve, reject) => service.close(e => e ? reject(e) : resolve())); }
}
test("loopback-only QR approval, one-time exchange, 0600 persistence, authenticated room", () =>
  serverForTest(async ({ client, setPhase, getRoomCount }) => {
    const state = new Enrollment();
    const issued = await client.begin();
    assert.equal(state.begin(issued).status, "pending");
    assert.equal((await client.poll(issued.challengeId)).status, "pending");
    setPhase("scanned");
    assert.equal(state.poll(await client.poll(issued.challengeId)).status, "scanned");
    setPhase("approved");
    assert.equal(state.poll(await client.poll(issued.challengeId)).status, "approved");
    state.claimExchange({ challengeId: issued.challengeId });
    const credential = await client.exchange(issued.challengeId);
    const root = await fs.mkdtemp(path.join(os.tmpdir(), "uu-qr-loopback-"));
    try {
      const vault = new PrivateCredentialVault(path.join(root, "credentials"));
      const summary = await vault.save(credential);
      assert.equal(summary.accountId, "fixture-account-01");
      assert.equal(JSON.stringify(summary).includes(accessToken), false);
      const saved = await vault.load();
      const ready = state.finishExchange({ challengeId: issued.challengeId,
        accountId: saved.accountId });
      assert.equal(ready.status, "ready");
      const room = await client.createRoom(saved.accessToken);
      assert.equal(room.accountId, saved.accountId);
      assert.equal(room.roomId, "fixture-room-01");
      assert.equal(getRoomCount(), 1);
      await assert.rejects(client.exchange(issued.challengeId), /FIXTURE_RESPONSE_REJECTED/);
    } finally { await fs.rm(root, { recursive: true, force: true }); }
  }));
test("missing approval prevents token exchange and room requires matching token", () =>
  serverForTest(async ({ client, getRoomCount }) => {
    await client.begin();
    await assert.rejects(client.exchange(challengeId), /FIXTURE_RESPONSE_REJECTED/);
    await assert.rejects(client.createRoom("fixture-wrong-token"), /FIXTURE_RESPONSE_REJECTED/);
    assert.equal(getRoomCount(), 0);
  }));
test("fixture client rejects external endpoints and credential injection", () => {
  for (const address of ["https://example.invalid:443/", "http://example.invalid:8888/",
    "http://127.0.0.1/", "http://user:pass@127.0.0.1:3000/",
    "http://127.0.0.1:3000/path", "file:///tmp/fixture"]) {
    assert.throws(() => new FixtureQRClient(address), /FIXTURE_LOOPBACK_ONLY|INVALID_FIXTURE_URL/);
  }
});
test("wrong QR challenge cannot be polled", () =>
  serverForTest(async ({ client }) => {
    await assert.rejects(client.poll("other-challenge"), /FIXTURE_RESPONSE_REJECTED/);
  }));
test("QR fixture cannot contact a remote domain", () =>
  serverForTest(async ({ client }) => {
    await assert.rejects(client.createRoom("fixture-wrong-token"), /FIXTURE_RESPONSE_REJECTED/);
  }));
