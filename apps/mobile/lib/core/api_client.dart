import "dart:async";
import "dart:convert";
import "dart:math";

import "package:http/http.dart" as http;

/// Result of a single API attempt, classified for retry logic.
enum AttemptKind { success, clientError, serverError, networkError, timeout }

/// Retry safety classification for mutations.
///
/// - [safe]: retrying after an ambiguous transport failure cannot duplicate
///   server effects (GET/HEAD, idempotent-by-key mutations where the server
///   de-duplicates the client key, or deletes).
/// - [unsafe]: the request may have landed server-side even though the
///   response was lost (payment initialization, transfers, OTP sends).
///   Blindly retrying could double-charge or double-send; the caller must
///   confirm state with a safe read before re-submitting.
enum RetrySafety { safe, unsafe }

/// Methods/paths whose *ambiguous* failures are safe to retry.
///
/// POST endpoints that are server-side idempotent by an explicit client key
/// (message sends carry clientMessageId) are safe: a lost response followed
/// by a retry resolves to the same message row via ON CONFLICT.
const _ambiguousSafePrefixes = <String>{
  "/conversations/", // message.send carries clientMessageId (server idempotent)
  "/business/orders/", // order pay/fulfill/cancel are single-transition server-side
  "/notifications/read", // read markers are monotonic/idempotent
  "/security/step-up/challenge", // one active challenge per user+purpose
};

/// Exposed for tests: which requests may be blindly retried after an
/// ambiguous (network/timeout) failure.
RetrySafety retrySafetyFor(String method, String path) => _retrySafety(method, path);

RetrySafety _retrySafety(String method, String path) {
  final m = method.toUpperCase();
  if (m == "GET" || m == "HEAD" || m == "OPTIONS") return RetrySafety.safe;
  if (m == "DELETE" || m == "PUT") return RetrySafety.safe;
  // POST: only known server-idempotent prefixes may be blindly retried.
  final clean = path.startsWith("/") ? path : "/$path";
  if (_ambiguousSafePrefixes.any((p) => clean.startsWith(p) || clean.startsWith("/v1$p"))) {
    return RetrySafety.safe;
  }
  return RetrySafety.unsafe;
}

class ApiResponse {
  final AttemptKind kind;
  final int? statusCode;
  final dynamic body;
  final String? errorCode;
  ApiResponse({required this.kind, this.statusCode, this.body, this.errorCode});

  bool get isSuccess => kind == AttemptKind.success;
  bool get isAuthError => errorCode == "OTP_INVALID_OR_EXPIRED" ||
      errorCode == "REFRESH_TOKEN_INVALID" ||
      statusCode == 401;
  bool get isRetryable =>
      kind == AttemptKind.networkError ||
      kind == AttemptKind.timeout ||
      kind == AttemptKind.serverError;
}

/// Real HTTP client for the OPPA API.
///
/// Africa-first network behavior:
/// - every request has a timeout (no hanging sockets on weak networks);
/// - retry classification: network/timeout/5xx retry, 4xx never retries;
/// - ENDPOINT-AWARE: ambiguous transport failures are only retried for
///   provably idempotent operations (reads, deletes, keyed POSTs). Financial
///   mutations (e.g. /wallet/transfer, /payments/initialize, /auth/*) are
///   never blindly retried after a lost response — the caller must reconcile
///   state with a safe read first;
/// - exponential backoff with jitter: 1s, 2s, 4s (+/- 30%) capped at 15s;
/// - compact JSON bodies; no polling loops inside the client itself.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? client,
    this.accessTokenGetter,
    this.onAuthError,
    this.maxRetries = 3,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Future<String?> Function()? accessTokenGetter;
  final Future<void> Function()? onAuthError;
  final int maxRetries;
  final Duration timeout;
  final Random _random = Random();

  Uri _uri(String path, [Map<String, String>? query]) {
    final clean = path.startsWith("/") ? path : "/$path";
    return Uri.parse("$baseUrl$v1Prefix$clean").replace(queryParameters: query);
  }

  static const v1Prefix = "/v1";

  Future<ApiResponse> get(String path, {Map<String, String>? query}) =>
      _send("GET", path, query: query);

  Future<ApiResponse> post(String path, {Object? body}) =>
      _send("POST", path, body: body);

  Future<ApiResponse> patch(String path, {Object? body}) =>
      _send("PATCH", path, body: body);

  Future<ApiResponse> put(String path, {Object? body}) =>
      _send("PUT", path, body: body);

  Future<ApiResponse> delete(String path) => _send("DELETE", path);

  Future<ApiResponse> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final safety = _retrySafety(method, path);
    var attempt = 0;
    while (true) {
      attempt += 1;
      final result = await _attempt(method, path, body: body, query: query);
      if (result.isSuccess ||
          !result.isRetryable ||
          attempt > maxRetries ||
          // Endpoint-aware: ambiguous failures on non-idempotent mutations
          // (e.g. /payments/initialize, /wallet/transfer, /auth/otp/*) are
          // NEVER retried — the request may have landed; the caller must
          // reconcile with a safe read instead of risking double effects.
          (safety == RetrySafety.unsafe &&
              (result.kind == AttemptKind.networkError ||
                  result.kind == AttemptKind.timeout))) {
        // A 401 on an authenticated call triggers session refresh upstream.
        if (result.isAuthError && onAuthError != null && attempt == 1) {
          await onAuthError!();
          continue; // One re-authenticated retry, then accept the result.
        }
        return result;
      }
      // Exponential backoff with 30% jitter, capped.
      final base = min(15000, 1000 * (1 << min(attempt, 4)));
      final jitter = (base * 0.3 * (_random.nextDouble() * 2 - 1)).round();
      await Future<void>.delayed(Duration(milliseconds: base + jitter));
    }
  }

  Future<ApiResponse> _attempt(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final headers = <String, String>{"accept": "application/json"};
    final token = await accessTokenGetter?.call();
    if (token != null && token.isNotEmpty) headers["authorization"] = "Bearer $token";
    if (body != null) headers["content-type"] = "application/json";

    try {
      final response = await _client
          .send(http.Request(method, _uri(path, query))
            ..headers.addAll(headers)
            ..body = body == null ? "" : jsonEncode(body))
          .timeout(timeout);
      dynamic decoded;
      final isJson = response.headers["content-type"].toString().contains("json");
      var errorCode = "";
      if (isJson) {
        try {
          decoded = jsonDecode(await response.stream.bytesToString());
        } catch (_) {
          decoded = null;
        }
        errorCode = decoded is Map && decoded["error"] is String
            ? decoded["error"] as String
            : "";
      } else {
        await response.stream.drain<void>();
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse(
            kind: AttemptKind.success, statusCode: response.statusCode, body: decoded);
      }
      return ApiResponse(
        kind: response.statusCode < 500
            ? AttemptKind.clientError
            : AttemptKind.serverError,
        statusCode: response.statusCode,
        body: decoded,
        errorCode: errorCode.isEmpty ? null : errorCode,
      );
    } on TimeoutException {
      return ApiResponse(kind: AttemptKind.timeout);
    } on SocketExceptionLike {
      return ApiResponse(kind: AttemptKind.networkError);
    } catch (_) {
      // http package surfaces network failures as assorted exceptions; treat
      // unknown transport errors as network errors (retryable) rather than
      // silently swallowing them as client errors.
      return ApiResponse(kind: AttemptKind.networkError);
    }
  }
}

/// Marker for transport-level failures (kept dependency-free).
class SocketExceptionLike implements Exception {}
