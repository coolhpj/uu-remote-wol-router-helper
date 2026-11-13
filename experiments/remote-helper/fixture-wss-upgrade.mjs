// Fixture-only WSS HTTP Upgrade proof over a real TLS socket on loopback.
// This must never dial a NetEase server or authorize WOL. The CA and private
// bearer come from synthetic test inputs, not the machine's trust store.
// Successful TLS + Upgrade is NOT proof of the vendor's room/account binding.
import tls from "node:tls";
import { randomBytes, createHash } from "node:crypto";
import { inspectSignalingServer } from "./vendor-room-contract.mjs";

const LOOPBACK = [127, 0, 0, 1].join(".");
const MAX_HEADERS = 8192;
const PATH = "/socket.io/?transport=websocket&EIO=4";
function fail(code) { throw new Error(code); }
function check(ok, code) { if (!ok) fail(code); }
function validateResponse(raw, expected) {
  const lines = raw.split("\r\n");
  check(lines[0] === "HTTP/1.1 101 Switching Protocols", "FIXTURE_WSS_UPGRADE_REJECTED");
  const headers = new Map();
  for (const line of lines.slice(1)) {
    if (!line) continue;
    const i = line.indexOf(":");
    check(i > 0, "FIXTURE_WSS_RESPONSE_INVALID");
    const name = line.slice(0, i).toLowerCase();
    check(!headers.has(name), "FIXTURE_WSS_RESPONSE_DUPLICATE_HEADER");
    headers.set(name, line.slice(i + 1).trim());
  }
  check(headers.get("upgrade")?.toLowerCase() === "websocket" &&
    headers.get("connection")?.toLowerCase().split(/\s*,\s*/).includes("upgrade") &&
    headers.get("sec-websocket-accept") === expected,
    "FIXTURE_WSS_ACCEPT_REJECTED");
}

export function fixtureWssUpgrade({
  roomCandidate, approvedHost, trustedCa, port,
  fixtureOnly = false, timeoutMs = 2000,
} = {}) {
  check(fixtureOnly === true, "FIXTURE_WSS_DISABLED");
  check(roomCandidate && typeof roomCandidate.prepareUpgradeRequest === "function",
    "FIXTURE_ROOM_REQUIRED");
  // Pin the proposed public WSS host before even creating a network socket.
  const approved = inspectSignalingServer("wss://" + approvedHost, approvedHost);
  check(Number.isInteger(port) && port > 0 && port <= 65535,
    "FIXTURE_PORT_INVALID");
  check(typeof trustedCa === "string" && trustedCa.includes("BEGIN CERTIFICATE") &&
    trustedCa.length < 10000, "FIXTURE_CA_REQUIRED");
  check(Number.isInteger(timeoutMs) && timeoutMs >= 100 &&
    timeoutMs <= 5000, "FIXTURE_TIMEOUT_INVALID");
  let plan;
  try { plan = roomCandidate.prepareUpgradeRequest({ enabled: true }); }
  catch { fail("FIXTURE_ROOM_UNAVAILABLE"); }
  check(plan?.url === approved.socketIOPath && plan?.authenticated === false &&
    plan?.maySendWol === false && plan?.sensitive === true &&
    typeof plan?.headers?.["X-NRD-AUTH"] === "string" &&
    // Explicitly test-only bearer. Never accidentally send an owner token.
    /^synthetic-[A-Za-z0-9-]{16,120}$/.test(plan.headers["X-NRD-AUTH"]),
    "FIXTURE_ROOM_PLAN_REJECTED");
  const bearer = plan.headers["X-NRD-AUTH"];
  const key = randomBytes(16).toString("base64");
  const accept = createHash("sha1").update(
    key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
  return new Promise((resolve, reject) => {
    let settled = false;
    let received = "";
    let socket;
    const terminate = (code, ok = false) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      socket?.destroy();
      if (!ok) { reject(new Error(code)); return; }
      resolve(Object.freeze({
        transport: "synthetic-tls-loopback",
        secureTls: true, hostnameChecked: true, upgradeAccepted: true,
        customHeaderSentToFixture: true, externalEndpointDialed: false,
        authenticated: false, registrationVerified: false,
        wakePermitted: false, packetSent: false, credentialsIncluded: false,
      }));
    };
    const timeout = setTimeout(() => terminate("FIXTURE_WSS_TIMEOUT"), timeoutMs);
    try {
      socket = tls.connect({
        host: LOOPBACK, port, servername: approvedHost,
        ca: trustedCa, rejectUnauthorized: true,
        minVersion: "TLSv1.2", ALPNProtocols: ["http/1.1"],
      });
    } catch { terminate("FIXTURE_TLS_SETUP_FAILED"); return; }
    socket.on("secureConnect", () => {
      if (!socket.authorized || socket.alpnProtocol !== "http/1.1") {
        terminate("FIXTURE_TLS_IDENTITY_REJECTED"); return;
      }
      // Certificate verification has completed before any bearer is sent.
      let active;
      try { active = roomCandidate.prepareUpgradeRequest({ enabled: true }); }
      catch { terminate("FIXTURE_ROOM_UNAVAILABLE"); return; }
      if (active.url !== approved.socketIOPath ||
          active.headers?.["X-NRD-AUTH"] !== bearer) {
        terminate("FIXTURE_ROOM_CHANGED"); return;
      }
      socket.write([
        "GET " + PATH + " HTTP/1.1",
        "Host: " + approvedHost,
        "Upgrade: websocket",
        "Connection: Upgrade",
        "Sec-WebSocket-Version: 13",
        "Sec-WebSocket-Key: " + key,
        "X-NRD-AUTH: " + bearer, "", "",
      ].join("\r\n"));
    });
    socket.on("data", chunk => {
      received += chunk.toString("latin1");
      if (received.length > MAX_HEADERS) {
        terminate("FIXTURE_WSS_RESPONSE_TOO_LARGE"); return;
      }
      const end = received.indexOf("\r\n\r\n");
      if (end < 0) return;
      try { validateResponse(received.slice(0, end), accept); }
      catch { terminate("FIXTURE_WSS_HANDSHAKE_REJECTED"); return; }
      terminate(null, true);
    });
    socket.on("error", () => terminate("FIXTURE_TLS_OR_TRANSPORT_REJECTED"));
    socket.on("close", () => terminate("FIXTURE_WSS_CLOSED"));
  });
}
