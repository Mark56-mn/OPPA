import "dart:async";

import "package:flutter_tts/flutter_tts.dart";
import "package:speech_to_text/speech_to_text.dart" as stt;

/// Voice capability state reported honestly to the UI. Never fakes
/// availability: if a device has no speech service (common on low-end or
/// stripped-down Android builds) callers surface "voice not available"
/// instead of a silent dead button.
enum VoiceAvailability { unknown, checking, available, unavailable }

/// Single wrapper over on-device speech-to-text and text-to-speech.
///
/// Africa-first notes:
/// - recognition runs through the platform speech service (offline where the
///   device supports it, e.g. Gboard downloaded language packs);
/// - nothing is uploaded by this app — audio goes only to the platform
///   engine the user already has;
/// - TTS speaks the recognized/translated text back for non-literate users;
/// - every failure path is reported as a state, never as fabricated text.
class VoiceService {
  VoiceService._();

  static final VoiceService instance = VoiceService._();

  final stt.SpeechToText _stt = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _sttReady = false;
  bool _ttsReady = false;

  VoiceAvailability sttAvailability = VoiceAvailability.unknown;
  VoiceAvailability ttsAvailability = VoiceAvailability.unknown;

  /// Prepares both engines. Safe to call repeatedly (e.g. each time a screen
  /// opens). Completes with an honest availability state either way.
  Future<void> ensureReady() async {
    if (sttAvailability == VoiceAvailability.checking ||
        ttsAvailability == VoiceAvailability.checking) {
      return;
    }
    if (sttAvailability == VoiceAvailability.unknown) {
      sttAvailability = VoiceAvailability.checking;
      try {
        _sttReady = await _stt.initialize(
          onError: (_) {},
          onStatus: (_) {},
        );
        sttAvailability = _sttReady
            ? VoiceAvailability.available
            : VoiceAvailability.unavailable;
      } catch (_) {
        _sttReady = false;
        sttAvailability = VoiceAvailability.unavailable;
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
  bool get canListen => _sttReady;

  /// Starts listening. [onPartial] fires live as words are recognized so the
  /// user sees their name/text appear as they speak. Returns false when the
  /// engine could not start (permission denied, no service, already busy).
  Future<bool> startListening({
    required void Function(String text) onPartial,
    required void Function(String finalText) onFinal,
    required String localeId,
    Duration? timeout,
  }) async {
    if (!_sttReady) return false;
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
        localeId: localeId,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
    } catch (_) {
      return false;
    }
    if (!available) return false;
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
/// to the platform engines; keys are the app language codes.
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
