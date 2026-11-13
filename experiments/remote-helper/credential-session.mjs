// Authentication lifecycle contract for a future owner-approved UU Remote adapter.
// No vendor endpoint, network, hard-coded credentials, or periodic background task.
// A caller must inject an authenticated refresh function returning a validated record.
import { credentialSummary } from "./private-credentials.mjs";

function reject(code) { throw new Error(code); }
const SKEW_MS = 60_000;

export class CredentialSession {
  #vault;
  #refresher;
  #now;
  #pending = null;
  #state = "uninitialized";
  #account = null;

  constructor({ vault, refresh, clock = Date.now }) {
    if (!vault || typeof vault.load !== "function" || typeof vault.save !== "function" ||
        typeof refresh !== "function" || typeof clock !== "function")
      reject("INVALID_SESSION_DEPENDENCY");
    this.#vault = vault;
    this.#refresher = refresh;
    this.#now = clock;
  }

  #clock() {
    const value = this.#now();
    if (!Number.isSafeInteger(value) || value < 0) reject("INVALID_SESSION_CLOCK");
    return value;
  }

  publicStatus() {
    return Object.freeze({ status: this.#state, accountId: this.#account,
      refreshInProgress: this.#pending !== null, containsCredential: false });
  }

  async restore() {
    if (this.#state !== "uninitialized") reject("SESSION_ALREADY_INITIALIZED");
    let record;
    try {
      record = await this.#vault.load();
    } catch {
      this.#state = "reauth_required";
      reject("SESSION_CREDENTIAL_UNAVAILABLE");
    }
    if (!record) {
      this.#state = "reauth_required";
      return this.publicStatus();
    }
    this.#account = record.accountId;
    if (record.expiresAt <= this.#clock()) {
      this.#state = "reauth_required";
      return this.publicStatus();
    }
    this.#state = "ready";
    return this.publicStatus();
  }

  async accessToken() {
    if (this.#state !== "ready") reject("SESSION_REAUTH_REQUIRED");
    const record = await this.#vault.load().catch(() => {
      this.#state = "reauth_required";
      reject("SESSION_CREDENTIAL_UNAVAILABLE");
    });
    if (!record || record.accountId !== this.#account) {
      this.#state = "reauth_required";
      reject("SESSION_ACCOUNT_CHANGED");
    }
    const now = this.#clock();
    if (record.expiresAt <= now) {
      this.#state = "reauth_required";
      reject("SESSION_EXPIRED");
    }
    if (record.expiresAt - now > SKEW_MS) return record.accessToken;

    if (!this.#pending) {
      this.#pending = this.#renew(record);
      // The pending promise stays shared among concurrent callers.
      void this.#pending.finally(() => { this.#pending = null; }).catch(() => {});
    }
    return this.#pending;
  }

  async #renew(current) {
    try {
      const newRecord = await this.#refresher({
        accountId: current.accountId, refreshToken: current.refreshToken
      });
      const check = credentialSummary(newRecord);
      if (check.accountId !== this.#account || check.expiresAt <= this.#clock() + SKEW_MS)
        reject("REFRESH_IDENTITY_OR_EXPIRY_INVALID");
      await this.#vault.save(newRecord);
      return newRecord.accessToken;
    } catch {
      this.#state = "reauth_required";
      reject("REFRESH_FAILED_REAUTH_REQUIRED");
    }
  }
}
