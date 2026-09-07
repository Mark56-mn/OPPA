import "dart:convert";
import "dart:math";
import "dart:typed_data";

import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:pointycastle/export.dart" as pc;
import "package:pointycastle/asn1.dart" as asn1;

/// Device key identity for security-core step-up (matches the backend exactly):
///
/// - Key: EC P-256 (prime256v1), the curve the server's DeviceProofService accepts.
/// - Enrollment: the SPKI PEM of the public key is sent as `deviceId` at OTP
///   verify; the server stores it via oppa_devices.device_public_key.
/// - Step-up proof: ECDSA-SHA256 over `${challenge}.${canonicalIntent}`,
///   DER-encoded signature, base64url-encoded. The server verifies with the
///   enrolled public key and rejects intent mismatches (intent binding).
///
/// Only the private scalar is persisted (secure storage). The public point is
/// re-derived from the domain generator on load, so rotation of the stored
/// scalar invalidates the enrolled identity rather than silently diverging.
class DeviceKeyManager {
  DeviceKeyManager({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _privKey = "oppa.device_private_key";

  pc.ECPrivateKey? _cachedPrivate;

  pc.ECDomainParameters get _domain => pc.ECDomainParameters("prime256v1");

  /// Loads or creates the device keypair. The private scalar never leaves the
  /// secure-storage-backed manager.
  Future<pc.ECPrivateKey> _privateKey() async {
    final cached = _cachedPrivate;
    if (cached != null) return cached;
    final domain = _domain;
    final existing = await _storage.read(key: _privKey);
    BigInt d;
    if (existing == null || existing.isEmpty) {
      // Real CSPRNG seeding: Fortuna is seeded from Random.secure() (OS
      // entropy), never from timestamps or counters — a predictable seed would
      // make the device key derivable by an attacker.
      final secureRandom = pc.FortunaRandom()
        ..seed(pc.KeyParameter(_fortunaSeed()));
      final generator = pc.ECKeyGenerator()
        ..init(pc.ParametersWithRandom(
            pc.ECKeyGeneratorParameters(domain), secureRandom));
      final pair = generator.generateKeyPair();
      d = (pair.privateKey as pc.ECPrivateKey).d!;
      await _storage.write(key: _privKey, value: d.toRadixString(16));
    } else {
      d = BigInt.parse(existing, radix: 16);
    }
    final key = pc.ECPrivateKey(d, domain);
    _cachedPrivate = key;
    return key;
  }

  Uint8List _fortunaSeed() {
    final seed = Uint8List(32); // Fortuna requires exactly 256 bits.
    final random = Random.secure();
    for (var i = 0; i < seed.length; i++) {
      seed[i] = random.nextInt(256);
    }
    return seed;
  }  /// SPKI PEM of the public key — the value sent as deviceId at enrollment.
  ///
  /// SubjectPublicKeyInfo ::= SEQUENCE { algorithm AlgorithmIdentifier,
  /// subjectPublicKey BIT STRING } per RFC 5480; the uncompressed point
  /// (0x04 || X || Y) is the BIT STRING content, prefixed by the 0x00 "no
  /// unused bits" octet.
  ///
  /// Encoded manually rather than via ASN1ObjectIdentifier: pointycastle's
  /// base-128 OID encoder emits multi-byte arcs in the wrong byte order
  /// (verified by test), which would corrupt the SPKI and fail server-side
  /// verification of every device key.
  Future<String> publicKeyPem() async {
    final priv = await _privateKey();
    final q = priv.parameters!.G * priv.d!;
    final pointBytes = q!.getEncoded(false);
    final algorithm = _derSequence([
      _derOid([1, 2, 840, 10045, 2, 1]), // id-ecPublicKey
      _derOid([1, 2, 840, 10045, 3, 1, 7]), // prime256v1
    ]);
    final spki = _derSequence([
      algorithm,
      _derTagged(0x03, Uint8List.fromList([0x00, ...pointBytes])), // BIT STRING
    ]);
    final b64 = base64Encode(spki);
    final lines = RegExp(".{1,64}").allMatches(b64).map((m) => m.group(0)).join("\n");
    return "-----BEGIN PUBLIC KEY-----\n$lines\n-----END PUBLIC KEY-----\n";
  }

  /// Minimal, correct DER: tag + length + value.
  static Uint8List _derTlv(int tag, List<int> content) {
    final lengthBytes = <int>[];
    var l = content.length;
    if (l < 0x80) {
      lengthBytes.add(l);
    } else {
      while (l > 0) {
        lengthBytes.insert(0, l & 0xff);
        l >>= 8;
      }
      lengthBytes.insert(0, 0x80 | lengthBytes.length);
    }
    return Uint8List.fromList([tag, ...lengthBytes, ...content]);
  }

  static Uint8List _derSequence(List<Uint8List> elements) =>
      _derTlv(0x30, elements.expand((e) => e).toList());

  static Uint8List _derOid(List<int> arcs) {
    final body = <int>[arcs[0] * 40 + arcs[1]];
    for (final arc in arcs.skip(2)) {
      if (arc < 0x80) {
        body.add(arc);
      } else {
        final bytes = <int>[];
        var v = arc;
        while (v > 0) {
          bytes.insert(0, v & 0x7f);
          v >>= 7;
        }
        for (var i = 0; i < bytes.length - 1; i++) {
          bytes[i] |= 0x80; // continuation bit on all but the last byte
        }
        body.addAll(bytes);
      }
    }
    return _derTlv(0x06, body);
  }

  static Uint8List _derTagged(int tag, List<int> content) => _derTlv(tag, content);

  /// Signs `${challenge}.${canonicalIntent}` with ECDSA-SHA256 (DER, b64url).
  Future<String> signStepUp({
    required String challenge,
    required String canonicalIntent,
  }) async {
    final priv = await _privateKey();
    final text = utf8.encode("$challenge.$canonicalIntent");
    final signer = pc.ECDSASigner(pc.SHA256Digest());
    signer.init(
      true,
      pc.ParametersWithRandom(
        pc.PrivateKeyParameter<pc.ECPrivateKey>(priv),
        pc.FortunaRandom()..seed(pc.KeyParameter(_fortunaSeed())),
      ),
    );
    final signature =
        signer.generateSignature(Uint8List.fromList(text)) as pc.ECSignature;
    // Node's createVerify("SHA256") expects a DER ECDSA signature:
    // SEQUENCE { r INTEGER, s INTEGER }.
    final der = asn1.ASN1Sequence(elements: [
      asn1.ASN1Integer(signature.r),
      asn1.ASN1Integer(signature.s),
    ]).encode();
    return base64Url.encode(der).replaceAll("=", "");
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
