// Local-only fake Socket.IO-like signaling room; NOT a vendor client.
// No real UU credentials or remote hosts are ever contacted here.
import { validateWakePush } from "./cloud-contract.mjs";
const LOOPBACK_HOST = [127, 0, 0, 1].join(".");
function fail(code) { throw new Error(code); }
function check(v, code) { if (!v) fail(code); }
export class FixtureRoomClient {
  #url; #config; #room; #registration; #clock; #onPlan;
  #socket = null; #status = "idle"; #rejected = 0; #accepted = 0;
  constructor({ url, room, config, registrationEvidence, clock = Date.now, onPlan = () => {} }) {
    let parsed;
    try { parsed = new URL(url); } catch { fail("INVALID_ROOM_URL"); }
    check(parsed.protocol === "ws:" && parsed.hostname === LOOPBACK_HOST &&
      /^[0-9]{1,5}$/.test(parsed.port) && parsed.pathname === "/fixture/room" &&
      !parsed.username && !parsed.password && !parsed.search && !parsed.hash,
      "FIXTURE_ROOM_LOOPBACK_ONLY");
    check(room && typeof room === "object" &&
      typeof room.roomId === "string" && /^fixture-[A-Za-z0-9-]{4,80}$/.test(room.roomId) &&
      typeof room.roomToken === "string" && room.roomToken.length >= 8 &&
      typeof room.accountId === "string" && room.accountId === config?.accountId &&
      Number.isSafeInteger(room.expiresAt) && room.expiresAt > clock(),
      "INVALID_ROOM_CONTRACT");
    check(registrationEvidence?.accepted === true && registrationEvidence?.enabled === true &&
      registrationEvidence?.cloudPushVerified === false, "REGISTRATION_GATE_REQUIRED");
    check(typeof onPlan === "function" && typeof clock === "function", "INVALID_ROOM_CALLBACK");
    this.#url = parsed.href; this.#room = { ...room }; this.#config = config;
    this.#registration = registrationEvidence;
    this.#clock = clock; this.#onPlan = onPlan;
  }
  #expired() {
    if (this.#clock() >= this.#room.expiresAt) {
      this.close();
      return true;
    }
    return false;
  }
  publicStatus() {
    this.#expired();
    return Object.freeze({ status: this.#status, rejectedMessages: this.#rejected,
      acceptedPlans: this.#accepted, containsCredentials: false });
  }
  connect() {
    check(this.#status === "idle", "ROOM_ALREADY_USED");
    if (this.#expired()) return Promise.reject(new Error("ROOM_EXPIRED"));
    check(typeof WebSocket === "function", "WEBSOCKET_UNAVAILABLE");
    this.#status = "connecting";
    const socket = new WebSocket(this.#url);
    this.#socket = socket;
    return new Promise((resolve, reject) => {
      let settled = false;
      const settle = (error = null) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        if (error) reject(error); else resolve(this.publicStatus());
      };
      const timeout = setTimeout(() => {
        this.close();
        settle(new Error("ROOM_AUTH_TIMEOUT"));
      }, 2000);
      socket.addEventListener("open", () => {
        if (this.#status !== "connecting") return;
        socket.send(JSON.stringify({ kind: "auth", roomId: this.#room.roomId,
          roomToken: this.#room.roomToken, accountId: this.#room.accountId }));
      });
      socket.addEventListener("message", event => {
        if (this.#expired() || this.#status === "closed") return;
        const data = event.data;
        if (typeof data !== "string" || data.length > 16 * 1024) {
          this.#rejected++;
          return;
        }
        if (this.#status === "connecting") {
          let ack;
          try { ack = JSON.parse(data); } catch { this.#rejected++; return; }
          if (ack?.kind === "room_ready" && ack.roomId === this.#room.roomId &&
              ack.accountId === this.#room.accountId) {
            this.#status = "ready"; settle();
          } else if (ack?.kind === "auth_rejected") {
            this.close();
            settle(new Error("ROOM_AUTH_REJECTED"));
          } else this.#rejected++;
          return;
        }
        if (this.#status !== "ready") return;
        try {
          const state = {
            authenticated: true, roomConnected: true,
            registrationAccepted: this.#registration.accepted,
            wolEnabled: this.#registration.enabled,
            accountId: this.#room.accountId, expired: false,
          };
          const planned = validateWakePush(data, state, this.#config);
          if (planned.kind === "authorized_wake_plan") {
            this.#onPlan(planned);
            this.#accepted++;
          } else this.#rejected++;
        } catch { this.#rejected++; }
      });
      socket.addEventListener("close", () => {
        this.#status = "closed";
        settle(new Error("ROOM_DISCONNECTED"));
      });
      socket.addEventListener("error", () => {
        this.close();
        settle(new Error("ROOM_SOCKET_ERROR"));
      });
    });
  }
  close() {
    this.#status = "closed";
    if (this.#socket && this.#socket.readyState < 2) this.#socket.close();
  }
}
