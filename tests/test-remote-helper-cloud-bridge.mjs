import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { registrationBody, registrationResult, validateWakePush }
  from "../experiments/remote-helper/cloud-contract.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sender = path.join(root, "experiments/remote-helper/wol-send.sh");
const fixtures = path.join(root, "tests/fixtures");
const helper = { lanInterface: "br-lan", ip: "198.51.100.1",
  mac: "02:aa:bb:cc:dd:ee", subnetMask: "255.255.255.0" };
const allowed = { mac: "02:10:20:30:40:50", ip: "198.51.100.40" };
const config = { accountId: "fixture-account", helper,
  allowedTargets: [allowed] };
const push = () => "42" + JSON.stringify(["bmsg_push", {
  type: "wake_on_lan", data: {
    target_device: { mac: allowed.mac, ip: allowed.ip, subnet_mask: helper.subnetMask }
  }
}]);
const room = () => ({ accountId: "fixture-account", authenticated: true,
  roomConnected: true, registrationAccepted: true, wolEnabled: true });

function fakeSender(plan) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "uu-wol-fixture-"));
  try {
    for (const file of ["remote-helper-ip.sh", "remote-helper-socat.sh"]) {
      const name = file.endsWith("ip.sh") ? "ip" : "socat";
      const dest = path.join(temp, name);
      fs.copyFileSync(path.join(fixtures, file), dest);
      fs.chmodSync(dest, 0o700);
    }
    const env = { ...process.env, PATH: temp + ":" + process.env.PATH,
      UU_TEST_IP_SCENARIO: "router", UU_TEST_EXPECT_MAC_HEX: "021020304050",
      UU_WOL_SEND_CONFIRM: "SEND_ONE_WOL_PACKET" };
    return spawnSync("sh", [sender, "--send", plan.targetIP,
      plan.targetMAC, plan.lanInterface], { encoding: "utf8", timeout: 5000, env });
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

test("fixture registration -> authenticated wake -> one mocked 102-byte datagram", () => {
  assert.deepEqual(registrationBody(helper), {
    mac: "02:AA:BB:CC:DD:EE",
    ip: "198.51.100.1", inner_ip: "198.51.100.1",
    subnet_mask: "255.255.255.0"
  });
  assert.equal(registrationResult(200, { code: 0, data: { turn_on_wol: true } }).accepted, true);
  const plan = validateWakePush(push(), room(), config);
  assert.equal(plan.kind, "authorized_wake_plan");
  assert.equal(plan.packetSent, false);
  const result = fakeSender(plan);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /MOCK_SOCAT_PACKET_102_BYTES_VALIDATED/);
  assert.match(result.stdout, /REMOTE_WOL_SOCKET_WRITE_PASS/);
});

test("unregistered account never yields a send plan", () => {
  assert.throws(() => validateWakePush(push(),
    { ...room(), registrationAccepted: false }, config), /AUTHENTICATED_ROOM_REQUIRED/);
});
test("wrong account never yields a send plan", () => {
  assert.throws(() => validateWakePush(push(),
    { ...room(), accountId: "unknown-account" }, config), /ACCOUNT_MISMATCH/);
});
test("disabled helper never yields a send plan", () => {
  assert.throws(() => validateWakePush(push(),
    { ...room(), wolEnabled: false }, config), /AUTHENTICATED_ROOM_REQUIRED/);
});
test("rejected server registration cannot be promoted to an authenticated wake session", () => {
  assert.throws(() => registrationResult(422, { code: 1001 }), /REGISTRATION_NOT_ACCEPTED/);
});
