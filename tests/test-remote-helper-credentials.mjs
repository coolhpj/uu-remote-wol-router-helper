import test from "node:test";
import assert from "node:assert/strict";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { PrivateCredentialVault, credentialSummary } from
  "../experiments/remote-helper/private-credentials.mjs";

const fakeRecord = () => ({ version: 1, provider: "uu-remote-helper",
  accountId: "fake-account-01", accessToken: "synthetic-access-token-01",
  refreshToken: "synthetic-refresh-token-01",
  expiresAt: Date.now() + 3_600_000 });
async function inTestFolder(fn) {
  const base = await fs.mkdtemp(path.join(os.tmpdir(), "uu-wol-auth-fixture-"));
  try { return await fn(base); } finally { await fs.rm(base, { recursive: true, force: true }); }
}
test("0600 identity file is written atomically inside private 0700 directory", () =>
  inTestFolder(async dir => {
    const vault = new PrivateCredentialVault(path.join(dir, "private"));
    const original = fakeRecord();
    const summary = await vault.save(original);
    assert.deepEqual(summary, credentialSummary(original));
    assert.equal(JSON.stringify(summary).includes(original.accessToken), false);
    const stat = await fs.stat(vault.filePath);
    const dirStat = await fs.stat(path.dirname(vault.filePath));
    assert.equal(stat.mode & 0o777, 0o600);
    assert.equal(dirStat.mode & 0o777, 0o700);
    const loaded = await vault.load();
    assert.deepEqual(loaded, original);
    assert.equal(Object.isFrozen(loaded), true);
    assert.deepEqual((await fs.readdir(path.dirname(vault.filePath))),
      ["remote-helper-identity.json"]);
  }));
test("replacement retains only the newest complete identity record", () =>
  inTestFolder(async dir => {
    const vault = new PrivateCredentialVault(path.join(dir, "private"));
    const old = fakeRecord();
    await vault.save(old);
    const next = { ...old, accessToken: "synthetic-access-token-02" };
    await vault.save(next);
    assert.deepEqual(await vault.load(), next);
    assert.deepEqual(await fs.readdir(path.dirname(vault.filePath)),
      ["remote-helper-identity.json"]);
  }));
test("missing file is not interpreted as an authenticated device", () =>
  inTestFolder(async dir => {
    const vault = new PrivateCredentialVault(path.join(dir, "private"));
    assert.equal(await vault.load(), null);
  }));
test("symlinked credential file is rejected without accessing its target", () =>
  inTestFolder(async dir => {
    const privateDir = path.join(dir, "private");
    await fs.mkdir(privateDir, { mode: 0o700 });
    await fs.writeFile(path.join(dir, "elsewhere"), "do-not-read", { mode: 0o600 });
    const vault = new PrivateCredentialVault(privateDir);
    await fs.symlink(path.join(dir, "elsewhere"), vault.filePath);
    await assert.rejects(vault.load(), /INSECURE_IDENTITY_PATH/);
    await assert.rejects(vault.save(fakeRecord()), /INSECURE_IDENTITY_PATH/);
  }));
test("symlinked directory and broad directory permissions fail closed", () =>
  inTestFolder(async dir => {
    const linked = path.join(dir, "linked");
    await fs.symlink(dir, linked);
    await assert.rejects(new PrivateCredentialVault(linked).load(), /INSECURE_IDENTITY_PATH/);
    const publicDir = path.join(dir, "public");
    await fs.mkdir(publicDir, { mode: 0o755 });
    await assert.rejects(new PrivateCredentialVault(publicDir).save(fakeRecord()),
      /INSECURE_IDENTITY_PERMISSIONS/);
  }));
test("world-readable, malformed and oversized credential files fail closed", () =>
  inTestFolder(async dir => {
    const dirPrivate = path.join(dir, "private");
    await fs.mkdir(dirPrivate, { mode: 0o700 });
    const vault = new PrivateCredentialVault(dirPrivate);
    await fs.writeFile(vault.filePath, "not-json", { mode: 0o600 });
    await assert.rejects(vault.load(), /INVALID_CREDENTIAL_JSON/);
    await fs.chmod(vault.filePath, 0o644);
    await assert.rejects(vault.load(), /INSECURE_IDENTITY_PERMISSIONS/);
    await fs.chmod(vault.filePath, 0o600);
    await fs.writeFile(vault.filePath, "z".repeat(11000));
    await assert.rejects(vault.load(), /IDENTITY_RECORD_TOO_LARGE/);
  }));
test("expired, extra-field and structurally invalid tokens rejected", () =>
  inTestFolder(async dir => {
    const vault = new PrivateCredentialVault(path.join(dir, "private"));
    const normal = fakeRecord();
    for (const wrong of [{ ...normal, expiresAt: Date.now() - 10 },
      { ...normal, extra: "no" }, { ...normal, refreshToken: "" },
      { ...normal, provider: "unknown" }, { ...normal, accountId: "" }]) {
      await assert.rejects(vault.save(wrong), /INVALID_CREDENTIAL_RECORD|UNEXPECTED_CREDENTIAL_FIELDS/);
    }
    assert.equal(await vault.load(), null);
  }));
test("invalid vault roots are rejected", () => {
  assert.throws(() => new PrivateCredentialVault("."), /INVALID_IDENTITY_DIRECTORY/);
  assert.throws(() => new PrivateCredentialVault("/"), /INVALID_IDENTITY_DIRECTORY/);
});
