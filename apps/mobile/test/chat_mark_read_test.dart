import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:oppa_mobile/core/api_client_base.dart";
import "package:oppa_mobile/core/connectivity_service.dart";
import "package:oppa_mobile/core/outbound_queue.dart";
import "package:oppa_mobile/data/repositories.dart";
import "package:oppa_mobile/ui/screens/chat_screens.dart";

/// Deterministic API double: canned responses per path fragment, recording
/// every request so tests can assert what the UI actually sent.
class _RecordingApi implements ApiClientBase {
  final List<({String method, String path, Object? body})> calls = [];

  /// Optional canned bodies keyed by predicate (used to vary GET history).
  Object? Function(String path)? getOverride;

  ApiResponse _ok(Object? body) => ApiResponse(
      kind: AttemptKind.success, statusCode: 200, body: body);

  @override
  Future<ApiResponse> get(String path, {Map<String, String>? query}) async {
    calls.add((method: "GET", path: path, body: null));
    final override = getOverride;
    if (override != null) return _ok(override(path));
    if (path.contains("/messages")) {
      // Newest-first, exactly like the production repository ordering the
      // thread UI assumes (it renders with reverse: true).
      return _ok({
        "messages": [
          {"id": "m-newest", "senderUserId": "u-other", "body": "latest incoming", "createdAt": "2026-01-15T09:14:00Z", "mine": false},
          {"id": "m-mine", "senderUserId": "u-me", "body": "my reply", "createdAt": "2026-01-15T09:00:00Z", "mine": true},
          {"id": "m-older", "senderUserId": "u-other", "body": "older incoming", "createdAt": "2026-01-15T08:40:00Z", "mine": false},
        ]
      });
    }
    if (path.endsWith("/calls")) return _ok({"calls": []});
    if (path.endsWith("/events")) return _ok({"events": []});
    return _ok({});
  }

  @override
  Future<ApiResponse> post(String path, {Object? body}) async {
    calls.add((method: "POST", path: path, body: body));
    return _ok({"updated": 2});
  }

  @override
  Future<ApiResponse> patch(String path, {Object? body}) async {
    calls.add((method: "PATCH", path: path, body: body));
    return _ok({});
  }

  @override
  Future<ApiResponse> put(String path, {Object? body}) async {
    calls.add((method: "PUT", path: path, body: body));
    return _ok({});
  }

  @override
  Future<ApiResponse> delete(String path) async {
    calls.add((method: "DELETE", path: path, body: null));
    return _ok({});
  }
}

Future<void> _pumpThread(WidgetTester tester, _RecordingApi api) async {
  SharedPreferences.setMockInitialValues({});
  final queue = OutboundQueue(api: api);
  await tester.pumpWidget(MaterialApp(
    home: ChatThreadScreen(
      conversation: const {"id": "conv-1", "title": "Amara"},
      messages: MessagesRepository(api, queue),
      calls: CallsRepository(api),
      connectivity: ConnectivityService(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    "opening a thread marks the newest incoming message read (badge clear)",
    (tester) async {
      final api = _RecordingApi();
      await _pumpThread(tester, api);

      final read = api.calls
          .where((c) => c.method == "POST" && c.path.endsWith("/read"))
          .toList();
      expect(read, hasLength(1),
          reason: "opening a thread must acknowledge incoming messages");
      expect(
        (read.single.body as Map)["upToMessageId"],
        "m-newest",
        reason: "receipts go up to the newest incoming message, not our own",
      );
    },
  );

  testWidgets(
    "a thread with no incoming messages sends no mark-read request",
    (tester) async {
      final api = _RecordingApi();
      // Stub a history that contains only the caller's own messages.
      api.getOverride = (path) => {
            "messages": [
              {"id": "m-only-mine", "senderUserId": "u-me", "body": "hi", "createdAt": "2026-01-15T09:00:00Z", "mine": true},
            ]
          };
      await _pumpThread(tester, api);

      expect(
        api.calls.where((c) => c.method == "POST" && c.path.endsWith("/read")),
        isEmpty,
      );
    },
  );
}
