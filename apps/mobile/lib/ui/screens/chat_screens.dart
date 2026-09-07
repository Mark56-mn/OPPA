import "dart:async";

import "package:flutter/material.dart";

import "../../core/api_client.dart";
import "../../core/connectivity_service.dart";
import "../../core/screen_data.dart";
import "../../data/repositories.dart";
import "../widgets/common.dart";
import "call_screen.dart";

/// Chats tab: conversation list with unread counts, cache-first.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({
    super.key,
    required this.conversations,
    required this.connectivity,
    required this.onOpenConversation,
  });

  final ConversationsRepository conversations;
  final ConnectivityService connectivity;
  final void Function(Map conversation) onOpenConversation;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  dynamic _state = const ViewLoading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const ViewLoading());
    final source = DataSource(
      connectivity: widget.connectivity,
      fetch: widget.conversations.list,
      decode: (b) => (b as Map).cast<String, dynamic>(),
      cacheKey: "conversations.list",
    );
    final result = await source.load();
    if (mounted) setState(() => _state = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Chats")),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
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
    final conversations = (data["conversations"] as List?) ?? const [];
    if (conversations.isEmpty) {
      return const StateViews.empty("No chats yet — add a contact to start");
    }
    return ListView.builder(
      itemCount: conversations.length,
      itemBuilder: (context, i) {
        final c = (conversations[i] as Map).cast<String, dynamic>();
        return ListTile(
          leading: CircleAvatar(
            child: Text(_initial(c["title"] as String? ?? c["id"] as String? ?? "?")),
          ),
          title: Text(c["title"] as String? ?? "Direct chat"),
          subtitle: Text(c["kind"] == "group" ? "Group" : "Direct"),
          trailing: ((c["unread"] as num?)?.toInt() ?? 0) > 0
              ? Badge(label: Text("${c["unread"]}"))
              : null,
          onTap: () => widget.onOpenConversation(c),
        );
      },
    );
  }

  static String _initial(String s) => s.isEmpty ? "?" : s.characters.first.toUpperCase();
}

/// One conversation thread: history, offline-pending sends, read receipts.
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
  List<Map> _history = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _pendingSends = {};

  String get _conversationId => widget.conversation["id"] as String;

  @override
  void initState() {
    super.initState();
    _load();
    _checkIncomingCall();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.conversation["title"] ?? "Chat"}"),
        actions: [
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
                        itemBuilder: (context, i) {
                          final m = _history[i];
                          return ListTile(
                            title: Text("${m["body"] ?? ""}"),
                            subtitle: Text("${m["createdAt"] ?? ""}"),
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
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                          hintText: "Message"), 
                      onSubmitted: (_) => _send(),
                    ),
                  ),
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
    final source = DataSource(
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
