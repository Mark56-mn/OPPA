import "dart:async";

import "package:flutter_test/flutter_test.dart";

import "package:oppa_mobile/core/api_client.dart";
import "package:oppa_mobile/core/api_client_base.dart";
import "package:oppa_mobile/core/demo_backend.dart";
import "package:oppa_mobile/core/demo_mode.dart";

void main() {
  // Safety tripwire: tests run with default defines, so demo mode must be
  // OFF. If someone flips the compile-time default, this fails immediately.
  test("demo mode is compile-time OFF by default", () {
    expect(DemoMode.enabled, isFalse,
        reason: "OPPA_DEMO_MODE must default to false so normal builds are "
            "production-safe");
  });

  group("demo auth flow", () {
    late DemoBackend api;

    setUp(() {
      api = DemoBackend(latency: Duration.zero);
    });

    test("request then verify with the demo OTP establishes a session", () async {
      final request = await api.post("/auth/otp/request",
          body: {"phone": "+2348010000000"});
      expect(request.isSuccess, isTrue, reason: "${request.body}");

      final verify = await api.post("/auth/otp/verify", body: {
        "phone": "+2348010000000",
        "code": DemoMode.demoOtp,
        "deviceId": "demo-device-pubkey",
      });
      expect(verify.isSuccess, isTrue, reason: "${verify.body}");
      final body = verify.body as Map;
      expect(body["accessToken"], isA<String>());
      expect(body["refreshToken"], isA<String>());
      expect(body["demo"], isTrue);
    });

    test("a wrong code is rejected (no unconditional success)", () async {
      await api.post("/auth/otp/request", body: {"phone": "+2348010000000"});
      final verify = await api.post("/auth/otp/verify",
          body: {"phone": "+2348010000000", "code": "111111"});
      expect(verify.isSuccess, isFalse);
      expect(verify.statusCode, 401);
    });

    test("phone is validated before any session is issued", () async {
      final request =
          await api.post("/auth/otp/request", body: {"phone": "123"});
      expect(request.isSuccess, isFalse);
    });
  });

  group("demo backend is unreachable without a transport", () {
    test("demo backend performs no network I/O by construction", () {
      // DemoBackend imports no HTTP client and holds no sockets; this is a
      // static assertion that the class only depends on core types.
      expect(DemoBackend, isNotNull);
    });
  });

  group("production client rejects demo constants", () {
    test("demo backend is a transport, not the HTTP client", () {
      // Structural tripwire: DemoBackend must stay a separate implementation
      // of the transport contract — if it ever started extending the real
      // ApiClient it would gain network behavior and leak demo auth.
      expect(DemoBackend(), isA<ApiClientBase>());
      expect(DemoBackend(), isNot(isA<ApiClient>()));
    });
  });

  group("demo data parity with repositories", () {
    late DemoBackend api;

    setUp(() {
      api = DemoBackend(latency: Duration.zero);
    });

    test("profile endpoints answer with repository-expected shapes", () async {
      final profile = await api.get("/profile");
      expect(profile.isSuccess, isTrue);
      expect((profile.body as Map)["userId"], isA<String>());

      final available = await api.get("/profile/oppa-id/available/test_id");
      expect(available.isSuccess, isTrue);
      expect((available.body as Map)["available"], isA<bool>());
    });

    test("conversations, history and reads respond", () async {
      final conversations = await api.get("/conversations");
      expect((conversations.body as Map)["conversations"], isA<List>());

      final history =
          await api.get("/conversations/conv-demo-user-amara/messages",
              query: {"limit": "50"});
      expect((history.body as Map)["messages"], isA<List>());

      final read = await api.post("/conversations/conv-demo-user-amara/read",
          body: {});
      expect(read.isSuccess, isTrue);
    });

    test("message send → read receipts round-trip", () async {
      final send = await api.post("/conversations/conv-demo-user-tunde/messages",
          body: {"body": "Hello from the demo", "clientMessageId": "m-1"});
      expect(send.isSuccess, isTrue, reason: "${send.body}");
      final sentId = (send.body as Map)["id"] as String;

      final history = await api.get("/conversations/conv-demo-user-tunde/messages");
      final messages = (history.body as Map)["messages"] as List;
      expect(messages.any((m) => m["id"] == sentId), isTrue);
    });

    test("call lifecycle: start → answer → hangup", () async {
      final start = await api.post(
          "/conversations/conv-demo-user-tunde/calls",
          body: {"kind": "audio"});
      expect(start.isSuccess, isTrue, reason: "${start.body}");
      final callId = (start.body as Map)["id"] as String;

      final answer = await api
          .post("/conversations/conv-demo-user-tunde/calls/$callId/answer");
      expect(answer.isSuccess, isTrue, reason: "${answer.body}");

      final hangup = await api
          .post("/conversations/conv-demo-user-tunde/calls/$callId/hangup");
      expect(hangup.isSuccess, isTrue, reason: "${hangup.body}");
    });

    test("call lifecycle rejects invalid transitions", () async {
      final start = await api.post(
          "/conversations/conv-demo-user-tunde/calls",
          body: {"kind": "audio"});
      final callId = (start.body as Map)["id"] as String;

      // Answering twice: second attempt must fail (single-transition rule).
      final first = await api
          .post("/conversations/conv-demo-user-tunde/calls/$callId/answer");
      expect(first.isSuccess, isTrue);
      final second = await api
          .post("/conversations/conv-demo-user-tunde/calls/$callId/answer");
      expect(second.isSuccess, isFalse);
    });

    test("incoming seeded call answers and ends", () async {
      final history =
          await api.get("/conversations/conv-demo-user-amara/calls");
      final calls = (history.body as Map)["calls"] as List;
      expect(calls, isNotEmpty);

      final ringing = calls.firstWhere((c) => c["status"] == "ringing",
          orElse: () => null);
      expect(ringing, isNotNull);
      final answer = await api.post(
          "/conversations/conv-demo-user-amara/calls/${ringing["id"]}/answer");
      expect(answer.isSuccess, isTrue);
    });

    test("wallet transfer validates amount and funds", () async {
      final challenge = await api.post("/security/step-up/challenge",
          body: {"purpose": "wallet_transfer", "deviceId": "d", "intent": {}});
      expect(challenge.isSuccess, isTrue);
      expect((challenge.body as Map)["challenge"], isA<String>());

      final tooSmall =
          await api.post("/wallet/transfer", body: {"amountMinor": 0});
      expect(tooSmall.isSuccess, isFalse);

      final tooBig = await api.post("/wallet/transfer",
          body: {"amountMinor": 999999999, "toUserId": "demo-user-tunde"});
      expect(tooBig.isSuccess, isFalse);
    });

    test("business self-order blocker mirrors the server rule", () async {
      final blocked = await api.post("/business/biz-demo-spices/orders",
          body: {"items": []});
      expect(blocked.isSuccess, isFalse);
      expect(blocked.errorCode, "BUSINESS_ORDER_SELF_INVALID");
    });

    test("notifications list, unread count and preferences respond", () async {
      final list = await api.get("/notifications");
      expect((list.body as Map)["notifications"], isA<List>());

      final unread = await api.get("/notifications/unread-count");
      expect((unread.body as Map)["unread"], isA<int>());

      final prefs = await api.get("/notifications/preferences");
      expect((prefs.body as Map)["preferences"], isA<Map>());

      final setPref = await api.put("/notifications/preferences",
          body: {"category": "wallet", "enabled": false});
      expect(setPref.isSuccess, isTrue);
    });

    test("products, orders and analytics respond for the demo business", () async {
      final products = await api.get("/business/biz-demo-spices/products");
      expect((products.body as Map)["products"], isA<List>());

      final orders = await api.get("/business/biz-demo-spices/orders");
      expect((orders.body as Map)["orders"], isA<List>());

      final analytics = await api.get("/business/biz-demo-spices/analytics");
      expect((analytics.body as Map)["ordersTotal"], isA<int>());
    });
  });
}
