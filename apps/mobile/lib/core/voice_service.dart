import "dart:async";

import "package:flutter_tts/flutter_tts.dart";
import "package:permission_handler/permission_handler.dart";
import "package:speech_to_text/speech_to_text.dart" as stt;

/// Voice capability state reported honestly to the UI. Never fakes
/// availability: if a device has no speech service (common on low-end or
/// stripped-down Android builds) callers surface "voice not available"
/// instead of a silent dead button.
enum VoiceAvailability { unknown, checking, available, unavailable }

/// Why dictation is (or is not) usable right now. Surfaced verbatim in the
/// UI — never silently ignored, never faked.
enum SttBlockReason { none, noSpeechService, permissionDenied, busy, unknown }

/// Single wrapper over on-device speech-to-text and text-to-speech.
///
/// Android capability notes (why each step exists):
/// - RECORD_AUDIO must be requested at runtime BEFORE initialize/listen —
///   without this the engine reports "not available" on every fresh install;
/// - `initialize()` must succeed before `listen()`; we cache the result and
///   never re-enter listen while a session is active (the plugin throws
///   "already active" on Android otherwise);
/// - requested locales are checked against `locales()` — asking an Android
///   device for ha-NG when only en-US packs are installed makes listen fail;
///   we fall back to the device default and say so.
class VoiceService {
  VoiceService._();

  static final VoiceService instance = VoiceService._();

  final stt.SpeechToText _stt = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _sttReady = false;
  bool _ttsReady = false;
  bool _listenInFlight = false;

  VoiceAvailability sttAvailability = VoiceAvailability.unknown;
  VoiceAvailability ttsAvailability = VoiceAvailability.unknown;
  SttBlockReason sttBlockReason = SttBlockReason.none;

  /// Prepares both engines: runtime mic permission first, then the platform
  /// speech service. Safe to call repeatedly; completes with an honest
  /// availability state either way.
  Future<void> ensureReady() async {
    if (sttAvailability == VoiceAvailability.checking ||
        ttsAvailability == VoiceAvailability.checking) {
      return;
    }
    if (sttAvailability == VoiceAvailability.unknown) {
      sttAvailability = VoiceAvailability.checking;
      try {
        // 1. Runtime microphone permission (Android 6+). Without this the
        // recognition service never starts and users see a dead mic button.
        final status = await Permission.microphone.status;
        var granted = status.isGranted;
        if (!granted && !status.isPermanentlyDenied) {
          granted = await Permission.microphone.request().isGranted;
        }
        if (!granted) {
          _sttReady = false;
          sttAvailability = VoiceAvailability.unavailable;
          sttBlockReason = SttBlockReason.permissionDenied;
          // TTS still works without the mic — check it below.
        } else {
          // 2. Platform recognition service (exists on virtually all GMS
          // Android devices; absent on stripped-down builds — reported, not
          // hidden).
          _sttReady = await _stt.initialize(
            onError: (_) {},
            onStatus: (_) {},
          );
          sttAvailability =
              _sttReady ? VoiceAvailability.available : VoiceAvailability.unavailable;
          if (!_sttReady) sttBlockReason = SttBlockReason.noSpeechService;
        }
      } catch (_) {
        _sttReady = false;
        sttAvailability = VoiceAvailability.unavailable;
        sttBlockReason = SttBlockReason.unknown;
      }
    }
    if (ttsAvailability == VoiceAvailability.unknown) {
      ttsAvailability = VoiceAvailability.checking;
      try {
        final ok = await _tts.isLanguageAvailable("en-US");
        _ttsReady = ok == true || ok.toString() == "true";
        ttsAvailability = _ttsReady
            ? VoiceAvailability.available
            : VoiceAvailability.unavailable;
      } catch (_) {
        _ttsReady = false;
        ttsAvailability = VoiceAvailability.unavailable;
      }
    }
  }

  /// True when dictation can be started right now.
  bool get canListen => _sttReady && !_listenInFlight;

  /// Resolves [localeId] against the engine's installed locales. Returns the
  /// requested tag when supported, otherwise null (= device default) so the
  /// UI can tell the user the language fell back to the device default.
  Future<String?> resolveLocale(String localeId) async {
    if (!_sttReady) return null;
    try {
      final locales = await _stt.locales();
      final ids = locales.map((l) => "$l").toSet();
      if (ids.contains(localeId)) return localeId;
      // Language-part match (e.g. request ha-NG, device offers ha-GH).
      final lang = localeId.split("-").first.toLowerCase();
      for (final id in ids) {
        if (id.toLowerCase().startsWith("$lang-") ||
            id.toLowerCase() == lang) {
          return id;
        }
      }
      return null; // device default; caller reports the fallback
    } catch (_) {
      return null;
    }
  }

  /// Starts listening. [onPartial] fires live as words are recognized so the
  /// user sees their name/text appear as they speak. Returns false when the
  /// engine could not start (permission denied, no service, already busy).
  Future<bool> startListening({
    required void Function(String text) onPartial,
    required void Function(String finalText) onFinal,
    required String localeId,
    Duration? timeout,
  }) async {
    if (!_sttReady) {
      sttBlockReason = sttAvailability == VoiceAvailability.unavailable
          ? sttBlockReason
          : SttBlockReason.noSpeechService;
      return false;
    }
    if (_listenInFlight) {
      sttBlockReason = SttBlockReason.busy;
      return false;
    }
    // Guard against the Android "already active" race: a previous session
    // that never delivered its final status leaves the engine busy.
    try {
      if (_stt.isListening) await _stt.stop();
    } catch (_) {}

    final effectiveLocale = await resolveLocale(localeId);
    var available = false;
    try {
      available = await _stt.listen(
        onResult: (result) {
          if (result.finalResult) {
            onFinal(result.recognizedWords.trim());
          } else {
            onPartial(result.recognizedWords.trim());
          }
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          localeId: effectiveLocale, // null = device default (reported)
        ),
      );
    } catch (_) {
      _listenInFlight = false;
      sttBlockReason = SttBlockReason.unknown;
      return false;
    }
    if (!available) {
      _listenInFlight = false;
      sttBlockReason = SttBlockReason.unknown;
      return false;
    }
    _listenInFlight = true;
    if (timeout != null) {
      Timer(timeout, () {
        if (_stt.isListening) stopListening();
      });
    }
    return true;
  }

  /// Stops an active dictation session. The engine delivers a final result
  /// through the same callback before or shortly after this call.
  Future<void> stopListening() async {
    _listenInFlight = false;
    try {
      await _stt.stop();
    } catch (_) {
      // Already stopped or engine unavailable — nothing to surface.
    }
  }

  bool get isListening => _sttReady && _stt.isListening;

  /// Speaks [text] in the platform voice for [languageTag] (BCP-47).
  /// Returns false when TTS is unavailable — callers show a message instead
  /// of pretending the text was read aloud.
  Future<bool> speak(String text, {String languageTag = "en-US"}) async {
    if (!_ttsReady || text.trim().isEmpty) return false;
    try {
      await _tts.setLanguage(languageTag);
      await _tts.setSpeechRate(0.45); // slightly slow: clear for all ages
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.speak(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

/// Locales OPPA ships UI support for. Map values are the BCP-47 tags passed
/// to the platform engines; keys are the app language codes. Availability is
/// checked at runtime (resolveLocale) and the UI says when a language is not
/// installed on the device.
const voiceLocales = <String, String>{
  "en": "en-US",
  "ha": "ha-NG", // Hausa (Nigeria) — engine support varies; checked at runtime
  "yo": "yo-NG", // Yoruba (Nigeria)
  "ig": "ig-NG", // Igbo (Nigeria)
  "pcm": "en-GH", // Nigerian Pidgin has no engine tag; closest English variant
  "fr": "fr-FR",
};

/// Engine locale for TTS playback. Falls back to English when a language has
/// no platform voice (the text still displays — only audio falls back).
const ttsLocales = <String, String>{
  "en": "en-US",
  "ha": "en-US",
  "yo": "en-US",
  "ig": "en-US",
  "pcm": "en-US",
  "fr": "fr-FR",
};
