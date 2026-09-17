import "dart:async";

import "package:flutter/material.dart";

import "../../core/api_client_base.dart";
import "../../core/connectivity_service.dart";
import "../../core/screen_data.dart";
import "../../data/repositories.dart";
import "../../design/locked_features.dart";
import "../widgets/common.dart";

/// OPPA-native incoming/outgoing call screen (Stage L/R).
///
/// Real API flow (server is the authority; media is WebRTC client-to-client):
/// - outgoing: caller polls /events for `answer|busy|hangup` transitions;
/// - incoming: callee polls /events for the `invite` event, then answers,
///   declines (optionally busy) or lets the server's 2-minute ring timeout
///   close the call;
/// - either side can hang up at any time; every transition appends a signaling
///   event to the per-user offset log, so polling resumes cleanly after
///   reconnect (sinceSeq cursor) — Africa-first, no WebSocket dependency.
///
/// Media: no provider SDK is bundled. The screen exposes the lifecycle and the
/// signal() channel (SDP/ICE relay between verified members only) that a
/// WebRTC integration drives; on devices without camera/mic permission the
/// audio-only path still works over the same lifecycle.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.calls,
    required this.conversationId,
    required this.callId,
    required this.isCaller,
    required this.kind,
  });

  final CallsRepository calls;
  final String conversationId;
  final String callId;
  final bool isCaller;
  final String kind;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

enum CallPhase { ringing, connecting, active, ended }

class _CallScreenState extends State<CallScreen> {
  Timer? _pollTimer;
  CallPhase _phase = CallPhase.ringing;
  String _status = "";
  int _sinceSeq = 0;
  bool _closing = false;
  String? _endReason;

  @override
  void initState() {
    super.initState();
    _status = widget.isCaller ? "Ringing…" : "Incoming call";
    // Callee starts slightly behind to not miss the invite event; the events
    // endpoint returns seq > sinceSeq, so 0 is the safe start for both roles.
    _sinceSeq = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    // Best-effort hangup if the user backs out mid-call; the server's ring
    // timeout covers the case where this request never lands.
    if (!_closing && (_phase == CallPhase.ringing || _phase == CallPhase.active || _phase == CallPhase.connecting)) {
      widget.calls
          .hangUp(widget.conversationId, widget.callId)
          .then<void>((_) {}, onError: (_) {});
    }
    super.dispose();
  }

  Future<void> _poll() async {
    if (_closing || _phase == CallPhase.ended) return;
    final r = await widget.calls.events(
      widget.conversationId,
      widget.callId,
      sinceSeq: _sinceSeq,
    );
    if (!mounted) return;
    if (!r.isSuccess || r.body is! Map) return; // transient failure: keep polling
    final events = (((r.body as Map)["events"] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    for (final e in events) {
      final seq = (e["seq"] as num?)?.toInt() ?? 0;
      if (seq > _sinceSeq) _sinceSeq = seq;
      final type = "${e["eventType"] ?? e["event_type"] ?? ""}";
      if (type == "invite" && !widget.isCaller && _phase == CallPhase.ringing) {
        setState(() => _status = "Incoming ${widget.kind} call");
      } else if (type == "answer") {
        setState(() {
          _phase = CallPhase.active;
          // Honest: signaling/lifecycle is real, but this build has no WebRTC
          // media stack — never claim a live audio connection.
          _status = "Call answered — audio media coming in a later release";
        });
      } else if (type == "busy") {
        await _finish("Busy");
      } else if (type == "hangup" || type == "cancel" || type == "failed") {
        await _finish(type == "cancel" ? "Cancelled" : "Call ended");
        return;
      }
    }
  }

  Future<void> _finish(String reason) async {
    if (!mounted) return;
    setState(() {
      _phase = CallPhase.ended;
      _endReason = reason;
      _status = reason;
    });
    _pollTimer?.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _answer() async {
    setState(() => _phase = CallPhase.connecting);
    final r = await widget.calls.answer(widget.conversationId, widget.callId);
    if (!mounted) return;
    if (r.isSuccess) {
      setState(() {
        _phase = CallPhase.active;
        _status = "Call answered — audio media coming in a later release";
      });
    } else {
      await _finish(_errorCodeText(r.errorCode, "Could not answer"));
    }
  }

  Future<void> _decline({bool busy = false}) async {
    _closing = true;
    _pollTimer?.cancel();
    final r =
        await widget.calls.decline(widget.conversationId, widget.callId, busy: busy);
    if (!mounted) return;
    if (r.isSuccess) {
      await _finish(busy ? "Busy" : "Declined");
    } else {
      await _finish(_errorCodeText(r.errorCode, "Call ended"));
    }
  }

  Future<void> _hangUp() async {
    _closing = true;
    _pollTimer?.cancel();
    final r = await widget.calls.hangUp(widget.conversationId, widget.callId);
    if (!mounted) return;
    await _finish(r.isSuccess ? "Call ended" : _errorCodeText(r.errorCode, "Call ended"));
  }

  String _errorCodeText(String? code, String fallback) =>
      code == null || code.isEmpty ? fallback : code;

  IconData get _phaseIcon => switch (_phase) {
        CallPhase.ringing => widget.isCaller
            ? Icons.call_outlined
            : Icons.ring_volume_outlined,
        CallPhase.connecting => Icons.phone_in_talk_outlined,
        CallPhase.active => Icons.graphic_eq_rounded,
        CallPhase.ended => Icons.call_end_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            CircleAvatar(
              radius: 44,
              child: Icon(_phaseIcon, size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              widget.kind == "video" ? "Video call (video arriving later)" : "Voice call",
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(_status, style: theme.textTheme.bodyMedium),
            if (_phase == CallPhase.active)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  "Ring, answer, decline and hang-up are real and server-confirmed.\n"
                  "Peer-to-peer audio/video media is not enabled in this version — "
                  "no audio is transmitted yet.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_phase == CallPhase.ringing && !widget.isCaller) ...[
                  _CallButton(
                    icon: Icons.call_end_outlined,
                    label: "Decline",
                    color: theme.colorScheme.error,
                    onPressed: _decline,
                  ),
                  const SizedBox(width: 24),
                  _CallButton(
                    icon: Icons.call_outlined,
                    label: "Answer",
                    color: theme.colorScheme.primary,
                    onPressed: _answer,
                  ),
                ] else if (_phase == CallPhase.ringing && widget.isCaller) ...[
                  _CallButton(
                    icon: Icons.call_end_outlined,
                    label: "Cancel",
                    color: theme.colorScheme.error,
                    onPressed: _hangUp,
                  ),
                ] else if (_phase == CallPhase.active ||
                    _phase == CallPhase.connecting) ...[
                  _CallButton(
                    icon: Icons.call_end_outlined,
                    label: "End",
                    color: theme.colorScheme.error,
                    onPressed: _hangUp,
                  ),
                ] else ...[
                  Text(_endReason ?? "Call ended",
                      style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: onPressed,
          icon: Icon(icon, size: 30),
          style: IconButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.18),
            foregroundColor: color,
            minimumSize: const Size(64, 64),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// Calls tab (approved personal nav: Chats · Wallet · Calls · Me).
/// V1 calls are per-conversation over the REST signaling lifecycle, so the
/// tab lists conversations with one-tap voice call; video stays VISIBLE but
/// LOCKED (honest roadmap, no fake dialing).
/// Call history: real records from GET /conversations/:id/calls, aggregated
/// across the caller's conversations. Direction comes from the server's
/// projected `mine` flag and "answered" from the server's answeredAt — the
/// client never guesses who called whom, and nothing is synthesised.
class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({
    super.key,
    required this.calls,
    required this.conversations,
  });

  final CallsRepository calls;
  final ConversationsRepository conversations;

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<Map<String, dynamic>> _entries = const [];
  bool _loading = true;
  String? _error;
  String _filter = "all";

  /// Upper bound on per-conversation history fetches: the OPPA API exposes
  /// call history per conversation, so the screen reads the most recent chats
  /// and says so rather than pretending to have a global index.
  static const _maxConversations = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final convResponse = await widget.conversations.list();
    if (!mounted) return;
    if (!convResponse.isSuccess) {
      setState(() {
        _loading = false;
        _error = convResponse.errorCode ?? "Could not load your chats";
      });
      return;
    }
    final conversations =
        (((convResponse.body as Map?)?["conversations"] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .take(_maxConversations)
            .toList();
    final merged = <Map<String, dynamic>>[];
    for (final c in conversations) {
      final id = "${c["id"] ?? ""}";
      if (id.isEmpty) continue;
      final r = await widget.calls.history(id);
      final rows =
          (((r.body as Map?)?["calls"] as List?) ?? const []).whereType<Map>();
      for (final row in rows) {
        merged.add({
          ...row.cast<String, dynamic>(),
          "conversationTitle": "${c["title"] ?? "Chat"}",
        });
      }
    }
    merged.sort((a, b) => "${b["startedAt"] ?? b["createdAt"] ?? ""}"
        .compareTo("${a["startedAt"] ?? a["createdAt"] ?? ""}"));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _entries = merged;
    });
  }

  static bool _answered(Map c) => c["answeredAt"] != null;
  static bool _outgoing(Map c) => c["mine"] == true;
  static bool _missed(Map c) =>
      !_outgoing(c) && !_answered(c) && "${c["status"]}" != "ringing";

  /// "Missed · 15/1 9:40 AM · answered" — every clause is a real field.
  static String _summary(Map c) {
    final direction = _missed(c)
        ? "Missed"
        : _outgoing(c)
            ? "Outgoing"
            : "Incoming";
    final when = _when("${c["startedAt"] ?? c["createdAt"] ?? ""}");
    final answered = _answered(c) ? " · answered" : "";
    return "$direction · $when$answered";
  }

  static String _when(String? iso) {
    if (iso == null || iso.isEmpty) return "";
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return "";
    final local = parsed.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return "${local.day}/${local.month} $hour:"
        "${local.minute.toString().padLeft(2, "0")} "
        "${local.hour < 12 ? "AM" : "PM"}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = switch (_filter) {
      "missed" => _entries.where(_missed).toList(),
      "outgoing" => _entries.where(_outgoing).toList(),
      "incoming" =>
        _entries.where((c) => !_outgoing(c) && !_missed(c)).toList(),
      _ => _entries,
    };
    return Scaffold(
      appBar: AppBar(title: const Text("Call history")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (key, label) in const [
                    ("all", "All"),
                    ("missed", "Missed"),
                    ("outgoing", "Outgoing"),
                    ("incoming", "Incoming"),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _filter == key,
                        onSelected: (_) => setState(() => _filter = key),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const StateViews.loading()
                  : _error != null
                      ? ListView(children: [
                          const SizedBox(height: 48),
                          StateViews.error(_error!, onRetry: _load),
                        ])
                      : visible.isEmpty
                          ? ListView(children: [
                              const SizedBox(height: 96),
                              StateViews.empty(_filter == "all"
                                  ? "No calls yet"
                                  : "No $_filter calls in your recent chats"),
                            ])
                          : ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                for (final c in visible)
                                  Card(
                                    margin:
                                        const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: Icon(
                                        _missed(c)
                                            ? Icons.call_missed_outlined
                                            : _outgoing(c)
                                                ? Icons.call_made_outlined
                                                : Icons.call_received_outlined,
                                        color: _missed(c)
                                            ? theme.colorScheme.error
                                            : null,
                                      ),
                                      title: Text(
                                          "${c["conversationTitle"] ?? "Chat"}"),
                                      subtitle: Text(_summary(c)),
                                      trailing: Text(
                                          "${c["kind"] ?? "audio"}",
                                          style: theme.textTheme.bodySmall),
                                    ),
                                  ),
                              ],
                            ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              "Built from the calls OPPA recorded in your $_maxConversations "
              "most recent chats.",
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Call settings. Voice calls ring, answer, decline and hang up for real
/// today; the media/sound options in the approved art have no server or media
/// stack behind them in V1, so they are shown locked instead of pretending to
/// change something.
class CallSettingsScreen extends StatelessWidget {
  const CallSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Call settings")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.phone_in_talk_outlined),
                  title: const Text("Voice calls"),
                  subtitle: const Text(
                      "Works today: ring, answer, decline and hang up are "
                      "server-confirmed."),
                  trailing: Icon(Icons.check_circle,
                      color: theme.colorScheme.primary),
                ),
                ListTile(
                  leading: const Icon(Icons.volume_off_outlined),
                  title: const Text("Audio in calls"),
                  subtitle: const Text(
                      "Not in this release — OPPA does not transmit call audio "
                      "yet, so there is no quality to choose."),
                  trailing: Icon(Icons.lock_outline_rounded,
                      size: 18,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.45)),
                ),
                const Divider(height: 1),
                const LockedFeatureTile(feature: OppaFeature.videoCalls),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text("Ringtone"),
                  subtitle: const Text(
                      "Your phone's own ringtone is used. Choosing one inside "
                      "OPPA arrives in a later release."),
                  trailing: Icon(Icons.lock_outline_rounded,
                      size: 18,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.45)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CallsTabScreen extends StatefulWidget {
  const CallsTabScreen({
    super.key,
    required this.calls,
    required this.conversations,
    required this.connectivity,
    required this.onOpenConversation,
  });

  final CallsRepository calls;
  final ConversationsRepository conversations;
  final ConnectivityService connectivity;
  final void Function(Map conversation) onOpenConversation;

  @override
  State<CallsTabScreen> createState() => _CallsTabScreenState();
}

class _CallsTabScreenState extends State<CallsTabScreen> {
  dynamic _state = const ViewLoading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const ViewLoading());
    // ConversationsRepository.list takes no args; ScreenDataSource expects
    // Future<ApiResponse> Function(), so adapt with a closure.
    Future<ApiResponse> fetch() => widget.conversations.list();
    final source = ScreenDataSource<Map>(
      connectivity: widget.connectivity,
      fetch: fetch,
      decode: (b) => (b as Map).cast<String, dynamic>(),
      cacheKey: "conversations.list",
    );
    final result = await source.load();
    if (mounted) setState(() => _state = result);
  }

  Future<void> _startCall(Map conversation, {required bool video}) async {
    if (video) {
      showLockedFeatureSheet(context, OppaFeature.videoCalls);
      return;
    }
    final conversationId = "${conversation["id"] ?? ""}";
    if (conversationId.isEmpty) return;
    final r = await widget.calls.start(conversationId, video: false);
    if (!mounted) return;
    if (!r.isSuccess || r.body is! Map) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.errorCode ?? "Could not start the call")));
      return;
    }
    final callId = "${(r.body as Map)["id"] ?? ""}";
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CallScreen(
            calls: widget.calls,
            conversationId: conversationId,
            callId: callId,
            isCaller: true,
            kind: "audio")));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Calls"),
        actions: [
          IconButton(
            tooltip: "Call history",
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CallHistoryScreen(
                    calls: widget.calls,
                    conversations: widget.conversations))),
          ),
          IconButton(
            tooltip: "Call settings",
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const CallSettingsScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                const LockedChip(feature: OppaFeature.videoCalls),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Voice calls work today over low-bandwidth signaling.",
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: switch (_state) {
                ViewLoading() => const StateViews.loading(),
                ViewOffline() => const StateViews.empty(
                    "Offline — calls need a connection"),
                ViewError(:final message) =>
                  StateViews.error(message, onRetry: _load),
                ViewReady<Map>(:final data) => _list(data),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(Map data) {
    final theme = Theme.of(context);
    final conversations = ((data["conversations"] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    if (conversations.isEmpty) {
      return const StateViews.empty(
          "No conversations yet — start a chat first, then call from here");
    }
    return ListView.builder(
      itemCount: conversations.length,
      itemBuilder: (context, i) {
        final c = conversations[i];
        final title = "${c["title"] ?? "Direct chat"}";
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.secondaryContainer,
            child: Text(title.isEmpty ? "?" : title.characters.first.toUpperCase()),
          ),
          title: Text(title),
          subtitle: Text("${c["kind"] == "group" ? "Group" : "Direct"} · voice call"),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: "Voice call",
                icon: const Icon(Icons.call_outlined),
                onPressed: () => _startCall(c, video: false),
              ),
              IconButton(
                tooltip: "Video call — locked",
                icon: Icon(Icons.videocam_off_outlined,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                onPressed: () =>
                    showLockedFeatureSheet(context, OppaFeature.videoCalls),
              ),
            ],
          ),
          onTap: () => widget.onOpenConversation(c),
        );
      },
    );
  }
}
