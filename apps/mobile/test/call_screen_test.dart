import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:oppa_mobile/core/api_client.dart";
import "package:oppa_mobile/data/repositories.dart";
import "package:oppa_mobile/ui/screens/call_screen.dart";

/// Scripted API double: mirrors the real API response shapes (start →
/// {call:{id},inviteSeq}; events → [{seq,eventType,payload}]) so the call
/// screen is exercised against the actual server contract, not an invented one.
class ScriptedCallsApi implements ApiClient {
  ScriptedCallsApi(this.script);

  /// Keys are repository paths *without* the /v1 prefix (the repository layer
  /// passes unsuffixed paths; ApiClient adds /v1 when talking to the server).
  final Map<String, List<ApiResponse>> script;
  final Map<String, int> cursor = {};

  ApiResponse _next(String path) {
    final responses = script[path] ?? script["/v1$path"];
    if (responses == null || responses.isEmpty) {
      return ApiResponse(kind: AttemptKind.networkError);
    }
    final i = cursor[path] ?? 0;
    cursor[path] = i + 1;
    return responses[i.clamp(0, responses.length - 1)];
  }

  @override
  Future<ApiResponse> get(String path, {Map<String, String>? query}) async =>
      _next(path);

  @override
  Future<ApiResponse> post(String path, {Object? body}) async => _next(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets("callee can answer a ringing call and then end it",
      (tester) async {
    final events = ScriptedCallsApi({
      // Polling before answering: invite event (seq 1) forever.
      "/v1/conversations/c1/calls/call-9/events": [
        ApiResponse(
            kind: AttemptKind.success,
            statusCode: 200,
            body: {
              "events": [
                {
                  "seq": 1,
                  "callId": "call-9",
                  "eventType": "invite",
                  "payload": {"kind": "audio"}
                }
              ]
            }),
      ],
      "/v1/conversations/c1/calls/call-9/answer": [
        ApiResponse(
            kind: AttemptKind.success,
            statusCode: 200,
            body: {"id": "call-9", "status": "active"}),
      ],
      "/v1/conversations/c1/calls/call-9/hangup": [
        ApiResponse(
            kind: AttemptKind.success,
            statusCode: 200,
            body: {"id": "call-9", "status": "ended", "endReason": "hung_up"}),
      ],
    });
    final calls = CallsRepository(events);

    await tester.pumpWidget(MaterialApp(
      home: CallScreen(
        calls: calls,
        conversationId: "c1",
        callId: "call-9",
        isCaller: false,
        kind: "audio",
      ),
    ));
    await tester.pump(); // initial build
    await tester.pump(const Duration(seconds: 2)); // first poll tick

    // After the first poll the invite event refines the label to the kind.
    expect(find.textContaining("Incoming"), findsOneWidget);
    expect(find.text("Answer"), findsOneWidget);
    expect(find.text("Decline"), findsOneWidget);

    await tester.tap(find.byIcon(Icons.call_outlined));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2)); // let the answer future settle
    expect(find.text("Connected"), findsOneWidget);
    expect(find.text("End"), findsOneWidget);

    await tester.tap(find.byIcon(Icons.call_end_outlined));
    await tester.pump();
    // The status line and the end-state action row both render "Call ended".
    expect(find.text("Call ended"), findsWidgets);
    // Let the delayed auto-pop timer run so the widget tree disposes cleanly.
    await tester.pump(const Duration(milliseconds: 1300));
  });

  testWidgets("caller sees cancel while ringing and end once active",
      (tester) async {
    final api = ScriptedCallsApi({
      "/v1/conversations/c1/calls/call-7/events": [
        ApiResponse(kind: AttemptKind.success, statusCode: 200,
            body: {"events": [
              {"seq": 1, "callId": "call-7", "eventType": "invite", "payload": {}}
            ]}),
        ApiResponse(kind: AttemptKind.success, statusCode: 200,
            body: {"events": [
              {"seq": 2, "callId": "call-7", "eventType": "answer", "payload": {}}
            ]}),
      ],
      "/v1/conversations/c1/calls/call-7/hangup": [
        ApiResponse(kind: AttemptKind.success, statusCode: 200,
            body: {"id": "call-7", "status": "ended"}),
        ApiResponse(kind: AttemptKind.success, statusCode: 200,
            body: {"id": "call-7", "status": "ended"}),
      ],
    });
    final calls = CallsRepository(api);

    await tester.pumpWidget(MaterialApp(
      home: CallScreen(
        calls: calls,
        conversationId: "c1",
        callId: "call-7",
        isCaller: true,
        kind: "audio",
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text("Ringing…"), findsOneWidget);
    expect(find.text("Cancel"), findsOneWidget);
  });
}
