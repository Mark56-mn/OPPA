import "dart:async";

import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

import "core/api_client.dart";
import "core/connectivity_service.dart";
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
  late final ApiClient api;
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
  OppaThemeId themeId = OppaThemeId.fluidAfrica;
  StreamSubscription<ConnectState>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    api = ApiClient(
      baseUrl: widget.baseUrl,
      accessTokenGetter: () async => tokenStore.accessToken(),
      onAuthError: () => session.refreshSession(),
    );
    tokenStore = SecureTokenStore();
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
    return MaterialApp(
      title: "OPPA",
      theme: buildOppaTheme(oppaTokens[themeId]!, brightness: Brightness.dark),
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
  }
}
