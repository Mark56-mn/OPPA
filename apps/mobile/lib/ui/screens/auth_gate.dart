import "package:flutter/material.dart";

import "../../core/device_key_manager.dart";
import "../../core/session_store.dart";
import "../../design/oppa_themes.dart";
import "../widgets/common.dart";

/// Real auth journey: phone → OTP → session. Device id is generated once and
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

class _AuthGateState extends State<AuthGate> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final DeviceKeyManager _deviceKeys = DeviceKeyManager();
  bool _sending = false;
  bool _verifying = false;
  bool _otpSent = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// Device identity: a generated EC P-256 keypair whose SPKI public PEM is
  /// the enrollment identifier the server stores and later verifies proofs
  /// against. Private key never leaves secure storage.
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
        setState(() => _otpSent = true);
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
      if (!response.isSuccess) {
        setState(() => _error = response.errorCode ?? "Verification failed");
      }
      // Success: SessionStore flips phase; the shell swaps to Home.
    } finally {
      if (mounted) setState(() => _verifying = false);
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
                if (!_otpSent) ...[
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
                ] else ...[
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
                    onPressed: _verifying ? null : () => setState(() => _otpSent = false),
                    child: const Text("Change number"),
                  ),
                ],
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
