// Engine.IO v4 / Socket.IO fixture transcript decoder (offline only).
// Reproduces public wire-level envelope facts, not a vendor-authenticated client.
// In particular, room_info acknowledgements are observations, NOT proof that
// a user's room token or a cloud wake push has been authenticated.
const MAX_WIRE_BYTES = 16 * 1024;
const MAX_OPEN_FIELD = 128;
const ROOM_INFO_REQUEST_ID = 11;

function reject(code) { throw new Error(code); }
function check(value, code) { if (!value) reject(code); }
function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function parseJSON(text, code) {
  try { return JSON.parse(text); } catch { reject(code); }
}
function readonly(value) { return Object.freeze(value); }

export class EngineIOV4FixtureTranscript {
  #phase = "await_engine_open";
  #deadline = null;
  #pingWindow = null;
  #clock;
  #roomAckObserved = false;
  #pushCount = 0;
  #rejected = 0;
  constructor({ clock = Date.now } = {}) {
    check(typeof clock === "function", "INVALID_CLOCK");
    this.#clock = clock;
  }
  #expired() {
    if (this.#deadline !== null && this.#clock() >= this.#deadline) {
      this.#phase = "closed";
      this.#roomAckObserved = false;
      return true;
    }
    return false;
  }
  publicStatus() {
    this.#expired();
    return readonly({
      phase: this.#phase, roomAckObserved: this.#roomAckObserved,
      untrustedPushes: this.#pushCount, rejected: this.#rejected,
      authenticated: false, credentialsIncluded: false,
    });
  }
  #ignore() {
    this.#rejected++;
    return readonly({ kind: "ignored", reply: null, trusted: false });
  }
  receive(packet) {
    try {
    check(typeof packet === "string" &&
      Buffer.byteLength(packet, "utf8") <= MAX_WIRE_BYTES &&
      packet.length > 0, "INVALID_ENGINE_PACKET");
    if (this.#expired() || this.#phase === "closed") reject("ENGINE_SESSION_CLOSED");
    if (packet === "1" || packet === "41") {
      this.#phase = "closed";
      this.#roomAckObserved = false;
      return readonly({ kind: "disconnected", reply: null, trusted: false });
    }

    if (this.#phase === "await_engine_open") {
      check(packet[0] === "0", "ENGINE_OPEN_REQUIRED");
      const info = parseJSON(packet.slice(1), "INVALID_ENGINE_OPEN");
      check(object(info) && typeof info.sid === "string" && info.sid.length > 0 &&
        info.sid.length <= MAX_OPEN_FIELD &&
        Number.isSafeInteger(info.pingInterval) &&
        Number.isSafeInteger(info.pingTimeout) &&
        info.pingInterval > 0 && info.pingTimeout > 0,
        "INVALID_ENGINE_OPEN");
      this.#pingWindow = Math.max(5000, Math.min(300000, info.pingInterval + info.pingTimeout));
      this.#deadline = this.#clock() + this.#pingWindow;
      this.#phase = "await_socket_connect";
      return readonly({ kind: "engine_open", reply: "40", trusted: false });
    }

    if (packet === "2") {
      this.#deadline = this.#clock() + this.#pingWindow;
      return readonly({ kind: "engine_ping", reply: "3", trusted: false });
    }

    if (this.#phase === "await_socket_connect") {
      if (!packet.startsWith("40")) return this.#ignore();
      if (packet.length > 2) {
        const data = parseJSON(packet.slice(2), "INVALID_SOCKET_CONNECT");
        check(object(data) && (data.sid === undefined ||
          (typeof data.sid === "string" && data.sid.length <= MAX_OPEN_FIELD)),
          "INVALID_SOCKET_CONNECT");
      }
      this.#phase = "await_room_info_ack";
      // Fixture identifier, not an inferred vendor permission grant.
      return readonly({ kind: "socket_connected", reply:
        '42' + ROOM_INFO_REQUEST_ID + '["room_info"]', trusted: false });
    }

    if (this.#phase === "await_room_info_ack") {
      const prefix = "43" + ROOM_INFO_REQUEST_ID;
      if (!packet.startsWith(prefix + "[")) return this.#ignore();
      const payload = parseJSON(packet.slice(prefix.length), "INVALID_ROOM_INFO_ACK");
      check(Array.isArray(payload) && payload.length >= 1 && payload.length <= 8,
        "INVALID_ROOM_INFO_ACK");
      this.#roomAckObserved = true;
      this.#phase = "observing_untrusted_room";
      return readonly({ kind: "room_info_observed", reply: null, trusted: false });
    }

    if (this.#phase === "observing_untrusted_room") {
      // This only parses the Socket.IO event envelope. No caller can infer
      // authorization or WOL permission from a successfully parsed envelope.
      if (!packet.startsWith("42[")) return this.#ignore();
      const body = parseJSON(packet.slice(2), "INVALID_SOCKET_EVENT");
      check(Array.isArray(body) && body.length === 2 &&
        typeof body[0] === "string" && body[0].length > 0 &&
        body[0].length < 64 && object(body[1]),
        "INVALID_SOCKET_EVENT");
      if (body[0] !== "bmsg_push") return this.#ignore();
      this.#pushCount++;
      return readonly({
        kind: "untrusted_bmsg_push", frame: packet,
        reply: null, trusted: false, packetSent: false,
      });
    }
    return this.#ignore();
    } catch (error) {
      // Malformed protocol data must never leave an apparently usable room.
      this.#phase = "closed";
      this.#roomAckObserved = false;
      throw error;
    }
  }
}
