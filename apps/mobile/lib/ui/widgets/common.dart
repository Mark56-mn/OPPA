import "package:flutter/material.dart";

/// Status banner for offline / reconnecting / pending states.
/// Honest-state UI: the user always knows what the app knows.
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.state, this.pendingCount = 0});

  final String state; // online | reconnecting | offline
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state == "online" && pendingCount == 0) return const SizedBox.shrink();
    final (String label, Color color, IconData icon) = switch ((state, pendingCount > 0)) {
      ("offline", _) => ("Offline — changes will send when you reconnect", theme.colorScheme.error, Icons.cloud_off),
      ("reconnecting", _) => ("Reconnecting…", theme.colorScheme.secondary, Icons.sync),
      (_, true) => ("$pendingCount change(s) waiting to send", theme.colorScheme.secondary, Icons.schedule_send),
      (_, false) => ("", theme.colorScheme.secondary, Icons.sync),
    };
    return Material(
      color: color.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: theme.textTheme.bodySmall?.copyWith(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

enum _StateKind { loading, empty, error }

/// Standard loading / empty / error states for all screens.
class StateViews extends StatelessWidget {
  const StateViews.loading({super.key})
      : _kind = _StateKind.loading,
        message = "",
        onRetry = null;

  const StateViews.empty(this.message, {super.key})
      : _kind = _StateKind.empty,
        onRetry = null;

  const StateViews.error(this.message, {super.key, this.onRetry})
      : _kind = _StateKind.error;

  final _StateKind _kind;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_kind == _StateKind.loading) const CircularProgressIndicator(),
            if (_kind == _StateKind.empty)
              Icon(Icons.inbox_outlined, size: 48,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            if (_kind == _StateKind.error)
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            if (_kind != _StateKind.loading)
              Text(message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
            if (_kind == _StateKind.error && onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text("Retry")),
            ],
          ],
        ),
      ),
    );
  }
}
