// Experimental UU Remote enrollment state contract, no network or persistence.
// The server-trust and token-exchange layers are NOT implemented here.
// QR references stay in RAM and are absent from public status or logs.
const MAX_TTL_MS = 5 * 60_000;
const STATES = new Set(["idle", "pending", "scanned", "approved", "exchanging",
  "ready", "denied", "expired", "cancelled", "failed"]);
function check(condition, code) { if (!condition) throw new Error(code); }
function challenge(value) {
  check(typeof value === "string" && /^[a-zA-Z0-9_-]{8,128}$/.test(value), "INVALID_QR_CHALLENGE");
  return value;
}
export class Enrollment {
  #state = "idle";
  #challenge = null;
  #qrUrl = null;
  #expiry = null;
  #accountId = null;
  #clock;
  #attempts = 0;
  constructor(clock = Date.now) {
    check(typeof clock === "function", "INVALID_CLOCK");
    this.#clock = clock;
  }
  #now() {
    const now = this.#clock();
    check(Number.isSafeInteger(now) && now >= 0, "INVALID_CLOCK");
    return now;
  }
  #expire() {
    if (["pending", "scanned", "approved"].includes(this.#state) &&
        this.#expiry !== null && this.#now() >= this.#expiry) {
      this.#state = "expired";
      this.#qrUrl = null;
    }
  }
  begin({ challengeId, qrUrl, expiresAt }) {
    this.#expire();
    check(["idle", "denied", "expired", "cancelled", "failed"].includes(this.#state),
      "ENROLLMENT_ALREADY_ACTIVE");
    const id = challenge(challengeId);
    const now = this.#now();
    check(typeof qrUrl === "string" && qrUrl.length <= 2048 &&
      qrUrl.startsWith("https://"), "INVALID_QR_URL");
    check(Number.isSafeInteger(expiresAt) && expiresAt > now &&
      expiresAt - now <= MAX_TTL_MS, "INVALID_QR_EXPIRY");
    this.#challenge = id;
    this.#qrUrl = qrUrl;
    this.#expiry = expiresAt;
    this.#accountId = null;
    this.#state = "pending";
    this.#attempts += 1;
    return this.publicStatus();
  }
  poll({ challengeId, status }) {
    this.#expire();
    check(challenge(challengeId) === this.#challenge, "QR_CHALLENGE_MISMATCH");
    check(["pending", "scanned"].includes(this.#state), "QR_POLL_NOT_ALLOWED");
    check(["pending", "scanned", "approved", "denied", "expired"].includes(status), "INVALID_QR_STATUS");
    // Never permit a server's repeated "pending" to undo a "scanned" status.
    if (this.#state === "scanned" && status === "pending") return this.publicStatus();
    this.#state = status;
    if (["denied", "expired"].includes(status)) this.#qrUrl = null;
    return this.publicStatus();
  }
  claimExchange({ challengeId }) {
    this.#expire();
    check(challenge(challengeId) === this.#challenge, "QR_CHALLENGE_MISMATCH");
    check(this.#state === "approved", "QR_NOT_APPROVED_OR_ALREADY_EXCHANGED");
    this.#state = "exchanging";
    this.#qrUrl = null;
    return this.publicStatus();
  }
  finishExchange({ challengeId, accountId }) {
    check(challenge(challengeId) === this.#challenge, "QR_CHALLENGE_MISMATCH");
    check(this.#state === "exchanging", "QR_EXCHANGE_NOT_ACTIVE");
    check(typeof accountId === "string" && /^[a-zA-Z0-9_-]{4,128}$/.test(accountId),
      "INVALID_ACCOUNT_ID");
    // AccountId MUST originate from a verified exchange over an authenticated
    // vendor connection. The state machine itself never authenticates a server.
    this.#accountId = accountId;
    this.#state = "ready";
    return this.publicStatus();
  }
  failure() {
    check(this.#state !== "ready", "CANNOT_FAIL_COMPLETED_ENROLLMENT");
    this.#state = "failed";
    this.#qrUrl = null;
    return this.publicStatus();
  }
  cancel() {
    check(this.#state !== "ready", "CANNOT_CANCEL_COMPLETED_ENROLLMENT");
    this.#state = "cancelled";
    this.#qrUrl = null;
    return this.publicStatus();
  }
  qrUrl() {
    this.#expire();
    check(["pending", "scanned", "approved"].includes(this.#state), "QR_UNAVAILABLE");
    return this.#qrUrl;
  }
  publicStatus() {
    this.#expire();
    check(STATES.has(this.#state), "INVALID_ENROLLMENT_STATE");
    return Object.freeze({ status: this.#state, attempts: this.#attempts,
      expiresAt: this.#expiry, accountId: this.#state === "ready" ? this.#accountId : null,
      containsCredential: false });
  }
}
