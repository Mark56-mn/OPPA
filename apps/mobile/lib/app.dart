import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:shared_preferences/shared_preferences.dart";

import "core/api_client.dart";
import "core/api_client_base.dart";
import "core/connectivity_service.dart";
import "core/demo_backend.dart";
import "core/demo_mode.dart";
import "core/outbound_queue.dart";
import "core/screen_data.dart";
import "core/session_store.dart";
import "data/repositories.dart";
import "design/oppa_themes.dart";
import "ui/screens.dart";

/// Composition root: wires the real API client, session lifecycle,
/// connectivity, durable outbound queue and repositories into the widget tree.
class OppaApp extends StatefulWidget {
  const OppaApp({
    super.key,
    required this.baseUrl,
    this.prefs,
    this.apiForTesting,
  });

  final String baseUrl;
  final SharedPreferences? prefs;

  /// Test-only transport override (constructor injection, not a runtime
  /// switch): main.dart never passes it, so production/demo selection remains
  /// purely compile-time. Used by startup/flow widget tests to run the full
  /// UI against an in-process backend instead of the network.
  final ApiClientBase? apiForTesting;

  @override
  State<OppaApp> createState() => _OppaAppState();
}

class _OppaAppState extends State<OppaApp> {
  late final ApiClientBase api;
  late final SecureTokenStore tokenStore;
  late final SessionStore session;
  late final ConnectivityService connectivity;
  late final OutboundQueue queue;
  late final ProfileRepository profiles;
  late final ContactsRepository contacts;
  late final ConversationsRepository conversations;
  late final MessagesRepository messages;
  late final WalletRepository wallet;
  late final CallsRepository calls;
  late final NotificationsRepository notifications;
  late final BusinessRepository business;
  OppaThemeId themeId = OppaThemeId.fluidAfrica;
  StreamSubscription<ConnectState>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    // The platform FlutterSecureStorage. Passing it explicitly is REQUIRED:
    // a null store makes every SecureTokenStore call throw StateError, which
    // used to leave bootstrap() stuck in AuthPhase.unknown forever — the first
    // APK hung on the startup spinner for exactly this reason.
    tokenStore = SecureTokenStore(storage: const FlutterSecureStorage());
    // Single injection point for demo vs production data layer. DemoMode is
    // compile-time; nothing at runtime can flip it (see demo_mode.dart).
    if (widget.apiForTesting != null) {
      api = widget.apiForTesting!;
    } else if (DemoMode.enabled) {
      api = DemoBackend();
    } else {
      api = ApiClient(
        baseUrl: widget.baseUrl,
        accessTokenGetter: () async => tokenStore.accessToken(),
        onAuthError: () => session.refreshSession(),
      );
    }
    session = SessionStore(api: api, tokens: tokenStore);
    connectivity = ConnectivityService();
    queue = OutboundQueue(api: api, prefs: widget.prefs);
    profiles = ProfileRepository(api);
    contacts = ContactsRepository(api);
    conversations = ConversationsRepository(api);
    messages = MessagesRepository(api, queue);
    wallet = WalletRepository(api);
    calls = CallsRepository(api);
    notifications = NotificationsRepository(api);
    business = BusinessRepository(api);

    ScreenDataSource.setCacheWriter((key, value) async {
      await widget.prefs?.setString("cache.$key", value);
    });
    connectivity.onRestored(queue.onConnectivityRestored);
    _connectivitySub = connectivity.stream.listen((_) => setState(() {}));
    // Rebuild the shell when auth phase flips (login/logout).
    session.stream.listen((_) {
      if (mounted) setState(() {});
    });
    session.bootstrap();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    connectivity.dispose();
    queue.dispose();
    session.dispose();
    super.dispose();
  }

  /// Re-runs startup session detection (used by the bootstrap-failure retry
  /// button). Safe to call repeatedly: concurrent callers share one bootstrap.
  void _retryBootstrap() => session.bootstrap();

  void _setTheme(OppaThemeId id) => setState(() => themeId = id);

  @override
  Widget build(BuildContext context) {
    // Fail-closed production guard: a product (AOT) build must never boot with
    // demo mode compiled in. Blocks the entire app, not just auth.
    if (DemoMode.enabled && DemoMode.isProductBuild) {
      return MaterialApp(
        title: "OPPA",
        home: Scaffold(
          backgroundColor: const Color(0xFF2B0B0B),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "Configuration error: demo mode must not be enabled in "
                "release builds. Rebuild without OPPA_DEMO_MODE.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ),
      );
    }
    // Onboarding gate: a verified session whose name step is still pending
    // stays in AuthGate (profile step) until completeOnboarding() runs. A
    // restart with a stored token skips this (bootstrap never sets the flag).
    final onboardingPending =
        session.phase == AuthPhase.authenticated && session.awaitingProfileName;
    final app = MaterialApp(
      title: "OPPA",
      theme: buildOppaTheme(oppaTokens[themeId]!, brightness: Brightness.dark),
      builder: (context, child) {
        if (!DemoMode.enabled) return child ?? const SizedBox.shrink();
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  color: Colors.amber,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        DemoMode.bannerLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      home: onboardingPending
          ? AuthGate(
              session: session,
              themeId: themeId,
              onThemeChanged: _setTheme,
            )
          : session.phase == AuthPhase.authenticated
          ? HomeShell(
              session: session,
              connectivity: connectivity,
              queue: queue,
              profiles: profiles,
              contacts: contacts,
              conversations: conversations,
              messages: messages,
              wallet: wallet,
              calls: calls,
              notifications: notifications,
              business: business,
              themeId: themeId,
              onThemeChanged: _setTheme,
              onSignOut: () async {
                await session.signOut();
                if (mounted) setState(() {});
              },
            )
          : session.phase == AuthPhase.signedOut
              ? AuthGate(
                  session: session,
                  themeId: themeId,
                  onThemeChanged: _setTheme,
                )
              : session.phase == AuthPhase.bootstrapFailed
                  // Fail-closed startup: a visible error + retry. Never a
                  // permanent spinner, never a silent authentication.
                  ? _BootstrapErrorView(
                      message: session.bootstrapError,
                      demo: DemoMode.enabled,
                      onRetry: _retryBootstrap,
                    )
                  // AuthPhase.unknown: only while bootstrap() is in flight
                  // (bounded by SessionStore.bootstrapTimeout).
                  : const Scaffold(
                      body: Center(child: CircularProgressIndicator())),
    );
    return app;
  }
}

/// Fail-closed startup error: shown only when bootstrap could not decide the
/// auth phase (secure-storage failure/timeout). Deliberately NOT a silent
/// authentication path — the user retries, which re-runs bootstrap.
class _BootstrapErrorView extends StatelessWidget {
  const _BootstrapErrorView({
    required this.message,
    required this.demo,
    required this.onRetry,
  });

  final String? message;
  final bool demo;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                message ?? "Startup failed unexpectedly.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                demo
                    ? "Demo build: stored demo sessions live in device secure "
                        "storage; retrying re-runs startup detection."
                    : "Your stored session could not be read. Retrying is safe "
                        "— worst case you sign in again with your phone.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.7),
                    ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text("Retry"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
