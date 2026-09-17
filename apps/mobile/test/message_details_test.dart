import "package:flutter_test/flutter_test.dart";

import "package:oppa_mobile/core/demo_backend.dart";

/// Message Details renders the server's receipt rows (deliveredAt / readAt per
/// member). These assertions pin the contract the UI depends on, so a receipt
/// state can never be invented client-side.
void main() {
  late DemoBackend api;

  setUp(() => api = DemoBackend(latency: Duration.zero));

  test("a confirmed send reports real delivered/read receipt rows", () async {
    final sent = await api.post(
      "/conversations/conv-demo-user-amara/messages",
      body: {"body": "Receipts please", "clientMessageId": "m-test-1"},
    );
    expect(sent.isSuccess, isTrue, reason: "${sent.errorCode}");
    final id = "${(sent.body as Map)["id"]}";

    final r = await api.get(
        "/conversations/conv-demo-user-amara/messages/$id/receipts");
    expect(r.isSuccess, isTrue, reason: "${r.errorCode}");
    final receipts = (((r.body as Map)["receipts"]) as List)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    expect(receipts, isNotEmpty,
        reason: "a sent message must have at least one recipient receipt");
    for (final row in receipts) {
      expect(row["userId"], isNotEmpty);
      expect(row["deliveredAt"], isNotNull,
          reason: "delivery is reported by the server, never assumed");
    }
  });

  test("seeded messages have receipts too (deterministic per conversation)", () async {
    final r = await api.get(
        "/conversations/conv-demo-user-amara/messages/seed-amara-1/receipts");
    expect(r.isSuccess, isTrue);
    final receipts = ((r.body as Map)["receipts"]) as List;
    expect(receipts, isNotEmpty);
    expect((receipts.first as Map)["deliveredAt"], isNotNull);
  });

  test("an unknown message has no receipts — nothing is fabricated", () async {
    final r = await api.get(
        "/conversations/conv-demo-user-amara/messages/does-not-exist/receipts");
    expect(r.isSuccess, isTrue);
    // No rows at all, rather than an invented reader/timestamp pair.
    expect(((r.body as Map)["receipts"]) as List, isEmpty);
  });
}
