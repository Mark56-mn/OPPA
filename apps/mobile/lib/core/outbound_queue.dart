import "dart:async";
import "dart:convert";
import "dart:math";

import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:shared_preferences/shared_preferences.dart";

import "api_client.dart";

/// A queued, not-yet-confirmed mutation.
class PendingOp {
  final String id; // client-generated idempotency key
  final String kind; // "message.send" | "conversation.read"
  final String path;
  final Map<String, dynamic> body;
  final DateTime queuedAt;
  final int attempts;
  PendingOp({
    required this.id,
    required this.kind,
    required this.path,
    required this.body,
    DateTime? queuedAt,
    this.attempts = 0,
  }) : queuedAt = queuedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        "id": id,
        "kind": kind,
        "path": path,
        "body": body,
        "queuedAt": queuedAt.toIso8601String(),
        "attempts": attempts,
      };

  static PendingOp fromJson(Map<String, dynamic> j) => PendingOp(
        id: j["id"] as String,
        kind: j["kind"] as String,
        path: j["path"] as String,
        body: (j["body"] as Map).cast<String, dynamic>(),
        queuedAt: DateTime.parse(j["queuedAt"] as String),
        attempts: (j["attempts"] as num?)?.toInt() ?? 0,
      );
}

/// Result of flushing one pending op.
enum FlushResult { confirmed, failedPermanent, retryLater }

/// Durable outbound queue for offline-first messaging (Stage N).
///
/// - persists to device storage so pending work survives app restarts;
/// - flushes on reconnect and periodically with backoff;
/// - mutations carry client idempotency keys so server retries are safe;
/// - financial operations NEVER use this queue (server must authorize
///   atomically while the user is present) — enforced by [enqueue].
class OutboundQueue {
  OutboundQueue({required this.api, SharedPreferences? prefs})
      : _prefs = prefs {
    _load();
  }

  final ApiClient api;
  SharedPreferences? _prefs;
  static const _storageKey = "oppa.outbound_queue.v1";
  static const _maxQueue = 200;
  static const _maxAttempts = 8;

  final _items = <PendingOp>[];
  final _random = Random();
  Timer? _flushTimer;
  bool _flushing = false;

  /// Notifies listeners (UI) of queue-depth changes.
  final _controller = StreamController<int>.broadcast();
  Stream<int> get depthStream => _controller.stream;
  int get depth => _items.length;

  /// Ops the caller may enqueue: messaging mutations with server-safe
  /// idempotency keys. Financial transfers/payments are deliberately excluded.
  static const enqueueableKinds = {"message.send", "conversation.read"};

  Future<void> enqueue(PendingOp op) async {
    if (!enqueueableKinds.contains(op.kind)) {
      throw ArgumentError("kind ${op.kind} is not safe for offline queueing");
    }
    if (_items.length >= _maxQueue) _items.removeAt(0);
    _items.add(op);
    await _persist();
    _notify();
    scheduleFlush(immediate: true);
  }

  /// Attempts every pending op in order. Confirmed ops are removed; permanent
  /// 4xx failures are dropped (server rejected them; retrying is pointless);
  /// network/5xx stay queued for the next window.
  Future<int> flush() async {
    if (_flushing || _items.isEmpty) return 0;
    _flushing = true;
    var confirmed = 0;
    try {
      final snapshot = List<PendingOp>.from(_items);
      for (final op in snapshot) {
        final result = await _attemptOne(op);
        if (result == FlushResult.confirmed) {
          _items.removeWhere((p) => p.id == op.id);
          confirmed += 1;
        } else if (result == FlushResult.failedPermanent) {
          _items.removeWhere((p) => p.id == op.id);
        } else {
          // retryLater: bump attempts; drop after too many to avoid rot.
          final bumped = PendingOp(
            id: op.id, kind: op.kind, path: op.path, body: op.body,
            queuedAt: op.queuedAt, attempts: op.attempts + 1,
          );
          _items.removeWhere((p) => p.id == op.id);
          if (bumped.attempts < _maxAttempts) _items.add(bumped);
        }
      }
      await _persist();
      _notify();
    } finally {
      _flushing = false;
    }
    return confirmed;
  }

  Future<FlushResult> _attemptOne(PendingOp op) async {
    final response = await api.post(op.path, body: op.body);
    switch (response.kind) {
      case AttemptKind.success:
        return FlushResult.confirmed;
      case AttemptKind.clientError:
        return FlushResult.failedPermanent;
      case AttemptKind.networkError:
      case AttemptKind.timeout:
      case AttemptKind.serverError:
        return FlushResult.retryLater;
    }
  }

  /// Schedules a flush: immediately on reconnect, otherwise with backoff.
  void scheduleFlush({bool immediate = false}) {
    _flushTimer?.cancel();
    if (immediate && _items.isNotEmpty) {
      _flushTimer = Timer(Duration.zero, () {
        flush().then((_) {
          if (_items.isNotEmpty) scheduleFlush(); // follow-up backoff cycle
        });
      });
      return;
    }
    if (_items.isEmpty) return;
    final delayMs = min(60000, 2000 * (1 << min(_items.length, 5)));
    _flushTimer = Timer(
      Duration(milliseconds: delayMs + _random.nextInt(1000)),
      () {
        flush().then((_) {
          if (_items.isNotEmpty) scheduleFlush();
        });
      },
    );
  }

  void onConnectivityRestored() => scheduleFlush(immediate: true);

  Future<void> _persist() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(
          _storageKey, jsonEncode(_items.map((e) => e.toJson()).toList()));
    } catch (_) {
      // Persistence failure must not crash the app; queue stays in memory.
    }
  }

  Future<void> _load() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_storageKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      _items
        ..clear()
        ..addAll(list.map((e) => PendingOp.fromJson((e as Map).cast<String, dynamic>())));
      _notify();
    } catch (_) {}
  }

  void _notify() => _controller.add(_items.length);

  void dispose() {
    _flushTimer?.cancel();
    _controller.close();
  }
}

/// Secure token storage: refresh + access tokens live in encrypted storage,
/// never in SharedPreferences, never in memory dumps beyond session lifetime.
class SecureTokenStore {
  SecureTokenStore({FlutterSecureStorage? storage}) : _storage = storage;
  final FlutterSecureStorage? _storage;

  static const _kRefresh = "oppa.refresh_token";
  static const _kAccess = "oppa.access_token";
  static const _kDeviceId = "oppa.device_id";
  static const _kDevicePublicKey = "oppa.device_public_key";

  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required String deviceId,
  }) async {
    final s = _require();
    await Future.wait([
      s.write(key: _kAccess, value: accessToken),
      s.write(key: _kRefresh, value: refreshToken),
      s.write(key: _kDeviceId, value: deviceId),
    ]);
  }

  Future<String?> accessToken() async => _require().read(key: _kAccess);
  Future<String?> refreshToken() async => _require().read(key: _kRefresh);
  /// The enrolled device ROW id (server-assigned), used in step-up proofs.
  Future<String?> deviceId() async => _require().read(key: _kDeviceId);
  /// The device public key PEM (client-generated identity), stored locally.
  Future<void> devicePublicKey(String pem) async =>
      _require().write(key: _kDevicePublicKey, value: pem);

  Future<void> clear() async {
    final s = _require();
    await Future.wait([
      s.delete(key: _kAccess),
      s.delete(key: _kRefresh),
      s.delete(key: _kDeviceId),
      s.delete(key: _kDevicePublicKey),
    ]);
  }

  FlutterSecureStorage _require() {
    final s = _storage;
    if (s == null) throw StateError("SecureTokenStore is not configured");
    return s;
  }
}
