import test from "node:test";
import assert from "node:assert/strict";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { PrivateCredentialVault } from "../experiments/remote-helper/private-credentials.mjs";
import { CredentialSession } from "../experiments/remote-helper/credential-session.mjs";

const now = () => Date.now();
const record = (expiresAt = now() + 3_600_000, accountId = "synthetic-account-01") => ({
  version: 1, provider: "uu-remote-helper", accountId, accessToken: "mock-access-01",
  refreshToken: "mock-refresh-01", expiresAt
});
async function fixture(run) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "uu-session-fixture-"));
  try {
    const vault = new PrivateCredentialVault(path.join(root, "private"));
    return await run(vault);
  } finally { await fs.rm(root, { recursive: true, force: true }); }
}
test("valid persisted credential can resume without refresh or network", () =>
  fixture(async vault => {
    const saved = record();
    await vault.save(saved);
    let calls = 0;
    const s = new CredentialSession({ vault, refresh: async () => { calls++; return saved; } });
    assert.equal((await s.restore()).status, "ready");
    assert.equal(await s.accessToken(), saved.accessToken);
    assert.equal(calls, 0);
    assert.equal(s.publicStatus().containsCredential, false);
    assert.equal(JSON.stringify(s.publicStatus()).includes(saved.accessToken), false);
  }));
test("missing identity requires owner authorization; no synthetic refresh is attempted", () =>
  fixture(async vault => {
    let calls = 0;
    const s = new CredentialSession({ vault, refresh: async () => { calls++; } });
    assert.equal((await s.restore()).status, "reauth_required");
    await assert.rejects(s.accessToken(), /SESSION_REAUTH_REQUIRED/);
    assert.equal(calls, 0);
  }));
test("a nearly expired access token refreshes exactly once under simultaneous calls", () =>
  fixture(async vault => {
    const earlier = record(now() + 25_000);
    await vault.save(earlier);
    let calls = 0;
    const s = new CredentialSession({ vault, refresh: async ({ accountId, refreshToken }) => {
      calls++;
      assert.equal(accountId, earlier.accountId);
      assert.equal(refreshToken, earlier.refreshToken);
      await new Promise(resolve => setTimeout(resolve, 30));
      return { ...record(), accessToken: "mock-new-access-02",
        refreshToken: "mock-new-refresh-02" };
    } });
    await s.restore();
    const results = await Promise.all([s.accessToken(), s.accessToken(), s.accessToken()]);
    assert.deepEqual(results, ["mock-new-access-02", "mock-new-access-02", "mock-new-access-02"]);
    assert.equal(calls, 1);
    assert.equal((await vault.load()).refreshToken, "mock-new-refresh-02");
    assert.equal((await s.accessToken()), "mock-new-access-02");
    assert.equal(s.publicStatus().refreshInProgress, false);
  }));
test("refresh never switches accounts, and requires reauthorization on failure", () =>
  fixture(async vault => {
    await vault.save(record(now() + 30_000));
    const s = new CredentialSession({ vault,
      refresh: async () => record(now() + 3_600_000, "unexpected-account") });
    await s.restore();
    await assert.rejects(s.accessToken(), /REFRESH_FAILED_REAUTH_REQUIRED/);
    assert.equal((await vault.load()).accountId, "synthetic-account-01");
    assert.equal(s.publicStatus().status, "reauth_required");
    await assert.rejects(s.accessToken(), /SESSION_REAUTH_REQUIRED/);
  }));
test("refresh response must remain valid for longer than safety skew", () =>
  fixture(async vault => {
    await vault.save(record(now() + 15_000));
    const s = new CredentialSession({ vault,
      refresh: async () => record(now() + 12_000) });
    await s.restore();
    await assert.rejects(s.accessToken(), /REFRESH_FAILED_REAUTH_REQUIRED/);
    assert.equal(s.publicStatus().status, "reauth_required");
  }));
test("expired stored token cannot be used even if an injected refresh would succeed", () =>
  fixture(async vault => {
    await vault.save(record(now() + 20_000));
    let current = now();
    let calls = 0;
    const s = new CredentialSession({ vault, clock: () => current,
      refresh: async () => { calls++; return record(); } });
    await s.restore();
    current += 35_000;
    await assert.rejects(s.accessToken(), /SESSION_CREDENTIAL_UNAVAILABLE|SESSION_EXPIRED/);
    assert.equal(calls, 0);
    assert.equal(s.publicStatus().status, "reauth_required");
  }));
test("missing, corrupted or replaced identity becomes reauthorization required", () =>
  fixture(async vault => {
    await vault.save(record());
    const s = new CredentialSession({ vault, refresh: async () => record() });
    await s.restore();
    await fs.unlink(vault.filePath);
    await assert.rejects(s.accessToken(), /SESSION_ACCOUNT_CHANGED/);
    assert.equal(s.publicStatus().status, "reauth_required");
  }));
test("restore and refresh are opt-in: repeated restore is forbidden", () =>
  fixture(async vault => {
    const s = new CredentialSession({ vault, refresh: async () => record() });
    await assert.rejects(s.accessToken(), /SESSION_REAUTH_REQUIRED/);
    await s.restore();
    await assert.rejects(s.restore(), /SESSION_ALREADY_INITIALIZED/);
  }));
