import "dart:async";
import "dart:convert";

import "api_client.dart";
import "connectivity_service.dart";

/// Generic view state for every screen: loading / ready / error / offline.
/// Africa-first: cached data renders immediately; freshness is best-effort.
sealed class ViewState {
  const ViewState();
}

class ViewLoading extends ViewState {
  const ViewLoading();
}

class ViewReady<T> extends ViewState {
  const ViewReady(this.data, {this.fromCache = false});
  final T data;
  final bool fromCache;
}

class ViewError extends ViewState {
  const ViewError(this.message, {this.canRetry = true});
  final String message;
  final bool canRetry;
}

class ViewOffline<T> extends ViewState {
  const ViewOffline(this.cachedData);
  final T? cachedData;
}

/// Data source for one screen: cache-first loads with honest offline/error
/// states. Never fabricates data — cache miss + offline = ViewOffline(null).
class ScreenDataSource<T> {
  ScreenDataSource({
    required this.connectivity,
    required this.fetch,
    required this.decode,
    required this.cacheKey,
  });

  final ConnectivityService connectivity;
  final Future<ApiResponse> Function() fetch;
  final T Function(dynamic body) decode;
  final String cacheKey;

  /// In-memory cache of raw JSON bodies keyed per screen; persisted via the
  /// app-level writer so state survives restarts.
  static final Map<String, String> _cache = <String, String>{};
  static Future<void> Function(String key, String value)? _writer;

  /// App-level cache writer (wired to SharedPreferences in main.dart).
  static void setCacheWriter(Future<void> Function(String, String) w) =>
      _writer = w;

  T? get cached {
    final raw = _cache[cacheKey];
    if (raw == null) return null;
    try {
      return decode(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<ViewState> load() async {
    final response = await fetch();
    if (response.isSuccess) {
      connectivity.markAlive();
      try {
        final data = decode(response.body);
        final raw = jsonEncode(response.body);
        _cache[cacheKey] = raw;
        unawaited(_writer?.call(cacheKey, raw).catchError((_) {}));
        return ViewReady<T>(data);
      } catch (_) {
        return const ViewError("Malformed response from server", canRetry: true);
      }
    }
    if (response.kind == AttemptKind.networkError ||
        response.kind == AttemptKind.timeout) {
      connectivity.markUnreachable();
      final c = cached;
      return c != null ? ViewReady<T>(c, fromCache: true) : ViewOffline<T>(null);
    }
    return ViewError(
      response.errorCode ?? "Something went wrong",
      canRetry: true,
    );
  }
}
