// Test-only Engine.IO v4 / Socket.IO WebSocket session. Not a vendor client.
// The injected socket factory may ONLY connect to loopback; the WSS upgrade
// plan and X-NRD-AUTH header are inspected but NEVER sent to a vendor host.
// Successful room_info is an untrusted observation, not authorization or WoL.
import { createHash } from "node:crypto";
import { EngineIOV4FixtureTranscript } from "./engineio-v4-transcript.mjs";

const loopback = [127, 0, 0, 1].join(".");
function fail(message) { throw new Error(message); }
function check(ok, message) { if (!ok) fail(message); }
function validateLoopback(url) {
  let u;
  try { u = new URL(url); } catch { fail("FIXTURE_SOCKET_URL_INVALID"); }
  check(u.protocol === "ws:" && u.hostname === loopback &&
    /^[1-9][0-9]{0,4}$/.test(u.port) && +u.port <= 65535 &&
    u.pathname === "/socket.io/" &&
    u.searchParams.size === 2 && u.searchParams.get("EIO") === "4" &&
    u.searchParams.get("transport") === "websocket" &&
    !u.username && !u.password && !u.hash,
    "FIXTURE_LOOPBACK_ONLY");
  return u.href;
}
function digest(bearer) { return createHash("sha256").update(bearer).digest("hex"); }

export class FixtureEngineIOV4Session {
  #candidate; #factory; #url; #clock; #connectMs; #checkMs;
  #socket = null; #transcript = null;
  #state = "idle"; #timer = null; #watch = null;
  #lastBearerDigest = null; #restarts = 0; #untrusted = 0; #rejected = 0;
  #active = null;

  constructor({ roomCandidate, fixtureUrl, socketFactory,
    clock = Date.now, connectTimeoutMs = 1800, checkIntervalMs = 50 } = {}) {
    check(roomCandidate && typeof roomCandidate.prepareUpgradeRequest === "function",
      "ROOM_CANDIDATE_REQUIRED");
    check(typeof socketFactory === "function" && typeof clock === "function",
      "INJECTED_FIXTURE_SOCKET_REQUIRED");
    check(Number.isInteger(connectTimeoutMs) && connectTimeoutMs >= 50 &&
      connectTimeoutMs <= 5000 && Number.isInteger(checkIntervalMs) &&
      checkIntervalMs >= 10 && checkIntervalMs <= 500, "INVALID_FIXTURE_TIMEOUT");
    this.#candidate = roomCandidate;
    this.#url = validateLoopback(fixtureUrl);
    this.#factory = socketFactory;
    this.#clock = clock;
    this.#connectMs = connectTimeoutMs;
    this.#checkMs = checkIntervalMs;
  }

  #expire() {
    if (this.#state !== "connecting" && this.#state !== "observing") return;
    try { this.#candidate.prepareUpgradeRequest({ enabled: true }); }
    catch { this.#end("ROOM_CREDENTIAL_EXPIRED"); return; }
    if (this.#transcript?.publicStatus().phase === "closed")
      this.#end("ENGINE_HEARTBEAT_EXPIRED");
  }

  publicStatus() {
    this.#expire();
    return Object.freeze({
      phase: this.#state,
      roomInfoObserved: this.#state === "observing",
      authenticated: false, registrationVerified: false, wakePermitted: false,
      packetSent: false, credentialsIncluded: false,
      untrustedPushes: this.#untrusted, rejectedFrames: this.#rejected,
      reconnectsUsingFreshCredentials: this.#restarts,
    });
  }

  #end(reason = "ROOM_DISCONNECTED") {
    this.#state = "closed";
    clearTimeout(this.#timer); clearInterval(this.#watch);
    this.#timer = null; this.#watch = null;
    this.#transcript = null;
    const socket = this.#socket;
    this.#socket = null;
    if (socket && socket.readyState < 2) {
      try { socket.close(); } catch { /* cleanup best effort */ }
    }
    if (this.#active) {
      const pending = this.#active;
      this.#active = null;
      pending.reject(new Error(reason));
    }
  }

  close() { this.#end("ROOM_CLOSED"); }

  connect({ fixtureOnly = false } = {}) {
    check(fixtureOnly === true, "EXPERIMENTAL_TRANSPORT_DISABLED");
    check(this.#state === "idle", "SESSION_ALREADY_STARTED");
    let plan;
    try { plan = this.#candidate.prepareUpgradeRequest({ enabled: true }); }
    catch { fail("ROOM_CREDENTIAL_EXPIRED"); }
    check(plan?.authenticated === false && plan?.maySendWol === false &&
      plan?.sensitive === true && typeof plan.url === "string" &&
      plan.url.startsWith("wss://") &&
      typeof plan.headers?.["X-NRD-AUTH"] === "string",
      "UNSAFE_ROOM_PLAN");
    this.#lastBearerDigest = digest(plan.headers["X-NRD-AUTH"]);
    this.#transcript = new EngineIOV4FixtureTranscript({ clock: this.#clock });
    this.#state = "connecting";
    this.#untrusted = 0; this.#rejected = 0;
    const promise = new Promise((resolve, reject) => {
      this.#active = { resolve, reject };
    });
    let socket;
    try {
      // The approved WSS plan is passed as *metadata only* for inspection.
      // Network dial URL is always separately pinned to local loopback.
      socket = this.#factory(Object.freeze({
        url: this.#url,
        approvedWssUrl: plan.url,
        privateUpgradeHeaders: plan.headers,
        fixtureOnly: true,
        authenticated: false,
      }));
      check(socket && typeof socket.addEventListener === "function" &&
        typeof socket.send === "function" && typeof socket.close === "function",
        "INVALID_FIXTURE_SOCKET");
    } catch {
      this.#end("FIXTURE_SOCKET_SETUP_FAILED");
      return promise;
    }
    this.#socket = socket;
    this.#timer = setTimeout(() => this.#end("ROOM_TRANSCRIPT_TIMEOUT"),
      this.#connectMs);
    this.#watch = setInterval(() => this.#expire(), this.#checkMs);
    this.#watch.unref?.();
    socket.addEventListener("message", event => {
      // An old socket may deliver queued events after an explicit reconnect.
      // Never let it affect the new session or emit a new-room reply.
      if (this.#socket !== socket) return;
      if (this.#state !== "connecting" && this.#state !== "observing") return;
      this.#expire();
      if (this.#state === "closed") return;
      let result;
      try { result = this.#transcript.receive(event.data); }
      catch (error) {
        this.#end(error?.message === "SOCKET_NAMESPACE_DENIED" ?
          "ROOM_AUTH_REJECTED" : "INVALID_ENGINE_TRANSCRIPT");
        return;
      }
      if (result.reply) {
        try { socket.send(result.reply); }
        catch { this.#end("ROOM_SOCKET_SEND_FAILED"); return; }
      }
      if (result.kind === "ignored") this.#rejected++;
      if (result.kind === "untrusted_bmsg_push") this.#untrusted++;
      if (result.kind === "disconnected") {
        this.#end("ROOM_DISCONNECTED");
        return;
      }
      if (result.kind === "room_info_observed" &&
          this.#state === "connecting") {
        this.#state = "observing";
        clearTimeout(this.#timer); this.#timer = null;
        if (this.#active) {
          const pending = this.#active;
          this.#active = null;
          pending.resolve(this.publicStatus());
        }
      }
    });
    socket.addEventListener("close", () => {
      if (this.#socket === socket) this.#end("ROOM_DISCONNECTED");
    });
    socket.addEventListener("error", () => {
      if (this.#socket === socket) this.#end("ROOM_SOCKET_ERROR");
    });
    return promise;
  }

  // Disconnection is terminal for a room ticket. Only a NEW candidate with
  // a different opaque bearer may create another *untrusted fixture session*.
  reconnect({ freshRoomCandidate, fixtureOnly = false } = {}) {
    check(this.#state === "closed", "RECONNECT_REQUIRES_DISCONNECT");
    check(fixtureOnly === true, "EXPERIMENTAL_TRANSPORT_DISABLED");
    check(freshRoomCandidate &&
      typeof freshRoomCandidate.prepareUpgradeRequest === "function" &&
      freshRoomCandidate !== this.#candidate, "FRESH_ROOM_REQUIRED");
    let candidatePlan;
    try { candidatePlan = freshRoomCandidate.prepareUpgradeRequest({ enabled: true }); }
    catch { fail("ROOM_CREDENTIAL_EXPIRED"); }
    check(typeof candidatePlan.headers?.["X-NRD-AUTH"] === "string" &&
      digest(candidatePlan.headers["X-NRD-AUTH"]) !== this.#lastBearerDigest,
      "ROOM_TICKET_REUSE_FORBIDDEN");
    this.#candidate = freshRoomCandidate;
    this.#state = "idle";
    this.#restarts++;
    return this.connect({ fixtureOnly });
  }
}
