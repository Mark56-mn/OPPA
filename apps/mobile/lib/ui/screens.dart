import "package:flutter/material.dart";

import "../core/connectivity_service.dart";
import "../core/outbound_queue.dart";
import "../core/session_store.dart";
import "../data/repositories.dart";
import "../design/oppa_themes.dart";
import "widgets/common.dart";
import "screens/call_screen.dart";
import "screens/chat_screens.dart";
import "screens/me_screens.dart";
import "screens/wallet_screens.dart";

export "screens/auth_gate.dart";

/// Bottom navigation shell matching the approved personal-app art:
///   Chats · Wallet · Calls · Me
/// Business is NOT a personal tab: it is a separate workspace opened through
/// the workspace switcher (one OPPA identity, Personal + Business workspaces,
/// no logout needed to switch).
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
    required this.business,
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
  final BusinessRepository business;
  final OppaThemeId themeId;
  final void Function(OppaThemeId) onThemeChanged;
  final Future<void> Function() onSignOut;

  void _openConversation(BuildContext context, Map conversation) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
            conversation: conversation,
            messages: messages,
            calls: calls,
            connectivity: connectivity)));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectState>(
      stream: connectivity.stream,
      builder: (context, _) {
        return DefaultTabController(
          length: 4,
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
                      ChatsScreen(
                        conversations: conversations,
                        connectivity: connectivity,
                        contacts: contacts,
                        profiles: profiles,
                        business: business,
                        messages: messages,
                        notifications: notifications,
                        session: session,
                        themeId: themeId,
                        onThemeChanged: onThemeChanged,
                        onOpenConversation: (c) => _openConversation(context, c),
                      ),
                      WalletScreen(
                          wallet: wallet,
                          session: session,
                          connectivity: connectivity),
                      CallsTabScreen(
                          calls: calls,
                          conversations: conversations,
                          connectivity: connectivity,
                          onOpenConversation: (c) => _openConversation(context, c)),
                      MeScreen(
                          session: session,
                          profiles: profiles,
                          notifications: notifications,
                          business: business,
                          connectivity: connectivity,
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
                Tab(icon: Icon(Icons.chat_bubble_outline), text: "Chats"),
                Tab(icon: Icon(Icons.account_balance_wallet_outlined), text: "Wallet"),
                Tab(icon: Icon(Icons.call_outlined), text: "Calls"),
                Tab(icon: Icon(Icons.person_outline), text: "Me"),
              ],
            ),
          ),
        );
      },
    );
  }
}
