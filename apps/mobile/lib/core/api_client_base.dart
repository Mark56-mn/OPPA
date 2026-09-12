/// Transport contract every repository depends on.
///
/// The real [ApiClient] (see `api_client.dart`) implements this over HTTP with
/// retry/backoff; `demo_backend.dart` implements it in-process for the
/// compile-time demo build. Repositories, SessionStore and OutboundQueue are
/// written against this interface only, so demo mode swaps the entire data
/// layer through one injection point and production code paths are unchanged.
abstract class ApiClientBase {
  Future<ApiResponse> get(String path, {Map<String, String>? query});
  Future<ApiResponse> post(String path, {Object? body});
  Future<ApiResponse> patch(String path, {Object? body});
  Future<ApiResponse> put(String path, {Object? body});
  Future<ApiResponse> delete(String path);
}
