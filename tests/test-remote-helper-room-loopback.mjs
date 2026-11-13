import test from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { createHash } from "node:crypto";
import dgram from "node:dgram";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { FixtureRoomClient } from "../experiments/remote-helper/fixture-room-client.mjs";
import { registrationResult } from "../experiments/remote-helper/cloud-contract.mjs";

const packetEncoderPath = fileURLToPath(new URL("../experiments/remote-helper/magic-packet-hex.sh", import.meta.url));
const accountId = "fixture-account-01";
const token = "fixture-validated-room-token";
const evidence = registrationResult(200, { code: 0, data: { turn_on_wol: true } });
const config = {
  accountId,
  helper: { lanInterface: "br-lan", ip: "198.51.100.1",
    subnetMask: "255.255.255.0", mac: "02:aa:bb:cc:dd:ee" },
  allowedTargets: [{ mac: "02:10:20:30:40:50", ip: "198.51.100.40" }]
};
const push = (target = config.allowedTargets[0]) =>
  "42" + JSON.stringify(["bmsg_push", { type: "wake_on_lan", data: {
    target_device: { ...target, subnet_mask: config.helper.subnetMask }
  } }]);
function serverFrame(message) {
  const data = Buffer.from(message, "utf8");
  if (data.length < 126) return Buffer.concat([Buffer.from([0x81, data.length]), data]);
  const header = Buffer.alloc(4);
  header[0] = 0x81; header[1] = 126; header.writeUInt16BE(data.length, 2);
  return Buffer.concat([header, data]);
}
function createServer(scenario) {
  const service = http.createServer((_req, res) => { res.writeHead(404); res.end(); });
  const sockets = new Set();
  service.on("upgrade", (req, socket) => {
    sockets.add(socket);
    socket.once("close", () => sockets.delete(socket));
    if (req.url !== "/fixture/room" || req.headers.upgrade?.toLowerCase() !== "websocket") {
      socket.destroy(); return;
    }
    const key = req.headers["sec-websocket-key"];
    if (typeof key !== "string" || !/^[a-zA-Z0-9+/=]{20,28}$/.test(key)) {
      socket.destroy(); return;
    }
    const accept = createHash("sha1").update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
      .digest("base64");
    socket.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n");
    if (scenario === "premature" || scenario === "valid") socket.write(serverFrame(push()));
    let buffer = Buffer.alloc(0);
    socket.on("data", chunk => {
      buffer = Buffer.concat([buffer, chunk]);
      while (buffer.length >= 6) {
        const opcode = buffer[0] & 15, len = buffer[1] & 127, masked = (buffer[1] & 128) !== 0;
        if (opcode === 8) { socket.end(); return; }
        if (opcode !== 1 || !masked || len >= 126) { socket.destroy(); return; }
        const required = 2 + 4 + len;
        if (buffer.length < required) return;
        const key = buffer.subarray(2, 6);
        const value = Buffer.alloc(len);
        for (let i=0; i<len; i++) value[i] = buffer[6+i] ^ key[i % 4];
        buffer = buffer.subarray(required);
        let auth;
        try { auth = JSON.parse(value.toString("utf8")); } catch { socket.destroy(); return; }
        const correct = auth.kind === "auth" && auth.roomId === "fixture-room-01" &&
          auth.accountId === accountId && auth.roomToken === token;
        if (!correct || scenario === "reject") {
          socket.write(serverFrame(JSON.stringify({ kind: "auth_rejected" })));
          continue;
        }
        if (scenario === "wrong-ack") {
          socket.write(serverFrame(JSON.stringify({
            kind: "room_ready", roomId: "fixture-room-01", accountId: "wrong-account"
          })));
          continue;
        }
        socket.write(serverFrame(JSON.stringify({
          kind: "room_ready", roomId: auth.roomId, accountId: auth.accountId
        })));
        if (scenario === "valid") {
          socket.write(serverFrame(push()));
          socket.write(serverFrame(push({ mac: "02:10:20:30:40:52", ip: "198.51.100.40" })));
        }
        if (scenario === "disconnect") socket.end();
      }
    });
  });
  return { service, sockets };
}
async function withRoom(scenario, fn) {
  const { service, sockets } = createServer(scenario);
  await new Promise(resolve => service.listen(0, "127.0.0.1", resolve));
  const port = service.address().port;
  const room = { roomId: "fixture-room-01", roomToken: token,
    accountId, expiresAt: Date.now() + 60_000 };
  try {
    return await fn({ url: "ws://127.0.0.1:" + port + "/fixture/room", room });
  } finally {
    for (const socket of sockets) socket.destroy();
    await new Promise(resolve => service.close(resolve));
  }
}
async function until(condition, timeout = 1800) {
  const started = Date.now();
  while (!condition()) {
    if (Date.now() - started > timeout) throw new Error("MOCK_ROOM_ASSERTION_TIMEOUT");
    await new Promise(resolve => setTimeout(resolve, 12));
  }
}
test("real loopback websocket: no premature push, trusted fixture ack, allowlisted wake plan", () =>
  withRoom("valid", async ({ url, room }) => {
    const plans = [];
    const client = new FixtureRoomClient({ url, room, config, registrationEvidence: evidence,
      onPlan(plan) { plans.push(plan); } });
    const status = await client.connect();
    assert.equal(status.status, "ready");
    await until(() => client.publicStatus().acceptedPlans === 1);
    assert.equal(plans.length, 1);
    assert.equal(plans[0].packetSent, false);
    assert.equal(plans[0].targetIP, "198.51.100.40");
    assert.equal(client.publicStatus().containsCredentials, false);
    assert.ok(client.publicStatus().rejectedMessages >= 2); // early push and wrong target
    client.close();
    await until(() => client.publicStatus().status === "closed");
  }));
test("wrong room token is rejected, no wake plan", () =>
  withRoom("valid", async ({ url, room }) => {
    const client = new FixtureRoomClient({ url, room: { ...room,
      roomToken: "fixture-invalid-token" }, config, registrationEvidence: evidence });
    await assert.rejects(client.connect(), /ROOM_AUTH_REJECTED/);
    assert.equal(client.publicStatus().acceptedPlans, 0);
    client.close();
  }));
test("room disconnect invalidates local authenticated session", () =>
  withRoom("disconnect", async ({ url, room }) => {
    const client = new FixtureRoomClient({ url, room, config, registrationEvidence: evidence });
    try { await client.connect(); } catch (e) {
      assert.match(e.message, /ROOM_DISCONNECTED/);
    }
    await until(() => client.publicStatus().status === "closed");
    assert.equal(client.publicStatus().acceptedPlans, 0);
    assert.throws(() => client.connect(), /ROOM_ALREADY_USED/);
  }));
test("stale or mismatched accounts never open a socket", () => {
  for (const url of ["wss://example.invalid/fixture/room",
    "ws://example.invalid:15000/fixture/room", "ws://127.0.0.1:1234/other"]) {
    assert.throws(() => new FixtureRoomClient({ url, config, registrationEvidence: evidence, room: {
      roomId: "fixture-room-01", accountId, roomToken: token, expiresAt: Date.now()+2000
    } }), /ROOM_LOOPBACK_ONLY/);
  }
  assert.throws(() => new FixtureRoomClient({
    url: "ws://127.0.0.1:1234/fixture/room", config, registrationEvidence: evidence,
    room: { roomId: "fixture-room-01", roomToken: token,
      accountId: "wrong-account", expiresAt: Date.now()+2000 }
  }), /INVALID_ROOM_CONTRACT/);
});
test("room authentication alone never implies helper registration", () => {
  const url = "ws://127.0.0.1:1234/fixture/room";
  const room = { roomId: "fixture-room-01", roomToken: token,
    accountId, expiresAt: Date.now() + 60_000 };
  assert.throws(() => new FixtureRoomClient({ url, room, config }),
    /REGISTRATION_GATE_REQUIRED/);
});
test("registered helper with WoL disabled cannot accept room pushes", () => {
  const url = "ws://127.0.0.1:1234/fixture/room";
  const room = { roomId: "fixture-room-01", roomToken: token,
    accountId, expiresAt: Date.now() + 60_000 };
  const disabled = registrationResult(200, { code: 0, data: { turn_on_wol: false } });
  assert.throws(() => new FixtureRoomClient({
    url, room, config, registrationEvidence: disabled
  }), /REGISTRATION_GATE_REQUIRED/);
});
test("expired room cannot open or process wake data", () =>
  withRoom("valid", async ({ url, room }) => {
    let current = room.expiresAt - 1;
    const client = new FixtureRoomClient({ url, room, config, registrationEvidence: evidence, clock: () => current });
    current = room.expiresAt + 1;
    await assert.rejects(client.connect(), /ROOM_EXPIRED/);
    assert.equal(client.publicStatus().status, "closed");
    assert.equal(client.publicStatus().acceptedPlans, 0);
  }));

test("virtual end-to-end: authenticated room push sends original 102-byte Magic Packet to isolated UDP loopback", async () => {
  // The only UDP destination is loopback inside this test runner, never a LAN.
  // The real WOL sender's route and one-shot approval gates remain separate.
  const receiver = dgram.createSocket("udp4");
  const sender = dgram.createSocket("udp4");
  const received = [], errors = [], planned = [];
  receiver.on("message", (bytes, info) => received.push({ bytes, info }));
  receiver.on("error", error => errors.push(error));
  sender.on("error", error => errors.push(error));
  try {
    await new Promise((resolve, reject) => {
      receiver.once("error", reject);
      receiver.bind(0, "127.0.0.1", resolve);
    });
    const port = receiver.address().port;
    await withRoom("valid", async ({ url, room }) => {
      const client = new FixtureRoomClient({
        url, room, config, registrationEvidence: evidence,
        onPlan(plan) {
          planned.push(plan);
          assert.equal(plan.packetSent, false);
          assert.equal(plan.targetIP, config.allowedTargets[0].ip);
          assert.equal(plan.targetMAC.replace(/:/g, "").toLowerCase(),
            config.allowedTargets[0].mac.replace(/:/g, "").toLowerCase());
          // Reuse the project's original shell packet encoder, not a test-only
          // encoder, then send its exact bytes over a real OS UDP loopback socket.
          const hex = execFileSync("sh", [packetEncoderPath, plan.targetMAC],
            { encoding: "utf8", timeout: 3000, maxBuffer: 2048 }).trim();
          assert.match(hex, /^[A-F0-9]{204}$/);
          sender.send(Buffer.from(hex, "hex"), port, "127.0.0.1",
            error => { if (error) errors.push(error); });
        }
      });
      try {
        const status = await client.connect();
        assert.equal(status.status, "ready");
        await until(() => received.length === 1 || errors.length > 0);
        await new Promise(resolve => setTimeout(resolve, 75));
        assert.deepEqual(errors, []);
        assert.equal(client.publicStatus().acceptedPlans, 1);
        assert.ok(client.publicStatus().rejectedMessages >= 2);
        assert.equal(planned.length, 1);
        assert.equal(received.length, 1, "only allowlisted post-auth push produces UDP");
        assert.equal(received[0].info.address, "127.0.0.1");
        const payload = received[0].bytes;
        assert.equal(payload.length, 102);
        const expectedMAC = Buffer.from(planned[0].targetMAC.replace(/:/g, ""), "hex");
        assert.deepEqual(payload.subarray(0, 6), Buffer.alloc(6, 0xff));
        for (let i = 0; i < 16; i++)
          assert.deepEqual(payload.subarray(6 + i * 6, 12 + i * 6), expectedMAC);
        assert.equal(client.publicStatus().containsCredentials, false);
      } finally { client.close(); }
    });
  } finally {
    receiver.close();
    sender.close();
  }
});
