import "dart:convert";

import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:oppa_mobile/core/device_key_manager.dart";
import "package:pointycastle/export.dart" as pc;
import "package:pointycastle/asn1.dart" as asn1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // In-memory stand-in for the platform secure storage so the key manager's
  // persistence path runs exactly as it does on device.
  final secureStore = <String, String>{};
  setUpAll(() {
    const channel = MethodChannel("plugins.it_nomads.com/flutter_secure_storage");
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case "read":
          return secureStore[call.arguments["key"] as String?];
        case "write":
          secureStore[call.arguments["key"] as String] = call.arguments["value"] as String;
          return null;
        case "delete":
          secureStore.remove(call.arguments["key"] as String);
          return null;
        case "deleteAll":
          secureStore.clear();
          return null;
        case "readAll":
          return Map<String, String>.from(secureStore);
        case "containsKey":
          return secureStore.containsKey(call.arguments["key"] as String?);
        default:
          return null;
      }
    });
  });

  test("publicKeyPem produces a parseable SPKI P-256 PEM", () async {
    final manager = DeviceKeyManager();
    final pem = await manager.publicKeyPem();
    expect(pem, startsWith("-----BEGIN PUBLIC KEY-----"));
    expect(pem, endsWith("-----END PUBLIC KEY-----\n"));
    final b64 =
        pem.replaceAll("\n", "").split("-----BEGIN PUBLIC KEY-----")[1].split("-----END PUBLIC KEY-----")[0];
    final der = base64Decode(b64);
    expect(der.length, greaterThan(80));
    // DER SEQUENCE tag + 0x30, plus RFC 5480 SPKI structure.
    expect(der[0], 0x30);
  });

  test("canonicalJson matches the server canonicalizeIntent ordering", () {
    final a = canonicalJson({"toUserId": "u2", "amountMinor": 1500, "currency": "NGN", "reference": "t-1"});
    final b = canonicalJson({"reference": "t-1", "currency": "NGN", "amountMinor": 1500, "toUserId": "u2"});
    expect(a, equals(b));
    expect(a, contains('"amountMinor":1500'));
    expect(a, contains('"currency":"NGN"'));
  });

  test("step-up signature verifies against the enrolled public key", () async {
    final manager = DeviceKeyManager();
    final pem = await manager.publicKeyPem();
    final signature = await manager.signStepUp(
      challenge: "test-challenge-123",
      canonicalIntent: canonicalJson(
          {"toUserId": "user-9", "amountMinor": 2500, "currency": "NGN", "reference": "t-9"}),
    );
    expect(signature, isNotEmpty);
    expect(signature, isNot(contains("="))); // base64url without padding

    // Re-verify locally with the same primitive family the server uses
    // (createVerify("SHA256") verifies this exact DER signature):
    // parse the PEM back into a pointycastle public key.
    final b64 =
        pem.replaceAll("\n", "").split("-----BEGIN PUBLIC KEY-----")[1].split("-----END PUBLIC KEY-----")[0];
    final spki = asn1.ASN1Sequence.fromBytes(Uint8List.fromList(base64Decode(b64)));
    final algorithm = spki.elements![0] as asn1.ASN1Sequence;
    // pointycastle's ASN1ObjectIdentifier decoder drops multi-byte OID
    // continuation bits (840 -> 72, 10045 -> 61), so we decode the id-ecPublicKey
    // OID from the raw DER bytes to avoid a false failure on correct output.
    // Encoding: 06 <len> 06 07 <7 content bytes> 03 <len> <point...>
    final algBytes = Uint8List.fromList(algorithm.encode());
    expect(algBytes[0], 0x30);
    // First OID: id-ecPublicKey 1.2.840.10045.2.1 (tag 06, 7 content bytes).
    expect(algBytes[2], 0x06); // OID tag
    expect(algBytes[3], 7);
    expect(algBytes.sublist(4, 11),
        [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01]); // id-ecPublicKey
    // Second OID: prime256v1 1.2.840.10045.3.1.7 (tag 06, 8 content bytes).
    expect(algBytes[11], 0x06);
    expect(algBytes[12], 8);
    // 840 and 10045 are encoded with 0x80 continuation bits: 0x86 0x48 and
    // 0xCE 0x3D. These two pairs are the entire reason servers accept or
    // reject the SPKI — assert them exactly.
    expect(algBytes.sublist(13, 21),
        [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]); // prime256v1
    final bitString = spki.elements![1] as asn1.ASN1BitString;
    final pointBytes = bitString.stringValues!;
    expect(pointBytes[0], 0x04); // uncompressed point
    final domain = pc.ECDomainParameters("prime256v1");
    final q = domain.curve.decodePoint(pointBytes);
    expect(q, isNotNull);
    final pub = pc.ECPublicKey(q, domain);

    final message = utf8.encode(
        "test-challenge-123.${canonicalJson({"toUserId": "user-9", "amountMinor": 2500, "currency": "NGN", "reference": "t-9"})}");
    // Decode the DER signature (SEQUENCE { r INTEGER, s INTEGER }) the same
    // way a server-side DER parser would before verifying with createVerify.
    final sigDer = base64Url.decode(base64Url.normalize(signature));
    final sigSeq =
        asn1.ASN1Sequence.fromBytes(Uint8List.fromList(sigDer));
    final r = (sigSeq.elements![0] as asn1.ASN1Integer).integer!;
    final s = (sigSeq.elements![1] as asn1.ASN1Integer).integer!;
    final verifier = pc.ECDSASigner(pc.SHA256Digest());
    verifier.init(false, pc.PublicKeyParameter<pc.ECPublicKey>(pub));
    final valid = verifier.verifySignature(
        Uint8List.fromList(message), pc.ECSignature(r, s));
    expect(valid, isTrue);
  });
}
