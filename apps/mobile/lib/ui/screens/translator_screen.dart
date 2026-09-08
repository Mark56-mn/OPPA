import "package:flutter/material.dart";

import "../../core/translation_service.dart";
import "../../core/voice_service.dart";
import "../../data/repositories.dart";

/// OPPA Translator — voice-first translation for market women and
/// non-literate users. Flow (matches the approved UI):
///   listen (mic) → detected text → translated text → play aloud →
///   optional send-to-chat.
/// Honest states: no speech engine → "voice not available"; phrase not in
/// the offline book → "No translation for this yet" (never a guess).
class TranslatorScreen extends StatefulWidget {
  const TranslatorScreen({
    super.key,
    required this.messages,
    this.initialText,
  });

  final MessagesRepository messages;
  final String? initialText;

  @override
  State<TranslatorScreen> createState() => _TranslatorScreenState();
}

class _TranslatorScreenState extends State<TranslatorScreen> {
  final _voice = VoiceService.instance;
  final _textController = TextEditingController();
  TranslationResult _result = const TranslationResult(
    input: "",
    output: "",
    fromCode: "auto",
    toCode: "en",
    usedOfflineBook: false,
  );
  String _fromCode = "auto";
  String _toCode = "en";
  bool _listening = false;
  bool _autoSpeak = true;
  String? _voiceError;

  @override
  void initState() {
    super.initState();
    _voice.ensureReady();
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _textController.text = widget.initialText!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _translate());
    }
  }

  @override
  void dispose() {
    _voice.stopListening();
    _voice.stopSpeaking();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _voice.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final locale = voiceLocales[_fromCode == "auto" ? "en" : _fromCode] ?? "en-US";
    final started = await _voice.startListening(
      localeId: locale,
      timeout: const Duration(seconds: 8),
      onPartial: (text) {
        if (mounted) {
          setState(() {
            _textController.text = text;
            _voiceError = null;
          });
        }
      },
      onFinal: (text) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _textController.text = text;
        });
        _translate();
      },
    );
    if (!mounted) return;
    if (started) {
      setState(() {
        _listening = true;
        _voiceError = null;
      });
    } else {
      setState(() => _voiceError = _voice.sttAvailability == VoiceAvailability.unavailable
          ? "Voice input is not available on this device"
          : "Could not start listening — try again");
    }
  }

  void _translate() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _result = TranslationResult(
            input: "",
            output: "",
            fromCode: _fromCode,
            toCode: _toCode,
            usedOfflineBook: false,
          ));
      return;
    }
    final result = const TranslationService().translate(
      text: text,
      from: _fromCode,
      to: _toCode,
    );
    setState(() => _result = result);
    if (_autoSpeak && result.usedOfflineBook) {
      _voice.speak(result.output, languageTag: ttsLocaleFor(_toCode));
    }
  }

  Future<void> _playTranslation() async {
    if (_result.output.isEmpty) return;
    final ok =
        await _voice.speak(_result.output, languageTag: ttsLocaleFor(_toCode));
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("No voice installed for this language — showing text only")));
    }
  }

  Future<void> _sendToChat() async {
    if (_result.output.isEmpty) return;
    final conversationId = await _promptConversationId();
    if (conversationId == null || !mounted) return;
    final (confirmed, response) = await widget.messages.send(
        conversationId, _result.output, offline: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(confirmed
            ? "Sent to chat ✓"
            : (response?.errorCode ?? "Could not send — check your connection"))));
  }

  Future<String?> _promptConversationId() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Send to chat"),
        content: TextField(
          controller: controller,
          maxLength: 64,
          decoration: const InputDecoration(
              labelText: "Conversation id",
              helperText: "Find it under Chats"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          FilledButton(
              onPressed: () {
                final v = controller.text.trim();
                if (v.isEmpty) return;
                Navigator.pop(context, v);
              },
              child: const Text("Send")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("OPPA Translator"),
        actions: [
          IconButton(
            tooltip: _autoSpeak ? "Auto-speak on" : "Auto-speak off",
            onPressed: () => setState(() => _autoSpeak = !_autoSpeak),
            icon: Icon(_autoSpeak ? Icons.volume_up : Icons.volume_off),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Language pickers
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: _LanguageDropdown(
                        label: "Speak",
                        value: _fromCode,
                        includeAuto: true,
                        onChanged: (v) {
                          if (v != null) setState(() => _fromCode = v);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: IconButton.outlined(
                        onPressed: () => setState(() {
                          final next = _fromCode == "auto" ? "en" : _fromCode;
                          _fromCode = _toCode;
                          _toCode = next;
                          _translate();
                        }),
                        icon: const Icon(Icons.swap_horiz),
                      ),
                    ),
                    Expanded(
                      child: _LanguageDropdown(
                        label: "Translate to",
                        value: _toCode,
                        includeAuto: false,
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _toCode = v);
                            _translate();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Input area
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _listening ? "Listening…" : "Speak or type",
                          style: theme.textTheme.titleSmall?.copyWith(
                              color: _listening
                                  ? theme.colorScheme.primary
                                  : null),
                        ),
                        const Spacer(),
                        if (_listening)
                          const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ),
                    TextField(
                      controller: _textController,
                      maxLines: 2,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        counterText: "",
                        hintText: "Say or type what you want to translate",
                      ),
                      onChanged: (_) {},
                      onSubmitted: (_) => _translate(),
                    ),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _voice.canListen || _listening
                              ? _toggleListen
                              : null,
                          icon: Icon(_listening
                              ? Icons.stop
                              : Icons.mic_rounded),
                          label: Text(_listening ? "Stop" : "Speak"),
                        ),
                        const Spacer(),
                        FilledButton.tonal(
                          onPressed: _translate,
                          child: const Text("Translate"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_voiceError != null) ...[
              _HonestNote(
                  icon: Icons.mic_off_outlined,
                  text: _voiceError!,
                  color: theme.colorScheme.error),
              const SizedBox(height: 12),
            ],
            // Result
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _result.input.isEmpty
                    ? Text("Translation appears here",
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5)))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${OppaLanguage.byCode(_result.fromCode).flag} → ${OppaLanguage.byCode(_result.toCode).flag}",
                            style: theme.textTheme.labelSmall,
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            _result.output,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              FilledButton.icon(
                                onPressed: _playTranslation,
                                icon: const Icon(Icons.volume_up_rounded),
                                label: const Text("Play"),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _sendToChat,
                                icon: const Icon(Icons.send_outlined),
                                label: const Text("Send to chat"),
                              ),
                            ],
                          ),
                          if (!_result.usedOfflineBook) ...[
                            const SizedBox(height: 12),
                            _HonestNote(
                              icon: Icons.info_outline,
                              text:
                                  "No offline translation for this yet — showing your original words.",
                              color: theme.colorScheme.secondary,
                            ),
                          ],
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text("Quick phrases",
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (key, english) in TranslationService.quickPhrases)
                  ActionChip(
                    label: Text(english),
                    onPressed: () {
                      final phrase = phrasebook[key]!;
                      setState(() {
                        _textController.text = phrase.inLang("en");
                      });
                      _translate();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text("Works offline",
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              "Translated phrases live on your phone — no data needed. "
              "Voice input uses your phone's speech service.",
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({
    required this.label,
    required this.value,
    required this.includeAuto,
    required this.onChanged,
  });

  final String label;
  final String value;
  final bool includeAuto;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <(String, String)>[
      if (includeAuto) ("auto", "Detect language"),
      for (final l in OppaLanguage.all) (l.code, l.nativeName),
    ];
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final (code, name) in options)
          DropdownMenuItem(value: code, child: Text(name, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}

class _HonestNote extends StatelessWidget {
  const _HonestNote({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color)),
        ),
      ],
    );
  }
}
