import "package:flutter/material.dart";

import "../../core/connectivity_service.dart";
import "../../core/screen_data.dart";
import "../../data/repositories.dart";
import "../widgets/common.dart";

/// Notifications screen: full list, unread badge, mark one/all read and
/// per-category preferences (real API: GET /notifications, unread-count,
/// POST /notifications/read, GET/PUT /notifications/preferences).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.notifications,
    required this.connectivity,
  });

  final NotificationsRepository notifications;
  final ConnectivityService connectivity;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  dynamic _state = const ViewLoading();
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const ViewLoading());
    final source = ScreenDataSource<Map>(
      connectivity: widget.connectivity,
      fetch: widget.notifications.list,
      decode: (b) => (b as Map).cast<String, dynamic>(),
      cacheKey: "notifications.list",
    );
    final result = await source.load();
    if (!mounted) return;
    setState(() => _state = result);
    final count = await widget.notifications.unreadCount();
    if (!mounted) return;
    if (count.isSuccess && count.body is Map) {
      setState(() =>
          _unread = ((count.body as Map)["unread"] as num?)?.toInt() ?? 0);
    }
  }

  Future<void> _markRead(Map notification) async {
    final id = "${notification["id"] ?? ""}";
    if (id.isEmpty) return;
    await widget.notifications.markRead(id);
    if (mounted) _load();
  }

  Future<void> _markAllRead() async {
    await widget.notifications.markAllRead();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("All marked as read")));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        actions: [
          if (_unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text("Mark all read ($_unread)"),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: switch (_state) {
          ViewLoading() => const StateViews.loading(),
          ViewOffline() => const StateViews.empty(
              "Offline — notifications will load when you reconnect"),
          ViewError(:final message) => StateViews.error(message, onRetry: _load),
          ViewReady<Map>(:final data) => _list(theme, data),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  Widget _list(ThemeData theme, Map data) {
    final items = (data["notifications"] as List?) ?? const [];
    if (items.isEmpty) return const StateViews.empty("You're all caught up 🎉");
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final n = (items[i] as Map).cast<String, dynamic>();
        final payload = (n["payload"] as Map?)?.cast<String, dynamic>() ?? const {};
        final title = "${payload["title"] ?? n["title"] ?? "Notification"}";
        final body = "${payload["body"] ?? n["body"] ?? ""}";
        final category = "${payload["category"] ?? n["category"] ?? "system"}";
        final read = n["readAt"] != null;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: Icon(_categoryIcon(category),
                size: 20, color: theme.colorScheme.primary),
          ),
          title: Text(title,
              style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: read ? FontWeight.w400 : FontWeight.w600)),
          subtitle: body.isEmpty ? null : Text(body, maxLines: 2),
          trailing: read
              ? null
              : IconButton(
                  tooltip: "Mark as read",
                  icon: const Icon(Icons.done_all, size: 20),
                  onPressed: () => _markRead(n),
                ),
        );
      },
    );
  }

  IconData _categoryIcon(String category) => switch (category) {
        "message" => Icons.chat_bubble_outline,
        "wallet" => Icons.account_balance_wallet_outlined,
        "payment" => Icons.payments_outlined,
        "security" => Icons.security_outlined,
        "device" => Icons.phonelink_outlined,
        "business" => Icons.storefront_outlined,
        "support" => Icons.support_agent_outlined,
        _ => Icons.notifications_outlined,
      };
}
