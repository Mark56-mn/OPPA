import "package:flutter/material.dart";

import "../../core/connectivity_service.dart";
import "../../core/screen_data.dart";
import "../../core/session_store.dart";
import "../../data/repositories.dart";
import "../widgets/common.dart";

/// Home: balance snapshot, recent notifications and quick actions.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.session,
    required this.wallet,
    required this.notifications,
    required this.connectivity,
    required this.onOpenNotifications,
    required this.onOpenSupport,
  });

  final SessionStore session;
  final WalletRepository wallet;
  final NotificationsRepository notifications;
  final ConnectivityService connectivity;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenSupport;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ViewState _walletState = const ViewLoading();
  ViewState _notificationsState = const ViewLoading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _walletState = const ViewLoading());
    final walletSource = ScreenDataSource<Map>(
      connectivity: widget.connectivity,
      fetch: widget.wallet.overview,
      decode: (b) => (b as Map).cast<String, dynamic>(),
      cacheKey: "wallet.overview",
    );
    final notificationSource = ScreenDataSource<Map>(
      connectivity: widget.connectivity,
      fetch: widget.notifications.list,
      decode: (b) => (b as Map).cast<String, dynamic>(),
      cacheKey: "notifications.list",
    );
    final w = await walletSource.load();
    final n = await notificationSource.load();
    if (mounted) {
      setState(() {
        _walletState = w;
        _notificationsState = n;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unreadBadge = _notificationsState is ViewReady<Map>
        ? ((_notificationsState as ViewReady<Map>).data["unread"] as int? ?? 0)
        : 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text("OPPA"),
        actions: [
          IconButton(
            onPressed: widget.onOpenNotifications,
            icon: Badge(
              isLabelVisible: unreadBadge > 0,
              label: Text("$unreadBadge"),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _BalanceCard(state: _walletState, onRetry: _load),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SupportScreen())),
                    icon: const Icon(Icons.support_agent_outlined),
                    label: const Text("Support"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () {}, // Connect flow lives in ConnectScreen
                    icon: const Icon(Icons.person_add_alt_outlined),
                    label: const Text("Connect"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text("Recent activity", style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _NotificationPreview(state: _notificationsState),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.state, required this.onRetry});
  final ViewState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: switch (state) {
          ViewLoading() => const Center(child: CircularProgressIndicator()),
          ViewOffline() => const Column(children: [
              Icon(Icons.cloud_off),
              SizedBox(height: 8),
              Text("Wallet unavailable offline"),
            ]),
          ViewError(:final message) => Column(children: [
              Text(message),
              const SizedBox(height: 8),
              FilledButton(onPressed: onRetry, child: const Text("Retry")),
            ]),
          ViewReady<Map>(:final data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Wallet balance",
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 4),
                Text(
                  "₦ ${_formatMinor((data["balanceMinor"] as num?)?.toInt() ?? 0)}",
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  static String _formatMinor(int minor) {
    final naira = minor ~/ 100;
    final kobo = minor % 100;
    return "$naira.${kobo.toString().padLeft(2, "0")}";
  }
}

class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview({required this.state});
  final ViewState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      ViewLoading() => const StateViews.loading(),
      ViewOffline() => const StateViews.empty("Offline — notifications will load when you reconnect"),
      ViewError(:final message) => StateViews.error(message),
      ViewReady<Map>(:final data) =>
        ((((data["notifications"] as List?) ?? const []).isEmpty))
            ? const StateViews.empty("You're all caught up")
            : Column(
                children: [
                  for (final n in (data["notifications"] as List).take(5))
                    ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: Text("${((n as Map)["payload"] as Map?)?["title"] ?? "Notification"}"),
                      subtitle: Text("${((n)["payload"] as Map?)?["body"] ?? ""}"),
                    ),
                ],
              ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Support / report screen (support-reporting surface): contacts support,
/// abuse reporting entry points and safety information.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Support & Safety")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("Get help", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.mail_outline),
              title: Text("support@oppa.africa"),
              subtitle: Text("Replies within 24 hours"),
            ),
          ),
          const SizedBox(height: 24),
          Text("Safety", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.report_outlined),
              title: Text("Report a user"),
              subtitle: Text("Chats → contact menu → Report. Reports are confidential."),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.block_outlined),
              title: Text("Block a user"),
              subtitle: Text("Chats → contact menu → Block. Blocked users cannot message you."),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.verified_user_outlined),
              title: Text("Your security"),
              subtitle: Text(
                  "Sessions are device-bound. Revoke lost devices from Me → Security."),
            ),
          ),
          const SizedBox(height: 24),
          Text("Trust", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.payments_outlined),
              title: Text("Money safety"),
              subtitle: Text(
                  "Balances are held server-side. Transfers require device-verified step-up confirmation. OPPA never asks for your OTP."),
            ),
          ),
        ],
      ),
    );
  }
}
