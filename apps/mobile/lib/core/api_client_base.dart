// Transport contract every repository depends on.
//
// The real ApiClient (see `api_client.dart`) implements this over HTTP with
// retry/backoff; `demo_backend.dart` implements it in-process for the
// compile-time demo build. Repositories, SessionStore and OutboundQueue are
// written against this interface only, so demo mode swaps the entire data
// layer through one injection point and production code paths are unchanged.

library;

/// Result of a single API attempt, classified for retry logic.
enum AttemptKind { success, clientError, serverError, networkError, timeout }

/// The result of one HTTP (or demo) request, decoupled from transport so the
/// demo backend can produce identical responses without sockets.
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

abstract class ApiClientBase {
  Future<ApiResponse> get(String path, {Map<String, String>? query});
  Future<ApiResponse> post(String path, {Object? body});
  Future<ApiResponse> patch(String path, {Object? body});
  Future<ApiResponse> put(String path, {Object? body});
  Future<ApiResponse> delete(String path);
}
