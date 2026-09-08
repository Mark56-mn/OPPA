import "package:flutter/material.dart";

import "../../core/connectivity_service.dart";
import "../../core/session_store.dart";
import "../../core/translation_service.dart";
import "../../data/repositories.dart";
import "../../design/oppa_themes.dart";
import "../widgets/common.dart";

/// Settings screen: app language (for voice + translation), notification
/// preferences (real PUT /notifications/preferences), data-saving and theme.
/// Plain-language, non-technical, per the design DNA.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.session,
    required this.notifications,
    required this.connectivity,
    required this.themeId,
    required this.onThemeChanged,
  });

  final SessionStore session;
  final NotificationsRepository notifications;
  final ConnectivityService connectivity;
  final OppaThemeId themeId;
  final void Function(OppaThemeId) onThemeChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, bool> _prefs = {};
  bool _prefsLoading = true;
  String? _prefsError;
  bool _dataSaving = false;

  // Categories mirror the server's NOTIFICATION_CATEGORIES.
  static const _categories = <(String, String, IconData)>[
    ("message", "New messages", Icons.chat_bubble_outline),
    ("wallet", "Money sent and received", Icons.account_balance_wallet_outlined),
    ("payment", "Payments and orders", Icons.payments_outlined),
    ("security", "Security alerts", Icons.security_outlined),
    ("device", "New devices", Icons.phonelink_outlined),
    ("business", "Business updates", Icons.storefront_outlined),
    ("support", "Support replies", Icons.support_agent_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    setState(() {
      _prefsLoading = true;
      _prefsError = null;
    });
    final r = await widget.notifications.preferences();
    if (!mounted) return;
    if (r.isSuccess && r.body is Map) {
      final raw = ((r.body as Map)["preferences"] as Map?) ?? const {};
      setState(() {
        _prefs = raw.map((k, v) => MapEntry("$k", v == true));
        _prefsLoading = false;
      });
    } else {
      setState(() {
        _prefsError = r.errorCode ?? "Could not load preferences";
        _prefsLoading = false;
      });
    }
  }

  Future<void> _setPref(String category, bool enabled) async {
    setState(() => _prefs[category] = enabled);
    final r = await widget.notifications.setPreference(category, enabled);
    if (!mounted) return;
    if (!r.isSuccess) {
      setState(() => _prefs[category] = !enabled);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.errorCode ?? "Could not save that setting")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("Language", style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
              "Used for voice input and translations. English works everywhere.",
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final l in OppaLanguage.all)
                    FilterChip(
                      label: Text("${l.flag} ${l.nativeName}"),
                      selected: false,
                      onSelected: (_) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                "${l.nativeName} phrases are ready in the translator")));
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text("Notifications", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_prefsLoading)
            const Center(child: Padding(
                padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
          if (_prefsError != null)
            StateViews.error(_prefsError!, onRetry: _loadPrefs),
          if (!_prefsLoading && _prefsError == null)
            Card(
              child: Column(
                children: [
                  for (final (code, label, icon) in _categories)
                    SwitchListTile(
                      secondary: Icon(icon),
                      title: Text(label),
                      value: _prefs[code] ?? true,
                      onChanged: (v) => _setPref(code, v),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Text("Data & battery", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.data_saver_on_outlined),
              title: const Text("Data saving"),
              subtitle: const Text(
                  "Pause big downloads on mobile data. Chats still send."),
              value: _dataSaving,
              onChanged: (v) => setState(() => _dataSaving = v),
            ),
          ),
          const SizedBox(height: 24),
          Text("Appearance", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final t in OppaThemeId.values)
                  RadioGroup<OppaThemeId>(
                    groupValue: widget.themeId,
                    onChanged: (v) {
                      if (v != null) widget.onThemeChanged(v);
                    },
                    child: RadioListTile<OppaThemeId>(
                      title: Text(oppaTokens[t]!.name),
                      value: t,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text("About", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text("OPPA"),
              subtitle: Text(
                  "Chat. Pay. Connect. The African Way.\nNot affiliated with WhatsApp."),
              isThreeLine: true,
            ),
          ),
        ],
      ),
    );
  }
}
