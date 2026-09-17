import "package:flutter/material.dart";

import "oppa_themes.dart";

/// V1 feature gating, rendered honestly in the UI.
///
/// Anything that is NOT part of the approved V1 build stays VISIBLE but
/// LOCKED — the reference UI shows the full product vision, and users see
/// where OPPA is going, but locked rows never pretend to work: tapping one
/// opens the same "coming in a later release" explanation. No locked control
/// ever reports success or fakes data.
enum OppaFeature {
  voiceTranslator("Voice Translator", Icons.translate_rounded,
      "Speak, translate and send to chat. Available now."),
  groupChats("Group chats", Icons.groups_2_outlined,
      "Group messaging is coming in a later release."),
  videoCalls("Video calls", Icons.videocam_outlined,
      "Video calling is coming in a later release. Voice calls work today."),
  ussdFunding("Fund with USSD", Icons.dialpad_outlined,
      "USSD top-ups are coming in a later release. Card and transfer work today."),
  bankTransfers("Bank transfer", Icons.account_balance_outlined,
      "Direct bank transfers are coming in a later release."),
  twoFactor("Two-factor authentication", Icons.shield_outlined,
      "2FA is coming in a later release. Your account is already device-bound."),
  profilePhoto("Profile photo", Icons.photo_camera_outlined,
      "Photo upload needs the media service, which is not in V1. Your name and OPPA ID are saved for real."),
  appLock("App lock PIN", Icons.pin_outlined,
      "An app-lock PIN is coming in a later release. This device is already bound to your account."),
  requestMoney("Request money", Icons.request_page_outlined,
      "Money requests are coming in a later release. Send and Deposit work today."),
  attachments("Attachments", Icons.attach_file,
      "Sending photos, files and voice notes is coming with the media service. Voice dictation works today."),
  biometricLogin("Biometric login", Icons.fingerprint_outlined,
      "Fingerprint and face unlock are coming in a later release."),
  dataStorage("Data & storage controls", Icons.storage_outlined,
      "Storage controls are coming in a later release."),
  dashDark("OPPA Dash (Dark)", Icons.dark_mode_outlined,
      "The fourth theme arrives with the next release. Three looks are live today."),
  stories("Stories", Icons.auto_awesome_outlined,
      "Stories are coming in a later release."),
  marketplace("Open marketplace", Icons.storefront_outlined,
      "The open marketplace arrives after V1. You can shop individual businesses today."),
  games("Games & entertainment", Icons.sports_esports_outlined,
      "Games are coming in a later release.");

  const OppaFeature(this.title, this.icon, this.explanation);
  final String title;
  final IconData icon;
  final String explanation;
}

// NOTE: enum const constructors require const arguments — all explanation
// strings above are literals, icons are const Icons.* getters.

/// Shows the honest "locked" sheet. One shared implementation so every
/// locked row behaves identically (same wording, same tone, no fake UX).
Future<void> showLockedFeatureSheet(BuildContext context, OppaFeature f) {
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(f.icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(f.title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(f.explanation, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Got it"),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A settings/list row that renders a locked feature: full opacity icon and
/// title, explicit lock, and the honest sheet on tap. Locked rows are
/// discoverable — they explain the roadmap instead of disappearing.
class LockedFeatureTile extends StatelessWidget {
  const LockedFeatureTile({super.key, required this.feature});

  final OppaFeature feature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      enabled: true,
      onTap: () => showLockedFeatureSheet(context, feature),
      leading: Icon(feature.icon),
      title: Text(feature.title),
      subtitle: Text("Coming in a later release",
          style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
      trailing: Icon(Icons.lock_outline_rounded,
          size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
    );
  }
}

/// Reusable "locked" chip for screens where a control exists but the feature
/// is not in V1 (e.g. the video toggle on the call screen).
class LockedChip extends StatelessWidget {
  const LockedChip({super.key, required this.feature});

  final OppaFeature feature;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.lock_outline_rounded, size: 16),
      label: Text(feature.title),
      onPressed: () => showLockedFeatureSheet(context, feature),
    );
  }
}

/// Theme names follow the approved "Choose Your OPPA Look" screen:
/// Fluid Africa (warm amber), OPPA Pulse (purple), Everyday OPPA (green).
/// `dash` stays locked until the fourth theme ships.
const oppaThemeDisplayNames = <OppaThemeId, String>{
  OppaThemeId.fluidAfrica: "Fluid Africa",
  OppaThemeId.pulse: "OPPA Pulse",
  OppaThemeId.everyday: "Everyday OPPA",
};
