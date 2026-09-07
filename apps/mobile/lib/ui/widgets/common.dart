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

/// Standard loading / empty / error states for all screens.
sealed class StateViews extends StatelessWidget {
  const StateViews({super.key});

  const factory StateViews.loading({Key? key}) = _LoadingViews;

  const factory StateViews.empty(String message, {Key? key}) = _EmptyViews;

  const factory StateViews.error(String message,
      {Key? key, VoidCallback? onRetry}) = _ErrorViews;
}

class _LoadingViews extends StateViews {
  const _LoadingViews({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _EmptyViews extends StateViews {
  const _EmptyViews(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 48,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}

class _ErrorViews extends StateViews {
  const _ErrorViews(this.message, {super.key, this.onRetry});

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
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text("Retry")),
            ],
          ],
        ),
      ),
    );
  }
}
