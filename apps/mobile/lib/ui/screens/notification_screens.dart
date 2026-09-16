import "package:flutter/material.dart";

import "../../core/connectivity_service.dart";
import "../../core/screen_data.dart";
import "../../core/session_store.dart";
import "../../data/repositories.dart";
import "../../design/oppa_themes.dart";
import "../widgets/common.dart";
import "settings_screen.dart";
import "workspace_switcher.dart";

/// Notifications screen (task §10): category filters, mark one/all read,
/// per-category preferences and tap-to-context routing — over the real API
/// (GET /notifications returns {notifications, unread}; POST /notifications/
/// read; GET/PUT /notifications/preferences with the same category set).
///
/// Locked by design: raw APNs/FCM push transport is not a V1 capability, so
/// the preferences sheet controls the server-side categories only and says so.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.notifications,
    required this.connectivity,
    this.session,
    this.business,
    this.themeId,
    this.onThemeChanged,
    this.onOpenConversation,
  });

  final NotificationsRepository notifications;
  final ConnectivityService connectivity;
  final SessionStore? session;
  final BusinessRepository? business;
  final OppaThemeId? themeId;
  final void Function(OppaThemeId)? onThemeChanged;
  final void Function(Map conversation)? onOpenConversation;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  dynamic _state = const ViewLoading();
  int _unread = 0;
  String? _loadedJson;
  String _filter = "all";

  static const _categories = <String, IconData>{
    "message": Icons.chat_bubble_outline,
    "wallet": Icons.account_balance_wallet_outlined,
    "payment": Icons.payments_outlined,
    "security": Icons.security_outlined,
    "device": Icons.phonelink_outlined,
    "business": Icons.storefront_outlined,
    "support": Icons.support_agent_outlined,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loadedJson == null) setState(() => _state = const ViewLoading());
    final source = ScreenDataSource<Map>(
      connectivity: widget.connectivity,
      fetch: widget.notifications.list,
      decode: (b) => (b as Map).cast<String, dynamic>(),
      cacheKey: "notifications.list",
    );
    final result = await source.load();
    if (!mounted) return;
    setState(() {
      _state = result;
      if (result is ViewReady<Map>) {
        _loadedJson = "";
        final d = result.data;
        _unread = (d["unread"] as num?)?.toInt() ?? _unread;
      }
    });
  }

  Future<void> _markRead(Map notification) async {
    final id = "${notification["id"] ?? ""}";
    if (id.isEmpty || notification["readAt"] != null) return;
    await widget.notifications.markRead(id);
    if (mounted) _load();
  }

  Future<void> _markAllRead() async {
    await widget.notifications.markAllRead();
    if (mounted) _load();
  }

  void _openContext(Map n) {
    // Best-effort tap-to-context; never navigates on unknown payloads.
    final payload = (n["payload"] as Map?)?.cast<String, dynamic>() ??
        (n["metadata"] as Map?)?.cast<String, dynamic>() ??
        const {};
    final conversationId = "${payload["conversationId"] ?? ""}";
    if (conversationId.isNotEmpty && widget.onOpenConversation != null) {
      final conv = <String, dynamic>{"id": conversationId};
      if (n["category"] == "message") conv["fromNotification"] = true;
      widget.onOpenConversation!(conv);
      return;
    }
    final category = "${n["category"] ?? payload["category"] ?? "system"}";
    if (category == "business" && widget.session != null && widget.business != null) {
      showWorkspaceSwitcher(context,
          session: widget.session!, business: widget.business!, connectivity: widget.connectivity);
      return;
    }
    if (category == "wallet" || category == "payment") {
      // Keep the user inside the personal shell; wallet state is only ever
      // shown from the server, so we route by tab index rather than
      // duplicating wallet screens here.
      final controller = DefaultTabController.maybeOf(context);
      if (controller != null) {
        controller.animateTo(1);
        Navigator.of(context).pop();
        return;
      }
    }
    if (category == "security" || category == "device") {
      final session = widget.session;
      final themeId = widget.themeId;
      final onThemeChanged = widget.onThemeChanged;
      if (session != null && themeId != null && onThemeChanged != null) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SettingsScreen(
                session: session,
                connectivity: widget.connectivity,
                themeId: themeId,
                onThemeChanged: onThemeChanged,
                notifications: widget.notifications)));
        return;
      }
    }
    // Support + unknown categories: no dedicated deep target in V1 — the list
    // itself carries the content, so nothing happens (honest no-op).
  }

  Future<void> _showPreferences() async {
    final current = await widget.notifications.preferences();
    if (!mounted) return;
    final prefs = (current.isSuccess && current.body is Map)
        ? (((current.body as Map)["preferences"] as Map?) ?? const {})
        : <dynamic, dynamic>{};
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text("Notification categories",
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                "Controls which in-app notifications OPPA delivers. "
                "Push notifications to the device arrive in a later release.",
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final entry in _categories.entries)
                SwitchListTile(
                  value: prefs[entry.key] is bool ? prefs[entry.key] as bool : true,
                  onChanged: (enabled) async {
                    setSheetState(() => prefs[entry.key] = enabled);
                    final r = await widget.notifications.setPreference(
                        entry.key, enabled);
                    if (!r.isSuccess && sheetContext.mounted) {
                      setSheetState(() => prefs[entry.key] = !enabled);
                      ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(
                          content: Text(r.errorCode ?? "Could not update preference")));
                    }
                  },
                  secondary: Icon(entry.value),
                  title: Text(_categoryLabel(entry.key)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _categoryLabel(String c) => switch (c) {
        "message" => "Messages",
        "wallet" => "Wallet",
        "payment" => "Payments",
        "security" => "Security alerts",
        "device" => "Devices & sign-in",
        "business" => "Business",
        "support" => "Support",
        _ => c,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        actions: [
          IconButton(
            tooltip: "Notification preferences",
            icon: const Icon(Icons.tune),
            onPressed: _showPreferences,
          ),
          if (_unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text("Mark all read ($_unread)"),
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: _filter == "all",
                    label: const Text("All"),
                    onSelected: (_) => setState(() => _filter = "all"),
                  ),
                ),
                for (final c in _categories.keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: _filter == c,
                      label: Text(_categoryLabel(c)),
                      onSelected: (_) => setState(() => _filter = c),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: switch (_state) {
                ViewLoading() => const StateViews.loading(),
                ViewOffline() => const StateViews.empty(
                    "Offline — notifications will load when you reconnect"),
                ViewError(:final message) =>
                  StateViews.error(message, onRetry: _load),
                ViewReady<Map>(:final data) => _list(theme, data),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(ThemeData theme, Map data) {
    final items = ((data["notifications"] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final filtered = _filter == "all"
        ? items
        : items.where((n) => "${n["category"] ?? (n["payload"] as Map?)?["category"]}" == _filter).toList();
    if (items.isEmpty) return const StateViews.empty("You're all caught up 🎉");
    if (filtered.isEmpty) {
      return StateViews.empty("No ${_categoryLabel(_filter).toLowerCase()} notifications");
    }
    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final n = filtered[i];
        final payload = (n["payload"] as Map?)?.cast<String, dynamic>() ?? const {};
        final title = "${payload["title"] ?? n["title"] ?? "Notification"}";
        final body = "${payload["body"] ?? n["body"] ?? ""}";
        final category =
            "${payload["category"] ?? n["category"] ?? "system"}";
        final read = n["readAt"] != null;
        return ListTile(
          onTap: () => _openContext(n),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                child: Icon(_categories[category] ?? Icons.notifications_outlined,
                    size: 20, color: theme.colorScheme.primary),
              ),
              if (!read)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          title: Text(title,
              style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: read ? FontWeight.w400 : FontWeight.w600)),
          subtitle: body.isEmpty ? null : Text(body, maxLines: 2),
          onLongPress: () => _markRead(n),
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
}
