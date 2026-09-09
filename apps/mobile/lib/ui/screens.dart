import "package:flutter/material.dart";

import "../core/connectivity_service.dart";
import "../core/outbound_queue.dart";
import "../core/session_store.dart";
import "../data/repositories.dart";
import "../design/oppa_themes.dart";
import "widgets/common.dart";
import "screens/business_app.dart";
import "screens/chat_screens.dart";
import "screens/home_screens.dart";
import "screens/me_screens.dart";
import "screens/notification_screens.dart";
import "screens/settings_screen.dart";
import "screens/translator_screen.dart";
import "screens/wallet_screens.dart";

export "screens/auth_gate.dart";

/// Bottom navigation shell implementing the V1 information architecture:
/// Personal workspace tabs — Home / Chats / Wallet / Me. Business is NOT a
/// personal tab: it is a separate workspace opened through the workspace
/// switcher (one OPPA identity, Personal + Business workspaces, no logout
/// needed to switch).
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
                      HomeScreen(
                        session: session,
                        wallet: wallet,
                        notifications: notifications,
                        contacts: contacts,
                        conversations: conversations,
                        business: business,
                        profiles: profiles,
                        connectivity: connectivity,
                        onOpenNotifications: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => NotificationsScreen(
                                    notifications: notifications,
                                    connectivity: connectivity))),
                        onOpenSupport: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SupportScreen())),
                        onOpenTranslator: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => TranslatorScreen(
                                    messages: messages))),
                        onOpenSettings: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => SettingsScreen(
                                    session: session,
                                    notifications: notifications,
                                    connectivity: connectivity,
                                    themeId: themeId,
                                    onThemeChanged: onThemeChanged))),
                        onOpenWorkspaceSwitcher: () => showWorkspaceSwitcher(
                            context,
                            session: session,
                            business: business,
                            connectivity: connectivity),
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
                Tab(icon: Icon(Icons.person_outline), text: "Me"),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Workspace switcher (required product architecture): one OPPA identity →
/// Personal workspace + zero or more Business workspaces. Shows
///   `Your Name — Personal`
///   `Business Name — Owner/Manager/Staff`
///   `+ Create a Business`
/// Switching never logs the user out; the Business workspace replaces the
/// navigation context until the user switches back.
Future<void> showWorkspaceSwitcher(
  BuildContext context, {
  required SessionStore session,
  required BusinessRepository business,
  required ConnectivityService connectivity,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _WorkspaceSwitcherSheet(
      business: business,
      session: session,
      connectivity: connectivity,
    ),
  );
}

class _WorkspaceSwitcherSheet extends StatefulWidget {
  const _WorkspaceSwitcherSheet({
    required this.business,
    required this.session,
    required this.connectivity,
  });

  final BusinessRepository business;
  final SessionStore session;
  final ConnectivityService connectivity;

  void openBusiness(BuildContext context, {required String id, required String name}) {
    Navigator.of(context).pop();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BusinessApp(
          session: session,
          business: business,
          connectivity: connectivity,
          initialBusinessId: id,
          initialBusinessName: name,
        ),
      ),
    );
  }

  @override
  State<_WorkspaceSwitcherSheet> createState() =>
      _WorkspaceSwitcherSheetState();
}

class _WorkspaceSwitcherSheetState extends State<_WorkspaceSwitcherSheet> {
  List<Map> _businesses = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await widget.business.listMine();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _businesses = r.isSuccess
          ? (((r.body as Map?)?["businesses"] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList()
          : const [];
      if (!r.isSuccess) _error = r.errorCode;
    });
  }

  Future<void> _createBusiness() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text("Create a business"),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
            decoration: const InputDecoration(
                hintText: "e.g. Mama's Kitchen",
                helperText: "You can change details later"),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel")),
            FilledButton(
                onPressed: () {
                  final v = controller.text.trim();
                  if (v.isEmpty) return;
                  Navigator.pop(context, v);
                },
                child: const Text("Create")),
          ],
        );
      },
    );
    if (name == null || !mounted) return;
    final r = await widget.business.create(name: name);
    if (!mounted) return;
    if (r.isSuccess) {
      widget.openBusiness(context,
          id: "${(r.body as Map)["id"] ?? ""}", name: name);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.errorCode ?? "Could not create the business")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Switch workspace",
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text("Your Personal and Business spaces stay separate.",
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text("Personal"),
                subtitle: const Text("Chats, wallet, calls, settings"),
                trailing: const Icon(Icons.check, color: Colors.green),
                onTap: () => Navigator.pop(context),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  StateViews.error(_error!, onRetry: _load),
                ]),
              ),
            for (final b in _businesses)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text("${b["name"] ?? "Business"}"),
                  subtitle: const Text("Business workspace"),
                  onTap: () => widget.openBusiness(context,
                      id: "${b["id"] ?? ""}",
                      name: "${b["name"] ?? "Business"}"),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _createBusiness,
              icon: const Icon(Icons.add_business),
              label: const Text("Create a Business"),
            ),
          ],
        ),
      ),
    );
  }
}
