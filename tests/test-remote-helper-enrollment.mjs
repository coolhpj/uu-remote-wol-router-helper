import test from "node:test";
import assert from "node:assert/strict";
import { Enrollment } from "../experiments/remote-helper/enrollment-state.mjs";

const qr = { challengeId: "qr-fixture-20261112",
  qrUrl: "https://qr.example.invalid/test-only",
  expiresAt: 1_080_000 };
const machine = (time = 1_000_000) => {
  let now = time;
  return { state: new Enrollment(() => now), tick: ms => { now += ms; } };
};

test("explicit QR enrollment can advance through scan, approval and exchange only once", () => {
  const { state } = machine();
  assert.equal(state.begin(qr).status, "pending");
  assert.equal(state.qrUrl(), qr.qrUrl);
  assert.equal(state.poll({ challengeId: qr.challengeId, status: "scanned" }).status, "scanned");
  assert.equal(state.poll({ challengeId: qr.challengeId, status: "pending" }).status, "scanned");
  assert.equal(state.poll({ challengeId: qr.challengeId, status: "approved" }).status, "approved");
  assert.equal(state.claimExchange({ challengeId: qr.challengeId }).status, "exchanging");
  assert.throws(() => state.claimExchange({ challengeId: qr.challengeId }), /ALREADY_EXCHANGED/);
  const status = state.finishExchange({ challengeId: qr.challengeId, accountId: "fake-account-01" });
  assert.equal(status.status, "ready");
  assert.equal(status.accountId, "fake-account-01");
  assert.equal(status.containsCredential, false);
  assert.equal(Object.isFrozen(status), true);
  assert.equal(JSON.stringify(status).includes(qr.qrUrl), false);
  assert.throws(() => state.qrUrl(), /QR_UNAVAILABLE/);
});
test("QR cannot approve or exchange before server confirmation", () => {
  const { state } = machine();
  state.begin(qr);
  assert.throws(() => state.claimExchange({ challengeId: qr.challengeId }), /NOT_APPROVED/);
  assert.throws(() => state.finishExchange({ challengeId: qr.challengeId, accountId: "fake-acc-01" }),
    /EXCHANGE_NOT_ACTIVE/);
  assert.throws(() => state.poll({ challengeId: "other-challenge", status: "approved" }),
    /CHALLENGE_MISMATCH/);
});
test("QR approval after expiry is rejected and re-enrollment needs a new challenge", () => {
  const { state, tick } = machine();
  state.begin(qr);
  tick(80_000);
  assert.equal(state.publicStatus().status, "expired");
  assert.throws(() => state.poll({ challengeId: qr.challengeId, status: "approved" }), /POLL_NOT_ALLOWED/);
  assert.throws(() => state.qrUrl(), /QR_UNAVAILABLE/);
  const next = { ...qr, challengeId: "qr-fixture-next", expiresAt: 1_160_000 };
  assert.equal(state.begin(next).status, "pending");
  assert.equal(state.publicStatus().attempts, 2);
  assert.throws(() => state.poll({ challengeId: qr.challengeId, status: "approved" }),
    /CHALLENGE_MISMATCH/);
});
test("denial, cancel and failure invalidate QR access without leaking links", () => {
  const a = machine().state;
  a.begin(qr);
  assert.equal(a.poll({ challengeId: qr.challengeId, status: "denied" }).status, "denied");
  assert.throws(() => a.qrUrl(), /QR_UNAVAILABLE/);
  a.begin({ ...qr, challengeId: "qr-fixture-retry" });
  assert.equal(a.cancel().status, "cancelled");
  assert.throws(() => a.qrUrl(), /QR_UNAVAILABLE/);
  a.begin({ ...qr, challengeId: "qr-fixture-final" });
  assert.equal(a.failure().status, "failed");
});
test("all unexpected or replayed transitions fail closed", () => {
  const a = machine().state;
  assert.throws(() => a.poll({ challengeId: qr.challengeId, status: "approved" }));
  assert.throws(() => a.begin({ ...qr, qrUrl: "http://example.invalid/unsafe" }), /INVALID_QR_URL/);
  assert.throws(() => a.begin({ ...qr, expiresAt: 1_400_000 }), /INVALID_QR_EXPIRY/);
  assert.throws(() => a.begin({ ...qr, challengeId: "." }), /INVALID_QR_CHALLENGE/);
  a.begin(qr);
  assert.throws(() => a.begin(qr), /ALREADY_ACTIVE/);
  assert.throws(() => a.poll({ challengeId: qr.challengeId, status: "unexpected" }), /INVALID_QR_STATUS/);
  a.poll({ challengeId: qr.challengeId, status: "approved" });
  a.claimExchange({ challengeId: qr.challengeId });
  assert.throws(() => a.finishExchange({ challengeId: qr.challengeId, accountId: "" }), /INVALID_ACCOUNT_ID/);
  a.finishExchange({ challengeId: qr.challengeId, accountId: "fake-acc-11" });
  assert.throws(() => a.cancel(), /CANNOT_CANCEL/);
  assert.throws(() => a.begin(qr), /ALREADY_ACTIVE/);
});
test("QR expiry is enforced at exchange claim, not just polling", () => {
  const m = machine();
  m.state.begin(qr);
  m.state.poll({ challengeId: qr.challengeId, status: "approved" });
  m.tick(82_000);
  assert.throws(() => m.state.claimExchange({ challengeId: qr.challengeId }), /NOT_APPROVED/);
});
