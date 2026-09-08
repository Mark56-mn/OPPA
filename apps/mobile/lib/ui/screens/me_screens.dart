import "package:flutter/material.dart";

import "../../core/connectivity_service.dart";
import "../../core/screen_data.dart";
import "../../core/session_store.dart";
import "../../data/repositories.dart";
import "../../design/oppa_themes.dart";
import "../widgets/common.dart";
import "business_app.dart" show BusinessApp;

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
            child: RadioGroup<OppaThemeId>(
              groupValue: widget.themeId,
              onChanged: (v) {
                if (v != null) widget.onThemeChanged(v);
              },
              child: Column(
                children: [
                  for (final t in OppaThemeId.values)
                    RadioListTile<OppaThemeId>(
                      title: Text(oppaTokens[t]!.name),
                      value: t,
                    ),
                ],
              ),
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
                  subtitle:
                      Text("Transfers and reversals require device verification."),
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
                  content:
                      const Text("You will need your phone code to sign back in."),
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

/// Business tab: the real merchant surface wired to the business API —
/// onboarding, products, incoming orders and analytics. Consumer order
/// placement lives in Connect so buyer and seller roles stay separate.
class BusinessScreen extends StatefulWidget {
  const BusinessScreen({
    super.key,
    required this.session,
    required this.business,
    required this.connectivity,
  });

  final SessionStore session;
  final BusinessRepository business;
  final ConnectivityService connectivity;

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  dynamic _state = const ViewLoading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const ViewLoading());
    final source = ScreenDataSource<Map>(
      connectivity: widget.connectivity,
      fetch: widget.business.listMine,
      decode: (b) => (b as Map).cast<String, dynamic>(),
      cacheKey: "business.mine",
    );
    final result = await source.load();
    if (!mounted) return;
    setState(() => _state = result);
  }

  List<Map> _businesses() {
    if (_state is! ViewReady<Map>) return const [];
    final list =
        ((_state as ViewReady<Map>).data["businesses"] as List?) ?? const [];
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  Future<void> _onboard() async {
    final name = await _prompt("Store name",
        hint: "e.g. Kano Spices", max: 120);
    if (name == null || !mounted) return;
    final response = await widget.business.create(name: name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(response.isSuccess
            ? "Store created"
            : (response.errorCode ?? "Could not create store"))));
    if (response.isSuccess) _load();
  }

  Future<String?> _prompt(String label, {String? hint, int max = 120}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: max,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(
              onPressed: () {
                final v = controller.text.trim();
                if (v.isEmpty) return;
                Navigator.pop(context, v);
              },
              child: const Text("Save")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Business")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onboard,
        icon: const Icon(Icons.add_business),
        label: const Text("New store"),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: switch (_state) {
          ViewLoading() => const StateViews.loading(),
          ViewOffline() => const StateViews.empty(
              "Offline — your store data loads when you reconnect"),
          ViewError(:final message) => StateViews.error(message, onRetry: _load),
          ViewReady<Map>() => _businesses().isEmpty
              ? const StateViews.empty(
                  "No store yet — create one to start selling on OPPA")
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final b in _businesses())
                      _BusinessCard(
                          business: b,
                          businessApi: widget.business,
                          session: widget.session,
                          connectivity: widget.connectivity),
                  ],
                ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({
    required this.business,
    required this.businessApi,
    required this.session,
    required this.connectivity,
  });

  final Map business;
  final BusinessRepository businessApi;
  final SessionStore session;
  final ConnectivityService connectivity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = "${business["id"] ?? ""}";
    final name = "${business["name"] ?? "Store"}";
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text("Business account", style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 12),
            // The Business app is its own surface with merchant navigation —
            // not consumer tabs with extra buttons.
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BusinessApp(
                      session: session,
                      business: businessApi,
                      connectivity: connectivity,
                      initialBusinessId: id,
                      initialBusinessName: name))),
              icon: const Icon(Icons.storefront_outlined),
              label: const Text("Open Business app"),
            ),
          ],
        ),
      ),
    );
  }
}
