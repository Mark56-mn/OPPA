import "dart:async";

import "package:flutter/material.dart";

import "../../core/demo_mode.dart";
import "../../core/device_key_manager.dart";
import "../../core/session_store.dart";
import "../../core/voice_service.dart";
import "../../design/locked_features.dart";
import "../../design/oppa_brand.dart";
import "../../design/oppa_themes.dart";

/// Real auth journey, matching the approved onboarding art:
///   Welcome (orb + OPPA PULSE) → phone → OTP → voice-name profile →
///   security note → "You're all set!" → Start OPPA.
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

enum _AuthStep { phone, otp, profile, done }

class _AuthGateState extends State<AuthGate> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _deviceKeys = DeviceKeyManager();
  final _voice = VoiceService.instance;
  _AuthStep _step = _AuthStep.phone;
  bool _sending = false;
  bool _verifying = false;
  bool _listening = false;
  bool _voiceMode = true;
  int _resendIn = 0;
  StreamSubscription<int>? _resendSub;
  String? _error;

  @override
  void initState() {
    super.initState();
    _voice.ensureReady();
  }

  @override
  void dispose() {
    _resendSub?.cancel();
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
        setState(() {
          _step = _AuthStep.otp;
          _resendIn = 45;
        });
        _startResendCountdown();
      } else {
        setState(() => _error = _friendlyError(response.errorCode) ??
            "Could not send the code");
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startResendCountdown() {
    _resendSub?.cancel();
    _resendSub = Stream<int>.periodic(const Duration(seconds: 1), (c) => c)
        .take(45)
        .listen((c) {
      if (!mounted) return;
      setState(() => _resendIn = 44 - c);
    });
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
        setState(() => _error = _friendlyError(response.errorCode) ??
            "Verification failed");
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  /// Server error codes → plain language (the copy on the approved art).
  String? _friendlyError(String? code) => switch (code) {
        "OTP_INVALID" || "OTP_WRONG" => "That code is not right — check and try again",
        "OTP_EXPIRED" => "That code expired — tap Resend code",
        "PHONE_INVALID" => "Enter a valid phone number",
        "DEVICE_NOT_ENROLLED" => "This device is not registered — reinstall and try again",
        _ => code,
      };

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_voiceBlockMessage())));
      setState(() => _voiceMode = false);
    }
  }

  /// Honest, plain-language reason dictation is unavailable right now.
  String _voiceBlockMessage() => switch (_voice.sttBlockReason) {
        SttBlockReason.permissionDenied =>
          "Microphone permission is off — allow it in Settings, or type your name",
        SttBlockReason.noSpeechService =>
          "This device has no speech service — type your name instead",
        SttBlockReason.busy =>
          "Still finishing the last listen — try again in a second",
        _ => "Voice input is not available right now — type your name instead",
      };

  /// The name is kept locally and saved by completeOnboarding(displayName)
  /// when the user taps Start OPPA on the confirmation screen — so the
  /// approved "You're all set!" step is actually visible before Home.
  void _finishProfile() {
    if (!mounted) return;
    setState(() {
      _error = null;
      _step = _AuthStep.done;
    });
  }

  /// Enters the app. Saving the name and completing onboarding happen here,
  /// atomically, just before the shell swaps in.
  Future<void> _startOppa() async {
    final name = _nameController.text.trim();
    await widget.session
        .completeOnboarding(displayName: name.isEmpty ? null : name);
    // The phase/flag flip rebuilds the tree; AuthGate is replaced by Home.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: switch (_step) {
                _AuthStep.phone => _phoneStep(theme, key: const ValueKey(0)),
                _AuthStep.otp => _otpStep(theme, key: const ValueKey(1)),
                _AuthStep.profile => _profileStep(theme, key: const ValueKey(2)),
                _AuthStep.done => _doneStep(theme, key: const ValueKey(3)),
              },
            ),
          ),
        ),
      ),
      bottomSheet: _error == null
          ? null
          : SafeArea(
              child: Material(
                color: theme.colorScheme.error.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Icon(Icons.error_outline,
                        size: 18, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error)),
                    ),
                  ]),
                ),
              ),
            ),
    );
  }

  /// Big brand header used by the first step (approved welcome art).
  Widget _brandHeader(ThemeData theme, {required String title, required String body}) =>
      Column(
        children: [
          const SizedBox(height: 8),
          const CustomPaint(
            size: Size.square(120),
            painter: OppaPulsePainter(),
          ),
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(
              text: "${OppaBrand.wordmark} ",
              style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800, letterSpacing: 4),
              children: [
                TextSpan(
                  text: OppaBrand.tagline,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.7))),
          const SizedBox(height: 28),
        ],
      );

  Widget _phoneStep(ThemeData theme, {Key? key}) => Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _brandHeader(
            theme,
            title: "Welcome to OPPA",
            body: OppaBrand.slogan,
          ),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(
              labelText: "Phone number",
              hintText: "+234 801 234 5678",
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 8),
          // Honest microcopy: the server sends real OTPs in production.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
              const SizedBox(width: 6),
              Text(
                DemoMode.enabled
                    ? "${DemoMode.bannerLabel}: no real SMS is sent"
                    : "We'll send you an OTP to verify",
                style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.55)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _sending ? null : _sendOtp,
            child: _sending
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Continue"),
          ),
          const SizedBox(height: 28),
          ThemePicker(themeId: widget.themeId, onThemeChanged: widget.onThemeChanged),
        ],
      );

  Widget _otpStep(ThemeData theme, {Key? key}) => Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _brandHeader(
            theme,
            title: "Verify your number",
            body: "We sent a 6-digit code to "
                "${_maskPhone(_phoneController.text.trim())}",
          ),
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
            style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 10),
            decoration: const InputDecoration(
              labelText: "6-digit code",
              counterText: "",
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed:
                  _resendIn > 0 || _verifying ? null : () => _sendOtp(),
              child: Text(
                _resendIn > 0
                    ? "Resend code in 00:${_resendIn.toString().padLeft(2, "0")}"
                    : "Resend code",
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _verifying ? null : _verifyOtp,
            child: _verifying
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Verify"),
          ),
          TextButton(
            onPressed: _verifying ? null : () => setState(() => _step = _AuthStep.phone),
            child: const Text("Change number"),
          ),
        ],
      );

  Widget _profileStep(ThemeData theme, {Key? key}) => Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _brandHeader(
            theme,
            title: "Create your profile",
            body: "What should we call you? Speak it — no spelling needed.",
          ),
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
            onPressed: _finishProfile,
            child: Text(_nameController.text.trim().isEmpty
                ? "Skip — add it later"
                : "Continue"),
          ),
        ],
      );

  /// Final onboarding screen (approved art: confetti + "You're all set!").
  Widget _doneStep(ThemeData theme, {Key? key}) => Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.emoji_events_outlined,
                    size: 120,
                    color: theme.colorScheme.primary.withValues(alpha: 0.25)),
                const CustomPaint(
                    size: Size.square(72), painter: OppaPulsePainter()),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text("You're all set!",
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            "Your OPPA account is ready. Let's get you connected.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _startOppa,
            child: const Text("Start OPPA"),
          ),
          TextButton(
            onPressed: _startOppa,
            child: const Text("Explore OPPA"),
          ),
        ],
      );

  static String _maskPhone(String phone) {
    if (phone.length < 5) return phone;
    final tail = phone.substring(phone.length - 3);
    return "•••  •••  $tail";
  }
}

/// Theme chooser shown at onboarding (theme = visual tokens only), using the
/// approved look names. The fourth look (OPPA Dash) is visible but locked.
class ThemePicker extends StatelessWidget {
  const ThemePicker({
    super.key,
    this.themeId,
    this.onThemeChanged,
  });

  final OppaThemeId? themeId;
  final void Function(OppaThemeId)? onThemeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Choose Your OPPA Look",
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text("Three unique themes. Same OPPA experience. Always you.",
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              RadioGroup<OppaThemeId>(
                groupValue: themeId,
                onChanged: (v) {
                  if (v != null) onThemeChanged?.call(v);
                },
                child: Column(
                  children: [
                    for (final t in OppaThemeId.values)
                      RadioListTile<OppaThemeId>(
                        value: t,
                        title: Text(oppaThemeDisplayNames[t]!),
                        secondary: _ThemeDot(color: oppaTokens[t]!.primary),
                      ),
                  ],
                ),
              ),
              // Visible-but-locked fourth look (honest roadmap surface).
              const LockedFeatureTile(feature: OppaFeature.dashDark),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeDot extends StatelessWidget {
  const _ThemeDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 22, height: 22, decoration: BoxDecoration(
        color: color, shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ));
}
