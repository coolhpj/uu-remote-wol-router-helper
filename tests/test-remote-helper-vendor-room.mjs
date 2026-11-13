import test from "node:test";
import assert from "node:assert/strict";
import { inspectSignalingServer, parseRoomCandidate } from "../experiments/remote-helper/vendor-room-contract.mjs";

const approved = "signal.example.org";
const roomToken = ["synthetic", "opaque", "room", "ticket"].join("-");
const time = 1_000_000;
const good = () => ({
  httpStatus: 200, payload: { code: 0, data: {
    signaling_server: "wss://" + approved,
    token: roomToken,
    signaling_list: ["wss://" + approved],
    ws_connect_timeout_ms: 8000,
  } },
  approvedSignalHost: approved,
  receivedAtMs: time,
  clock: () => time + 100,
});
function wrongRoom(fix) {
  const v = good();
  fix(v);
  return v;
}
function fakeJWT(exp) {
  return [
    Buffer.from('{"alg":"none"}').toString("base64url"),
    Buffer.from(JSON.stringify({ exp })).toString("base64url"),
    "fixture-signature"
  ].join(".");
}

test("fresh 200 business-code-0 room response validates WSS signaling origin, but not authorization", () => {
  const result = parseRoomCandidate(good());
  assert.deepEqual(result.publicStatus(), {
    acceptedResponseShape: true, exactHostMatched: true,
    engineIOVersion: 4, socketIOPathValidated: true,
    authenticated: false, registrationVerified: false,
    wakePermitted: false, tokenExposed: false,
  });
  assert.equal(result.publicStatus(), result.publicStatus());
  assert.equal(result.publicStatus().authenticated, false);
});
test("default OFF prevents accessing token and upgrade metadata", () => {
  const room = parseRoomCandidate(good());
  assert.throws(() => room.prepareUpgradeRequest(), /ROOM_TRANSPORT_DISABLED/);
  assert.throws(() => room.prepareUpgradeRequest({ enabled: "true" }), /ROOM_TRANSPORT_DISABLED/);
});
test("explicitly enabled request contains WSS URL and private header but never WOL permission", () => {
  const room = parseRoomCandidate(good());
  const request = room.prepareUpgradeRequest({ enabled: true });
  assert.equal(request.url, "wss://signal.example.org/socket.io/?transport=websocket&EIO=4");
  assert.deepEqual(request.headers, { "X-NRD-AUTH": roomToken });
  assert.equal(request.authenticated, false);
  assert.equal(request.maySendWol, false);
  assert.equal(request.sensitive, true);
  assert.ok(Object.isFrozen(request.headers));
  assert.ok(Object.isFrozen(request));
});
test("public JSON serialization contains no bearer, hostname, user or handshake headers", () => {
  const room = parseRoomCandidate(good());
  const serialized = JSON.stringify(room);
  for (const forbidden of [roomToken, approved, "X-NRD-AUTH", "signaling_server", '"token":'])
    assert.equal(serialized.includes(forbidden), false);
  assert.equal(JSON.parse(serialized).wakePermitted, false);
});
test("exact-match WSS host and single Socket.IO endpoint", () => {
  assert.deepEqual(inspectSignalingServer("wss://" + approved, approved), {
    origin: "wss://" + approved,
    socketIOPath: "wss://" + approved + "/socket.io/?transport=websocket&EIO=4",
    exactHostMatched: true,
  });
});
test("rejects HTTP, ws, offsite, credentials, query, fragments and unexpected path", () => {
  const hosts = [
    "http://" + approved, "ws://" + approved, "https://" + approved,
    "wss://signal.example.net", "wss://signal.example.org.evil.net",
    "wss://name:pass@" + approved, "wss://" + approved + "/api",
    "wss://" + approved + "?ticket=synthetic",
    "wss://" + approved + "/#anchor", "wss://" + approved + ":8443",
    "wss://127.0.0.1", "wss://localhost",
    "wss://10.10.10.10", "wss://[::1]",
    "wss://" + approved + "/socket.io/",
  ];
  for (const host of hosts) assert.throws(
    () => inspectSignalingServer(host, approved), /SIGNALING_ENDPOINT_REJECTED/,
    "must reject " + host);
});
test("approved hostname rejects wildcards, private/internal domains, IPs and invalid pins", () => {
  for (const v of ["*", "*.example.org", "localhost", "127.0.0.1",
    "signal.local", "signal.example.invalid", "signal.example.test",
    "Signal.Example.Org", "signal..example.org", "example", "", 5]) {
    assert.throws(() => inspectSignalingServer("wss://" + approved, v),
      /INVALID_APPROVED_SIGNAL_HOST|UNTRUSTED_SIGNAL_HOST/);
  }
});
test("HTTP and business status failures never return signaling details", () => {
  for (const [httpStatus,code] of [[201,0], [401,0], [200,401], [200,"0"],[200,null]]) {
    const arg = wrongRoom(v => { v.httpStatus=httpStatus; v.payload.code=code; });
    assert.throws(() => parseRoomCandidate(arg), /ROOM_CREATE_NOT_ACCEPTED/);
  }
  assert.throws(() => parseRoomCandidate(wrongRoom(v=>{v.payload.data=null;})),
    /ROOM_CREATE_NOT_ACCEPTED/);
});
test("malformed and missing room response fields fail closed", () => {
  for (const bad of [undefined, null, 5, {}, [], "", "abc\r\nX-Bad: 1"]) {
    const a = wrongRoom(v=>{v.payload.data.token=bad;});
    assert.throws(() => parseRoomCandidate(a), /INVALID_ROOM_BEARER/);
  }
  assert.throws(() => parseRoomCandidate(wrongRoom(v=>{
    delete v.payload.data.signaling_server;
  })), /INVALID_SIGNALING_SERVER/);
});
test("bearer CRLF injection, long strings and URL-like tickets are rejected", () => {
  for (const v of ["good-token-value\r\nX-Evil: 1", "https://evil.net?token=abcd",
    "x".repeat(4097), "a b c d e f g h", "x".repeat(15)]) {
    assert.throws(() => parseRoomCandidate(wrongRoom(x=>{
      x.payload.data.token = v;
    })), /INVALID_ROOM_BEARER/);
  }
});
test("room candidate has strict 120s maximum freshness even with caller options", () => {
  assert.throws(() => parseRoomCandidate(wrongRoom(x=>{
    x.maxAgeMs = 120001;
  })), /ROOM_CLOCK_INVALID/);
  assert.throws(() => parseRoomCandidate(wrongRoom(x=>{
    x.receivedAtMs = time - 61_000;
  })), /ROOM_CREATE_STALE/);
  assert.throws(() => parseRoomCandidate(wrongRoom(x=>{
    x.receivedAtMs = time + 200;
  })), /ROOM_CREATE_STALE/);
});
test("enabled request expires at the same bound, even after a successful parse", () => {
  let now = time;
  const a = good();
  a.clock=()=>now;
  const room=parseRoomCandidate(a);
  now=time+60000;
  assert.throws(() => room.prepareUpgradeRequest({enabled:true}), /ROOM_CREATE_STALE/);
});
test("unknown or inconsistent fallback signaling servers are never silently selected", () => {
  assert.throws(() => parseRoomCandidate(wrongRoom(v=>{
    v.payload.data.signaling_list=["wss://evil.example.net"];
  })), /UNAPPROVED_SIGNALING_FALLBACK/);
  assert.throws(() => parseRoomCandidate(wrongRoom(v=>{
    v.payload.data.signaling_list=[];
  })), /UNAPPROVED_SIGNALING_FALLBACK/);
  assert.throws(() => parseRoomCandidate(wrongRoom(v=>{
    v.payload.data.signaling_list=Array(9).fill("wss://"+approved);
  })), /UNAPPROVED_SIGNALING_FALLBACK/);
});
test("unsupported websocket handshake timeout is rejected before any network IO", () => {
  for (const timeout of [0,999,20001,"8000",null]) {
    assert.throws(() => parseRoomCandidate(wrongRoom(v=>{
      v.payload.data.ws_connect_timeout_ms=timeout;
    })), /UNSAFE_SIGNAL_TIMEOUT/);
  }
});
test("expired JWT-looking token is rejected only as freshness, never used for positive auth", () => {
  const expired = fakeJWT(200);
  assert.throws(() => parseRoomCandidate(wrongRoom(v=>{
    v.payload.data.token=expired;
  })), /ROOM_BEARER_EXPIRED/);
  const fresh = parseRoomCandidate(wrongRoom(v=>{
    v.payload.data.token=fakeJWT(4000);
  }));
  assert.equal(fresh.publicStatus().authenticated,false);
  assert.equal(fresh.publicStatus().wakePermitted,false);
});
test("malformed JWT-like bearer cannot bypass token expiry inspection", () => {
  for (const token of ["header.invalid.payload", "header.e30.signature",
    "header." + Buffer.from('{"exp":"4000"}').toString("base64url") + ".signature"]) {
    assert.throws(() => parseRoomCandidate(wrongRoom(v => {
      v.payload.data.token = token;
    })), /INVALID_ROOM_BEARER/);
  }
});
test("invalid shape and unsafe clock cannot bypass no-network contract", () => {
  assert.throws(()=>parseRoomCandidate({}),/ROOM_CLOCK_INVALID/);
  assert.throws(()=>parseRoomCandidate(wrongRoom(v=>{v.clock=()=>NaN;})),/ROOM_CREATE_STALE/);
  assert.throws(()=>parseRoomCandidate(wrongRoom(v=>{v.maxAgeMs=0;})),/ROOM_CLOCK_INVALID/);
  assert.throws(()=>parseRoomCandidate(wrongRoom(v=>{v.clock="now";})),/ROOM_CLOCK_INVALID/);
});
