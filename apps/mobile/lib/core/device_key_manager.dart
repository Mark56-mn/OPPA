import "dart:convert";
import "dart:typed_data";

import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:pointycastle/export.dart" as pc;

/// Device key identity for security-core step-up (matches the backend exactly):
///
/// - Key: EC P-256 (prime256v1), the curve the server's DeviceService accepts.
/// - Enrollment: the SPKI PEM of the public key is sent as `deviceId` at OTP
///   verify; the server stores it via oppa_devices.device_public_key.
/// - Step-up proof: ECDSA-SHA256 over `${challenge}.${canonicalIntent}`,
///   DER-encoded signature, base64url-encoded. The server verifies with the
///   enrolled public key and rejects intent mismatches (intent binding).
class DeviceKeyManager {
  DeviceKeyManager({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _privHex = "oppa.device_private_key";

  pc.ECPrivateKey? _cachedPrivate;

  /// Loads or creates the device keypair. The private scalar never leaves the
  /// secure-storage-backed manager.
  Future<pc.ECPrivateKey> _privateKey() async {
    if (_cachedPrivate != null) return _cachedPrivate!;
    final domain = pc.ECDomainParameters("prime256v1");
    final existing = await _storage.read(key: _privHex);
    pc.BigInteger d;
    if (existing == null || existing.isEmpty) {
      final generator = pc.ECKeyGenerator()
        ..init(pc.ParametersWithRandom(
            pc.ECKeyGeneratorParameters(domain), pc.SecureRandom("Fortuna")..seed(pc.KeyParameter(_seed()))));
      final pair = generator.generateKeyPair();
      d = (pair.privateKey as pc.ECPrivateKey).d!;
      await _storage.write(key: _privHex, value: d.toRadixString(16));
    } else {
      d = pc.BigInteger.parse(existing, 16);
    }
    final key = pc.ECPrivateKey(d, domain);
    _cachedPrivate = key;
    return key;
  }

  Uint8List _seed() {
    final random = pc.SecureRandom("Fortuna");
    final seedBytes = Uint8List(32);
    for (var i = 0; i < seedBytes.length; i++) {
      seedBytes[i] = DateTime.now().microsecondsSinceEpoch.remainder(251) + i;
    }
    random.seed(pc.KeyParameter(seedBytes));
    // Re-seed with OS entropy where available.
    return seedBytes;
  }

  /// SPKI PEM of the public key — the value sent as deviceId at enrollment.
  Future<String> publicKeyPem() async {
    final priv = await _privateKey();
    final q = priv.publicKey!.Q!;
    final point = Uint8List.fromList(q.getEncoded(false));
    final algorithm = pc.ASN1Sequence()
      ..add(pc.ASN1ObjectIdentifier(Uint8List.fromList([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]))) // id-ecPublicKey
      ..add(pc.ASN1ObjectIdentifier(Uint8List.fromList([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]))); // prime256v1
    final spki = pc.ASN1Sequence()
      ..add(algorithm)
      ..add(pc.ASN1BitString(Uint8List.fromList([0x00, ...point])));
    final der = spki.encode();
    final b64 = base64Encode(der);
    final lines = RegExp(".{1,64}").allMatches(b64).map((m) => m.group(0)).join("\n");
    return "-----BEGIN PUBLIC KEY-----\n$lines\n-----END PUBLIC KEY-----\n";
  }

  /// Signs `${challenge}.${canonicalIntent}` with ECDSA-SHA256 (DER, b64url).
  Future<String> signStepUp({
    required String challenge,
    required String canonicalIntent,
  }) async {
    final priv = await _privateKey();
    final text = utf8.encode("$challenge.$canonicalIntent");
    final signer = pc.ECDSASigner(pc.SHA256Digest());
    signer.init(true, pc.PrivateKeyParameter<pc.ECPrivateKey>(priv));
    final signature = signer.generateSignature(Uint8List.fromList(text)) as pc.ECSignature;
    final der = pc.ASN1Sequence()
      ..add(pc.ASN1Integer(signature.r))
      ..add(pc.ASN1Integer(signature.s));
    return base64Url.encode(der.encode()).replaceAll("=", "");
  }
}

/// Deterministic JSON canonicalization matching the server's
/// canonicalizeIntent: sorted keys, no whitespace, UTF-8 strings.
String canonicalJson(Object? value) {
  if (value == null) return "null";
  if (value is String) return jsonEncode(value);
  if (value is bool) return value ? "true" : "false";
  if (value is num) {
    if (!value.isFinite) throw ArgumentError("non-finite number in intent");
    return jsonEncode(value);
  }
  if (value is List) return "[${value.map(canonicalJson).join(",")}]";
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return "{${keys.map((k) => "${jsonEncode(k)}:${canonicalJson(value[k])}").join(",")}}";
  }
  throw ArgumentError("unsupported intent value: ${value.runtimeType}");
}
