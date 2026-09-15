import "dart:async";

import "package:flutter/material.dart";

import "../../core/api_client.dart";
import "../../core/connectivity_service.dart";
import "../../core/screen_data.dart";
import "../../core/session_store.dart";
import "../../core/translation_service.dart";
import "../../core/voice_service.dart";
import "../../data/repositories.dart";
import "../../design/oppa_themes.dart";
import "../widgets/common.dart";
import "call_screen.dart";
import "home_screens.dart" show ConnectScreen;
import "translator_screen.dart";
import "workspace_switcher.dart" show showWorkspaceSwitcher;

/// Chats tab (approved art): header with search + filter chips
/// (All/Unread/Groups/Businesses), conversation rows with unread badges and
/// the floating new-chat action.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({
    super.key,
    required this.conversations,
    required this.connectivity,
    required this.contacts,
    required this.profiles,
    required this.business,
    required this.messages,
    required this.notifications,
    required this.session,
    required this.themeId,
    required this.onThemeChanged,
    required this.onOpenConversation,
  });

  final ConversationsRepository conversations;
  final ConnectivityService connectivity;
  final ContactsRepository contacts;
  final ProfileRepository profiles;
  final BusinessRepository business;
  final MessagesRepository messages;
  final NotificationsRepository notifications;
  final SessionStore session;
  final OppaThemeId themeId;
  final void Function(OppaThemeId) onThemeChanged;
  final void Function(Map conversation) onOpenConversation;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

enum _ChatFilter { all, unread, groups, businesses }

class _ChatsScreenState extends State<ChatsScreen> {
  dynamic _state = const ViewLoading();
  _ChatFilter _filter = _ChatFilter.all;
  String _query = "";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const ViewLoading());
    final source = ScreenDataSource<Map>(
      connectivity: widget.connectivity,
      fetch: widget.conversations.list,
      decode: (b) => (b as Map).cast<String, dynamic>(),
      cacheKey: "conversations.list",
    );
    final result = await source.load();
    if (mounted) setState(() => _state = result);
  }

  void _openConnect() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConnectScreen(
            contacts: widget.contacts,
            conversations: widget.conversations,
            business: widget.business,
            profiles: widget.profiles)));
  }

  void _openTranslator() {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TranslatorScreen(messages: widget.messages)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chats"),
        actions: [
          IconButton(
            tooltip: "Translator",
            onPressed: _openTranslator,
            icon: const Icon(Icons.translate_rounded),
          ),
          IconButton(
            tooltip: "Search chats",
            onPressed: () => showSearch(
                context: context,
                delegate: _ConversationSearch(_state, widget.onOpenConversation)),
            icon: const Icon(Icons.search_outlined),
          ),
          // Workspace switcher: Personal ↔ Business without logout.
          IconButton(
            tooltip: "Business workspace",
            onPressed: () => showWorkspaceSwitcher(context,
                session: widget.session,
                business: widget.business,
                connectivity: widget.connectivity),
            icon: const Icon(Icons.swap_horiz_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: "New chat",
        onPressed: _openConnect,
        child: const Icon(Icons.add_comment_outlined),
      ),
      body: Column(
        children: [
          // Filter chips (approved art: All · Unread · Groups · Businesses).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                    decoration: const InputDecoration(
                      hintText: "Search chats…",
                      prefixIcon: Icon(Icons.search_outlined),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final f in _ChatFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(switch (f) {
                        _ChatFilter.all => "All",
                        _ChatFilter.unread => "Unread",
                        _ChatFilter.groups => "Groups",
                        _ChatFilter.businesses => "Businesses",
                      }),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: RefreshIndicator(onRefresh: _load, child: _buildBody(context))),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return switch (_state) {
      ViewLoading() => const StateViews.loading(),
      ViewOffline() => const StateViews.empty("Offline — chats will load when you reconnect"),
      ViewError(:final message) => StateViews.error(message, onRetry: _load),
      ViewReady<Map>(:final data) => _list(context, data),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _list(BuildContext context, Map data) {
    final all = ((data["conversations"] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final conversations = all.where((c) {
      final unread = (c["unreadCount"] as num?)?.toInt() ?? 0;
      final kind = "${c["kind"] ?? "direct"}";
      final title = "${c["title"] ?? "Direct chat"}".toLowerCase();
      if (_query.isNotEmpty && !title.contains(_query)) return false;
      return switch (_filter) {
        _ChatFilter.all => true,
        _ChatFilter.unread => unread > 0,
        _ChatFilter.groups => kind == "group",
        _ChatFilter.businesses => kind == "business",
      };
    }).toList();
    if (conversations.isEmpty) {
      return StateViews.empty(_query.isEmpty && _filter == _ChatFilter.all
          ? "No chats yet — tap + to add a contact"
          : "No chats match this filter");
    }
    return ListView.builder(
      itemCount: conversations.length,
      itemBuilder: (context, i) {
        final c = conversations[i];
        // Production field name (unreadCount); demo backend matches it.
        final unread = (c["unreadCount"] as num?)?.toInt() ?? 0;
        final kind = "${c["kind"] ?? "direct"}";
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            child: Text(_initial(c["title"] as String? ?? c["id"] as String? ?? "?")),
          ),
          title: Text(
            c["title"] as String? ?? "Direct chat",
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500),
          ),
          subtitle: Text(switch (kind) {
            "group" => "Group",
            "business" => "Business",
            _ => "Direct",
          }),
          trailing: unread > 0
              ? Badge(
                  label: Text("$unread"),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                )
              : null,
          onTap: () => widget.onOpenConversation(c),
        );
      },
    );
  }

  static String _initial(String s) => s.isEmpty ? "?" : s.characters.first.toUpperCase();
}

/// Full-screen search over the loaded conversation list (client-side over the
/// server list; no invented data).
class _ConversationSearch extends SearchDelegate<String> {
  _ConversationSearch(this._state, this.onOpen);

  final dynamic _state;
  final void Function(Map) onOpen;

  @override
  List<Widget> buildActions(BuildContext context) => [
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ""),
      ];

  @override
  Widget buildLeading(BuildContext context) =>
      BackButton(onPressed: () => close(context, ""));

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    if (_state is! ViewReady<Map>) {
      return const StateViews.empty("Chats are still loading…");
    }
    final list = (((_state as ViewReady<Map>).data["conversations"] as List?) ?? const [])
        .whereType<Map>()
        .where((c) => "${c["title"] ?? "Direct chat"}"
            .toLowerCase()
            .contains(query.toLowerCase()))
        .toList();
    if (list.isEmpty) return const StateViews.empty("No chats match");
    return ListView(
      children: [
        for (final c in list)
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: Text("${c["title"] ?? "Direct chat"}"),
            onTap: () {
              close(context, "");
              onOpen(c.cast<String, dynamic>());
            },
          ),
      ],
    );
  }
}

/// One conversation thread: real chat bubbles, voice-to-text composer,
/// per-message translate + read-aloud, offline-pending sends, read receipts.
class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.conversation,
    required this.messages,
    required this.calls,
    required this.connectivity,
  });

  final Map conversation;
  final MessagesRepository messages;
  final CallsRepository calls;
  final ConnectivityService connectivity;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _voice = VoiceService.instance;
  List<Map> _history = const [];
  bool _loading = true;
  bool _listening = false;
  String? _error;
  final Set<String> _pendingSends = {};
  // Per-message translations (messageId → translated text) and the language
  // they were rendered into, so a translate action is one tap and repeatable.
  final Map<String, TranslationResult> _translations = {};
  String _myTranslateTarget = "en";

  String get _conversationId => widget.conversation["id"] as String;

  @override
  void initState() {
    super.initState();
    _load();
    _checkIncomingCall();
    _voice.ensureReady();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _voice.stopListening();
    _voice.stopSpeaking();
    super.dispose();
  }

  /// Incoming-call pickup: when opening a thread, check the conversation's
  /// call log for a call still ringing that the user did not start. Surfacing
  /// it here (REST polling, no push dependency) keeps V1 Africa-first — the
  /// server's 2-minute ring timeout guarantees no stale ringing forever.
  Future<void> _checkIncomingCall() async {
    final r = await widget.calls.history(_conversationId);
    if (!mounted || !r.isSuccess || r.body is! Map) return;
    final calls = (((r.body as Map)["calls"] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    for (final c in calls) {
      final status = "${c["status"] ?? ""}";
      if (status != "ringing") continue;
      final callId = "${c["id"] ?? ""}";
      if (callId.isEmpty) continue;
      final invite = await widget.calls.events(_conversationId, callId, sinceSeq: 0);
      if (!mounted) return;
      final hasInvite = invite.isSuccess &&
          invite.body is Map &&
          ((invite.body as Map)["events"] as List?)
              ?.whereType<Map>()
              .any((e) => "${e["eventType"] ?? e["event_type"] ?? ""}" == "invite") ==
          true;
      if (!hasInvite) continue; // Only our own ring events; caller cancels are excluded by status.
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CallScreen(
              calls: widget.calls,
              conversationId: _conversationId,
              callId: callId,
              isCaller: false,
              kind: "${c["kind"] ?? "audio"}")));
      return;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final response = await widget.messages.history(_conversationId);
    if (!mounted) return;
    if (response.isSuccess && response.body is Map) {
      final list = ((response.body as Map)["messages"] as List?) ?? const [];
      setState(() {
        _history = list.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _loading = false;
      });
    } else if (response.kind == AttemptKind.networkError ||
        response.kind == AttemptKind.timeout) {
      setState(() {
        _error = "Offline — showing nothing cached yet";
        _loading = false;
      });
    } else {
      setState(() {
        _error = response.errorCode ?? "Could not load messages";
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final offline = widget.connectivity.state != ConnectState.online;
    final (confirmed, _) = await widget.messages.send(
      _conversationId,
      text,
      offline: offline,
    );
    if (!mounted) return;
    if (confirmed) {
      await _load();
    } else {
      setState(() => _pendingSends.add(text));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Message saved — will send when connected")));
    }
  }

  Future<void> _toggleVoiceInput() async {
    if (_listening) {
      await _voice.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final started = await _voice.startListening(
      localeId: voiceLocales[_myTranslateTarget] ?? "en-US",
      timeout: const Duration(seconds: 10),
      onPartial: (text) {
        if (mounted) _controller.text = text;
      },
      onFinal: (text) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _controller.text = text;
        });
      },
    );
    if (!mounted) return;
    if (started) {
      setState(() => _listening = true);
    } else {
      // Honest reason instead of a generic dead-end (permission vs missing
      // speech service vs busy engine).
      final message = switch (_voice.sttBlockReason) {
        SttBlockReason.permissionDenied =>
          "Microphone permission is off — allow it in Settings to dictate",
        SttBlockReason.noSpeechService =>
          "This device has no speech service — type your message instead",
        SttBlockReason.busy =>
          "Still finishing the last listen — try again in a second",
        _ => "Voice input is not available right now",
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Translates a message into [target] via the offline phrasebook and, when
  /// [speak] is set, reads it aloud (for non-literate users).
  Future<void> _translateMessage(Map message,
      {required String target, required bool speak}) async {
    final id = "${message["id"] ?? ""}";
    final body = "${message["body"] ?? ""}";
    if (body.isEmpty) return;
    final result = const TranslationService().translate(
        text: body, from: "auto", to: target);
    if (!mounted) return;
    setState(() => _translations[id] = result);
    if (speak && result.usedOfflineBook) {
      final ok =
          await _voice.speak(result.output, languageTag: ttsLocaleFor(target));
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("No voice installed for this language")));
      }
    } else if (speak) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Not in the offline phrasebook yet — no translation")));
    }
  }

  Future<void> _startCall({required bool video}) async {
    final response = await widget.calls.start(_conversationId, video: video);
    if (!mounted) return;
    if (response.isSuccess && response.body is Map) {
      final body = (response.body as Map).cast<String, dynamic>();
      final callId = "${body["call"]?["id"] ?? body["id"] ?? ""}";
      if (callId.isNotEmpty) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CallScreen(
                calls: widget.calls,
                conversationId: _conversationId,
                callId: callId,
                isCaller: true,
                kind: video ? "video" : "audio")));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Calling…")));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(response.errorCode ?? "Call failed")));
    }
  }

  Future<void> _openTranslator() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TranslatorScreen(messages: widget.messages)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.conversation["title"] ?? "Chat"}"),
        actions: [
          IconButton(
            onPressed: _openTranslator,
            icon: const Icon(Icons.translate),
            tooltip: "Translate",
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.translate_outlined),
            tooltip: "Translation language",
            onSelected: (v) => setState(() => _myTranslateTarget = v),
            itemBuilder: (_) => [
              for (final l in OppaLanguage.all)
                CheckedPopupMenuItem(
                  value: l.code,
                  checked: _myTranslateTarget == l.code,
                  child: Text(l.nativeName),
                ),
            ],
          ),
          IconButton(
            onPressed: () => _startCall(video: false),
            icon: const Icon(Icons.call_outlined),
            tooltip: "Voice call",
          ),
          IconButton(
            onPressed: () => _startCall(video: true),
            icon: const Icon(Icons.videocam_outlined),
            tooltip: "Video call",
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Material(
              color: theme.colorScheme.error.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  const Icon(Icons.cloud_off, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: theme.textTheme.bodySmall)),
                  TextButton(onPressed: _load, child: const Text("Retry")),
                ]),
              ),
            ),
          Expanded(
            child: _loading
                ? const StateViews.loading()
                : _history.isEmpty
                    ? const StateViews.empty("Say hello 👋")
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        itemCount: _history.length,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemBuilder: (context, i) {
                          final m = _history[i];
                          final isMine =
                              m["senderUserId"] != null && m["mine"] == true;
                          return _MessageBubble(
                            message: m,
                            isMine: isMine,
                            translation: _translations["${m["id"] ?? ""}"],
                            onTranslate: () => _translateMessage(m,
                                target: _myTranslateTarget, speak: false),
                            onTranslateSpeak: () => _translateMessage(m,
                                target: _myTranslateTarget, speak: true),
                          );
                        },
                      ),
          ),
          if (_pendingSends.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "${_pendingSends.length} pending — will send on reconnect",
                style: theme.textTheme.bodySmall,
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: _listening ? "Listening…" : "Message",
                        prefixIcon: IconButton(
                          icon: Icon(
                            _listening ? Icons.stop_circle : Icons.mic_none,
                            color: _listening ? theme.colorScheme.primary : null,
                          ),
                          onPressed: _toggleVoiceInput,
                          tooltip: _listening ? "Stop" : "Voice input",
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send_outlined),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A chat bubble with sender alignment, status, and translate/read-aloud
/// actions. Sent state is honest: pending shows a clock, confirmed a check.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.translation,
    required this.onTranslate,
    required this.onTranslateSpeak,
  });

  final Map message;
  final bool isMine;
  final TranslationResult? translation;
  final VoidCallback onTranslate;
  final VoidCallback onTranslateSpeak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = "${message["body"] ?? ""}";
    final time = "${message["createdAt"] ?? ""}";
    final translated = translation;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onTranslate,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: isMine
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                body,
                style: theme.textTheme.bodyLarge?.copyWith(
                    color: isMine ? theme.colorScheme.onPrimary : null),
              ),
              if (translated != null && translated.usedOfflineBook) ...[
                const SizedBox(height: 6),
                Text(
                  translated.output,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: isMine
                        ? theme.colorScheme.onPrimary.withValues(alpha: 0.9)
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time.length >= 16 ? time.substring(11, 16) : time,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: (isMine
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface)
                            .withValues(alpha: 0.6)),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onTranslateSpeak,
                    child: Icon(Icons.volume_up_outlined,
                        size: 16,
                        color: (isMine
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface)
                            .withValues(alpha: 0.6)),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onTranslate,
                    child: Icon(Icons.translate,
                        size: 16,
                        color: (isMine
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface)
                            .withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Connect tab: add contacts, block/report from the contact menu.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    required this.contacts,
    required this.connectivity,
  });

  final ContactsRepository contacts;
  final ConnectivityService connectivity;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  dynamic _state = const ViewLoading();
  final _addController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _state = const ViewLoading());
    final source = ScreenDataSource<Map>(
      connectivity: widget.connectivity,
      fetch: widget.contacts.list,
      decode: (b) => (b as Map).cast<String, dynamic>(),
      cacheKey: "contacts.list",
    );
    final result = await source.load();
    if (mounted) setState(() => _state = result);
  }

  Future<void> _addContact() async {
    final userId = _addController.text.trim();
    if (userId.isEmpty) return;
    final response = await widget.contacts.add(userId);
    if (!mounted) return;
    _addController.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(response.isSuccess
            ? "Contact added"
            : (response.errorCode ?? "Could not add contact"))));
    if (response.isSuccess) _load();
  }

  Future<void> _block(Map contact) async {
    final response = await widget.contacts.block(contact["userId"] as String);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(response.isSuccess ? "Blocked" : "Could not block")));
    _load();
  }

  Future<void> _report(Map contact) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text("Report user"),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(hintText: "What happened?"),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text("Report")),
          ],
        );
      },
    );
    if (reason == null || reason.isEmpty) return;
    final response = await widget.contacts.report(contact["userId"] as String, reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(response.isSuccess
            ? "Report sent — thank you"
            : (response.errorCode ?? "Could not send report"))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Connect")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addController,
                    decoration: const InputDecoration(hintText: "User id"),
                  ),
                ),
                IconButton.filled(onPressed: _addContact, icon: const Icon(Icons.person_add_alt)),
              ],
            ),
          ),
          Expanded(
            child: switch (_state) {
              ViewLoading() => const StateViews.loading(),
              ViewOffline() => const StateViews.empty("Offline"),
              ViewError(:final message) => StateViews.error(message, onRetry: _load),
              ViewReady<Map>(:final data) => _list(data),
              _ => const SizedBox.shrink(),
            },
          ),
        ],
      ),
    );
  }

  Widget _list(Map data) {
    final contacts = (data["contacts"] as List?) ?? const [];
    if (contacts.isEmpty) return const StateViews.empty("No contacts yet");
    return ListView.builder(
      itemCount: contacts.length,
      itemBuilder: (context, i) {
        final c = (contacts[i] as Map).cast<String, dynamic>();
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text("${c["nickname"] ?? c["userId"]}"),
          subtitle: Text("${c["phone"] ?? ""}"),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == "block") _block(c);
              if (v == "report") _report(c);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: "block", child: Text("Block")),
              PopupMenuItem(value: "report", child: Text("Report")),
            ],
          ),
        );
      },
    );
  }
}

// Shorthand import alias to keep screen files tidy.
typedef DataSource = ScreenDataSource<dynamic>;
