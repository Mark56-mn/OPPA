import "package:flutter/material.dart";
import "package:flutter/services.dart" show FilteringTextInputFormatter;

import "../../core/connectivity_service.dart";
import "../../core/screen_data.dart";
import "../../core/session_store.dart";
import "../../core/voice_service.dart";
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
  final _oppaId = TextEditingController();
  String? _currentOppaId;
  String? _oppaIdMessage;
  bool _oppaIdBusy = false;
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
            ),
          ),
          if (_oppaIdMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_oppaIdMessage!,
                  style: theme.textTheme.bodySmall),
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
    final name = await _promptBusinessName();
    if (name == null || !mounted) return;
    final response = await widget.business.create(name: name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(response.isSuccess
            ? "Store created"
            : (response.errorCode ?? "Could not create store"))));
    if (response.isSuccess) _load();
  }

  /// Voice-assisted onboarding (approved UI: "Type ⌨ | 🎙 Speak"). Sellers
  /// who cannot spell their store name can say it, check the transcription,
  /// edit it, and confirm. Mirrors the consumer voice-name flow.
  Future<String?> _promptBusinessName() {
    return showDialog<String>(context: context, builder: (_) => const _BusinessNameDialog());
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

/// Voice-assisted business onboarding: Type ⌨ / 🎙 Speak, editable
/// transcription, spoken read-back, confirm. The editable field is the
/// point — speech recognition is imperfect and the seller must be able to
/// fix what was heard before their store is created.
class _BusinessNameDialog extends StatefulWidget {
  const _BusinessNameDialog();

  @override
  State<_BusinessNameDialog> createState() => _BusinessNameDialogState();
}

class _BusinessNameDialogState extends State<_BusinessNameDialog> {
  final _voice = VoiceService.instance;
  final _nameController = TextEditingController();
  bool _voiceMode = true;
  bool _listening = false;

  @override
  void dispose() {
    if (_listening) _voice.stopListening();
    _voice.stopSpeaking();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _voice.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final locale = voiceLocales["en"] ?? "en-US";
    final started = await _voice.startListening(
      localeId: locale,
      timeout: const Duration(seconds: 8),
      onPartial: (text) {
        if (mounted) _nameController.text = text;
      },
      onFinal: (text) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _nameController.text = text;
        });
        // Read it back so the seller confirms what was heard.
        _voice.speak(text, languageTag: locale);
      },
    );
    if (!mounted) return;
    setState(() => _listening = started);
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              "Voice input is not available on this device — type your store name instead")));
      setState(() => _voiceMode = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text("Name your business"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("What is your store called?",
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false,
                  icon: Icon(Icons.keyboard_alt_outlined),
                  label: Text("Type")),
              ButtonSegment(
                  value: true, icon: Icon(Icons.mic_rounded), label: Text("Speak")),
            ],
            selected: {_voiceMode},
            onSelectionChanged: (s) => setState(() => _voiceMode = s.first),
          ),
          const SizedBox(height: 16),
          if (_voiceMode) ...[
            Center(
              child: GestureDetector(
                onTap: _toggleListen,
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: _listening
                      ? theme.colorScheme.primary.withValues(alpha: 0.2)
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    _listening ? Icons.stop : Icons.mic_rounded,
                    size: 30,
                    color: _listening ? theme.colorScheme.primary : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _listening
                  ? "Listening… say your store name"
                  : "Tap to speak your store name",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _nameController,
            maxLength: 120,
            enabled: !_listening,
            autofocus: !_voiceMode,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: _voiceMode ? "Check and edit the name" : "Store name",
              helperText: _voiceMode ? "Is this right? Tap to correct it" : null,
              hintText: "e.g. Kano Spices",
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        FilledButton(
          onPressed: _listening || _nameController.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _nameController.text.trim()),
          child: const Text("Create store"),
        ),
      ],
    );
  }
}
