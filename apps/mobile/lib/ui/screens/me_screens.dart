import "package:flutter/material.dart";

import "../../core/connectivity_service.dart";
import "../../core/session_store.dart";
import "../../data/repositories.dart";
import "../../design/oppa_themes.dart";
import "../widgets/common.dart";

/// Me / Security tab: profile, theme, security posture, sign-out.
class MeScreen extends StatefulWidget {
  const MeScreen({
    super.key,
    required this.session,
    required this.profiles,
    required this.themeId,
    required this.onThemeChanged,
    required this.onSignOut,
  });

  final SessionStore session;
  final ProfileRepository profiles;
  final OppaThemeId themeId;
  final void Function(OppaThemeId) onThemeChanged;
  final Future<void> Function() onSignOut;

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  final _name = TextEditingController();
  final _about = TextEditingController();
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
    super.dispose();
  }

  Future<void> _load() async {
    final response = await widget.profiles.mine();
    if (!mounted) return;
    if (response.isSuccess && response.body is Map) {
      final p = (response.body as Map).cast<String, dynamic>();
      _name.text = "${p["displayName"] ?? ""}";
      _about.text = "${p["about"] ?? ""}";
    }
    setState(() => _state = response.isSuccess
        ? const ViewReady<Map>({}, fromCache: false)
        : ViewError(response.errorCode ?? "Could not load profile"));
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Me")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_state is ViewError)
            StateViews.error((_state as ViewError).message, onRetry: _load),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: "Display name"),
            maxLength: 80,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _about,
            decoration: const InputDecoration(labelText: "About"),
            maxLength: 280,
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text("Save profile")),
          const SizedBox(height: 24),
          Text("Appearance", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final t in OppaThemeId.values)
                  RadioListTile<OppaThemeId>(
                    title: Text(oppaTokens[t]!.name),
                    value: t,
                    groupValue: widget.themeId,
                    onChanged: (v) {
                      if (v != null) widget.onThemeChanged(v);
                    },
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
                  title: Text("Devices are bound to your account"),
                  subtitle: Text("Sessions only work on registered devices."),
                ),
                ListTile(
                  leading: Icon(Icons.key_outlined),
                  title: Text("Sensitive actions need step-up"),
                  subtitle: Text("Transfers and reversals require device verification."),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Sign out?"),
                  content: const Text("You will need your phone code to sign back in."),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Sign out")),
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

/// Business tab: merchant surface. V1 keeps consumer and merchant permissions
/// separate; this screen reads the caller's businesses and orders.
class BusinessScreen extends StatelessWidget {
  const BusinessScreen({super.key, required this.connectivity});

  final ConnectivityService connectivity;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Business")),
      body: const StateViews.empty(
          "Business onboarding opens with your first store — coming to this build"),
    );
  }
}
