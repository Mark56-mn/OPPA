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
    required this.contacts,
    required this.conversations,
    required this.business,
    required this.connectivity,
    required this.onOpenNotifications,
    required this.onOpenSupport,
  });

  final SessionStore session;
  final WalletRepository wallet;
  final NotificationsRepository notifications;
  final ContactsRepository contacts;
  final ConversationsRepository conversations;
  final BusinessRepository business;
  final ConnectivityService connectivity;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenSupport;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ViewState _walletState = const ViewLoading();
  ViewState _notificationsState = const ViewLoading();

  void _openConnect() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConnectScreen(
            contacts: widget.contacts,
            conversations: widget.conversations,
            business: widget.business)));
  }

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
                    onPressed: _openConnect,
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

/// Connect: find people by user id, add contacts, and manage them
/// (start chat, block, report). Server enforces all authorization.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    super.key,
    required this.contacts,
    required this.conversations,
    required this.business,
  });

  final ContactsRepository contacts;
  final ConversationsRepository conversations;
  final BusinessRepository business;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _addController = TextEditingController();
  List<Map> _contacts = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await widget.contacts.list();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.isSuccess) {
        _contacts = (((r.body as Map?)?["contacts"] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      } else {
        _error = r.errorCode ?? "Could not load contacts";
      }
    });
  }

  Future<void> _add() async {
    final userId = _addController.text.trim();
    if (userId.isEmpty) return;
    final r = await widget.contacts.add(userId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.isSuccess
            ? "Contact added"
            : (r.errorCode ?? "Could not add contact"))));
    if (r.isSuccess) {
      _addController.clear();
      _load();
    }
  }

  Future<void> _block(String userId) async {
    final r = await widget.contacts.block(userId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.isSuccess
            ? "User blocked"
            : (r.errorCode ?? "Could not block"))));
  }

  Future<void> _report(String userId) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text("Report user"),
          content: TextField(
            controller: controller,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: "What happened?"),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel")),
            FilledButton(
                onPressed: () {
                  if (controller.text.trim().isEmpty) return;
                  Navigator.pop(context, controller.text.trim());
                },
                child: const Text("Report")),
          ],
        );
      },
    );
    if (reason == null) return;
    final r = await widget.contacts.report(userId, reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.isSuccess
            ? "Report sent — our safety team will review"
            : (r.errorCode ?? "Could not send report"))));
  }

  Future<void> _startChat(String userId) async {
    final r = await widget.conversations.createDirect(userId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.isSuccess
            ? "Chat ready — find it under Chats"
            : (r.errorCode ?? "Could not start chat"))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Connect"),
        actions: [
          IconButton(
            tooltip: "Shop",
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ShopScreen(business: widget.business))),
            icon: const Icon(Icons.storefront_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addController,
                    decoration: const InputDecoration(
                        labelText: "Add by user id"),
                    maxLength: 128,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.person_add_alt_outlined),
                  label: const Text("Add"),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const StateViews.loading()
                : _error != null
                    ? StateViews.error(_error!, onRetry: _load)
                    : _contacts.isEmpty
                        ? const StateViews.empty(
                            "No contacts yet — add someone by their user id")
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              children: [
                                for (final c in _contacts)
                                  ListTile(
                                    leading: CircleAvatar(
                                        child: Text(_initial(
                                            "${c["displayName"] ?? c["userId"] ?? "?"}"))),
                                    title: Text(
                                        "${c["displayName"] ?? c["userId"] ?? "Unknown"}"),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (action) {
                                        final id = "${c["userId"] ?? ""}";
                                        if (action == "chat") _startChat(id);
                                        if (action == "block") _block(id);
                                        if (action == "report") _report(id);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: "chat", child: Text("Start chat")),
                                        PopupMenuItem(
                                            value: "block", child: Text("Block")),
                                        PopupMenuItem(
                                            value: "report",
                                            child: Text("Report")),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }  static String _initial(String s) =>
      s.isEmpty ? "?" : s.characters.first.toUpperCase();
}

/// Consumer shopping: browse a business's catalog, order and pay from the
/// OPPA wallet. The server derives the amount from product prices and blocks
/// self-ordering — the client cannot set prices or bypass the blocker.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.business});

  final BusinessRepository business;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _businessIdController = TextEditingController();
  List<Map> _products = const [];
  String? _businessId;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _businessIdController.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final id = _businessIdController.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await widget.business.listProducts(id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.isSuccess) {
        _businessId = id;
        _products = (((r.body as Map?)?["products"] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      } else {
        _error = r.errorCode ?? "Could not load that business";
      }
    });
  }

  Future<void> _orderAndPay(Map product) async {
    final businessId = _businessId;
    if (businessId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm order"),
        content: Text(
            "Order ${product["name"]} for ₦ ${((product["priceMinor"] as num? ?? 0) / 100).toStringAsFixed(2)}?\n\nPayment comes from your OPPA wallet."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Order and pay")),
        ],
      ),
    );
    if (confirmed != true) return;
    final reference = "shop-${DateTime.now().microsecondsSinceEpoch}";
    // 1. Place the order (server computes the amount from product prices).
    final placed = await widget.business.placeOrder(businessId, items: [
      {"productId": product["id"], "quantity": 1}
    ], customerOrderReference: reference);
    if (!mounted) return;
    if (!placed.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(placed.errorCode ?? "Could not place the order")));
      return;
    }
    final orderId =
        "${(placed.body as Map?)?["id"] ?? ""}";
    // 2. Pay from the wallet (server debits/credits atomically).
    final paid = await widget.business.payOrder(orderId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(paid.isSuccess
            ? "Order paid ✓"
            : (paid.errorCode == "WALLET_INSUFFICIENT_FUNDS"
                ? "Not enough wallet balance"
                : (paid.errorCode ?? "Payment failed")))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Shop")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _businessIdController,
                    decoration: const InputDecoration(
                        labelText: "Business id"),
                    maxLength: 64,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : _browse,
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text("Browse"),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          Expanded(
            child: _loading
                ? const StateViews.loading()
                : _businessId == null
                    ? const StateViews.empty(
                        "Enter a business id to browse its catalog")
                    : _products.isEmpty
                        ? const StateViews.empty("No products available")
                        : RefreshIndicator(
                            onRefresh: _browse,
                            child: ListView(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              children: [
                                for (final p in _products)
                                  Card(
                                    margin:
                                        const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: const Icon(
                                          Icons.inventory_2_outlined),
                                      title: Text("${p["name"] ?? "Product"}"),
                                      subtitle: Text(
                                          "₦ ${((p["priceMinor"] as num? ?? 0) / 100).toStringAsFixed(2)}"),
                                      trailing: FilledButton.tonal(
                                        onPressed: () => _orderAndPay(p),
                                        child: const Text("Buy"),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
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
