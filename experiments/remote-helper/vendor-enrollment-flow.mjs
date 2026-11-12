// An opt-in, single-device QR enrollment orchestrator for future authorized use.
// No networking, credential storage, host inspection, WOL, embedded keys or timers.
// Only the injected, separately gated HTTPS transport may contact the vendor.
// Public status and thrown errors never contain QR tickets, identities or tokens.
import {
  makeQrStatusBody, interpretQrStatus, makeQrExchangeBody,
} from "./vendor-wire-contract.mjs";

const QR_TTL_MS = 5 * 60_000;
const MAX_POLLS = 16;
function fail(code) { throw new Error(code); }
function requiredString(v, min = 8, max = 512) {
  return typeof v === "string" && v.length >= min && v.length <= max &&
    !/[\x00-\x1f\x7f]/.test(v);
}
function accepted(response) {
  if (response?.httpStatus !== 200 || response?.businessCode !== 0 ||
      !response?.privatePayload || response.privatePayload.code !== 0 ||
      typeof response.privatePayload.data !== "object" ||
      response.privatePayload.data === null ||
      Array.isArray(response.privatePayload.data))
    fail("VENDOR_BUSINESS_RESPONSE_REJECTED");
  return response.privatePayload.data;
}
function validatedVirtualIdentity(identity) {
  if (!identity || typeof identity !== "object" || Array.isArray(identity))
    fail("VIRTUAL_IDENTITY_REQUIRED");
  const required = ["name", "client_id", "system_id", "machine_guid",
    "os", "base_board", "cpu", "video", "mac", "memory", "screen"];
  if (Object.keys(identity).length !== required.length ||
      required.some(k => !Object.hasOwn(identity, k))) fail("VIRTUAL_IDENTITY_FIELDS_INVALID");
  for (const key of ["name", "client_id", "system_id", "machine_guid", "os", "base_board", "cpu"]) {
    if (!requiredString(identity[key], 1, 128)) fail("VIRTUAL_IDENTITY_FIELD_INVALID");
  }
  const mac = identity.mac;
  if (typeof mac !== "string" || !/^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(mac))
    fail("VIRTUAL_MAC_INVALID");
  const first = Number.parseInt(mac.slice(0, 2), 16);
  // A virtual experiment must not disclose or reuse the physical host NIC.
  if ((first & 3) !== 2) fail("VIRTUAL_MAC_NOT_LOCALLY_ADMINISTERED");
  if (!Number.isSafeInteger(identity.memory) || identity.memory < 64 ||
      identity.memory > 1048576) fail("VIRTUAL_MEMORY_INVALID");
  if (!Array.isArray(identity.video) || identity.video.length > 8 ||
      !Array.isArray(identity.screen) || identity.screen.length > 8)
    fail("VIRTUAL_HARDWARE_INVALID");
  const json = JSON.stringify(identity);
  if (Buffer.byteLength(json, "utf8") > 4096) fail("VIRTUAL_IDENTITY_TOO_LARGE");
  return JSON.parse(json);
}

export class VendorQrEnrollment {
  #transport;
  #onInitialized;
  #onCredentials;
  #now;
  #device;
  #state = "idle";
  #didInit = false;
  #busy = false;
  #issued = null;
  #expiresAt = null;
  #lastCode = 1;
  #polls = 0;

  constructor({
    enabled = false, transport, virtualDevice, onDeviceInitialized,
    onCredentials, clock = Date.now,
  } = {}) {
    if (enabled !== true) fail("VENDOR_ENROLLMENT_DISABLED");
    if (!transport || typeof transport.request !== "function" ||
        typeof transport.issueQr !== "function" ||
        typeof onDeviceInitialized !== "function" ||
        typeof onCredentials !== "function" || typeof clock !== "function")
      fail("VENDOR_ENROLLMENT_DEPENDENCY_MISSING");
    this.#transport = transport;
    this.#device = validatedVirtualIdentity(virtualDevice);
    this.#onInitialized = onDeviceInitialized;
    this.#onCredentials = onCredentials;
    this.#now = clock;
  }
  #time() {
    const t = this.#now();
    if (!Number.isSafeInteger(t) || t < 0) fail("VENDOR_ENROLLMENT_CLOCK_INVALID");
    return t;
  }
  #expire() {
    if (["pending", "scanned", "approved", "poll_paused"].includes(this.#state) &&
        this.#expiresAt !== null && this.#time() >= this.#expiresAt) {
      this.#state = "expired";
      this.#issued = null;
    }
  }
  publicStatus() {
    this.#expire();
    return Object.freeze({
      state: this.#state,
      hasQr: !!this.#issued,
      pollCount: this.#polls,
      deviceInitialized: this.#didInit,
      credentialsInResult: false,
      wolPacketSent: false,
    });
  }
  async #run(fn) {
    if (this.#busy) fail("VENDOR_ENROLLMENT_BUSY");
    this.#busy = true;
    try { return await fn(); } finally { this.#busy = false; }
  }
  async initialize() {
    if (this.#state !== "idle") fail("VENDOR_DEVICE_INIT_ALREADY_ATTEMPTED");
    this.#state = "initializing";
    return this.#run(async () => {
      try {
        const response = await this.#transport.request(
          "/api/v1/device/windows/init", this.#device);
        const data = accepted(response);
        if (!requiredString(data.device_id, 8, 256)) fail("VENDOR_DEVICE_ID_INVALID");
        // The caller may install the returned device ID into its next-request
        // signing-header provider. No identity is logged or returned publicly.
        if (this.#state === "cancelled") fail("VENDOR_ENROLLMENT_CANCELLED");
        await this.#onInitialized(data.device_id);
        if (this.#state === "cancelled") fail("VENDOR_ENROLLMENT_CANCELLED");
        this.#didInit = true;
        this.#state = "initialized";
        return this.publicStatus();
      } catch {
        if (this.#state !== "cancelled") this.#state = "failed";
        fail("VENDOR_DEVICE_INIT_FAILED");
      }
    });
  }
  async issueQr() {
    if (this.#state !== "initialized") fail("VENDOR_QR_ISSUE_NOT_ALLOWED");
    this.#state = "issuing";
    return this.#run(async () => {
      try {
        const issued = await this.#transport.issueQr();
        let url;
        try { url = new URL(issued?.qrcodeJumpUrl); }
        catch { fail("VENDOR_QR_ISSUANCE_INVALID"); }
        if (!requiredString(issued?.statusQueryTicket) ||
            !requiredString(issued?.qrcodeJumpUrl) ||
            url.protocol !== "https:" || !url.hostname ||
            url.username || url.password || url.hash)
          fail("VENDOR_QR_ISSUANCE_INVALID");
        if (this.#state === "cancelled") fail("VENDOR_ENROLLMENT_CANCELLED");
        this.#issued = Object.freeze({
          statusQueryTicket: issued.statusQueryTicket,
          qrcodeJumpUrl: issued.qrcodeJumpUrl,
        });
        this.#expiresAt = this.#time() + QR_TTL_MS;
        this.#polls = 0;
        this.#lastCode = 1;
        this.#state = "pending";
        return this.publicStatus();
      } catch {
        if (this.#state !== "cancelled") this.#state = "failed";
        this.#issued = null;
        fail("VENDOR_QR_ISSUE_FAILED");
      }
    });
  }
  ownerQr({ confirmPrivateDisplay = false } = {}) {
    this.#expire();
    if (confirmPrivateDisplay !== true) fail("QR_PRIVATE_DISPLAY_NOT_CONFIRMED");
    if (!["pending", "scanned", "approved", "poll_paused"].includes(this.#state) ||
        !this.#issued) fail("QR_NOT_AVAILABLE");
    // Bearer-like QR URL: show only in a protected owner UI, never stdout/CI.
    return this.#issued.qrcodeJumpUrl;
  }
  async pollOnce() {
    this.#expire();
    if (!["pending", "scanned"].includes(this.#state) || !this.#issued)
      fail("VENDOR_QR_POLL_NOT_ALLOWED");
    if (this.#polls >= MAX_POLLS) {
      this.#state = "poll_paused";
      fail("VENDOR_QR_POLL_BUDGET_EXHAUSTED");
    }
    return this.#run(async () => {
      const body = makeQrStatusBody(this.#issued, this.#lastCode);
      this.#polls += 1;
      let outcome;
      try {
        const response = await this.#transport.request(
          "/api/v1/qrcode/login/status", body);
        outcome = interpretQrStatus(response.httpStatus, response.privatePayload);
      } catch {
        if (this.#state !== "cancelled") this.#state = "poll_paused";
        fail("VENDOR_QR_POLL_FAILED_NOT_EXPIRED");
      }
      if (this.#state === "cancelled") fail("VENDOR_ENROLLMENT_CANCELLED");
      this.#expire();
      if (this.#state === "expired") return this.publicStatus();
      if (outcome.state === "refresh_required") {
        this.#state = "expired"; this.#issued = null;
      } else if (outcome.state === "approved") {
        this.#state = "approved";
      } else if (outcome.state === "scanned") {
        this.#state = "scanned"; this.#lastCode = 2;
      } else if (this.#state !== "scanned") {
        this.#state = "pending"; this.#lastCode = 1;
      }
      return this.publicStatus();
    });
  }
  resumePoll({ ownerConfirmed = false } = {}) {
    this.#expire();
    if (ownerConfirmed !== true || this.#state !== "poll_paused")
      fail("VENDOR_QR_RETRY_NOT_APPROVED");
    if (this.#polls >= MAX_POLLS) fail("VENDOR_QR_POLL_BUDGET_EXHAUSTED");
    this.#state = this.#lastCode === 2 ? "scanned" : "pending";
    return this.publicStatus();
  }
  async exchange() {
    this.#expire();
    if (this.#state !== "approved" || !this.#issued)
      fail("VENDOR_QR_NOT_APPROVED");
    return this.#run(async () => {
      // The single-use ticket is removed BEFORE the exchange request.
      const body = makeQrExchangeBody(this.#issued);
      this.#issued = null;
      this.#state = "exchanging";
      try {
        const response = await this.#transport.request(
          "/api/v1/login/by_qrcode", body);
        const data = accepted(response);
        if (!requiredString(data.user_id, 1, 256) ||
            !requiredString(data.token, 8, 8192))
          fail("VENDOR_LOGIN_RESPONSE_INVALID");
        // An authorized secure vault can consume credentials here. No public
        // status, tool result or log receives the token or account identifier.
        if (this.#state === "cancelled") fail("VENDOR_ENROLLMENT_CANCELLED");
        await this.#onCredentials({
          accountId: data.user_id, accessToken: data.token,
        });
        if (this.#state === "cancelled") fail("VENDOR_ENROLLMENT_CANCELLED");
        this.#state = "ready";
        return this.publicStatus();
      } catch {
        if (this.#state !== "cancelled") this.#state = "failed";
        fail("VENDOR_QR_EXCHANGE_FAILED_REAUTH_REQUIRED");
      }
    });
  }
  cancel() {
    if (this.#state === "ready") fail("VENDOR_ENROLLMENT_ALREADY_READY");
    this.#state = "cancelled";
    this.#issued = null;
    return this.publicStatus();
  }
}
