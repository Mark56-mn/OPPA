import "dart:async";

import "package:flutter/foundation.dart";

import "api_client_base.dart";
import "outbound_queue.dart";

enum AuthPhase {
  /// Initial value before bootstrap() settles. Renders a spinner for at most
  /// the (short) bootstrap duration — see the fail-closed contract below.
  unknown,
  signedOut,
  authenticated,

  /// Bootstrap could not decide (secure-storage error or read timeout).
  /// The app shows a visible error + Retry; it must never be silent.
  bootstrapFailed,
}

/// Real session lifecycle against the OPPA API (or the in-process demo
/// backend):
/// phone → OTP → (access, refresh, deviceId) → refresh rotation → logout.
class SessionStore {
  SessionStore({
    required this.api,
    required this.tokens,
    this.bootstrapTimeout = const Duration(seconds: 10),
  });

  final ApiClientBase api;
  final SecureTokenStore tokens;

  /// Upper bound for the secure-token probe during bootstrap. Generous for
  /// low-end devices / keystore cold starts; only an unexpected hang trips it.
  final Duration bootstrapTimeout;

  /// Human-readable startup failure when [AuthPhase.bootstrapFailed]. Never
  /// contains secrets — it is rendered directly in the retry UI.
  String? bootstrapError;

  Completer<void>? _bootstrapInFlight;
  bool _disposed = false;

  final _phaseController = StreamController<AuthPhase>.broadcast();
  AuthPhase _phase = AuthPhase.unknown;
  String? _refreshing;
  final _refreshWaiters = <Completer<bool>>[];

  AuthPhase get phase => _phase;
  Stream<AuthPhase> get stream => _phaseController.stream;

  /// True after OTP verify but before the profile name step completes.
  bool get awaitingProfileName => _awaitingProfile;
  bool _awaitingProfile = false;

  /// Startup diagnostics — phase transitions and coarse storage outcomes
  /// only. Printed via debugPrint so `adb logcat -s flutter` captures them on
  /// a device. NEVER logs tokens, phone numbers, or any other secret.
  void _log(String message) => debugPrint("OPPA.session: $message");

  /// Fail-closed startup: resolves AuthPhase.unknown exactly once.
  ///
  /// unknown → bootstrap → signedOut (no stored session)
  ///                     → authenticated (stored session)
  ///                     → bootstrapFailed (visible error; retry re-runs this)
  ///
  /// Guarantees (added after the first APK hung on the auth spinner forever):
  /// - can never hang: the secure-token read is bounded by [bootstrapTimeout];
  /// - can never silently authenticate: an unexpected failure goes to a
  ///   VISIBLE bootstrapFailed state with a Retry action, never signedIn;
  /// - concurrent callers share one bootstrap; a completed/failed bootstrap
  ///   can be re-run by calling bootstrap() again (used by the Retry button).
  Future<void> bootstrap() {
    final inFlight = _bootstrapInFlight;
    if (inFlight != null) return inFlight.future;
    final completer = Completer<void>();
    _bootstrapInFlight = completer;
    return _doBootstrap().whenComplete(() {
      _bootstrapInFlight = null;
      completer.complete();
    });
  }

  Future<void> _doBootstrap() async {
    _log("bootstrap: start");
    try {
      final refresh = await tokens
          .refreshToken()
          .timeout(bootstrapTimeout,
              onTimeout: () => throw TimeoutException(
                  "SecureTokenStore.refreshToken did not settle"));
      _log("bootstrap: refresh token read done (present=${refresh != null})");
      _setPhase(refresh == null ? AuthPhase.signedOut : AuthPhase.authenticated);
    } catch (error) {
      // Fail closed: visible error + retry — never a permanent spinner and
      // never a silent authentication. Common causes: platform keystore
      // failure, missing secure-storage platform channel, or a hang above.
      bootstrapError = error is TimeoutException
          ? "Secure storage did not respond during startup."
          : "Secure storage is unavailable on this device.";
      _log("bootstrap: failed — switching to visible retry UI ($error)");
      _setPhase(AuthPhase.bootstrapFailed);
    }
  }

  /// Onboarding final step: save the display name (voice-dictated or typed)
/// through the real profile API, then enter the app. Skipping keeps the
/// account valid — the name can be added later in Me → Profile.
  Future<void> completeOnboarding({String? displayName}) async {
    if (displayName != null && displayName.isNotEmpty) {
      final response = await api.patch("/profile", body: {
        "displayName": displayName,
      });
      // A failed name save must not lock the user out of the app they just
      // verified into: surface nothing fatal, continue to Home.
      if (!response.isSuccess) {
        // The name was not saved; Home's profile screen still allows saving it.
        _awaitingProfile = true;
      }
    }
    // Onboarding finished (saved, skipped, or save failed non-fatally): the
    // personal shell may now take over.
    _awaitingProfile = false;
    _setPhase(AuthPhase.authenticated);
  }

  Future<ApiResponse> requestOtp(String phone) =>
      api.post("/auth/otp/request", body: {"phone": phone});

  Future<ApiResponse> verifyOtp(String phone, String code, String devicePublicKeyPem) async {
    final response = await api.post("/auth/otp/verify", body: {
      "phone": phone,
      "code": code,
      "deviceId": devicePublicKeyPem,
    });
    if (response.isSuccess && response.body is Map) {
      final body = response.body as Map;
      final access = body["accessToken"];
      final refresh = body["refreshToken"];
      final deviceId = body["deviceId"];
      if (access is String && refresh is String && deviceId is String) {
        // Server returns the enrolled device ROW id; the public key PEM is the
        // stable local identity we enrolled with.
        await tokens.save(accessToken: access, refreshToken: refresh, deviceId: deviceId);
        await tokens.devicePublicKey(devicePublicKeyPem);
        // The session is live, but onboarding (the voice/typed name step in
        // AuthGate) is still pending — the shell must not swap in until it
        // completes or is explicitly skipped.
        _awaitingProfile = true;
        _setPhase(AuthPhase.authenticated);
      }
    }
    return response;
  }

  /// Rotates the refresh token. Concurrent callers share one rotation.
  Future<bool> refreshSession() async {
    final inFlight = _refreshing;
    if (inFlight != null) {
      final completer = Completer<bool>();
      _refreshWaiters.add(completer);
      return completer.future;
    }
    _refreshing = "in-flight";
    try {
      final refresh = await tokens.refreshToken();
      if (refresh == null) {
        _completeWaiters(false);
        return false;
      }
      final response = await api.post("/auth/refresh", body: {"refreshToken": refresh});
      if (response.isSuccess && response.body is Map) {
        final body = response.body as Map;
        final access = body["accessToken"];
        final newRefresh = body["refreshToken"];
        final deviceId = await tokens.deviceId();
        if (access is String && newRefresh is String && deviceId != null) {
          await tokens.save(accessToken: access, refreshToken: newRefresh, deviceId: deviceId);
          _completeWaiters(true);
          return true;
        }
      }
      // Refresh rejected: refresh-token replay or expiry — sign out locally.
      await signOut();
      _completeWaiters(false);
      return false;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> signOut() async {
    await tokens.clear();
    _awaitingProfile = false;
    _setPhase(AuthPhase.signedOut);
  }

  void _completeWaiters(bool ok) {
    for (final c in _refreshWaiters) {
      if (!c.isCompleted) c.complete(ok);
    }
    _refreshWaiters.clear();
  }

  void _setPhase(AuthPhase p) {
    _phase = p;
    _log("phase → $p");
    if (!_disposed) _phaseController.add(p);
  }

  void dispose() {
    _disposed = true;
    _phaseController.close();
  }
}
