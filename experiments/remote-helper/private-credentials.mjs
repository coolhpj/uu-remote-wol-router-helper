// Optional account-token storage for isolated future UU Remote helper.
// Never reads or writes live credentials unless a caller explicitly opts in.
// IMPORTANT: plaintext 0600 (not encryption); do not mount shared/NAS folders.
import { promises as fs, constants as flags } from "node:fs";
import path from "node:path";
import { randomBytes } from "node:crypto";

const NAME = "remote-helper-identity.json";
function fault(code) { throw new Error(code); }
function verifyRecord(value, now = Date.now()) {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      value.version !== 1 || value.provider !== "uu-remote-helper" ||
      typeof value.accountId !== "string" ||
      !/^[a-zA-Z0-9_-]{4,128}$/.test(value.accountId) ||
      typeof value.accessToken !== "string" || value.accessToken.length < 8 ||
      value.accessToken.length > 4096 ||
      typeof value.refreshToken !== "string" || value.refreshToken.length < 8 ||
      value.refreshToken.length > 4096 ||
      !Number.isSafeInteger(value.expiresAt) || value.expiresAt <= now ||
      value.expiresAt > now + 365 * 24 * 3600_000) fault("INVALID_CREDENTIAL_RECORD");
  const keys = Object.keys(value).sort();
  if (keys.join(",") !== "accessToken,accountId,expiresAt,provider,refreshToken,version")
    fault("UNEXPECTED_CREDENTIAL_FIELDS");
  return { version: 1, provider: "uu-remote-helper", accountId: value.accountId,
    accessToken: value.accessToken, refreshToken: value.refreshToken,
    expiresAt: value.expiresAt };
}
function checkPrivate(stat, expectedDirectory = false) {
  if (stat.isSymbolicLink() || (expectedDirectory ? !stat.isDirectory() : !stat.isFile()))
    fault("INSECURE_IDENTITY_PATH");
  if (typeof process.getuid !== "function" || stat.uid !== process.getuid() ||
      (stat.mode & 0o077) !== 0 || (expectedDirectory && (stat.mode & 0o700) !== 0o700))
    fault("INSECURE_IDENTITY_PERMISSIONS");
}
export function credentialSummary(record) {
  const value = verifyRecord(record);
  return Object.freeze({ provider: value.provider, accountId: value.accountId,
    expiresAt: value.expiresAt, hasTokens: true });
}
export class PrivateCredentialVault {
  #directory;
  constructor(directory) {
    if (typeof directory !== "string" || !path.isAbsolute(directory) ||
        directory.includes("\0") || directory === "/") fault("INVALID_IDENTITY_DIRECTORY");
    this.#directory = path.resolve(directory);
  }
  get filePath() { return path.join(this.#directory, NAME); }
  async #ensureDirectory() {
    if (typeof process.getuid !== "function") fault("UNSUPPORTED_IDENTITY_PLATFORM");
    try {
      await fs.mkdir(this.#directory, { mode: 0o700 });
    } catch (error) {
      if (error.code !== "EEXIST") fault("IDENTITY_DIRECTORY_UNAVAILABLE");
    }
    const stat = await fs.lstat(this.#directory);
    checkPrivate(stat, true);
  }
  async #checkExisting() {
    try {
      const stat = await fs.lstat(this.filePath);
      checkPrivate(stat, false);
      if (stat.size > 10000) fault("IDENTITY_RECORD_TOO_LARGE");
      return true;
    } catch (error) {
      if (error.code === "ENOENT") return false;
      throw error;
    }
  }
  async save(record) {
    const normalized = verifyRecord(record);
    await this.#ensureDirectory();
    await this.#checkExisting();
    let temporary;
    let handle;
    try {
      temporary = path.join(this.#directory, ".identity-" + randomBytes(12).toString("hex"));
      handle = await fs.open(temporary, flags.O_WRONLY | flags.O_CREAT | flags.O_EXCL |
        (flags.O_NOFOLLOW || 0), 0o600);
      await handle.writeFile(JSON.stringify(normalized) + "\n", { encoding: "utf8" });
      await handle.sync();
      await handle.close(); handle = null;
      // Atomic replacement of a regular owned file; no existing symlink allowed.
      await this.#checkExisting();
      await fs.rename(temporary, this.filePath);
      const parent = await fs.open(this.#directory, flags.O_RDONLY);
      try { await parent.sync(); } finally { await parent.close(); }
    } finally {
      if (handle) await handle.close();
      if (temporary) await fs.unlink(temporary).catch(error => {
        if (error.code !== "ENOENT") throw error;
      });
    }
    return credentialSummary(normalized);
  }
  async load() {
    await this.#ensureDirectory();
    if (!await this.#checkExisting()) return null;
    let handle;
    try {
      handle = await fs.open(this.filePath, flags.O_RDONLY | (flags.O_NOFOLLOW || 0));
      const stat = await handle.stat();
      checkPrivate(stat, false);
      if (stat.size > 10000) fault("IDENTITY_RECORD_TOO_LARGE");
      const bytes = await handle.readFile({ encoding: "utf8" });
      let parsed;
      try { parsed = JSON.parse(bytes); } catch { fault("INVALID_CREDENTIAL_JSON"); }
      return Object.freeze(verifyRecord(parsed));
    } finally {
      if (handle) await handle.close();
    }
  }
}
