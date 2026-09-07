// Cross-runtime proof of the mobile device-key contract: the exact encodings
// the Flutter DeviceKeyManager emits (RFC 5480 SPKI PEM enrollment + DER
// ECDSA-SHA256 step-up signature over `${challenge}.${canonicalIntent}`) must
// verify with the server's own primitives — Node's createVerify("SHA256")
// with the SPKI public key, exactly as apps/api DeviceProofService does.
//
// The Dart side (pointycastle ECDSA + manual DER) is asserted byte-for-byte by
// apps/mobile/test/crypto_contract_test.dart; this script closes the loop in
// the backend's runtime so an enrolled app key would pass server verification.
const { webcrypto, createVerify, createPublicKey } = require("node:crypto");

// The backend's accepted algorithm/curve OIDs (RFC 5480).
const OID_EC_PUBLIC_KEY = "06 07 2A 86 48 CE 3D 02 01"; // id-ecPublicKey
const OID_PRIME256V1 = "06 08 2A 86 48 CE 3D 03 01 07"; // prime256v1

const hexPairs = (buf) => buf.toString("hex").toUpperCase().match(/../g).join(" ");

// Generate an EC P-256 pair and export the public key as an SPKI PEM using the
// same layout the Dart manager emits (64-char base64 lines, uncompressed point).
async function generateSpkiPem() {
  const pair = await webcrypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const spki = Buffer.from(await webcrypto.subtle.exportKey("spki", pair.publicKey));
  const b64 = spki.toString("base64").replace(/(.{64})/g, "$1\n");
  return {
    privateKey: pair.privateKey,
    pem: `-----BEGIN PUBLIC KEY-----\n${b64}\n-----END PUBLIC KEY-----\n`,
  };
}

// Parse the SPKI PEM back to DER, asserting the exact algorithm/curve OIDs the
// server expects, and import it as a Node KeyObject (server-side equivalent).
function parseSpkiPem(pem) {
  const der = Buffer.from(pem.split("\n").filter((l) => l && !l.startsWith("-----")).join(""), "base64");
  if (der[0] !== 0x30) throw new Error("SPKI must be a DER SEQUENCE");
  // SPKI layout: [0]=0x30 [1]=len [2]=0x30 [3]=alg-len [4]=0x06 [5]=oid-len ...
  const algOidLen = der[5];
  const oidAlg = hexPairs(der.subarray(4, 4 + 2 + algOidLen));
  if (oidAlg !== OID_EC_PUBLIC_KEY) throw new Error(`wrong algorithm OID: ${oidAlg}`);
  const curveTlv = der.subarray(4 + 2 + algOidLen);
  if (curveTlv[0] !== 0x06) throw new Error("curve parameter is not an OID");
  const oidCurve = hexPairs(curveTlv.subarray(0, 2 + curveTlv[1]));
  if (oidCurve !== OID_PRIME256V1) throw new Error(`wrong curve OID: ${oidCurve}`);
  return createPublicKey({ key: der, format: "der", type: "spki" });
}

// ECDSA P-256 signature over SHA-256; raw output is IEEE P1363 (r||s).
async function signMessage(privateKey, message) {
  return Buffer.from(await webcrypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, privateKey, message));
}

// Convert raw (r||s) to DER SEQUENCE{INTEGER r, INTEGER s} — the encoding the
// mobile client emits via pointycastle's ASN1 encoder.
function rawSignatureToDer(raw) {
  const half = raw.length / 2;
  const integerTlv = (b) => {
    if (b[0] & 0x80) b = Buffer.concat([Buffer.from([0x00]), b]); // keep positive
    return Buffer.concat([Buffer.from([0x02, b.length]), b]);
  };
  const r = integerTlv(raw.subarray(0, half));
  const s = integerTlv(raw.subarray(half));
  const body = Buffer.concat([r, s]);
  return Buffer.concat([Buffer.from([0x30, body.length]), body]);
}

async function main() {
  // 1. Enrollment: the SPKI PEM must carry exactly the server-accepted OIDs.
  const { privateKey, pem } = await generateSpkiPem();
  const serverPublicKey = parseSpkiPem(pem);

  // 2. Step-up message: `${challenge}.${canonicalIntent}` (server's signedText).
  const challenge = "test-challenge-123";
  const canonicalIntent = '{"amountMinor":2500,"currency":"NGN","reference":"t-9","toUserId":"user-9"}';
  const message = Buffer.from(`${challenge}.${canonicalIntent}`, "utf8");

  // 3. Sign, then verify through the server's primitive with the enrolled key.
  const rawSig = await signMessage(privateKey, message);
  const derSig = rawSignatureToDer(rawSig);
  if (derSig[0] !== 0x30 || derSig[2] !== 0x02) {
    throw new Error("converted signature is not DER SEQUENCE{r,s}");
  }
  const verifier = createVerify("SHA256");
  verifier.update(message);
  verifier.end();
  const verified = verifier.verify({ key: serverPublicKey, dsaEncoding: "der" }, derSig);
  if (!verified) throw new Error("DER signature failed createVerify('SHA256') verification");

  // 4. Round-trip report for the handoff.
  const messageDigest = Buffer.from(await webcrypto.subtle.digest("SHA-256", message)).toString("hex");
  console.log(JSON.stringify({
    ok: true,
    contract: {
      curve: "P-256 (prime256v1)",
      algorithmOid: OID_EC_PUBLIC_KEY,
      curveOid: OID_PRIME256V1,
      signedText: "challenge.canonicalIntent",
      hash: "SHA-256",
      signatureEncoding: "DER SEQUENCE{r,s}",
      keyEnrollment: "SPKI PEM",
    },
    checks: {
      spkiPemParsedWithServerOids: true,
      derSignatureVerifiedByCreateVerify: verified,
    },
    spkiDerBytes: pem.split("\n").filter((l) => l && !l.startsWith("-----")).join("").length,
    messageSha256: messageDigest,
  }));
}

main().then(
  () => process.exit(0),
  (err) => {
    console.error("device-key contract verification failed:", err.message);
    process.exit(1);
  },
);
