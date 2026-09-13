import "dart:async";

import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart";
import "package:flutter_test/flutter_test.dart";

import "package:oppa_mobile/core/api_client_base.dart";
import "package:oppa_mobile/core/outbound_queue.dart";
import "package:oppa_mobile/core/session_store.dart";

/// Controllable in-memory FlutterSecureStorage platform for startup tests.
/// [gate] optionally blocks reads forever to exercise the bootstrap timeout.
class _StubSecurePlatform extends FlutterSecureStoragePlatform {
  _StubSecurePlatform(this.values);

  final Map<String, String> values;
  Completer<void>? gate;
  int readCalls = 0;

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    values.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    readCalls += 1;
    final g = gate;
    if (g != null) await g.future;
    return values[key];
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(values);

  @override
  Future<void> write({
    required String key,
    required String? value,
    required Map<String, String> options,
  }) async {
    values[key] = value ?? "";
  }
}

/// Minimal ApiClientBase: bootstrap never talks to the network, so any call
/// here is a bug — surface it loudly in the test failure.
class _NoNetworkApi implements ApiClientBase {
  @override
  Future<ApiResponse> get(String path, {Map<String, String>? query}) =>
      Future.error(StateError("bootstrap must not call the network"));

  @override
  Future<ApiResponse> post(String path, {Object? body}) =>
      Future.error(StateError("bootstrap must not call the network"));

  @override
  Future<ApiResponse> patch(String path, {Object? body}) =>
      Future.error(StateError("bootstrap must not call the network"));

  @override
  Future<ApiResponse> put(String path, {Object? body}) =>
      Future.error(StateError("bootstrap must not call the network"));

  @override
  Future<ApiResponse> delete(String path) =>
      Future.error(StateError("bootstrap must not call the network"));
}

void main() {
  late _StubSecurePlatform platform;

  setUp(() {
    platform = _StubSecurePlatform({});
    FlutterSecureStoragePlatform.instance = platform;
  });

  SessionStore makeSession({Duration? timeout}) => SessionStore(
        api: _NoNetworkApi(),
        tokens: SecureTokenStore(storage: const FlutterSecureStorage()),
        bootstrapTimeout: timeout ?? const Duration(seconds: 2),
      );

  test("fresh install (empty secure storage) → signedOut, never stuck", () async {
    final session = makeSession();
    final phases = <AuthPhase>[];
    session.stream.listen(phases.add);
    await session.bootstrap();
    // Broadcast events are delivered asynchronously — drain the loop.
    await Future<void>.delayed(Duration.zero);
    expect(session.phase, AuthPhase.signedOut);
    expect(phases.last, AuthPhase.signedOut);
    session.dispose();
  });

  test("stored refresh token (restart after login) → authenticated", () async {
    platform.values["oppa.refresh_token"] = "stored-refresh";
    final session = makeSession();
    await session.bootstrap();
    expect(session.phase, AuthPhase.authenticated);
    session.dispose();
  });

  test("secure-storage failure → bootstrapFailed (visible), never signedIn",
      () async {
    // Force the read itself to fail like a broken platform keystore.
    FlutterSecureStoragePlatform.instance = _ThrowingSecurePlatform();
    final session = makeSession();
    await session.bootstrap();
    expect(session.phase, AuthPhase.bootstrapFailed);
    expect(session.bootstrapError, isNotNull);
    // Fail-closed means fail VISIBLE, not silently authenticated.
    expect(session.phase, isNot(AuthPhase.authenticated));
    session.dispose();
  });

  test("hung secure-storage read → bootstrapFailed within the timeout",
      () async {
    platform.gate = Completer<void>(); // read never settles
    final session = makeSession(timeout: const Duration(milliseconds: 80));
    final watch = Stopwatch()..start();
    await session.bootstrap();
    watch.stop();
    expect(session.phase, AuthPhase.bootstrapFailed);
    expect(session.bootstrapError, contains("did not respond"));
    // The bounded timeout must actually bound the wait.
    expect(watch.elapsed.inSeconds, lessThan(5));
    session.dispose();
  });

  test("retry after bootstrapFailed re-runs bootstrap and recovers", () async {
    FlutterSecureStoragePlatform.instance = _ThrowingSecurePlatform();
    final session = makeSession();
    await session.bootstrap();
    expect(session.phase, AuthPhase.bootstrapFailed);

    // "Fix the device": a working storage with a stored session.
    platform.values["oppa.refresh_token"] = "recovered-refresh";
    FlutterSecureStoragePlatform.instance = platform;
    await session.bootstrap();
    expect(session.phase, AuthPhase.authenticated);
    session.dispose();
  });

  test("concurrent bootstrap callers share one run", () async {
    final session = makeSession();
    final phases = <AuthPhase>[];
    session.stream.listen(phases.add);
    final a = session.bootstrap();
    final b = session.bootstrap();
    await Future.wait([a, b]);
    await Future<void>.delayed(Duration.zero);
    expect(session.phase, AuthPhase.signedOut);
    // One run → exactly one phase transition.
    expect(phases.where((p) => p == AuthPhase.signedOut).length, 1);
    session.dispose();
  });

  test("bootstrap never calls the network (demo mode stays fully offline)",
      () async {
    final session = makeSession();
    await session.bootstrap();
    expect(session.phase, AuthPhase.signedOut);
    session.dispose();
  });

  test("default bootstrap timeout is generous (10s) for low-end devices",
      () async {
    final session = SessionStore(
      api: _NoNetworkApi(),
      tokens: SecureTokenStore(storage: const FlutterSecureStorage()),
    );
    expect(session.bootstrapTimeout, const Duration(seconds: 10));
    session.dispose();
  });
}

/// Platform fake whose every operation throws — models a broken keystore or
/// a missing platform channel on device.
class _ThrowingSecurePlatform extends FlutterSecureStoragePlatform {
  Never _fail() => throw StateError("secure storage unavailable");

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      _fail();

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) =>
      Future.error(_fail());

  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      Future.error(_fail());

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      _fail();

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      _fail();

  @override
  Future<void> write({
    required String key,
    required String? value,
    required Map<String, String> options,
  }) =>
      Future.error(_fail());
}
