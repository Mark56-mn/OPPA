import "package:flutter/material.dart";
import "package:flutter/services.dart" show FilteringTextInputFormatter;

import "../../core/connectivity_service.dart";
import "../../core/screen_data.dart";
import "../../core/session_store.dart";
import "../../data/repositories.dart";
import "../../design/locked_features.dart";
import "../../design/oppa_themes.dart";
import "../widgets/common.dart";
import "home_screens.dart" show SupportScreen;
import "notification_screens.dart";
import "settings_screen.dart";
import "workspace_switcher.dart" show showWorkspaceSwitcher;

/// Me tab (approved art "My Profile"): profile header, edit profile,
/// notifications, settings, support, security posture, locked roadmap rows
/// (2FA, biometrics, storage), theme and sign-out.
class MeScreen extends StatefulWidget {
  const MeScreen({
    super.key,
    required this.session,
    required this.profiles,
    required this.notifications,
    required this.business,
    required this.connectivity,
    required this.themeId,
    required this.onThemeChanged,
    required this.onSignOut,
  });

  final SessionStore session;
  final ProfileRepository profiles;
  final NotificationsRepository notifications;
  final BusinessRepository business;
  final ConnectivityService connectivity;
  final OppaThemeId themeId;
  final void Function(OppaThemeId) onThemeChanged;
  final Future<void> Function() onSignOut;

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  final _name = TextEditingController();
  final _about = TextEditingController();
  final _oppaId = TextEditingController();
  String? _phone;
  String? _currentOppaId;
  String? _oppaIdMessage;
  bool _oppaIdBusy = false;
  bool _editing = false;
  dynamic _state = const ViewLoading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    _oppaId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final response = await widget.profiles.mine();
    if (!mounted) return;
    if (response.isSuccess && response.body is Map) {
      final p = (response.body as Map).cast<String, dynamic>();
      _name.text = "${p["displayName"] ?? ""}";
      _about.text = "${p["about"] ?? ""}";
      _phone = p["phone"] as String?;
      _currentOppaId = p["oppaId"] as String?;
      _oppaId.text = _currentOppaId ?? "";
    }
    setState(() => _state = response.isSuccess
        ? const ViewReady<Map>({}, fromCache: false)
        : ViewError(response.errorCode ?? "Could not load profile"));
  }

  /// Claims or changes the OPPA ID. The server owns the rules; this only
  /// pre-checks availability for honest inline feedback, then submits.
  Future<void> _saveOppaId() async {
    final id = _oppaId.text.trim().toLowerCase();
    if (id == _currentOppaId) {
      setState(() => _oppaIdMessage = "That is your current OPPA ID");
      return;
    }
    setState(() => _oppaIdBusy = true);
    final check = await widget.profiles.oppaIdAvailable(id);
    if (!mounted) return;
    if (check.isSuccess) {
      final available = ((check.body as Map?)?["available"] as bool?) ?? false;
      if (!available) {
        setState(() {
          _oppaIdBusy = false;
          _oppaIdMessage = "That OPPA ID is taken — try another";
        });
        return;
      }
    }
    final r = await widget.profiles.setOppaId(id);
    if (!mounted) return;
    setState(() {
      _oppaIdBusy = false;
      _oppaIdMessage = r.isSuccess
          ? "OPPA ID saved — people can find you as $id"
          : switch (r.errorCode) {
              "OPPA_ID_TAKEN" => "That OPPA ID is taken — try another",
              "OPPA_ID_RESERVED" => "That name is reserved — try another",
              "OPPA_ID_INVALID" =>
                "Use 3–32 letters, numbers or _ starting with a letter",
              "OPPA_ID_CHANGE_RATE_LIMITED" =>
                "Too many changes — try again in an hour",
              _ => r.errorCode ?? "Could not save OPPA ID",
            };
    });
    if (r.isSuccess) {
      setState(() => _currentOppaId = id);
    }
  }

  Future<void> _save() async {
    final response = await widget.profiles.update(
      displayName: _name.text.trim(),
      about: _about.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(response.isSuccess
            ? "Profile saved"
            : (response.errorCode ?? "Could not save profile"))));
    if (response.isSuccess) setState(() => _editing = false);
  }

  /// Opens the full workspace switcher (Personal ↔ Business, no logout).
  void _openWorkspaceSwitcher() {
    showWorkspaceSwitcher(context,
        session: widget.session,
        business: widget.business,
        connectivity: widget.connectivity);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _name.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text("Me"),
        actions: [
          IconButton(
            tooltip: "Switch workspace",
            onPressed: _openWorkspaceSwitcher,
            icon: const Icon(Icons.swap_horiz_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile header (approved art: avatar, name, phone, Online).
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    name.isEmpty ? "?" : name.characters.first.toUpperCase(),
                    style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
                Text(name.isEmpty ? "Add your name" : name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  _phone ??
                      (_currentOppaId == null
                          ? ""
                          : "oppa.com/$_currentOppaId"),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _editing = !_editing),
                  icon: Icon(_editing ? Icons.close : Icons.edit_outlined,
                      size: 18),
                  label: Text(_editing ? "Close editor" : "Edit profile"),
                ),
              ],
            ),
          ),
          if (_state is ViewError) ...[
            const SizedBox(height: 12),
            StateViews.error((_state as ViewError).message, onRetry: _load),
          ],
          if (_editing) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      decoration:
                          const InputDecoration(labelText: "Display name"),
                      maxLength: 80,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _about,
                      decoration: const InputDecoration(labelText: "About"),
                      maxLength: 280,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: _save, child: const Text("Save profile")),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text("OPPA ID", style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            "Your unique name on OPPA — people find and add you with it.",
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _oppaId,
            maxLength: 32,
            enabled: !_oppaIdBusy,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp("[a-zA-Z0-9_]")),
            ],
            decoration: InputDecoration(
              labelText: _currentOppaId == null
                  ? "Choose your OPPA ID"
                  : "Your OPPA ID",
              prefixText: "oppa.com/ ",
              helperText: "3–32 characters, starts with a letter",
              suffixIcon: _currentOppaId == null
                  ? null
                  : const Icon(Icons.check_circle_outline,
                      color: Colors.green, size: 20),
            ),
          ),
          if (_oppaIdMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_oppaIdMessage!, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _oppaIdBusy ? null : _saveOppaId,
            child: _oppaIdBusy
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_currentOppaId == null
                    ? "Claim OPPA ID"
                    : "Change OPPA ID"),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text("Notifications"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => NotificationsScreen(
                          notifications: widget.notifications,
                          connectivity: widget.connectivity))),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text("Settings"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                          session: widget.session,
                          notifications: widget.notifications,
                          connectivity: widget.connectivity,
                          themeId: widget.themeId,
                          onThemeChanged: widget.onThemeChanged))),
                ),
                ListTile(
                  leading: const Icon(Icons.support_agent_outlined),
                  title: const Text("Help & Support"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SupportScreen())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text("Security", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.phonelink_lock_outlined),
                  title: Text("Devices & Sessions"),
                  subtitle: Text(
                      "Sessions only work on registered, device-bound phones."),
                ),
                LockedFeatureTile(feature: OppaFeature.twoFactor),
                LockedFeatureTile(feature: OppaFeature.biometricLogin),
                LockedFeatureTile(feature: OppaFeature.dataStorage),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text("Appearance", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<OppaThemeId>(
              groupValue: widget.themeId,
              onChanged: (v) {
                if (v != null) widget.onThemeChanged(v);
              },
              child: Column(
                children: [
                  for (final t in OppaThemeId.values)
                    RadioListTile<OppaThemeId>(
                      title: Text(oppaThemeDisplayNames[t]!),
                      value: t,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Sign out?"),
                  content: const Text(
                      "You will need your phone code to sign back in."),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Cancel")),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text("Sign out")),
                  ],
                ),
              );
              if (confirmed == true) await widget.onSignOut();
            },
            icon: const Icon(Icons.logout),
            label: const Text("Sign out"),
          ),
        ],
      ),
    );
  }
}
