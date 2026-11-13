import test from "node:test";
import assert from "node:assert/strict";
import { ipv4, normalizeMAC, subnet, registrationBody, registrationResult, validateWakePush }
  from "../experiments/remote-helper/cloud-contract.mjs";

const helper = { lanInterface: "br-lan", mac: "02:aa:bb:cc:dd:ee",
  ip: "198.51.100.1", subnetMask: "255.255.255.0" };
const known = { ip: "198.51.100.40", mac: "02:10:20:30:40:50" };
const base = () => ({
  accountId: "fixture-account", helper: { ...helper }, allowedTargets: [{ ...known }]
});
const session = () => ({
  accountId: "fixture-account", authenticated: true, roomConnected: true,
  registrationAccepted: true, wolEnabled: true, expired: false
});
const frame = (event = {
  type: "wake_on_lan",
  data: { target_device: { mac: known.mac, ip: known.ip, subnet_mask: helper.subnetMask } }
}) => "42" + JSON.stringify(["bmsg_push", event]);

test("helper registration includes inner_ip and LAN fields", () => {
  const body = registrationBody(helper);
  assert.deepEqual(body, {
    mac: helper.mac.toUpperCase(), ip: helper.ip,
    inner_ip: helper.ip, subnet_mask: helper.subnetMask
  });
  assert.equal(Object.isFrozen(body), true);
});
test("HTTP/business acceptance remains distinct from real remote wake", () => {
  assert.deepEqual(registrationResult(200, { code: 0, data: { turn_on_wol: true } }), {
    accepted: true, enabled: true, cloudPushVerified: false
  });
  assert.deepEqual(registrationResult(200, { code: 0 }), {
    accepted: true, enabled: null, cloudPushVerified: false
  });
  assert.deepEqual(registrationResult(200, { code: 0, data: { turn_on_wol: false } }), {
    accepted: true, enabled: false, cloudPushVerified: false
  });
});
test("authenticated room & local allowlist produce inert wake plan", () => {
  const p = validateWakePush(frame(), session(), base());
  assert.deepEqual(p, {
    kind: "authorized_wake_plan", packetSent: false,
    lanInterface: "br-lan", sourceIP: "198.51.100.1",
    targetIP: known.ip, targetMAC: known.mac,
    directedBroadcast: "198.51.100.255", port: 9,
    verification: "offline-only; cloud transport and host wake unverified"
  });
  assert.equal(Object.isFrozen(p), true);
});
test("unrelated cloud events are ignored", () => {
  assert.deepEqual(validateWakePush(frame({ type: "remote_control", data: {} }), session(), base()),
    { kind: "ignored", packetSent: false });
  assert.deepEqual(validateWakePush("42" + JSON.stringify(["room_info", { type: "wake_on_lan" }]), session(), base()),
    { kind: "ignored", packetSent: false });
});

for (const value of ["", "001.2.3.4", "198.51.100", "198.51.100.999",
  "198.51.100.3:9", "1.2.3.-1", "010.1.2.3"]) {
  test("invalid IPv4 rejected " + JSON.stringify(value), () => {
    assert.throws(() => ipv4(value), /INVALID_IPV4/);
  });
}
for (const value of ["", "01:aa:bb:cc:dd:ee", "00:00:00:00:00:00",
  "ff:ff:ff:ff:ff:ff", "02:aa:bb", "02:aa:bb:cc:dd:gg"]) {
  test("invalid MAC rejected " + JSON.stringify(value), () => {
    assert.throws(() => normalizeMAC(value), /INVALID_MAC|MULTICAST_MAC/);
  });
}
test("subnet prefixes and host boundaries are strictly checked", () => {
  assert.equal(subnet("198.51.100.20", "255.255.254.0").directedBroadcast, "198.51.101.255");
  for (const mask of ["255.0.255.0", "0.0.0.0", "255.255.255.255", "255.255.255.254"])
    assert.throws(() => subnet("198.51.100.10", mask), /UNSUPPORTED_SUBNET_MASK/);
  assert.throws(() => subnet("198.51.100.0", "255.255.255.0"), /INVALID_HELPER_HOST/);
  for (const ip of ["239.1.2.3", "127.0.0.2", "169.254.1.40", "0.2.3.4"])
    assert.throws(() => subnet(ip, "255.255.255.0"), /INVALID_HELPER_HOST/);
});
for (const [status, payload] of [[422, { code: 1001 }], [200, { code: 1001 }],
  [204, { code: 0 }], [200, {}], [200, { code: "0" }], [200, null]]) {
  test("bad HTTP/business code rejected " + status + " " + JSON.stringify(payload), () => {
    assert.throws(() => registrationResult(status, payload), /REGISTRATION_NOT_ACCEPTED/);
  });
}
for (const override of [{ authenticated: false }, { roomConnected: false },
  { registrationAccepted: false }, { wolEnabled: false }, { expired: true }, { accountId: "" },
  { accountId: "other-account" }]) {
  test("unauthorized session rejected " + JSON.stringify(override), () => {
    assert.throws(() => validateWakePush(frame(), { ...session(), ...override }, base()),
      /AUTHENTICATED_ROOM_REQUIRED|ACCOUNT_MISMATCH/);
  });
}
for (const [label, target] of [
  ["wrong MAC", { mac: "02:10:20:30:40:52", ip: known.ip, subnet_mask: helper.subnetMask }],
  ["outside LAN", { mac: known.mac, ip: "203.0.113.88", subnet_mask: helper.subnetMask }],
  ["wrong IP", { mac: known.mac, ip: "198.51.100.41", subnet_mask: helper.subnetMask }],
  ["wrong mask", { mac: known.mac, ip: known.ip, subnet_mask: "255.255.0.0" }],
  ["network IP", { mac: known.mac, ip: "198.51.100.0", subnet_mask: helper.subnetMask }],
  ["broadcast IP", { mac: known.mac, ip: "198.51.100.255", subnet_mask: helper.subnetMask }],
  ["multicast MAC", { mac: "01:10:20:30:40:50", ip: known.ip, subnet_mask: helper.subnetMask }]
]) {
  test("cloud target mismatch rejected: " + label, () => {
    assert.throws(() => validateWakePush(frame({
      type: "wake_on_lan", data: { target_device: target }
    }), session(), base()));
  });
}
test("helper MAC cannot be used as a target MAC", () => {
  const config = base();
  config.allowedTargets = [{ mac: helper.mac, ip: known.ip }];
  const hostile = frame({
    type: "wake_on_lan",
    data: { target_device: { mac: helper.mac, ip: known.ip, subnet_mask: helper.subnetMask } }
  });
  assert.throws(() => validateWakePush(hostile, session(), config), /HELPER_CANNOT_WAKE_ITSELF/);
});
test("empty and duplicate allowlists rejected", () => {
  const cfg = base();
  cfg.allowedTargets = [];
  assert.throws(() => validateWakePush(frame(), session(), cfg), /EMPTY_OR_OVERSIZED_ALLOWLIST/);
  cfg.allowedTargets = [known, { ...known }];
  assert.throws(() => validateWakePush(frame(), session(), cfg), /DUPLICATE_ALLOWLIST_MAC/);
});
test("WAN-like helper and nonlocal authorized targets rejected", () => {
  const cfg = base();
  cfg.helper.lanInterface = "wan";
  assert.throws(() => validateWakePush(frame(), session(), cfg), /INVALID_LAN_INTERFACE/);
  cfg.helper.lanInterface = "br-lan";
  cfg.allowedTargets = [{ ...known, ip: "203.0.113.40" }];
  assert.throws(() => validateWakePush(frame(), session(), cfg), /ALLOWLIST_TARGET_OUTSIDE_LAN/);
});
for (const input of ["not-socketio", "42{", '42["bmsg_push"]',
  '42["bmsg_push",null]', '42["bmsg_push",{"type":"wake_on_lan"}]',
  '42["bmsg_push",{"type":"wake_on_lan","data":{"target_device":null}}]',
  "42" + "x".repeat(20000)]) {
  test("malformed signaling frames rejected " + input.slice(0, 35), () => {
    assert.throws(() => validateWakePush(input, session(), base()));
  });
}
