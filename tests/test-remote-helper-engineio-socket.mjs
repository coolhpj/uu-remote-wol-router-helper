import test from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { createHash } from "node:crypto";
import { FixtureEngineIOV4Session } from "../experiments/remote-helper/fixture-engineio-socket.mjs";
import { parseRoomCandidate } from "../experiments/remote-helper/vendor-room-contract.mjs";

const loopback = [127, 0, 0, 1].join(".");
const wssHost = "signal.example.org";
const expectedPath = "/socket.io/?transport=websocket&EIO=4";
const token1 = "synthetic-room-ticket-first";
const token2 = "synthetic-room-ticket-second";
const createCandidate = (token = token1, clock = Date.now) => {
  const now = clock();
  return parseRoomCandidate({
    httpStatus: 200,
    payload: { code: 0, data: {
      signaling_server: "wss://" + wssHost, token,
    } },
    approvedSignalHost: wssHost, receivedAtMs: now, clock,
  });
};
function serverFrame(value) {
  const data = Buffer.from(value, "utf8");
  if (data.length < 126) return Buffer.concat([Buffer.from([0x81, data.length]), data]);
  const header = Buffer.alloc(4);
  header[0] = 0x81; header[1] = 126; header.writeUInt16BE(data.length, 2);
  return Buffer.concat([header, data]);
}
const wake = "42" + JSON.stringify(["bmsg_push", {
  type: "wake_on_lan",
  data: { target_device: { mac: ["02","10","20","30","40","50"].join(":"),
    ip: "198.51.100.40", subnet_mask: "255.255.255.0" } },
}]);
function createServer(scenario = "valid") {
  const service = http.createServer((_request, res) => {
    res.writeHead(404); res.end();
  });
  const connections = new Set();
  const received = [];
  let upgrades = 0;
  service.on("upgrade", (req, socket) => {
    upgrades++;
    connections.add(socket);
    socket.once("close", () => connections.delete(socket));
    if (req.url !== expectedPath || req.headers.upgrade?.toLowerCase() !== "websocket") {
      socket.destroy(); return;
    }
    const key = req.headers["sec-websocket-key"];
    if (typeof key !== "string") { socket.destroy(); return; }
    const accept = createHash("sha1").update(
      key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
    socket.write("HTTP/1.1 101 Switching Protocols\r\n" +
      "Upgrade: websocket\r\nConnection: Upgrade\r\n" +
      "Sec-WebSocket-Accept: " + accept + "\r\n\r\n");
    socket.write(serverFrame('0{"sid":"fixture-sid","pingInterval":1000,"pingTimeout":1000}'));
    let pending = Buffer.alloc(0);
    socket.on("data", data => {
      pending = Buffer.concat([pending, data]);
      while (pending.length >= 6) {
        const opcode = pending[0] & 0x0f;
        const masked = !!(pending[1] & 0x80);
        const length = pending[1] & 0x7f;
        if (opcode === 8) { socket.end(); return; }
        if (opcode !== 1 || !masked || length >= 126) { socket.destroy(); return; }
        if (pending.length < 6 + length) return;
        const mask = pending.subarray(2, 6);
        const raw = pending.subarray(6, 6 + length);
        const bytes = Buffer.from(raw);
        for (let i = 0; i < bytes.length; i++) bytes[i] ^= mask[i % 4];
        pending = pending.subarray(6 + length);
        const packet = bytes.toString("utf8");
        received.push(packet);
        if (packet === "40") {
          if (scenario === "reject-namespace") {
            socket.write(serverFrame('44{"message":"not authorized"}'));
          } else {
            socket.write(serverFrame('40{"sid":"namespace-sid"}'));
            if (scenario === "premature") socket.write(serverFrame(wake));
          }
        }
        if (packet === '4211["room_info"]') {
          if (scenario === "wrong-ack") socket.write(serverFrame('4312[{"ok":true}]'));
          else if (scenario === "malformed-ack") socket.write(serverFrame("4311[bad]"));
          else if (scenario !== "silent-room") {
            socket.write(serverFrame('4311[{"ok":"fixture-only"}]'));
            if (scenario === "valid" || scenario === "premature") {
              socket.write(serverFrame(wake));
              socket.write(serverFrame("2"));
            }
            if (scenario === "disconnect") socket.end();
          }
        }
      }
    });
  });
  return { service, connections, received, get upgrades() { return upgrades; } };
}
async function withServer(scenario, fn) {
  const server = createServer(scenario);
  await new Promise(resolve => server.service.listen(0, loopback, resolve));
  const url = "ws://" + loopback + ":" + server.service.address().port + expectedPath;
  try { return await fn({ ...server, url, get upgrades() { return server.upgrades; } }); }
  finally {
    for (const socket of server.connections) socket.destroy();
    await new Promise(resolve => server.service.close(resolve));
  }
}
const factory = ({ url, approvedWssUrl, privateUpgradeHeaders, fixtureOnly }) => {
  assert.equal(fixtureOnly, true);
  assert.equal(approvedWssUrl, "wss://signal.example.org/socket.io/?transport=websocket&EIO=4");
  assert.ok(privateUpgradeHeaders["X-NRD-AUTH"].startsWith("synthetic-room-ticket-"));
  // WHATWG WebSocket on Node does not forward this custom private header.
  // The production TLS/upgrade/authentication path is intentionally absent.
  return new WebSocket(url);
};
const make = ({ url, token = token1, clock, scenarioFactory = factory,
  connectTimeoutMs = 450 } = {}) => new FixtureEngineIOV4Session({
    roomCandidate: createCandidate(token, clock || Date.now),
    fixtureUrl: url, socketFactory: scenarioFactory, clock,
    connectTimeoutMs, checkIntervalMs: 15,
  });
async function until(fn, timeout = 600) {
  const start = Date.now();
  while (!fn()) {
    if (Date.now() - start > timeout) throw new Error("FIXTURE_CONDITION_TIMEOUT");
    await new Promise(resolve => setTimeout(resolve, 8));
  }
}
test("transport is disabled by default and makes no connection", async () =>
  withServer("valid", async context => {
    const session = make({ url:context.url });
    assert.throws(() => session.connect(), /EXPERIMENTAL_TRANSPORT_DISABLED/);
    assert.equal(session.publicStatus().phase, "idle");
    assert.equal(context.upgrades, 0);
  }));
test("fixture dialer rejects external and localhost names before any network activity", () => {
  for (const url of ["wss://signal.example.org/socket.io/?transport=websocket&EIO=4",
    "ws://localhost:3001/socket.io/?transport=websocket&EIO=4",
    "ws://" + loopback + ":3001/evil",
    "ws://" + loopback + ":3001/socket.io/?transport=websocket&EIO=3",
    "ws://" + loopback + ":3001/socket.io/?transport=websocket&EIO=4&key=x"]) {
    assert.throws(() => make({url}), /FIXTURE_LOOPBACK_ONLY/);
  }
});
test("real loopback WebSocket frames: 0 -> 40 -> 4211 -> 4311, push inert, 2 -> 3", () =>
  withServer("valid", async ({url, received}) => {
    const session = make({url});
    try {
      const ready = await session.connect({fixtureOnly:true});
      assert.equal(ready.phase, "observing");
      assert.equal(ready.roomInfoObserved, true);
      assert.equal(ready.authenticated, false);
      await until(() => session.publicStatus().untrustedPushes === 1 &&
        received.includes("3"));
      assert.deepEqual(received.slice(0, 3), [
        "40", '4211["room_info"]', "3",
      ]);
      assert.equal(session.publicStatus().packetSent, false);
      assert.equal(session.publicStatus().wakePermitted, false);
      assert.equal(JSON.stringify(session.publicStatus()).includes(token1), false);
    } finally { session.close(); }
  }));
test("a premature cloud wake frame is discarded, never upgraded to authentication", () =>
  withServer("premature", async ({url}) => {
    const session = make({url});
    try {
      await session.connect({fixtureOnly:true});
      await until(() => session.publicStatus().untrustedPushes === 1);
      assert.ok(session.publicStatus().rejectedFrames >= 1);
      assert.equal(session.publicStatus().authenticated, false);
      assert.equal(session.publicStatus().packetSent, false);
    } finally { session.close(); }
  }));
test("actual WebSocket CONNECT_ERROR fails immediately without a room ticket or WOL", () =>
  withServer("reject-namespace", async ({url}) => {
    const session = make({url, connectTimeoutMs:1000});
    await assert.rejects(session.connect({fixtureOnly:true}), /ROOM_AUTH_REJECTED/);
    assert.equal(session.publicStatus().phase, "closed");
    assert.equal(session.publicStatus().wakePermitted, false);
    assert.equal(session.publicStatus().untrustedPushes, 0);
  }));
test("wrong room_info acknowledgement fails to establish observing room", () =>
  withServer("wrong-ack", async ({url}) => {
    const session = make({url, connectTimeoutMs:120});
    await assert.rejects(session.connect({fixtureOnly:true}), /ROOM_TRANSCRIPT_TIMEOUT/);
    assert.equal(session.publicStatus().phase, "closed");
    assert.equal(session.publicStatus().wakePermitted, false);
  }));
test("malformed room_info acknowledgement permanently closes the fixture session", () =>
  withServer("malformed-ack", async ({url}) => {
    const session = make({url});
    await assert.rejects(session.connect({fixtureOnly:true}), /INVALID_ENGINE_TRANSCRIPT/);
    assert.equal(session.publicStatus().phase, "closed");
    assert.equal(session.publicStatus().authenticated, false);
  }));
test("disconnect invalidates observed room without generating a wake packet", () =>
  withServer("disconnect", async ({url}) => {
    const session = make({url});
    try {
      await session.connect({fixtureOnly:true}).catch(error => {
        assert.match(error.message, /ROOM_DISCONNECTED/);
      });
      await until(() => session.publicStatus().phase === "closed");
      assert.equal(session.publicStatus().packetSent, false);
      assert.equal(session.publicStatus().roomInfoObserved, false);
    } finally { session.close(); }
  }));
test("an expired token candidate is rejected before any socket is created", async () =>
  withServer("valid", async context => {
    const { url } = context;
    let now = 1000000;
    const candidate = createCandidate(token1, () => now);
    now += 61000;
    const session = new FixtureEngineIOV4Session({
      roomCandidate: candidate, fixtureUrl:url, socketFactory:factory,
      clock:()=>now,
    });
    assert.throws(() => session.connect({fixtureOnly:true}), /ROOM_CREDENTIAL_EXPIRED/);
    assert.equal(context.upgrades, 0);
  }));
test("expiry during a connected fixture invalidates all room observations", () =>
  withServer("valid", async ({url}) => {
    let now = 1000000;
    const session = make({url, clock:()=>now});
    try {
      await session.connect({fixtureOnly:true});
      now += 61000;
      assert.equal(session.publicStatus().phase, "closed");
      assert.equal(session.publicStatus().roomInfoObserved, false);
      assert.equal(session.publicStatus().wakePermitted, false);
    } finally { session.close(); }
  }));
test("a disconnected ticket is single-use even if rewrapped as a new room candidate", () =>
  withServer("valid", async ({url}) => {
    const session = make({url});
    await session.connect({fixtureOnly:true});
    session.close();
    assert.throws(() => session.reconnect({
      freshRoomCandidate:createCandidate(token1),fixtureOnly:true,
    }), /ROOM_TICKET_REUSE_FORBIDDEN/);
    assert.equal(session.publicStatus().phase, "closed");
  }));
test("only a newly issued candidate with a new token may restart fixture connection", () =>
  withServer("valid", async context => {
    const { url } = context;
    const session = make({url});
    await session.connect({fixtureOnly:true});
    session.close();
    const after = await session.reconnect({
      freshRoomCandidate:createCandidate(token2),fixtureOnly:true,
    });
    assert.equal(after.phase, "observing");
    assert.equal(after.reconnectsUsingFreshCredentials, 1);
    assert.equal(after.authenticated, false);
    assert.equal(after.wakePermitted, false);
    assert.equal(context.upgrades, 2);
    session.close();
  }));
test("injected socket failure is closed and never contains sensitive bearer in error", async () =>
  withServer("valid", async ({url}) => {
    const session = make({url, scenarioFactory:() => { throw new Error(token1); }});
    await assert.rejects(session.connect({fixtureOnly:true}), e => {
      assert.equal(e.message, "FIXTURE_SOCKET_SETUP_FAILED");
      assert.equal(e.message.includes(token1), false);
      return true;
    });
    assert.equal(session.publicStatus().phase, "closed");
  }));
test("unapproved fake registration metadata never grants WOL, even after room_info", () =>
  withServer("valid", async ({url}) => {
    const session = make({url});
    try {
      const status = await session.connect({fixtureOnly:true});
      assert.equal(status.registrationVerified, false);
      assert.equal(status.wakePermitted, false);
      assert.equal(status.authenticated, false);
    } finally { session.close(); }
  }));

test("missing Engine.IO ping closes a live fixture after its bounded heartbeat window", () =>
  withServer("valid", async ({url}) => {
    let now = 1000000;
    const session = make({url, clock:()=>now});
    try {
      await session.connect({fixtureOnly:true});
      assert.equal(session.publicStatus().phase, "observing");
      now += 5001;
      assert.equal(session.publicStatus().phase, "closed");
      assert.equal(session.publicStatus().roomInfoObserved, false);
      assert.equal(session.publicStatus().wakePermitted, false);
    } finally { session.close(); }
  }));
test("reconnection requires its own explicit opt-in even with a new bearer", () =>
  withServer("valid", async context => {
    const session = make({url:context.url});
    await session.connect({fixtureOnly:true});
    session.close();
    assert.throws(() => session.reconnect({
      freshRoomCandidate:createCandidate(token2),
    }), /EXPERIMENTAL_TRANSPORT_DISABLED/);
    assert.equal(context.upgrades, 1);
    assert.equal(session.publicStatus().phase, "closed");
  }));
test("expired replacement bearer cannot silently reconnect after disconnect", () =>
  withServer("valid", async context => {
    let now = 1000000;
    const staleReplacement = createCandidate(token2, () => now);
    const session = make({url:context.url, clock:()=>now});
    await session.connect({fixtureOnly:true});
    session.close();
    now += 61000;
    assert.throws(() => session.reconnect({
      freshRoomCandidate:staleReplacement, fixtureOnly:true,
    }), /ROOM_CREDENTIAL_EXPIRED/);
    assert.equal(context.upgrades, 1);
    assert.equal(session.publicStatus().phase, "closed");
  }));
