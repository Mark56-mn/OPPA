import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:oppa_mobile/core/api_client.dart";
import "package:oppa_mobile/core/outbound_queue.dart";
import "package:shared_preferences/shared_preferences.dart";

class FakeApi implements ApiClient {
  FakeApi(this.responses);
  final List<ApiResponse> responses;
  int calls = 0;

  @override
  Future<ApiResponse> post(String path, {Object? body}) async {
    if (calls >= responses.length) {
      return ApiResponse(kind: AttemptKind.networkError);
    }
    return responses[calls++];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test("queue persists pending ops and flushes them in order", () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = FakeApi([
      ApiResponse(kind: AttemptKind.success, statusCode: 201, body: {"ok": true}),
      ApiResponse(kind: AttemptKind.success, statusCode: 201, body: {"ok": true}),
    ]);
    final queue = OutboundQueue(api: api as dynamic, prefs: prefs);
    await queue.enqueue(PendingOp(
      id: "m1", kind: "message.send",
      path: "/conversations/c1/messages",
      body: {"body": "hello", "clientMessageId": "m1"},
    ));
    await queue.enqueue(PendingOp(
      id: "m2", kind: "conversation.read",
      path: "/conversations/c1/read",
      body: {},
    ));
    expect(queue.depth, 2);

    final confirmed = await queue.flush();
    expect(confirmed, 2);
    expect(queue.depth, 0);
  });

  test("queue rejects financial kinds (server-authoritative money)", () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final queue = OutboundQueue(api: FakeApi([]) as dynamic, prefs: prefs);
    expect(
      () => queue.enqueue(PendingOp(
          id: "x", kind: "wallet.transfer", path: "/wallet/transfer", body: {})),
      throwsArgumentError,
    );
  });

  test("permanent 4xx failures are dropped, network failures retried", () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = FakeApi([
      ApiResponse(kind: AttemptKind.clientError, statusCode: 400, errorCode: "MESSAGE_BODY_INVALID"),
      ApiResponse(kind: AttemptKind.networkError),
    ]);
    final queue = OutboundQueue(api: api as dynamic, prefs: prefs);
    await queue.enqueue(PendingOp(
        id: "bad", kind: "message.send", path: "/c/m", body: {}));
    await queue.enqueue(PendingOp(
        id: "net", kind: "message.send", path: "/c/m", body: {}));
    final confirmed = await queue.flush();
    expect(confirmed, 0);
    expect(queue.depth, 1, reason: "network-failed op stays queued");
  });

  test("queue survives restart via persisted storage", () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = OutboundQueue(api: FakeApi([]) as dynamic, prefs: prefs);
    await first.enqueue(PendingOp(
        id: "persist", kind: "message.send", path: "/c/m", body: {"body": "x"}));

    final second = OutboundQueue(api: FakeApi([]) as dynamic, prefs: prefs);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(second.depth, 1, reason: "queued op survives app restart");
  });
}
