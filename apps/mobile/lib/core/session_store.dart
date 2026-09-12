import "dart:async";

import "api_client.dart";
import "api_client_base.dart";
import "outbound_queue.dart";

enum AuthPhase { unknown, signedOut, authenticated }

/// Real session lifecycle against the OPPA API:
/// phone → OTP → (access, refresh, deviceId) → refresh rotation → logout.
class SessionStore {
  SessionStore({required this.api, required this.tokens});

  final ApiClientBase api;
  final SecureTokenStore tokens;

  final _phaseController = StreamController<AuthPhase>.broadcast();
  AuthPhase _phase = AuthPhase.unknown;
  String? _refreshing;
  final _refreshWaiters = <Completer<bool>>[];

  AuthPhase get phase => _phase;
  Stream<AuthPhase> get stream => _phaseController.stream;

  /// True after OTP verify but before the profile name step completes.
  bool get awaitingProfileName => _awaitingProfile;
  bool _awaitingProfile = false;

  Future<void> bootstrap() async {
    final refresh = await tokens.refreshToken();
    _setPhase(refresh == null ? AuthPhase.signedOut : AuthPhase.authenticated);
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
    _phaseController.add(p);
  }

  void dispose() => _phaseController.close();
}
