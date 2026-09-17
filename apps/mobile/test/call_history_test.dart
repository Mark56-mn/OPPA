import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:oppa_mobile/core/connectivity_service.dart";
import "package:oppa_mobile/core/demo_backend.dart";
import "package:oppa_mobile/data/repositories.dart";
import "package:oppa_mobile/ui/screens/call_screen.dart";

/// Call history must be built from the server's own record: `callerUserId` plus
/// the projected `mine` flag, and `answeredAt` to separate answered calls from
/// missed ones. These tests fail if the client ever has to infer direction.
void main() {
  test("call history uses the production contract, not a demo-only field", () async {
    final api = DemoBackend(latency: Duration.zero);
    // Start a real (demo) call so the history has a caller-owned entry.
    final started = await api.post("/conversations/conv-demo-user-amara/calls",
        body: {"kind": "audio"});
    expect(started.isSuccess, isTrue, reason: "${started.errorCode}");

    final r = await api.get("/conversations/conv-demo-user-amara/calls");
    expect(r.isSuccess, isTrue);
    final calls = (((r.body as Map)["calls"]) as List)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    expect(calls, isNotEmpty);

    final mine = calls.firstWhere((c) => c["id"] == (started.body as Map)["id"]);
    expect(mine["mine"], isTrue, reason: "the caller placed this call");
    expect(mine["callerUserId"], DemoBackend.me.id);
    expect(mine["startedAt"], isNotNull);
    expect(mine.containsKey("outgoing"), isFalse,
        reason: "demo-only keys must not exist — production never sends them");

    // The seeded incoming call is reported as NOT mine (so it can be labelled
    // Incoming), again decided by the server-side projection.
    final incoming = calls.firstWhere((c) => c["id"] == "call-seed-incoming");
    expect(incoming["mine"], isFalse);
    expect(incoming["callerUserId"], isNot(DemoBackend.me.id));
    expect(incoming["answeredAt"], isNull,
        reason: "a ringing call has not been answered");
  });

  testWidgets("call history filters by Missed / Outgoing / Incoming",
      (tester) async {
    final api = DemoBackend(latency: Duration.zero);
    final connectivity = ConnectivityService();
    addTearDown(connectivity.dispose);
    await tester.pumpWidget(MaterialApp(
      home: CallHistoryScreen(
        calls: CallsRepository(api),
        conversations: ConversationsRepository(api),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text("Call history"), findsOneWidget);
    for (final label in ["All", "Missed", "Outgoing", "Incoming"]) {
      expect(find.text(label), findsOneWidget);
    }
    // The screen states where its data comes from instead of implying a global
    // call index the API does not have.
    expect(find.textContaining("most recent chats"), findsOneWidget);

    await tester.tap(find.text("Outgoing"));
    await tester.pumpAndSettle();
    expect(find.text("No outgoing calls in your recent chats"), findsOneWidget);
  });
}
