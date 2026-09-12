import "package:flutter/material.dart";

import "../../core/demo_mode.dart";
import "../../core/device_key_manager.dart";
import "../../core/session_store.dart";
import "../../core/voice_service.dart";
import "../../design/oppa_themes.dart";

/// Real auth journey: phone → OTP → profile (voice name) → session.
/// The profile step supports voice input for users who cannot spell —
/// "Tap to speak your name" (approved UI). Device id is generated once and
/// kept in secure storage; the server binds sessions to it.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.session,
    required this.themeId,
    required this.onThemeChanged,
  });

  final SessionStore session;
  final OppaThemeId themeId;
  final void Function(OppaThemeId) onThemeChanged;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _AuthStep { phone, otp, profile }

class _AuthGateState extends State<AuthGate> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _deviceKeys = DeviceKeyManager();
  final _voice = VoiceService.instance;
  _AuthStep _step = _AuthStep.phone;
  bool _sending = false;
  bool _verifying = false;
  bool _savingProfile = false;
  bool _listening = false;
  bool _voiceMode = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _voice.ensureReady();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    _voice.stopListening();
    _voice.stopSpeaking();
    super.dispose();
  }

  Future<String> _deviceId() => _deviceKeys.publicKeyPem();

  Future<void> _sendOtp() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final phone = _phoneController.text.trim();
      final response = await widget.session.requestOtp(phone);
      if (!mounted) return;
      if (response.isSuccess) {
        setState(() => _step = _AuthStep.otp);
      } else {
        setState(() => _error = response.errorCode ?? "Could not send the code");
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyOtp() async {
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final deviceId = await _deviceId();
      final response = await widget.session.verifyOtp(
        _phoneController.text.trim(),
        _codeController.text.trim(),
        deviceId,
      );
      if (!mounted) return;
      if (response.isSuccess) {
        // Session is live; the name step is a local profile save before the
        // shell swaps in. Users can also skip and add it later in Me.
        setState(() => _step = _AuthStep.profile);
      } else {
        setState(() => _error = response.errorCode ?? "Verification failed");
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _toggleListenName() async {
    if (_listening) {
      await _voice.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final started = await _voice.startListening(
      localeId: voiceLocales["en"] ?? "en-US",
      timeout: const Duration(seconds: 6),
      onPartial: (text) {
        if (mounted) _nameController.text = text;
      },
      onFinal: (text) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _nameController.text = text;
        });
        // Read the name back so non-literate users confirm what was heard.
        _voice.speak(text, languageTag: voiceLocales["en"] ?? "en-US");
      },
    );
    if (!mounted) return;
    setState(() => _listening = started);
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              "Voice input is not available on this device — type your name instead")));
      setState(() => _voiceMode = false);
    }
  }

  Future<void> _finishProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      // Skip: the shell handles a blank profile; user can add it in Me.
      widget.session.completeOnboarding();
      return;
    }
    setState(() => _savingProfile = true);
    try {
      await widget.session.completeOnboarding(displayName: name);
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("OPPA",
                    style: theme.textTheme.headlineLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  "Africa-first messaging, wallet, business and calls.\nYour network. Your money. Your words.",
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 32),
                switch (_step) {
                  _AuthStep.phone => _phoneStep(theme),
                  _AuthStep.otp => _otpStep(theme),
                  _AuthStep.profile => _profileStep(theme),
                },
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: 32),
                const ThemePicker(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneStep(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(
              labelText: "Phone number",
              hintText: "+234 801 234 5678",
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _sending ? null : _sendOtp,
            child: _sending
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Send code"),
          ),
        ],
      );

  Widget _otpStep(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (DemoMode.enabled) ...[
            // Development-only hint: this code exists only inside the demo
            // backend in this app process. It is never accepted by production
            // authentication (it is simply a wrong code there).
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade700.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade700),
              ),
              child: Text(
                "${DemoMode.bannerLabel}: development OTP is ${DemoMode.demoOtp}. "
                "No network request is made.",
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.amber.shade100),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
            decoration: const InputDecoration(
              labelText: "6-digit code",
              counterText: "",
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _verifying ? null : _verifyOtp,
            child: _verifying
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Verify and continue"),
          ),
          TextButton(
            onPressed: _verifying ? null : () => setState(() => _step = _AuthStep.phone),
            child: const Text("Change number"),
          ),
        ],
      );

  Widget _profileStep(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("What should we call you?",
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text("Tap the mic and say your name. Others will see it when you chat.",
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
          const SizedBox(height: 20),
          // Voice / type mode switch (approved UI: "Type ⌨ | 🎙 Speak").
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.keyboard_alt_outlined), label: Text("Type")),
              ButtonSegment(value: true, icon: Icon(Icons.mic_rounded), label: Text("Speak")),
            ],
            selected: {_voiceMode},
            onSelectionChanged: (s) => setState(() => _voiceMode = s.first),
          ),
          const SizedBox(height: 16),
          if (_voiceMode) ...[
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _toggleListenName,
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: _listening
                          ? theme.colorScheme.primary.withValues(alpha: 0.2)
                          : theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        _listening ? Icons.stop : Icons.mic_rounded,
                        size: 36,
                        color: _listening ? theme.colorScheme.primary : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _listening ? "Listening… say your name" : "Tap to speak your name",
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Approved flow: speak → EDIT the transcription → confirm.
            // Speech recognition is imperfect; the user must be able to fix
            // what was heard before it is saved to their profile.
            TextField(
              controller: _nameController,
              maxLength: 80,
              enabled: !_listening,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: "Check and edit your name",
                helperText: "Is this right? Tap to correct it",
                suffixIcon: _nameController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: "Clear",
                        onPressed: () => setState(() => _nameController.clear()),
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ] else ...[
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              autofocus: true,
              decoration: const InputDecoration(labelText: "Your name"),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _savingProfile ? null : _finishProfile,
            child: _savingProfile
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_nameController.text.trim().isEmpty
                    ? "Skip — add it later"
                    : "Confirm and continue"),
          ),
          TextButton(
            onPressed: _savingProfile ? null : () => widget.session.completeOnboarding(),
            child: const Text("Skip for now"),
          ),
        ],
      );
}

/// Theme chooser shown at onboarding (theme = visual tokens only).
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key, this.onThemeChanged});

  final void Function(OppaThemeId)? onThemeChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final t in OppaThemeId.values)
          ActionChip(
            label: Text(oppaTokens[t]!.name),
            onPressed: onThemeChanged != null ? () => onThemeChanged!(t) : null,
          ),
      ],
    );
  }
}
