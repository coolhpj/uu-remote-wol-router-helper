import test from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import {
  prepareSignedRequest, prepareExternallySignedRequest,
} from "../experiments/remote-helper/vendor-wire-contract.mjs";
import { createVendorHttpsClient, VENDOR_ORIGIN } from "../experiments/remote-helper/vendor-https-client.mjs";

const fakeKey = "ONLY-FIXTURE-NOT-A-VENDOR-KEY";
const clockMs = 1763000000000;
const params = Object.freeze({ "x-param-ts": "1763000000",
  "x-param-plat": "1", "x-param-vn": "test" });
const path = "/api/v1/room/create";
const signer = async ({ canonical, sensitive, signal }) => {
  assert.equal(sensitive, true);
  assert.equal(signal.aborted, false);
  return createHmac("sha256", fakeKey).update(canonical).digest("hex");
};
const args = () => ({ method: "POST", path, xParams: params, body: {},
  externalSigner: signer, explicitlyAuthorized: true });
const response = body => new Response(JSON.stringify(body), {
  status: 200, headers: { "content-type": "application/json" },
});

test("external signer is disabled without explicit authorization", async () => {
  let calls = 0;
  await assert.rejects(prepareExternallySignedRequest({
    ...args(), explicitlyAuthorized: false,
    externalSigner: async () => { calls++; return "a".repeat(64); },
  }), /EXTERNAL_SIGNING_DISABLED/);
  assert.equal(calls, 0);
});
test("a missing external provider fails before any request can be built", async () => {
  await assert.rejects(prepareExternallySignedRequest({
    ...args(), externalSigner: undefined,
  }), /EXTERNAL_SIGNER_UNAVAILABLE/);
});
test("one external synthetic signature equals the original local HMAC canonical contract", async () => {
  const expected = prepareSignedRequest({
    method:"POST", path, xParams:params, body:{}, signingKey:fakeKey,
  });
  const result = await prepareExternallySignedRequest(args());
  assert.deepEqual(result, expected);
  assert.equal(result.bodyText, "{}");
  assert.equal(result.publicSummary.hasSignature, true);
  assert.equal(result.publicSummary.authenticated, undefined);
});
test("canonical input has approved method, path, and is marked sensitive", async () => {
  let details;
  await prepareExternallySignedRequest({ ...args(), externalSigner: async challenge => {
    details=challenge;
    return signer(challenge);
  } });
  assert.equal(details.method, "POST");
  assert.equal(details.path, path);
  assert.ok(details.canonical.startsWith("POST/api/v1/room/create"));
  assert.equal(details.canonical.endsWith("{}"), true);
  assert.equal(details.sensitive, true);
  assert.equal(Object.isFrozen(details), true);
});
test("non-allowlisted route and invalid x-param cannot reach signer", async () => {
  let calls=0;
  const provider=async()=>{calls++;return "f".repeat(64);};
  await assert.rejects(prepareExternallySignedRequest({
    ...args(),path:"/api/v1/unknown",externalSigner:provider,
  }),/UNLISTED_VENDOR_API_PATH/);
  await assert.rejects(prepareExternallySignedRequest({
    ...args(),xParams:{...params,"x-param-sign":"forged"},externalSigner:provider,
  }),/INVALID_SIGNING_PARAMS/);
  assert.equal(calls,0);
});
test("GET cannot smuggle a signed JSON body", async () => {
  await assert.rejects(prepareExternallySignedRequest({
    ...args(),method:"GET",body:{},
  }),/GET_BODY_FORBIDDEN/);
});
test("malformed or uppercase signatures are rejected (no silent normalization)", async () => {
  for(const value of ["", "a".repeat(63), "Z".repeat(64),
    "A".repeat(64), "a".repeat(64)+"\r\n", undefined, 5, {}, null]) {
    await assert.rejects(prepareExternallySignedRequest({
      ...args(),externalSigner:async()=>value,
    }),/EXTERNAL_SIGNATURE_INVALID/);
  }
});
test("external signer failure never leaks its secret in an error", async () => {
  const secret="synthetic-private-value-withheld";
  await assert.rejects(prepareExternallySignedRequest({
    ...args(),externalSigner:async()=>{throw new Error(secret);},
  }),error=>{
    assert.equal(error.message,"EXTERNAL_SIGNER_FAILED");
    assert.equal(error.message.includes(secret),false);
    return true;
  });
});
test("an external signer timeout is bounded and not exposed to callers", async () => {
  let aborted = false;
  await assert.rejects(prepareExternallySignedRequest({
    ...args(),signerTimeoutMs:120,
    externalSigner:async({signal})=>new Promise(()=>{
      signal.addEventListener("abort",()=>{aborted=true;});
    }),
  }),/EXTERNAL_SIGNER_FAILED/);
  assert.equal(aborted,true);
});
test("improper signing timeout settings fail closed", async () => {
  for(const signerTimeoutMs of [0, 99,10001,"300",Infinity]) {
    await assert.rejects(prepareExternallySignedRequest({
      ...args(),signerTimeoutMs,
    }),/EXTERNAL_SIGNER_TIMEOUT_INVALID/);
  }
});
test("direct signing key and external signer are mutually exclusive", () => {
  assert.throws(()=>createVendorHttpsClient({
    enabled:true,signingKey:fakeKey,externalSigner:signer,
    explicitlyAuthorizedSigner:true,
  }),/AMBIGUOUS_VENDOR_SIGNING_SOURCE/);
});
test("HTTPS client rejects an unapproved external signer before calling any fetch", () => {
  let calls=0;
  assert.throws(()=>createVendorHttpsClient({
    enabled:true,externalSigner:signer,explicitlyAuthorizedSigner:false,
    fetchImpl:async()=>{calls++;return response({code:0,data:{}});},
  }),/EXTERNAL_SIGNING_DISABLED/);
  assert.equal(calls,0);
});
test("HTTPS signed room/create with injected signer and fake fetch is private and inert", async () => {
  let called=0;
  const client=createVendorHttpsClient({
    enabled:true,externalSigner:signer,explicitlyAuthorizedSigner:true,
    xParams:params,clock:()=>clockMs,
    fetchImpl:async(url,init)=>{
      called++;
      assert.equal(url,VENDOR_ORIGIN+path);
      assert.equal(init.body,"{}");
      assert.equal(init.method,"POST");
      assert.equal(init.headers["x-param-sign"].length,64);
      assert.equal(init.redirect,"error");
      assert.equal(init.credentials,"omit");
      assert.ok(!JSON.stringify(init).includes(fakeKey));
      return response({code:0,data:{
        token:"synthetic-external-room-ticket",
        signaling_server:"wss://signal.example.org",
      }});
    },
  });
  const room=await client.createRoomCandidate({approvedSignalHost:"signal.example.org"});
  assert.equal(called,1);
  assert.equal(room.publicStatus().authenticated,false);
  assert.equal(room.publicStatus().wakePermitted,false);
  assert.equal(JSON.stringify(room).includes("synthetic-external-room-ticket"),false);
});
test("external signer callback error blocks HTTPS send, and error is redacted", async () => {
  let sent=0;
  const client=createVendorHttpsClient({
    enabled:true,externalSigner:async()=>{throw Error("sensitive-fixture-payload");},
    explicitlyAuthorizedSigner:true,xParams:params,clock:()=>clockMs,
    fetchImpl:async()=>{sent++;return response({code:0,data:{}});},
  });
  await assert.rejects(client.request(path,{}),/EXTERNAL_SIGNER_FAILED/);
  assert.equal(sent,0);
});
test("stale timestamp after signing is not transmitted by HTTPS", async () => {
  let sent=0;
  const client=createVendorHttpsClient({
    enabled:true,externalSigner:signer,explicitlyAuthorizedSigner:true,
    xParams:{...params,"x-param-ts":"1763000300"},clock:()=>clockMs,
    fetchImpl:async()=>{sent++;return response({code:0,data:{}});},
  });
  await assert.rejects(client.request(path,{}),/VENDOR_SIGNING_TIMESTAMP_STALE/);
  assert.equal(sent,0);
});
test("external signer can handle only a new timestamp per subsequent request", async () => {
  let now=clockMs;
  const seen=[];
  const client=createVendorHttpsClient({
    enabled:true,externalSigner:async challenge=>{
      seen.push(challenge.canonical);
      return signer(challenge);
    },explicitlyAuthorizedSigner:true,
    xParams:({nowSeconds})=>({"x-param-ts":String(nowSeconds),
      "x-param-plat":"1"}),
    clock:()=>now,
    fetchImpl:async()=>response({code:0,data:{status:1}}),
  });
  await client.request("/api/v1/qrcode/login/status",{});
  now+=18000;
  await client.request("/api/v1/qrcode/login/status",{});
  assert.equal(seen.length,2);
  assert.notEqual(seen[0],seen[1]);
});
