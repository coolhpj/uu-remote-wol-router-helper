import test, { before, after } from "node:test";
import assert from "node:assert/strict";
import tls from "node:tls";
import { promises as fs, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { parseRoomCandidate } from "../experiments/remote-helper/vendor-room-contract.mjs";
import { fixtureWssUpgrade } from "../experiments/remote-helper/fixture-wss-upgrade.mjs";

const host = "signal.example.org";
const mismatchHost = "another.example.org";
const loopback = [127, 0, 0, 1].join(".");
const token = "synthetic-room-ticket-abcdefghijkl";
let dir, good, mismatch, untrusted;
function certPair(name, leafHost) {
  const keyPath = path.join(dir, name + ".key");
  const certPath = path.join(dir, name + ".pem");
  // All keys are generated in an OS temporary directory with private mode,
  // never stored in git, emitted in tool logs, or re-used as vendor secrets.
  execFileSync("openssl", [
    "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-nodes",
    "-keyout", keyPath, "-out", certPath, "-days", "1",
    "-subj", "/CN=" + leafHost, "-addext", "subjectAltName=DNS:" + leafHost,
  ], { stdio: "ignore", timeout: 12000 });
  return { key:readFileSync(keyPath,"utf8"), cert:readFileSync(certPath,"utf8") };
}
before(async () => {
  dir = await fs.mkdtemp(path.join(tmpdir(), "uu-wss-fixture-"));
  await fs.chmod(dir, 0o700);
  good = certPair("synthetic-good", host);
  mismatch = certPair("synthetic-otherhost", mismatchHost);
  untrusted = certPair("synthetic-untrusted", host);
});
after(async () => { if (dir) await fs.rm(dir, { recursive:true, force:true }); });
function candidate(roomToken = token, clock = Date.now) {
  const now=clock();
  return parseRoomCandidate({
    httpStatus:200, payload:{code:0,data:{
      signaling_server:"wss://"+host,token:roomToken,
    }},
    approvedSignalHost:host,receivedAtMs:now,clock,
  });
}
function respond(s, type, request) {
  if (type === "silent") return;
  if (type === "oversized") {
    s.write("HTTP/1.1 101 Switching Protocols\r\nX-Large: "+
      "x".repeat(9000)+"\r\n\r\n");
    return;
  }
  if (type === "reject") {
    s.end("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n");
    return;
  }
  if (type === "redirect") {
    s.end("HTTP/1.1 302 Found\r\nLocation: https://another.example.org/\r\n\r\n");
    return;
  }
  const matched=request.match(/^Sec-WebSocket-Key: ([A-Za-z0-9+/=]+)$/im);
  const accept=matched?createHash("sha1").update(
    matched[1]+"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64"):"";
  const answer = [
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket","Connection: Upgrade",
    "Sec-WebSocket-Accept: "+(type==="forged"? "invalid-accept" : accept),
    ...(type==="duplicate"?["Sec-WebSocket-Accept: "+accept]:[]),
    "","",
  ].join("\r\n");
  s.write(answer);
}
async function withTlsServer({certificate=good,alpn=["http/1.1"],type="accept"}={},fn) {
  const seen=[];
  const live=new Set();
  const service=tls.createServer({key:certificate.key,cert:certificate.cert,ALPNProtocols:alpn}, socket=>{
    live.add(socket);
    socket.once("close",()=>live.delete(socket));
    socket.on("error",()=>{});
    let data="";
    socket.on("data",part=>{
      data+=part.toString("latin1");
      if(data.length>12000){socket.destroy();return;}
      if(!data.includes("\r\n\r\n"))return;
      if(seen.includes(data))return;
      seen.push(data);
      respond(socket,type,data);
    });
  });
  service.on("tlsClientError",()=>{});
  service.on("error",()=>{});
  await new Promise((resolve,reject)=>{
    service.once("error",reject);
    service.listen(0,loopback,resolve);
  });
  const port=service.address().port;
  try {
    return await fn({port,seen});
  } finally {
    for(const socket of live)socket.destroy();
    await new Promise(resolve=>service.close(resolve));
  }
}
const probe=({port,ca=good?.cert,room=candidate(),approvedHost=host,fixtureOnly=true,timeoutMs=800}={})=>
  fixtureWssUpgrade({roomCandidate:room,approvedHost,port,trustedCa:ca,fixtureOnly,timeoutMs});

test("synthetic TLS validates trusted certificate/SNI, then sends WSS Upgrade + private header",()=>
  withTlsServer({},async ({port,seen})=>{
    const status=await probe({port});
    assert.deepEqual(status,{
      transport:"synthetic-tls-loopback", secureTls:true,hostnameChecked:true,
      upgradeAccepted:true,customHeaderSentToFixture:true,externalEndpointDialed:false,
      authenticated:false,registrationVerified:false,wakePermitted:false,
      packetSent:false,credentialsIncluded:false,
    });
    assert.equal(seen.length,1);
    const request=seen[0];
    assert.ok(request.startsWith(
      "GET /socket.io/?transport=websocket&EIO=4 HTTP/1.1\r\n"));
    assert.match(request,/^Host: signal\.example\.org\r?$/im);
    assert.match(request,/^X-NRD-AUTH: synthetic-room-ticket-abcdefghijkl\r?$/im);
    assert.ok(!JSON.stringify(status).includes(token));
    assert.ok(!JSON.stringify(status).includes(host));
  }));
test("default disabled means zero TLS dials and no request header transmission",()=>
  withTlsServer({},async ({port,seen})=>{
    assert.throws(()=>probe({port,fixtureOnly:false}),/FIXTURE_WSS_DISABLED/);
    assert.equal(seen.length,0);
  }));
test("certificate hostname mismatch is rejected BEFORE synthetic bearer is sent",()=>
  withTlsServer({certificate:mismatch},async({port,seen})=>{
    await assert.rejects(probe({port}),/FIXTURE_TLS_OR_TRANSPORT_REJECTED|FIXTURE_TLS_IDENTITY_REJECTED/);
    assert.equal(seen.length,0);
  }));
test("certificate signed by an untrusted fixture CA cannot see bearer",()=>
  withTlsServer({certificate:untrusted},async({port,seen})=>{
    await assert.rejects(probe({port}),/FIXTURE_TLS_OR_TRANSPORT_REJECTED|FIXTURE_TLS_IDENTITY_REJECTED/);
    assert.equal(seen.length,0);
  }));
test("ALPN mismatch prevents WSS upgrade and bearer disclosure",()=>
  withTlsServer({alpn:["h2"]},async({port,seen})=>{
    await assert.rejects(probe({port}),/FIXTURE_TLS_IDENTITY_REJECTED|FIXTURE_TLS_OR_TRANSPORT_REJECTED/);
    assert.equal(seen.length,0);
  }));
test("HTTP 403 is not mistaken for accepted room authentication",()=>
  withTlsServer({type:"reject"},async({port,seen})=>{
    await assert.rejects(probe({port}),/FIXTURE_WSS_HANDSHAKE_REJECTED/);
    assert.equal(seen.length,1);
  }));
test("HTTP redirect is rejected; WSS handshake never follows offsite Location",()=>
  withTlsServer({type:"redirect"},async({port,seen})=>{
    await assert.rejects(probe({port}),/FIXTURE_WSS_HANDSHAKE_REJECTED/);
    assert.equal(seen.length,1);
  }));
test("forged Sec-WebSocket-Accept is rejected after TLS",()=>
  withTlsServer({type:"forged"},async({port})=>{
    await assert.rejects(probe({port}),/FIXTURE_WSS_HANDSHAKE_REJECTED/);
  }));
test("duplicate accept header cannot override WSS response verifier",()=>
  withTlsServer({type:"duplicate"},async({port})=>{
    await assert.rejects(probe({port}),/FIXTURE_WSS_HANDSHAKE_REJECTED/);
  }));
test("HTTP Upgrade response size is bounded even with a trusted certificate",()=>
  withTlsServer({type:"oversized"},async({port})=>{
    await assert.rejects(probe({port}),/FIXTURE_WSS_RESPONSE_TOO_LARGE/);
  }));
test("a silent TLS server triggers a bounded handshake timeout, not authentication",()=>
  withTlsServer({type:"silent"},async({port})=>{
    await assert.rejects(probe({port,timeoutMs:120}),/FIXTURE_WSS_TIMEOUT/);
  }));
test("wrong preapproved host cannot trigger the loopback TLS dial",()=>
  withTlsServer({},async({port,seen})=>{
    assert.throws(()=>probe({port,approvedHost:"other.example.org"}),
      /FIXTURE_ROOM_PLAN_REJECTED/);
    assert.equal(seen.length,0);
  }));
test("expired room candidate blocks sending bearer before the TLS socket exists",()=>
  withTlsServer({},async({port,seen})=>{
    let now=1000000;
    const room=candidate(token,()=>now);
    now+=61000;
    assert.throws(()=>probe({port,room}),/FIXTURE_ROOM_UNAVAILABLE/);
    assert.equal(seen.length,0);
  }));
test("the fixture transport refuses real-looking owner tokens, including credentials accidentally supplied",()=>
  withTlsServer({},async({port,seen})=>{
    const room=candidate("opaque-real-looking-bearer-xxxxxxxx");
    assert.throws(()=>probe({port,room}),/FIXTURE_ROOM_PLAN_REJECTED/);
    assert.equal(seen.length,0);
  }));
test("rejects malformed CA and ports before creating network sockets",()=>
  withTlsServer({},async({port,seen})=>{
    assert.throws(()=>probe({port,ca:"not-a-ca"}),/FIXTURE_CA_REQUIRED/);
    assert.throws(()=>probe({port:0}),/FIXTURE_PORT_INVALID/);
    assert.throws(()=>probe({port,timeoutMs:0}),/FIXTURE_TIMEOUT_INVALID/);
    assert.equal(seen.length,0);
  }));
