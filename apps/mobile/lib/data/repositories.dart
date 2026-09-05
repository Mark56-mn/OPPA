import "../core/api_client.dart";
import "../core/outbound_queue.dart";

/// Profile (display name, about, avatar). Server validates lengths.
class ProfileRepository {
  ProfileRepository(this._api);
  final ApiClient _api;

  Future<ApiResponse> mine() => _api.get("/profile");
  Future<ApiResponse> update({String? displayName, String? about, String? avatarUrl}) =>
      _api.patch("/profile", body: {
        if (displayName != null) "displayName": displayName,
        if (about != null) "about": about,
        if (avatarUrl != null) "avatarUrl": avatarUrl,
      });
}

/// Contacts with block/report (support surface).
class ContactsRepository {
  ContactsRepository(this._api);
  final ApiClient _api;

  Future<ApiResponse> list() => _api.get("/contacts");
  Future<ApiResponse> add(String userId, {String? nickname}) =>
      _api.post("/contacts", body: {"userId": userId, if (nickname != null) "nickname": nickname});
  Future<ApiResponse> remove(String userId) => _api.delete("/contacts/$userId");
  Future<ApiResponse> block(String userId) => _api.post("/contacts/$userId/block");
  Future<ApiResponse> report(String userId, String reason) =>
      _api.post("/contacts/$userId/report", body: {"reason": reason});
}

/// Conversations: direct and groups.
class ConversationsRepository {
  ConversationsRepository(this._api);
  final ApiClient _api;

  Future<ApiResponse> list() => _api.get("/conversations");
  Future<ApiResponse> createDirect(String userId) =>
      _api.post("/conversations/direct", body: {"userId": userId});
  Future<ApiResponse> createGroup(String title, List<String> memberUserIds) =>
      _api.post("/conversations/groups", body: {"title": title, "memberUserIds": memberUserIds});
  Future<ApiResponse> addMember(String conversationId, String userId) =>
      _api.post("/conversations/$conversationId/members", body: {"userId": userId});
  Future<ApiResponse> leave(String conversationId) =>
      _api.post("/conversations/$conversationId/leave");
  Future<ApiResponse> unread(String conversationId) =>
      _api.get("/conversations/$conversationId/unread");
}

/// Messaging: send goes through the durable queue when offline; history and
/// receipts are read-through with pagination.
class MessagesRepository {
  MessagesRepository(this._api, this._queue);
  final ApiClient _api;
  final OutboundQueue _queue;

  Future<ApiResponse> history(String conversationId, {String? before, int limit = 50}) {
    final query = <String, String>{"limit": "$limit"};
    if (before != null) query["before"] = before;
    return _api.get("/conversations/$conversationId/messages", query: query);
  }

  /// Sends a message with a client idempotency key. When the network is down,
  /// the op is queued durably (survives restart) and flushed on reconnect.
  /// Returns (confirmed, response-or-null). Never fabricates success offline.
  Future<(bool, ApiResponse?)> send(
    String conversationId,
    String body, {
    required bool offline,
  }) async {
    final clientMessageId =
        "m-${DateTime.now().microsecondsSinceEpoch}-${body.hashCode}";
    final payload = {"body": body, "clientMessageId": clientMessageId};
    if (offline) {
      await _queue.enqueue(PendingOp(
        id: clientMessageId,
        kind: "message.send",
        path: "/conversations/$conversationId/messages",
        body: payload,
      ));
      return (false, null);
    }
    final response = await _api.post(
        "/conversations/$conversationId/messages", body: payload);
    final confirmed = response.isSuccess;
    return (confirmed, response);
  }

  Future<ApiResponse> markRead(String conversationId, {String? upTo}) =>
      _api.post("/conversations/$conversationId/read",
          body: {if (upTo != null) "upToMessageId": upTo});
  Future<ApiResponse> edit(String conversationId, String messageId, String body) =>
      _api.patch("/conversations/$conversationId/messages/$messageId", body: {"body": body});
  Future<ApiResponse> delete(String conversationId, String messageId) =>
      _api.delete("/conversations/$conversationId/messages/$messageId");
}

/// Wallet + payments: NEVER optimistic. Financial state is server-authoritative;
/// the client only reads state and submits requests while online.
///
/// Transfer requires the security-core step-up flow:
///   POST /security/step-up/challenge {purpose, deviceId, intent}
///   → server returns a challenge; client signs it with its device key;
///   POST /wallet/transfer {toUserId, amountMinor, reference, deviceId, challenge, signature}
/// The server binds the proof to the exact intent (recipient/amount/reference),
/// so a captured proof cannot authorize different values.
class WalletRepository {
  WalletRepository(this._api);
  final ApiClient _api;

  Future<ApiResponse> overview() => _api.get("/wallet");
  Future<ApiResponse> history({String? before, int limit = 25}) {
    final query = <String, String>{"limit": "$limit"};
    if (before != null) query["before"] = before;
    return _api.get("/wallet/transactions", query: query);
  }

  /// Requests a step-up challenge bound to the exact transfer intent.
  Future<ApiResponse> requestTransferChallenge({
    required String deviceId,
    required String toUserId,
    required int amountMinor,
    required String reference,
  }) =>
      _api.post("/security/step-up/challenge", body: {
        "purpose": "wallet_transfer",
        "deviceId": deviceId,
        "intent": {"toUserId": toUserId, "amountMinor": amountMinor, "currency": "NGN", "reference": reference},
      });

  /// Peer transfer. Deliberately synchronous: no offline queue for money.
  Future<ApiResponse> transfer({
    required String toUserId,
    required int amountMinor,
    required String reference,
    required String deviceId,
    required String challenge,
    required String signature,
  }) =>
      _api.post("/wallet/transfer", body: {
        "toUserId": toUserId,
        "amountMinor": amountMinor,
        "reference": reference,
        "deviceId": deviceId,
        "challenge": challenge,
        "signature": signature,
      });

  Future<ApiResponse> initializePayment({
    required String provider,
    required int amountMinor,
    required String email,
  }) =>
      _api.post("/payments/initialize", body: {
        "provider": provider,
        "amountMinor": amountMinor,
        "email": email,
      });

  Future<ApiResponse> paymentHistory({int limit = 20, int offset = 0}) =>
      _api.get("/payments/history", query: {"limit": "$limit", "offset": "$offset"});
}

/// OPPA-native calls: start/answer/decline/hangup + event polling.
class CallsRepository {
  CallsRepository(this._api);
  final ApiClient _api;

  Future<ApiResponse> start(String conversationId, {required bool video}) =>
      _api.post("/conversations/$conversationId/calls", body: {"kind": video ? "video" : "audio"});
  Future<ApiResponse> answer(String conversationId, String callId) =>
      _api.post("/conversations/$conversationId/calls/$callId/answer");
  Future<ApiResponse> decline(String conversationId, String callId, {bool busy = false}) =>
      _api.post("/conversations/$conversationId/calls/$callId/decline", body: {"busy": busy});
  Future<ApiResponse> hangUp(String conversationId, String callId) =>
      _api.post("/conversations/$conversationId/calls/$callId/hangup");
  Future<ApiResponse> history(String conversationId) =>
      _api.get("/conversations/$conversationId/calls");
  Future<ApiResponse> events(String conversationId, String callId, {int sinceSeq = 0}) =>
      _api.get("/conversations/$conversationId/calls/$callId/events",
          query: {"sinceSeq": "$sinceSeq"});
  Future<ApiResponse> signal(String conversationId, String callId,
          {required String type, Map<String, dynamic>? payload}) =>
      _api.post("/conversations/$conversationId/calls/$callId/signal",
          body: {"type": type, if (payload != null) "payload": payload});
}

/// Notifications + preferences (in-app event delivery). Matches the API:
/// GET /notifications, GET /notifications/unread-count, POST /notifications/read
/// (with optional notificationId), GET/PUT /notifications/preferences.
class NotificationsRepository {
  NotificationsRepository(this._api);
  final ApiClient _api;

  Future<ApiResponse> list({String? before, int limit = 50}) {
    final query = <String, String>{"limit": "$limit"};
    if (before != null) query["before"] = before;
    return _api.get("/notifications", query: query);
  }

  Future<ApiResponse> unreadCount() => _api.get("/notifications/unread-count");
  Future<ApiResponse> markRead(String notificationId) =>
      _api.post("/notifications/read", body: {"notificationId": notificationId});
  Future<ApiResponse> markAllRead() => _api.post("/notifications/read", body: {});
  Future<ApiResponse> preferences() => _api.get("/notifications/preferences");
  Future<ApiResponse> setPreference(String category, bool enabled) =>
      _api.put("/notifications/preferences", body: {"category": category, "enabled": enabled});
}
