import "package:flutter/material.dart";

import "../core/connectivity_service.dart";
import "../core/outbound_queue.dart";
import "../core/session_store.dart";
import "../data/repositories.dart";
import "../design/oppa_themes.dart";
import "screens/auth_gate.dart";
import "screens/chat_screens.dart";
import "screens/home_screens.dart";
import "screens/me_screens.dart";
import "screens/wallet_screens.dart";

export "screens/auth_gate.dart";

/// Bottom navigation shell implementing the V1 information architecture:
/// Home / Chats / Wallet / Business / Me — with Calls reachable from any chat,
/// Connect and Support from Home, theme and security from Me.
class HomeShell extends StatelessWidget {
  const HomeShell({
    super.key,
    required this.session,
    required this.connectivity,
    required this.queue,
    required this.profiles,
    required this.contacts,
    required this.conversations,
    required this.messages,
    required this.wallet,
    required this.calls,
    required this.notifications,
    required this.themeId,
    required this.onThemeChanged,
    required this.onSignOut,
  });

  final SessionStore session;
  final ConnectivityService connectivity;
  final OutboundQueue queue;
  final ProfileRepository profiles;
  final ContactsRepository contacts;
  final ConversationsRepository conversations;
  final MessagesRepository messages;
  final WalletRepository wallet;
  final CallsRepository calls;
  final NotificationsRepository notifications;
  final OppaThemeId themeId;
  final void Function(OppaThemeId) onThemeChanged;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectState>(
      stream: connectivity.stream,
      builder: (context, _) {
        return DefaultTabController(
          length: 5,
          child: Scaffold(
            body: StreamBuilder<int>(
              stream: queue.depthStream,
              builder: (context, depthSnap) => Column(
                children: [
                  StatusBanner(
                    state: switch (connectivity.state) {
                      ConnectState.online => "online",
                      ConnectState.reconnecting => "reconnecting",
                      ConnectState.offline => "offline",
                    },
                    pendingCount: depthSnap.data ?? 0,
                  ),
                  Expanded(
                    child: TabBarView(children: [
                      HomeScreen(
                        session: session,
                        wallet: wallet,
                        notifications: notifications,
                        connectivity: connectivity,
                        onOpenNotifications: () {},
                        onOpenSupport: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SupportScreen())),
                      ),
                      ChatsScreen(
                        conversations: conversations,
                        connectivity: connectivity,
                        onOpenConversation: (c) =>
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => ChatThreadScreen(
                                    conversation: c,
                                    messages: messages,
                                    calls: calls,
                                    connectivity: connectivity))),
                      ),
                      WalletScreen(
                          wallet: wallet,
                          session: session,
                          connectivity: connectivity),
                      BusinessScreen(connectivity: connectivity),
                      MeScreen(
                          session: session,
                          profiles: profiles,
                          themeId: themeId,
                          onThemeChanged: onThemeChanged,
                          onSignOut: onSignOut),
                    ]),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.home_outlined), text: "Home"),
                Tab(icon: Icon(Icons.chat_bubble_outline), text: "Chats"),
                Tab(icon: Icon(Icons.account_balance_wallet_outlined), text: "Wallet"),
                Tab(icon: Icon(Icons.storefront_outlined), text: "Business"),
                Tab(icon: Icon(Icons.person_outline), text: "Me"),
              ],
            ),
          ),
        );
      },
    );
  }
}
