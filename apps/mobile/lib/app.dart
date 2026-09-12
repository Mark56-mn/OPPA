import "dart:async";

import "package:flutter/material.dart";
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
  const OppaApp({super.key, required this.baseUrl, this.prefs});

  final String baseUrl;
  final SharedPreferences? prefs;

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
    tokenStore = SecureTokenStore();
    // Single injection point for demo vs production data layer. DemoMode is
    // compile-time; nothing at runtime can flip it (see demo_mode.dart).
    if (DemoMode.enabled) {
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
    final app = MaterialApp(
      title: "OPPA",
      theme: buildOppaTheme(oppaTokens[themeId]!, brightness: Brightness.dark),
      builder: (context, child) {
        // Visible, honest development indicator across every demo screen.
        if (!DemoMode.enabled) return child ?? const SizedBox.shrink();
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  color: Colors.amber.shade700,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        DemoMode.bannerLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
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
      home: session.phase == AuthPhase.authenticated
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
              : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
    return app;
  }
}
