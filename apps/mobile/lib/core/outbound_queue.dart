import "dart:async";
import "dart:convert";
import "dart:math";

import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:shared_preferences/shared_preferences.dart";

import "api_client.dart";
import "api_client_base.dart";

/// A queued, not-yet-confirmed mutation.
class PendingOp {
  final String id; // client-generated idempotency key
  final String kind; // "message.send" | "conversation.read"
  final String path;
  final Map<String, dynamic> body;
  final DateTime queuedAt;
  final int attempts;

  /// Durable delivery state — nothing is ever silently discarded:
  /// - pending: will be sent on the next flush window;
  /// - retrying: transient failure, backoff in progress;
  /// - blocked: the server rejected this op (4xx). The message is KEPT so
  ///   the user can edit/retry/delete it; it is no longer auto-sent;
  /// - failed: retry budget exhausted. The message is KEPT and surfaced;
  ///   a manual retry resets attempts.
  final String state;
  static const statePending = "pending";
  static const stateRetrying = "retrying";
  static const stateBlocked = "blocked";
  static const stateFailed = "failed";

  PendingOp({
    required this.id,
    required this.kind,
    required this.path,
    required this.body,
    DateTime? queuedAt,
    this.attempts = 0,
    this.state = statePending,
  }) : queuedAt = queuedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        "id": id,
        "kind": kind,
        "path": path,
        "body": body,
        "queuedAt": queuedAt.toIso8601String(),
        "attempts": attempts,
        "state": state,
      };

  static PendingOp fromJson(Map<String, dynamic> j) => PendingOp(
        id: j["id"] as String,
        kind: j["kind"] as String,
        path: j["path"] as String,
        body: (j["body"] as Map).cast<String, dynamic>(),
        queuedAt: DateTime.parse(j["queuedAt"] as String),
        attempts: (j["attempts"] as num?)?.toInt() ?? 0,
        state: (j["state"] as String?) ?? statePending,
      );
}

/// Result of flushing one pending op.
enum FlushResult { confirmed, failedPermanent, retryLater }

/// Durable outbound queue for offline-first messaging (Stage N, hardened).
///
/// LOSSLESS GUARANTEES (Stage 2 hardening):
/// - persists to device storage so pending work survives app restarts;
/// - flushes on reconnect and periodically with backoff;
/// - mutations carry client idempotency keys so server retries are safe;
/// - the queue NEVER silently drops messages: full-queue pressure keeps the
///   oldest op and reports full via [isFull] (enqueue rejects instead of
///   evicting), and exhausted retries / permanent rejections transition ops
///   to blocked/failed states where they remain inspectable and recoverable;
/// - financial operations NEVER use this queue (server must authorize
///   atomically while the user is present) — enforced by [enqueue].
class OutboundQueue {
  OutboundQueue({required this.api, SharedPreferences? prefs})
      : _prefs = prefs {
    _load();
  }

  final ApiClientBase api;
  SharedPreferences? _prefs;
  static const _storageKey = "oppa.outbound_queue.v1";
  static const _maxQueue = 200;
  static const _maxAttempts = 8;

  /// Ops currently eligible for automatic flushing (pending or retrying).
  static const _autoStates = {PendingOp.statePending, PendingOp.stateRetrying};

  final _items = <PendingOp>[];
  final _random = Random();
  Timer? _flushTimer;
  bool _flushing = false;

  /// Notifies listeners (UI) of queue-depth changes.
  final _controller = StreamController<int>.broadcast();
  Stream<int> get depthStream => _controller.stream;

  /// Auto-flushable ops (pending/retrying). Blocked/failed ops are retained
  /// but excluded from automatic delivery until the user acts.
  int get depth =>
      _items.where((o) => _autoStates.contains(o.state)).length;

  /// All retained ops including blocked/failed ones (for user recovery UI).
  List<PendingOp> get all => List.unmodifiable(_items);

  int get blockedCount =>
      _items.where((o) => o.state == PendingOp.stateBlocked).length;
  int get failedCount =>
      _items.where((o) => o.state == PendingOp.stateFailed).length;
  bool get isFull => _items.length >= _maxQueue;

  /// Ops the caller may enqueue: messaging mutations with server-safe
  /// idempotency keys. Financial transfers/payments are deliberately excluded.
  static const enqueueableKinds = {"message.send", "conversation.read"};

  /// Enqueues an op. Throws [StateError] when the queue is full — the caller
  /// must surface that to the user instead of silently evicting a pending
  /// message (no message loss under queue pressure).
  Future<void> enqueue(PendingOp op) async {
    if (!enqueueableKinds.contains(op.kind)) {
      throw ArgumentError("kind ${op.kind} is not safe for offline queueing");
    }
    if (isFull) {
      throw StateError("Outbound queue is full ($_maxQueue); deliver or clear blocked/failed ops first");
    }
    _items.add(op);
    await _persist();
    _notify();
    scheduleFlush(immediate: true);
  }

  /// User-driven retry: resets a blocked/failed op so it is auto-flushed again.
  Future<bool> retry(String id) async {
    final i = _items.indexWhere((o) => o.id == id);
    if (i < 0) return false;
    final op = _items[i];
    _items[i] = PendingOp(
      id: op.id, kind: op.kind, path: op.path, body: op.body,
      queuedAt: op.queuedAt, attempts: 0, state: PendingOp.statePending,
    );
    await _persist();
    _notify();
    scheduleFlush(immediate: true);
    return true;
  }

  /// Explicit user deletion of a blocked/failed op — the ONLY way an
  /// undelivered message leaves the queue.
  Future<bool> discard(String id) async {
    final before = _items.length;
    _items.removeWhere((o) => o.id == id);
    if (_items.length != before) {
      await _persist();
      _notify();
      return true;
    }
    return false;
  }

  /// Attempts every auto-flushable op in order. Confirmed ops are removed;
  /// permanent 4xx rejections transition to `blocked` (kept for user recovery);
  /// exhausted retries transition to `failed` (kept). Nothing is dropped.
  Future<int> flush() async {
    if (_flushing) return 0;
    if (!_items.any((o) => _autoStates.contains(o.state))) return 0;
    _flushing = true;
    var confirmed = 0;
    try {
      final snapshot = List<PendingOp>.from(_items);
      for (final op in snapshot) {
        if (!_autoStates.contains(op.state)) continue;
        final result = await _attemptOne(op);
        if (result == FlushResult.confirmed) {
          _items.removeWhere((p) => p.id == op.id);
          confirmed += 1;
        } else if (result == FlushResult.failedPermanent) {
          _replace(op, PendingOp.stateBlocked, op.attempts + 1);
        } else {
          final nextAttempts = op.attempts + 1;
          _replace(
            op,
            nextAttempts >= _maxAttempts ? PendingOp.stateFailed : PendingOp.stateRetrying,
            nextAttempts,
          );
        }
      }
      await _persist();
      _notify();
    } finally {
      _flushing = false;
    }
    return confirmed;
  }

  void _replace(PendingOp op, String state, int attempts) {
    final i = _items.indexWhere((p) => p.id == op.id);
    if (i < 0) return;
    _items[i] = PendingOp(
      id: op.id, kind: op.kind, path: op.path, body: op.body,
      queuedAt: op.queuedAt, attempts: attempts, state: state,
    );
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
    final hasAuto = _items.any((o) => _autoStates.contains(o.state));
    if (immediate && hasAuto) {
      _flushTimer = Timer(Duration.zero, () {
        flush().then((_) {
          if (_items.any((o) => _autoStates.contains(o.state))) {
            scheduleFlush(); // follow-up backoff cycle
          }
        });
      });
      return;
    }
    if (!hasAuto) return;
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

  void _notify() => _controller.add(depth);

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
