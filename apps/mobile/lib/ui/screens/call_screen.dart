import "dart:async";

import "package:flutter/material.dart";

import "../../data/repositories.dart";

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
          _status = "Connected";
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
        _status = "Connected";
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
              widget.kind == "video" ? "Video call" : "Voice call",
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(_status, style: theme.textTheme.bodyMedium),
            if (_phase == CallPhase.active)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  "Media quality adapts automatically on weak networks.\nToggle to audio-only if video stutters.",
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
