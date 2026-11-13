import test from "node:test";
import assert from "node:assert/strict";
import { EngineIOV4FixtureTranscript } from "../experiments/remote-helper/engineio-v4-transcript.mjs";
import { validateWakePush } from "../experiments/remote-helper/cloud-contract.mjs";

// Fixture-only wire frames. These are NOT captured from a NetEase session.
const open = (pingInterval = 25000, pingTimeout = 20000) =>
  '0' + JSON.stringify({ sid: "fixture-session", pingInterval, pingTimeout });
const fixtureMAC = ["02", "aa", "bb", "cc", "dd", "ee"].join(":");
const targetMAC = ["02", "10", "20", "30", "40", "50"].join(":");
const wake = '42' + JSON.stringify(["bmsg_push", {
  type: "wake_on_lan", data: { target_device: {
    mac: targetMAC, ip: "198.51.100.40", subnet_mask: "255.255.255.0",
  } },
}]);
function observeRoom(t) {
  assert.deepEqual(t.receive(open()), { kind: "engine_open", reply: "40", trusted: false });
  assert.deepEqual(t.receive('40{"sid":"fixture-namespace"}'), {
    kind: "socket_connected", reply: '4211["room_info"]', trusted: false,
  });
  assert.deepEqual(t.receive('4311[{"status":"fixture-ok"}]'), {
    kind: "room_info_observed", reply: null, trusted: false,
  });
}
test("Engine.IO open must precede Socket.IO connect, no credential in public status", () => {
  const t = new EngineIOV4FixtureTranscript();
  assert.throws(() => t.receive("40"), /ENGINE_OPEN_REQUIRED/);
  assert.equal(t.publicStatus().authenticated, false);
  assert.equal(t.publicStatus().phase, "closed");
});
test("realistic EIO4 open -> 40 connect -> numbered room_info ack stays untrusted", () => {
  const t = new EngineIOV4FixtureTranscript();
  observeRoom(t);
  assert.deepEqual(t.publicStatus(), {
    phase: "observing_untrusted_room", roomAckObserved: true,
    untrustedPushes: 0, rejected: 0,
    authenticated: false, credentialsIncluded: false,
  });
});
test("Socket.IO room event before room_info ack is ignored", () => {
  const t = new EngineIOV4FixtureTranscript();
  t.receive(open());
  t.receive("40{}");
  const response = t.receive(wake);
  assert.equal(response.kind, "ignored");
  assert.equal(t.publicStatus().untrustedPushes, 0);
  assert.equal(t.publicStatus().roomAckObserved, false);
});
test("wrong Socket.IO ack request identifier cannot satisfy room info", () => {
  const t = new EngineIOV4FixtureTranscript();
  t.receive(open()); t.receive("40");
  assert.equal(t.receive('4312[{"status":"ok"}]').kind, "ignored");
  assert.equal(t.receive('43[{"status":"ok"}]').kind, "ignored");
  assert.equal(t.publicStatus().roomAckObserved, false);
});
test("untrusted bmsg_push frame remains inert even with a valid wire envelope", () => {
  const t = new EngineIOV4FixtureTranscript();
  observeRoom(t);
  const response = t.receive(wake);
  assert.equal(response.kind, "untrusted_bmsg_push");
  assert.equal(response.trusted, false);
  assert.equal(response.packetSent, false);
  const config = {
    accountId: "fixture-account",
    helper: { lanInterface: "br-lan", ip: "198.51.100.1",
      subnetMask: "255.255.255.0", mac: fixtureMAC },
    allowedTargets: [{ mac: targetMAC, ip: "198.51.100.40" }],
  };
  assert.throws(() => validateWakePush(response.frame, {
    authenticated: t.publicStatus().authenticated,
    roomConnected: true, registrationAccepted: true, wolEnabled: true,
    accountId: config.accountId,
  }, config), /AUTHENTICATED_ROOM_REQUIRED/);
  // An independent authenticated transport (not this parser) would need to
  // supply verified account/room/registration evidence; no packet is sent here.
  const syntheticAuthorized = validateWakePush(response.frame, {
    authenticated: true, roomConnected: true, registrationAccepted: true,
    wolEnabled: true, accountId: config.accountId,
  }, config);
  assert.equal(syntheticAuthorized.kind, "authorized_wake_plan");
  assert.equal(syntheticAuthorized.packetSent, false);
});
test("server ping 2 asks for pong 3 and resets bounded heartbeat window", () => {
  let now = 1000;
  const t = new EngineIOV4FixtureTranscript({ clock: () => now });
  t.receive(open(1000, 1000));
  now += 4500;
  assert.deepEqual(t.receive("2"), {
    kind: "engine_ping", reply: "3", trusted: false,
  });
  now += 4500;
  assert.equal(t.publicStatus().phase, "await_socket_connect");
  now += 501;
  assert.equal(t.publicStatus().phase, "closed");
  assert.throws(() => t.receive("40"), /ENGINE_SESSION_CLOSED/);
});
test("oversized heartbeat metadata is rejected before parsing", () => {
  const t = new EngineIOV4FixtureTranscript();
  assert.throws(() => t.receive("0" + "x".repeat(16400)), /INVALID_ENGINE_PACKET/);
  assert.equal(t.publicStatus().phase, "closed");
});
test("invalid ping interval, timeout or session ID cannot open engine", () => {
  for (const bad of [
    '0{}', '0{"sid":5,"pingInterval":1,"pingTimeout":1}',
    '0{"sid":"x","pingInterval":0,"pingTimeout":2}',
    '0{"sid":"x","pingInterval":1,"pingTimeout":-2}',
    '0{"sid":"x","pingInterval":"25000","pingTimeout":20000}',
    '0{"sid":"x","pingInterval":2}',
    '0{"sid":', '0{"sid":"x","pingInterval":null,"pingTimeout":20000}',
  ]) {
    assert.throws(() => new EngineIOV4FixtureTranscript().receive(bad),
      /INVALID_ENGINE_OPEN/);
  }
});
test("malformed connect payload is rejected and cannot infer authentication", () => {
  const t = new EngineIOV4FixtureTranscript();
  t.receive(open());
  assert.throws(() => t.receive('40{"sid":42}'), /INVALID_SOCKET_CONNECT/);
  assert.equal(t.publicStatus().authenticated, false);
});
test("malformed room ack does not unlock the wake event gate", () => {
  const t = new EngineIOV4FixtureTranscript();
  t.receive(open()); t.receive("40");
  assert.equal(t.receive("4311{}").kind, "ignored");
  assert.throws(() => t.receive("4311[bad]"), /INVALID_ROOM_INFO_ACK/);
  assert.equal(t.publicStatus().roomAckObserved, false);
});
test("explicit Socket.IO CONNECT_ERROR immediately rejects namespace and closes", () => {
  const t = new EngineIOV4FixtureTranscript();
  t.receive(open());
  assert.throws(() => t.receive('44{"message":"not authorized"}'),
    /SOCKET_NAMESPACE_DENIED/);
  assert.equal(t.publicStatus().phase, "closed");
  assert.equal(t.publicStatus().authenticated, false);
});
test("Socket.IO namespace disconnect revokes previously observed room", () => {
  const t = new EngineIOV4FixtureTranscript();
  observeRoom(t);
  assert.equal(t.receive("41").kind, "disconnected");
  assert.equal(t.publicStatus().roomAckObserved, false);
  assert.throws(() => t.receive(wake), /ENGINE_SESSION_CLOSED/);
});
test("Engine.IO close invalidates even a pre-room session", () => {
  const t = new EngineIOV4FixtureTranscript();
  t.receive(open()); t.receive("1");
  assert.equal(t.publicStatus().phase, "closed");
  assert.throws(() => t.receive(open()), /ENGINE_SESSION_CLOSED/);
});
test("non-wake Socket.IO events and unrecognized protocol frames are not dispatched", () => {
  const t = new EngineIOV4FixtureTranscript();
  observeRoom(t);
  assert.equal(t.receive('42["room_info",{}]').kind, "ignored");
  assert.equal(t.receive('43[{"status":"ok"}]').kind, "ignored");
  assert.equal(t.publicStatus().untrustedPushes, 0);
});
test("malformed or non-object Socket.IO payloads fail closed", () => {
  const t = new EngineIOV4FixtureTranscript();
  observeRoom(t);
  assert.equal(t.receive("42{}").kind, "ignored");
  for (const bad of ['42[4,{}]', '42["bmsg_push",null]',
    '42["bmsg_push",[]]', '42[', '42["bmsg_push",{},"unexpected"]']) {
    const instance = new EngineIOV4FixtureTranscript();
    observeRoom(instance);
    assert.throws(() => instance.receive(bad), /INVALID_SOCKET_EVENT/);
    assert.equal(instance.publicStatus().phase, "closed");
    assert.equal(instance.publicStatus().untrustedPushes, 0);
  }
  assert.equal(t.publicStatus().untrustedPushes, 0);
});
test("min and max Engine.IO heartbeat windows are bounded", () => {
  let now = 0;
  const low = new EngineIOV4FixtureTranscript({ clock: () => now });
  low.receive(open(1, 1)); now = 4999;
  assert.equal(low.publicStatus().phase, "await_socket_connect");
  now = 5000;
  assert.equal(low.publicStatus().phase, "closed");
  now = 0;
  const high = new EngineIOV4FixtureTranscript({ clock: () => now });
  high.receive(open(300000, 300000)); now = 299999;
  assert.equal(high.publicStatus().phase, "await_socket_connect");
  now = 300000;
  assert.equal(high.publicStatus().phase, "closed");
});
