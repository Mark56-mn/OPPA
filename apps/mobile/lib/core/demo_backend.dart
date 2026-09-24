import "api_client_base.dart";

export "api_client_base.dart" show AttemptKind, ApiResponse;

import "demo_mode.dart";

/// In-process deterministic backend for OPPA DEMO builds.
///
/// Implements exactly the endpoint surface that `lib/data/repositories.dart`
/// calls, with the same JSON shapes the real API returns. It never performs
/// I/O: no sockets, no production URLs, nothing to leak. The demo OTP lives
/// only inside this object in the app process.
///
/// This class is compiled into every build but is UNREACHABLE unless
/// DemoMode.enabled is true (compile-time), and the startup guard refuses to
/// boot it in a product build (app.dart).
class DemoBackend implements ApiClientBase {
  DemoBackend({this.latency = const Duration(milliseconds: 250)}) {
    _seedNotifications();
  }

  /// Small artificial latency so loading/progress states are visible and
  /// honest (the UI is exercised with its real async flow).
  final Duration latency;
  final DateTime _epoch = DateTime.now();

  // ---------------------------------------------------------------- state
  String _myPhone = "";
  String _myName = "";
  String _myAbout = "";
  String _myOppaId = "";
  final Set<String> _readMessageIds = {};
  final Set<String> _readNotifications = {};
  final Set<String> _contactIds = {};
  final Set<String> _blockedIds = {};
  final Map<String, int> _unreadByConversation = {};
  final List<_SentMessage> _sentMessages = [];
  final List<Map<String, dynamic>> _pendingSends = [];
  final List<Map<String, dynamic>> _myOrders = [];
  final List<Map<String, dynamic>> _notifications = [];
  final Map<String, bool> _prefs = {};
  int _balanceMinor = 1250000;
  int _transferCount = 0;
  final List<Map<String, dynamic>> _transactions = [];
  final List<_DemoCall> _calls = [];

  // Fixed deterministic ids (stable across restarts of the demo session).
  static const me = _DemoPerson(
    id: "demo-user-me",
    name: "Demo User",
    phone: "+234 801 000 0000",
    oppaId: "demo_user",
  );
  static const _amara = _DemoPerson(
      id: "demo-user-amara", name: "Amara Okafor", phone: "+234 802 111 2222", oppaId: "amara_01");
  static const _tunde = _DemoPerson(
      id: "demo-user-tunde", name: "Tunde Bakare", phone: "+234 803 333 4444", oppaId: "tunde_b");
  static const _zainab = _DemoPerson(
      id: "demo-user-zainab", name: "Zainab Musa", phone: "+234 805 555 6666", oppaId: "zainab_m");

  String get _myDisplayName => _myName.isEmpty ? me.name : _myName;

  Future<ApiResponse> _ok(Map<String, dynamic> body) async {
    await Future<void>.delayed(latency);
    return ApiResponse(
        kind: AttemptKind.success, statusCode: 200, body: body);
  }

  ApiResponse _err(String code, int status) =>
      ApiResponse(kind: AttemptKind.clientError, statusCode: status,
          errorCode: code, body: {"error": code});

  // -------------------------------------------------------- ApiClientBase
  @override
  Future<ApiResponse> get(String path, {Map<String, String>? query}) async {
    await Future<void>.delayed(latency);
    if (path.startsWith("/profile")) return _getProfile(path);
    if (path == "/contacts") return _ok({"contacts": _contactsJson()});
    if (path == "/conversations") return _ok({"conversations": _conversationsJson()});
    // Must be matched before the plain /messages route (same suffix family).
    if (path.contains("/messages/") && path.endsWith("/receipts")) {
      return _ok({"receipts": _receiptsJson(path)});
    }
    if (path.startsWith("/conversations/") && path.endsWith("/messages")) {
      return _ok({"messages": _historyJson(_conversationId(path, "/messages"))});
    }
    if (path.startsWith("/conversations/") && path.endsWith("/calls")) {
      return _ok({"calls": _callsJson(_conversationId(path, "/calls"))});
    }
    if (path.startsWith("/conversations/") && path.endsWith("/events")) {
      return _ok({"events": _callEvents(path, query)});
    }
    if (path == "/notifications") {
      return _ok({"notifications": _notificationsJson()});
    }
    if (path == "/notifications/unread-count") {
      return _ok({"unread": _unreadNotifications()});
    }
    if (path == "/notifications/preferences") {
      return _ok({"preferences": _preferencesJson()});
    }
    if (path == "/wallet") return _ok({"balanceMinor": _balanceMinor});
    if (path == "/wallet/transactions") {
      return _ok({"transactions": List<Map<String, dynamic>>.from(_transactions)});
    }
    if (path == "/payments/history") {
      return _ok({"payments": _paymentHistoryJson()});
    }
    // NOTE: the bare "/business" path must be routed too. Matching only
    // "/business/" sent GET /business (the switcher's list) and POST /business
    // (create) to NOT_FOUND, which is exactly why the Business workspace looked
    // broken and "creating a business" did nothing.
    if (path == "/business" || path.startsWith("/business/")) {
      return _getBusiness(path, query ?? const {});
    }
    return _err("NOT_FOUND", 404);
  }

  @override
  Future<ApiResponse> post(String path, {Object? body}) async {
    await Future<void>.delayed(latency);
    final map = (body is Map) ? body.cast<String, dynamic>() : <String, dynamic>{};
    switch (path) {
      case "/auth/otp/request":
        final phone = "${map["phone"] ?? ""}";
        if (phone.trim().length < 7) return _err("PHONE_INVALID", 400);
        _myPhone = phone.trim();
        return _ok({"sent": true, "demo": true});
      case "/auth/otp/verify":
        // Demo verification ONLY: the code is checked inside this process
        // against the compiled-in demo constant. No network, no production.
        final code = "${map["code"] ?? ""}";
        if (code != DemoMode.demoOtp) return _err("OTP_INVALID_OR_EXPIRED", 401);
        _myName = "";
        _myAbout = "";
        _myOppaId = "";
        return _ok({
          "accessToken": "demo-access-token",
          "refreshToken": "demo-refresh-token",
          "deviceId": "demo-device",
          "demo": true,
        });
      case "/auth/refresh":
        return _ok({
          "accessToken": "demo-access-token",
          "refreshToken": "demo-refresh-token",
          "demo": true,
        });
      case "/profile/oppa-id":
        final raw = "${map["oppaId"] ?? ""}";
        final id = raw.trim().toLowerCase();
        // Same shape/reserved/taken rules as the real server
        // (postgres-profile-repository.validateOppaId) so onboarding exercises
        // the production failure paths, including the claimed-in-a-race case.
        if (!_oppaIdShape.hasMatch(id)) return _err("OPPA_ID_INVALID", 400);
        if (_reservedOppaIds.contains(id)) return _err("OPPA_ID_RESERVED", 409);
        if (_oppaIdTakenBy(id, exceptMe: true)) return _err("OPPA_ID_TAKEN", 409);
        _myOppaId = id;
        return _ok({"oppaId": id});
      case "/contacts":
        final userId = "${map["userId"] ?? ""}";
        if (userId.isEmpty || userId == me.id) return _err("CONTACT_SELF_INVALID", 400);
        _contactIds.add(userId);
        return _ok({"ok": true});
      case "/notifications/read":
        final id = "${map["notificationId"] ?? ""}";
        if (id.isEmpty) {
          _readNotifications.addAll(_notifications.map((n) => "${n["id"]}"));
        } else {
          _readNotifications.add(id);
        }
        return _ok({"ok": true});
      case "/notifications/preferences":
        // Handled via put(); a POST here is not a conversation action.
        break;
      case "/conversations/direct":
        final userId = "${map["userId"] ?? ""}";
        _contactIds.add(userId);
        final person = _person(userId);
        return _ok({
          "id": "conv-${person.id}",
          "title": person.name,
          "kind": "direct",
          "unreadCount": _unreadByConversation["conv-${person.id}"] ?? 0,
        });
      case "/payments/initialize":
        return _ok({
          "authorizationUrl": "https://demo.invalid/authorize?simulated=1",
          "reference": "demo-pay-${_epoch.millisecondsSinceEpoch}",
          "simulated": true,
        });
      default:
        break;
    }
    if (path.startsWith("/conversations/") && path.endsWith("/messages")) {
      final conversationId = _conversationId(path, "/messages");
      final text = "${map["body"] ?? ""}";
      if (text.isEmpty) return _err("MESSAGE_BODY_REQUIRED", 400);
      final sent = _SentMessage(
        id: "msg-${_epoch.microsecondsSinceEpoch}-${_sentMessages.length}",
        conversationId: conversationId,
        body: text,
        createdAt: DateTime.now().toIso8601String(),
      );
      _sentMessages.add(sent);
      return _ok({
        "id": sent.id,
        "conversationId": conversationId,
        "body": sent.body,
        "createdAt": sent.createdAt,
        "mine": true,
      });
    }
    if (path.startsWith("/conversations/") && path.endsWith("/read")) {
      final conversationId = _conversationId(path, "/read");
      _unreadByConversation[conversationId] = 0;
      return _ok({"ok": true});
    }
    if (path.startsWith("/conversations/") && path.endsWith("/calls")) {
      final conversationId = _conversationId(path, "/calls");
      final call = _DemoCall(
        id: "call-${_epoch.millisecondsSinceEpoch}",
        conversationId: conversationId,
        kind: "${map["kind"] ?? "audio"}",
        status: "ringing",
        outgoing: true,
        createdAt: DateTime.now().toIso8601String(),
      );
      _calls.add(call);
      return _ok({"id": call.id, "status": "ringing", "kind": call.kind});
    }
    // ------------------------------------------------ call lifecycle (demo)
    // Mirrors the server's single-transition lifecycle: answer → active,
    // decline/hangup → ended. No media: the demo call screen records
    // lifecycle state only.
    if (path.startsWith("/conversations/") && path.endsWith("/answer")) {
      final conversationId = _conversationId(path, "/answer");
      return _callAnswer(conversationId, _callIdFromSuffix(path, "/answer"));
    }
    if (path.startsWith("/conversations/") && path.endsWith("/decline")) {
      return _callDecline(_callIdFromSuffix(path, "/decline"));
    }
    if (path.startsWith("/conversations/") && path.endsWith("/hangup")) {
      return _callHangUp(_callIdFromSuffix(path, "/hangup"));
    }
    if (path.startsWith("/conversations/") && path.endsWith("/signal")) {
      // Signal posts are accepted and discarded (no peer in demo mode).
      return _ok({"ok": true});
    }
    if (path == "/conversations/groups") {
      final members =
          ((map["memberUserIds"] as List?) ?? const []).map((e) => "$e").toSet();
      _contactIds.addAll(members);
      return _ok({
        "id": "conv-group-${_epoch.millisecondsSinceEpoch}",
        "title": "${map["title"] ?? "Group"}",
        "kind": "group",
        "unreadCount": 0,
      });
    }
    if (path.startsWith("/conversations/") && path.endsWith("/leave")) {
      return _ok({"ok": true});
    }
    if (path.startsWith("/conversations/") && path.endsWith("/members")) {
      final userId = "${map["userId"] ?? ""}";
      if (userId.isNotEmpty) _contactIds.add(userId);
      return _ok({"ok": true});
    }
    if (path.startsWith("/contacts/") && path.endsWith("/block")) {
      final userId =
          path.substring("/contacts/".length, path.length - "/block".length);
      _blockedIds.add(userId);
      return _ok({"ok": true});
    }
    if (path.startsWith("/contacts/") && path.endsWith("/report")) {
      return _ok({"ok": true});
    }
    if (path == "/security/step-up/challenge") {
      // The demo challenge is inert; the client still signs it, exercising
      // the real crypto path without a server.
      return _ok({"challenge": "demo-challenge-${_epoch.millisecondsSinceEpoch}"});
    }
    if (path == "/wallet/transfer") {
      return _walletTransfer(map);
    }
    if (path == "/business" || path.startsWith("/business/")) {
      return _postBusiness(path, map);
    }
    return _err("NOT_FOUND", 404);
  }

  @override
  Future<ApiResponse> patch(String path, {Object? body}) async {
    await Future<void>.delayed(latency);
    final map = (body is Map) ? body.cast<String, dynamic>() : <String, dynamic>{};
    if (path == "/profile") {
      if (map["displayName"] is String) _myName = map["displayName"] as String;
      if (map["about"] is String) _myAbout = map["about"] as String;
      if (map["avatarUrl"] is String) {} // accepted; no avatar store in demo
      return _ok({"displayName": _myDisplayName, "about": _myAbout});
    }
    if (path.startsWith("/business/") && path.contains("/staff/")) {
      // /business/:businessId/staff/:userId — owner-only role change.
      final role = "${map["role"] ?? ""}";
      if (role != "manager" && role != "staff") {
        return _err("BUSINESS_ROLE_INVALID", 400);
      }
      final userId = path.split("/").last;
      final businessId = path.split("/")[2];
      for (final member in _staff) {
        if (member["userId"] == userId && member["businessId"] == businessId) {
          if (member["role"] == "owner") {
            return _err("BUSINESS_ROLE_IMMUTABLE", 409);
          }
          member["role"] = role;
          return _ok(Map<String, dynamic>.from(member));
        }
      }
      return _err("STAFF_NOT_FOUND", 404);
    }

    // /business/:businessId/products/:productId — owner/manager edit.
    final productEdit = RegExp(r'^/business/([^/]+)/products/([^/]+)$')
        .firstMatch(path);
    if (productEdit != null) {
      final businessId = productEdit.group(1)!;
      final productId = productEdit.group(2)!;
      if (_roleIn(businessId) != "owner" && _roleIn(businessId) != "manager") {
        return _err("BUSINESS_PERMISSION_DENIED", 403);
      }
      final i = _products.indexWhere(
          (p) => p["id"] == productId && p["businessId"] == businessId);
      if (i < 0) return _err("BUSINESS_PRODUCT_NOT_FOUND", 404);
      final product = _products[i];
      if (map.containsKey("name")) {
        final name = "${map["name"] ?? ""}".trim();
        if (name.isEmpty || name.length > 120) {
          return _err("BUSINESS_PRODUCT_NAME_INVALID", 400);
        }
        product["name"] = name;
      }
      if (map.containsKey("description")) product["description"] = map["description"];
      if (map.containsKey("priceMinor")) {
        final price = (map["priceMinor"] as num?)?.toInt() ?? 0;
        if (price <= 0) return _err("BUSINESS_PRODUCT_PRICE_INVALID", 400);
        product["priceMinor"] = price;
      }
      if (map.containsKey("status")) {
        final status = "${map["status"] ?? ""}";
        if (status != "active" && status != "archived") {
          return _err("BUSINESS_PRODUCT_STATUS_INVALID", 400);
        }
        product["status"] = status;
      }
      return _ok(Map<String, dynamic>.from(product));
    }

    // /business/:businessId — owner-only profile edit.
    final businessEdit = RegExp(r'^/business/([^/]+)$').firstMatch(path);
    if (businessEdit != null) {
      final businessId = businessEdit.group(1)!;
      final found = _businessById(businessId);
      if (found == null) return _err("BUSINESS_NOT_FOUND", 404);
      if (_roleIn(businessId) != "owner") {
        return _err("BUSINESS_PERMISSION_DENIED", 403);
      }
      if (map.containsKey("name")) {
        final name = "${map["name"] ?? ""}".trim();
        if (name.isEmpty || name.length > 120) return _err("BUSINESS_NAME_INVALID", 400);
        found["name"] = name;
      }
      if (map.containsKey("description")) found["description"] = map["description"];
      return _ok(Map<String, dynamic>.from(found));
    }
    return _err("NOT_FOUND", 404);
  }

  @override
  Future<ApiResponse> put(String path, {Object? body}) async {
    await Future<void>.delayed(latency);
    final map = (body is Map) ? body.cast<String, dynamic>() : <String, dynamic>{};
    if (path == "/notifications/preferences") {
      final category = "${map["category"] ?? ""}";
      _prefs[category] = map["enabled"] == true;
      return _ok({"preferences": _preferencesJson()});
    }
    return _err("NOT_FOUND", 404);
  }

  @override
  Future<ApiResponse> delete(String path) async {
    await Future<void>.delayed(latency);
    if (path.startsWith("/contacts/")) {
      final userId = path.substring("/contacts/".length);
      _contactIds.remove(userId);
      return _ok({"ok": true});
    }
    return _err("NOT_FOUND", 404);
  }

  // ------------------------------------------------------------- profile
  Future<ApiResponse> _getProfile(String path) async {
    if (path == "/profile") {
      return _ok({
        "userId": me.id,
        "displayName": _myDisplayName,
        "about": _myAbout,
        "phone": _myPhone.isEmpty ? me.phone : _myPhone,
        "oppaId": _myOppaId.isEmpty ? null : _myOppaId,
        "demo": true,
      });
    }
    if (path.startsWith("/profile/oppa-id/available/")) {
      final raw = path.substring("/profile/oppa-id/available/".length);
      if (!_oppaIdShape.hasMatch(raw)) {
        return _ok({"available": false, "reason": "OPPA_ID_INVALID"});
      }
      final taken = _reservedOppaIds.contains(raw) || _oppaIdTakenBy(raw);
      return _ok({
        "available": !taken,
        "reason": taken ? "OPPA_ID_TAKEN" : null,
      });
    }
    if (path.startsWith("/profile/oppa-id/lookup/")) {
      final id = path.substring("/profile/oppa-id/lookup/".length);
      final person = _personByOppaId(id);
      if (person == null) return _err("OPPA_ID_NOT_FOUND", 404);
      return _ok({"userId": person.id, "displayName": person.name});
    }
    return _err("NOT_FOUND", 404);
  }

  // ------------------------------------------------------------ contacts
  List<Map<String, dynamic>> _contactsJson() {
    return [
      for (final p in _people)
        {
          "userId": p.id,
          "displayName": p.name,
          "phone": p.phone,
          "nickname": null,
          "blocked": _blockedIds.contains(p.id),
        },
    ];
  }

  // -------------------------------------------------------- conversations
  // Field names mirror the production API exactly (postgres-conversation-
  // repository returns `unreadCount`); the UI must not special-case demo.
  List<Map<String, dynamic>> _conversationsJson() => [
        for (final c in _conversations)
          {
            "id": c.id,
            "title": c.title,
            "kind": c.kind,
            "unreadCount": _unreadByConversation[c.id] ?? 0,
            "lastMessageAt": c.lastMessageAt,
          },
      ];

  List<_DemoConversation> get _conversations => const [
        _DemoConversation(
            id: "conv-demo-user-amara",
            title: "Amara Okafor",
            kind: "direct",
            lastMessageAt: "2026-01-15T09:14:00Z"),
        _DemoConversation(
            id: "conv-demo-user-tunde",
            title: "Tunde Bakare",
            kind: "direct",
            lastMessageAt: "2026-01-15T08:02:00Z"),
        _DemoConversation(
            id: "conv-market-sisters",
            title: "Market Sisters 🛍️",
            kind: "group",
            lastMessageAt: "2026-01-14T17:45:00Z"),
      ];

  String _conversationId(String path, String suffix) {
    final start = path.indexOf("/conversations/") + "/conversations/".length;
    return path.substring(start, path.length - suffix.length);
  }

  _DemoPerson _person(String id) {
    for (final p in _people) {
      if (p.id == id) return p;
    }
    return _amara;
  }

  /// Server shape rules, mirrored so the demo onboarding cannot accept a
  /// handle the real API would reject: 3–32 chars, [a-z0-9_], leading letter.
  static final _oppaIdShape = RegExp(r'^[a-z][a-z0-9_]{2,31}$');

  /// Reserved product/system terms (subset of the server's list — enough to
  /// exercise the OPPA_ID_RESERVED path honestly in the demo).
  static const _reservedOppaIds = <String>{
    'oppa', 'admin', 'administrator', 'root', 'system', 'support', 'help',
    'security', 'wallet', 'payments', 'paystack', 'flutterwave', 'business',
    'official', 'team', 'staff', 'moderator', 'mod', 'abuse', 'fraud',
    'whatsapp', 'meta',
  };

  /// True when another OPPA account already holds [id] (demo members own the
  /// handles shown in Connect, so the taken path is real, not simulated).
  bool _oppaIdTakenBy(String id, {bool exceptMe = false}) {
    for (final p in _people) {
      if (p.oppaId == id) return true;
    }
    if (exceptMe) return false;
    return _myOppaId.isNotEmpty && _myOppaId == id;
  }

  /// The demo peer who is NOT the signed-in user for a conversation — used as
  /// the caller id of incoming demo calls.
  String _otherMemberId(String conversationId) {
    for (final p in _people) {
      if (conversationId.endsWith(p.id)) return p.id;
    }
    return _people.first.id;
  }

  _DemoPerson? _personByOppaId(String oppaId) {
    for (final p in _people) {
      if (p.oppaId == oppaId) return p;
    }
    return null;
  }

  static const _people = [_amara, _tunde, _zainab];

  // ------------------------------------------------------------- messages
  List<Map<String, dynamic>> _historyJson(String conversationId) {
    final base = <Map<String, dynamic>>[
      ..._seedMessages(conversationId),
      // Pending (offline) sends surface as pending bubbles.
      for (final p in _pendingSends)
        if (p["conversationId"] == conversationId) ...[
          {
            "id": p["id"],
            "senderUserId": me.id,
            "body": p["body"],
            "createdAt": p["createdAt"],
            "mine": true,
            "status": "pending",
          }
        ],
      // Confirmed sends from this session.
      for (final m in _sentMessages)
        if (m.conversationId == conversationId)
          {
            "id": m.id,
            "senderUserId": me.id,
            "body": m.body,
            "createdAt": m.createdAt,
            "mine": true,
            "readAt": _readMessageIds.contains(m.id) ? m.createdAt : null,
            // Production parity: at least one OTHER member has read it
            // (demo recipients auto-read a few seconds after delivery).
            "readByAny": _otherRead(m),
          },
    ];
    return base;
  }

  /// Whether someone other than the sender has read [m]. Demo recipients read
  /// their messages 3 seconds after the send was confirmed — deterministic,
  /// honest (it mirrors the server receipt model), and testable.
  bool _otherRead(_SentMessage m) {
    final sentAt = DateTime.parse(m.createdAt);
    final readCutoff = sentAt.add(const Duration(seconds: 3));
    return _readMessageIds.contains(m.id) ||
        DateTime.now().isAfter(readCutoff);
  }

  /// Receipts for one message, derived from the same deterministic rule the
  /// bubbles use (`_otherRead`): a real per-recipient delivered/read state, not
  /// a client-side assumption. Mirrors GET /messages/:id/receipts.
  List<Map<String, dynamic>> _receiptsJson(String path) {
    final match = RegExp(
            r'^/conversations/([^/]+)/messages/([^/]+)/receipts$')
        .firstMatch(path);
    if (match == null) return const [];
    final conversationId = match.group(1)!;
    final messageId = match.group(2)!;
    final sent = _sentMessages.where((m) => m.id == messageId).toList();
    final seededAt = _seedSentAt(conversationId, messageId);
    // Unknown message id: no receipt rows at all (the real server has none to
    // return). Inventing a recipient here would fabricate a receipt state.
    if (sent.isEmpty && seededAt == null) return const [];
    final sentAt = sent.isNotEmpty
        ? DateTime.parse(sent.first.createdAt)
        : DateTime.parse(seededAt!);
    final read = _readMessageIds.contains(messageId) ||
        DateTime.now().isAfter(sentAt.add(const Duration(seconds: 3)));
    final recipients =
        _people.where((p) => p.id != me.id).take(1).toList();
    return [
      for (final p in recipients)
        {
          "userId": p.id,
          "deliveredAt": sentAt.add(const Duration(seconds: 1)).toIso8601String(),
          "readAt": read
              ? sentAt.add(const Duration(seconds: 3)).toIso8601String()
              : null,
        },
    ];
  }

  /// Created-at of a seeded message, or null when the id is not one of ours.
  String? _seedSentAt(String conversationId, String messageId) {
    for (final m in _seedMessages(conversationId)) {
      if (m["id"] == messageId) return "${m["createdAt"]}";
    }
    return null;
  }

  List<Map<String, dynamic>> _seedMessages(String conversationId) {
    switch (conversationId) {
      case "conv-demo-user-amara":
        return const [
          {"id": "seed-amara-1", "senderUserId": "demo-user-amara", "body": "Good morning! Did the fabric arrive?", "createdAt": "2026-01-15T08:40:00Z", "mine": false},
          {"id": "seed-amara-2", "senderUserId": "demo-user-me", "body": "Yes — three rolls of Ankara, exactly as ordered 🎉", "createdAt": "2026-01-15T08:52:00Z", "mine": true, "readAt": "2026-01-15T08:55:00Z"},
          {"id": "seed-amara-3", "senderUserId": "demo-user-amara", "body": "Perfect. Sending the balance now.", "createdAt": "2026-01-15T09:14:00Z", "mine": false},
        ];
      case "conv-demo-user-tunde":
        return const [
          {"id": "seed-tunde-1", "senderUserId": "demo-user-tunde", "body": "Are you joining the call later?", "createdAt": "2026-01-15T08:00:00Z", "mine": false},
        ];
      case "conv-market-sisters":
        return const [
          {"id": "seed-group-1", "senderUserId": "demo-user-zainab", "body": "Market runs tomorrow at 7am — who is in?", "createdAt": "2026-01-14T17:20:00Z", "mine": false},
          {"id": "seed-group-2", "senderUserId": "demo-user-me", "body": "Count me in 🙌", "createdAt": "2026-01-14T17:31:00Z", "mine": true, "readAt": "2026-01-14T17:32:00Z"},
          {"id": "seed-group-3", "senderUserId": "demo-user-amara", "body": "I will bring the lists.", "createdAt": "2026-01-14T17:45:00Z", "mine": false},
        ];
      default:
        return const [];
    }
  }

  // ------------------------------------------------------------ wallet
  // Simulated financial flows. Every screen in demo mode shows the DEMO
  // BUILD banner; amounts here are play money in an isolated local ledger.

  Future<ApiResponse> _walletTransfer(Map<String, dynamic> map) async {
    final amount = (map["amountMinor"] as num?)?.toInt() ?? 0;
    if (amount <= 0) return _err("WALLET_AMOUNT_INVALID", 400);
    if (amount > _balanceMinor) return _err("WALLET_INSUFFICIENT_FUNDS", 409);
    // Deterministic script: the 3rd transfer fails, to exercise the failure
    // state honestly (the UI shows the server's error either way).
    _transferCount += 1;
    if (_transferCount % 3 == 0) {
      return _err("WALLET_INSUFFICIENT_FUNDS", 409);
    }
    _balanceMinor -= amount;
    // Field names mirror production exactly (postgres-wallet-repository):
    // type credit|debit + balanceAfterMinor. No demo-only keys.
    _transactions.insert(0, {
      "id": "txn-${_epoch.microsecondsSinceEpoch}",
      "type": "debit",
      "amountMinor": amount,
      "balanceAfterMinor": _balanceMinor,
      "reference": "${map["reference"] ?? "demo-transfer"}",
      "description": "Transfer",
      "createdAt": DateTime.now().toIso8601String(),
    });
    return _ok({"status": "completed", "balanceMinor": _balanceMinor});
  }

  // ------------------------------------------------------------- payments
  List<Map<String, dynamic>> _paymentHistoryJson() => const [
        {"id": "pay-demo-1", "provider": "paystack", "amountMinor": 200000, "status": "pending", "reference": "demo-pay-pending", "createdAt": "2026-01-15T07:10:00Z"},
        {"id": "pay-demo-2", "provider": "flutterwave", "amountMinor": 500000, "status": "successful", "reference": "demo-pay-ok", "createdAt": "2026-01-14T19:02:00Z"},
        {"id": "pay-demo-3", "provider": "paystack", "amountMinor": 150000, "status": "failed", "reference": "demo-pay-fail", "createdAt": "2026-01-13T12:40:00Z"},
      ];

  // ------------------------------------------------------------ business
  /// Seed business. Created businesses are appended to [_businesses] and are
  /// real for the rest of the session: they appear in the switcher, own their
  /// products/orders/staff, and survive navigation. (Before this, creation
  /// returned an id that GET /business never listed and every screen silently
  /// fell back to the seed store — "creating a business" only looked like it
  /// worked.)
  static const _seedBusinessId = "biz-demo-spices";
  static const _demoBusiness = <String, dynamic>{
    "id": _seedBusinessId,
    "name": "Kano Spices Demo",
    "description": "Demo store for UI testing — no real orders or money",
    "status": "active",
    "role": "owner",
  };

  final List<Map<String, dynamic>> _businesses = [
    Map<String, dynamic>.from(_demoBusiness),
  ];

  Map<String, dynamic>? _businessById(String id) {
    for (final b in _businesses) {
      if (b["id"] == id) return b;
    }
    return null;
  }

  /// Role of the signed-in demo user in [businessId] (the demo user owns every
  /// business it creates, exactly like the real owner row).
  String? _roleIn(String businessId) =>
      _businessById(businessId) == null ? null : "owner";

  Future<ApiResponse> _getBusiness(String path,
      [Map<String, String> query = const {}]) async {
    if (path == "/business") {
      return _ok({
        "businesses": _businesses
            .map((b) => Map<String, dynamic>.from(b))
            .toList(),
      });
    }
    if (path == "/business/orders/mine") {
      return _ok({"orders": List<Map<String, dynamic>>.from(_myOrders)});
    }

    // /business/:id — a single business the caller is staff of.
    final single = RegExp(r'^/business/([^/]+)$').firstMatch(path);
    if (single != null) {
      final found = _businessById(single.group(1)!);
      if (found == null) return _err("BUSINESS_NOT_FOUND", 404);
      return _ok(Map<String, dynamic>.from(found));
    }

    final products = RegExp(r'^/business/([^/]+)/products$').firstMatch(path);
    if (products != null) {
      final id = products.group(1)!;
      if (_businessById(id) == null) return _err("BUSINESS_NOT_FOUND", 404);
      // includeArchived is staff-only on the real server (the route checks the
      // caller's role); here the caller is always the owner of the store.
      final includeArchived = query["includeArchived"] == "1";
      return _ok({
        "products": _products
            .where((p) =>
                p["businessId"] == id &&
                (includeArchived || "${p["status"]}" == "active"))
            .map((p) => Map<String, dynamic>.from(p))
            .toList(),
      });
    }

    final orders = RegExp(r'^/business/([^/]+)/orders$').firstMatch(path);
    if (orders != null) {
      final id = orders.group(1)!;
      if (_businessById(id) == null) return _err("BUSINESS_NOT_FOUND", 404);
      final mine = _orders.where((o) => o["businessId"] == id).toList();
      return _ok({"orders": mine.map((o) => Map<String, dynamic>.from(o)).toList()});
    }

    final analytics = RegExp(r'^/business/([^/]+)/analytics$').firstMatch(path);
    if (analytics != null) {
      final id = analytics.group(1)!;
      if (_businessById(id) == null) return _err("BUSINESS_NOT_FOUND", 404);
      final mine = _orders.where((o) => o["businessId"] == id).toList();
      final counted = mine.where((o) {
        final s = "${o["status"]}";
        return s == "paid" || s == "fulfilled";
      });
      return _ok({
        "ordersTotal": mine.length,
        "ordersPaid": counted.length,
        "revenueMinor": counted.fold<int>(
            0, (sum, o) => sum + ((o["amountMinor"] as num?)?.toInt() ?? 0)),
      });
    }

    final staff = RegExp(r'^/business/([^/]+)/staff$').firstMatch(path);
    if (staff != null) {
      final id = staff.group(1)!;
      if (_businessById(id) == null) return _err("BUSINESS_NOT_FOUND", 404);
      return _ok({
        "staff": _staff
            .where((m) => m["businessId"] == id)
            .map((m) => Map<String, dynamic>.from(m))
            .toList(),
      });
    }
    return _err("NOT_FOUND", 404);
  }

  Future<ApiResponse> _postBusiness(String path, Map<String, dynamic> map) async {
    if (path == "/business") {
      final name = "${map["name"] ?? ""}".trim();
      // Same validation as the real route: a blank or oversized name is a
      // client bug and must not create a store.
      if (name.isEmpty || name.length > 120) {
        return _err("BUSINESS_NAME_INVALID", 400);
      }
      final created = <String, dynamic>{
        "id": "biz-${_epoch.millisecondsSinceEpoch}",
        "name": name,
        "description": map["description"],
        "status": "active",
        "role": "owner",
      };
      _businesses.add(created);
      // Owner staff row, exactly like createBusiness() does in Postgres.
      _staff.add({
        "businessId": created["id"],
        "userId": me.id,
        "displayName": _myDisplayName,
        "role": "owner",
        "phoneMasked": null,
      });
      return _ok(Map<String, dynamic>.from(created));
    }
    if (path.startsWith("/business/") && path.endsWith("/products")) {
      final businessId =
          path.substring("/business/".length, path.length - "/products".length);
      if (_businessById(businessId) == null) {
        return _err("BUSINESS_NOT_FOUND", 404);
      }
      final price = (map["priceMinor"] as num?)?.toInt() ?? 0;
      final productName = "${map["name"] ?? ""}".trim();
      if (productName.isEmpty) return _err("BUSINESS_PRODUCT_NAME_INVALID", 400);
      if (price <= 0) return _err("BUSINESS_PRODUCT_PRICE_INVALID", 400);
      final product = <String, dynamic>{
        "id": "prod-${_epoch.microsecondsSinceEpoch}",
        "businessId": businessId,
        "name": productName,
        "priceMinor": price,
        "currency": "NGN",
        "description": map["description"],
        "status": "active",
      };
      _products.insert(0, product);
      return _ok(Map<String, dynamic>.from(product));
    }
    if (path.startsWith("/business/") && path.endsWith("/orders")) {
      final businessId = path.substring("/business/".length, path.length - "/orders".length);
      if (businessId == _seedBusinessId) {
        // Self-ordering blocker mirrors the real server rule.
        return _err("BUSINESS_ORDER_SELF_INVALID", 403);
      }
      final items = (map["items"] as List?) ?? const [];
      final amountMinor = items.fold<int>(0, (sum, raw) {
        final item = (raw as Map).cast<String, dynamic>();
        final product = _products.where((p) => p["id"] == item["productId"]).toList();
        final price = product.isEmpty ? 0 : (product.first["priceMinor"] as int);
        return sum + price * ((item["quantity"] as num?)?.toInt() ?? 1);
      });
      final order = {
        "id": "order-${_epoch.microsecondsSinceEpoch}",
        "businessId": businessId,
        "businessName": "Sister Store Demo",
        "amountMinor": amountMinor,
        "status": "pending",
        "customerOrderReference": map["customerOrderReference"] ?? "demo-order",
        "metadata": {"items": items},
        "createdAt": DateTime.now().toIso8601String(),
      };
      _myOrders.insert(0, order);
      return _ok(order);
    }
    if (path.startsWith("/business/orders/") && path.endsWith("/pay")) {
      final orderId = path.substring("/business/orders/".length, path.length - "/pay".length);
      final i = _myOrders.indexWhere((o) => o["id"] == orderId);
      if (i < 0) return _err("BUSINESS_ORDER_NOT_FOUND", 404);
      final order = _myOrders[i];
      if ("${order["status"]}" != "pending") return _err("BUSINESS_ORDER_STATE_INVALID", 409);
      final amount = (order["amountMinor"] as num?)?.toInt() ?? 0;
      if (amount > _balanceMinor) return _err("WALLET_INSUFFICIENT_FUNDS", 409);
      _balanceMinor -= amount;
      order["status"] = "paid";
      _transactions.insert(0, {
        "id": "txn-${_epoch.microsecondsSinceEpoch}",
        "type": "debit",
        "amountMinor": amount,
        "balanceAfterMinor": _balanceMinor,
        "reference": "order:$orderId",
        "description": "Order payment",
        "createdAt": DateTime.now().toIso8601String(),
      });
      return _ok(order);
    }
    if (path.startsWith("/business/orders/") && path.endsWith("/cancel")) {
      final orderId = path.substring("/business/orders/".length, path.length - "/cancel".length);
      final i = _myOrders.indexWhere((o) => o["id"] == orderId);
      if (i < 0) return _err("BUSINESS_ORDER_NOT_FOUND", 404);
      if ("${_myOrders[i]["status"]}" != "pending") {
        return _err("BUSINESS_ORDER_STATE_INVALID", 409);
      }
      _myOrders[i]["status"] = "cancelled";
      return _ok(_myOrders[i]);
    }
    if (path.startsWith("/business/orders/") && path.endsWith("/fulfill")) {
      // Merchant fulfillment: paid → fulfilled, single transition,
      // idempotent on the already-fulfilled record (mirrors the server).
      final orderId =
          path.substring("/business/orders/".length, path.length - "/fulfill".length);
      final all = [..._orders, ..._myOrders];
      final i = all.indexWhere((o) => o["id"] == orderId);
      if (i < 0) return _err("BUSINESS_ORDER_NOT_FOUND", 404);
      final order = all[i];
      final status = "${order["status"]}";
      if (status == "fulfilled") return _ok(order);
      if (status != "paid") return _err("BUSINESS_ORDER_STATE_INVALID", 409);
      order["status"] = "fulfilled";
      return _ok(order);
    }

    final staffAdd =
        RegExp(r'^/business/([^/]+)/staff$').firstMatch(path);
    if (staffAdd != null) {
      final businessId = staffAdd.group(1)!;
      if (_businessById(businessId) == null) return _err("BUSINESS_NOT_FOUND", 404);
      final userId = "${map["userId"] ?? ""}";
      if (userId.isEmpty) return _err("USER_ID_REQUIRED", 400);
      final role = "${map["role"] ?? ""}";
      if (role != "manager" && role != "staff") {
        return _err("BUSINESS_ROLE_INVALID", 400);
      }
      _staff.add({
        "businessId": businessId,
        "userId": userId,
        "displayName": "Staff member",
        "role": role,
        "phoneMasked": null,
      });
      return _ok({"ok": true});
    }
    return _err("NOT_FOUND", 404);
  }

  /// Products belong to a business — the seed rows carry the seed id so a
  /// newly created store starts genuinely empty (it does not inherit another
  /// store's catalogue).
  final List<Map<String, dynamic>> _products = [
    {"id": "prod-suya-mix", "businessId": "biz-demo-spices", "name": "Suya Spice Mix 200g", "priceMinor": 150000, "description": "Demo product", "status": "active"},
    {"id": "prod-yaji", "businessId": "biz-demo-spices", "name": "Yaji Pepper 100g", "priceMinor": 80000, "description": "Demo product", "status": "active"},
    {"id": "prod-legacy", "businessId": "biz-demo-spices", "name": "Old Groundnut Blend (archived)", "priceMinor": 60000, "description": "Demo product", "status": "archived"},
  ];

  final List<Map<String, dynamic>> _orders = [
    {"id": "order-demo-paid-1", "businessId": "biz-demo-spices", "amountMinor": 230000, "status": "paid", "customerUserId": "demo-user-tunde", "customerOrderReference": "demo-ref-102", "metadata": {"items": [{"name": "Suya Spice Mix 200g", "quantity": 1}, {"name": "Yaji Pepper 100g", "quantity": 1}]}, "createdAt": "2026-01-15T06:20:00Z"},
    {"id": "order-demo-fulfilled-1", "businessId": "biz-demo-spices", "amountMinor": 150000, "status": "fulfilled", "customerUserId": "demo-user-amara", "customerOrderReference": "demo-ref-101", "metadata": {"items": [{"name": "Suya Spice Mix 200g", "quantity": 1}]}, "createdAt": "2026-01-14T15:00:00Z"},
    {"id": "order-demo-pending-1", "businessId": "biz-demo-spices", "amountMinor": 80000, "status": "pending", "customerUserId": "demo-user-zainab", "customerOrderReference": "demo-ref-103", "metadata": {"items": [{"name": "Yaji Pepper 100g", "quantity": 1}]}, "createdAt": "2026-01-15T09:40:00Z"},
    {"id": "order-demo-cancelled-1", "businessId": "biz-demo-spices", "amountMinor": 60000, "status": "cancelled", "customerUserId": "demo-user-tunde", "customerOrderReference": "demo-ref-099", "metadata": {"items": [{"name": "Old Groundnut Blend", "quantity": 1}]}, "createdAt": "2026-01-12T10:00:00Z"},
  ];

  /// Staff rows are scoped to a business (the real roster joins on
  /// business_id), so a new store starts with only its own owner row.
  final List<Map<String, dynamic>> _staff = [
    {"businessId": _seedBusinessId, "userId": "demo-user-me", "displayName": "Demo User (owner)", "role": "owner", "phoneMasked": "+234 801 *** 0000"},
    {"businessId": _seedBusinessId, "userId": "demo-user-amara", "displayName": "Amara Okafor", "role": "manager", "phoneMasked": "+234 802 *** 2222"},
    {"businessId": _seedBusinessId, "userId": "demo-user-tunde", "displayName": "Tunde Bakare", "role": "staff", "phoneMasked": "+234 803 *** 4444"},
  ];

  // --------------------------------------------------------------- calls
  Future<ApiResponse> _callAnswer(String conversationId, String callId) async {
    for (var i = 0; i < _calls.length; i++) {
      if (_calls[i].id == callId && _calls[i].status == "ringing") {
        _calls[i] = _calls[i].copyWith(status: "active");
        return _ok({"id": callId, "status": "active", "conversationId": conversationId});
      }
    }
    // Seeded incoming call (id not in _calls): answer moves it to active.
    if (callId == "call-seed-incoming") {
      _calls.add(_DemoCall(
        id: callId,
        conversationId: conversationId,
        kind: "audio",
        status: "active",
        outgoing: false,
        createdAt: DateTime.now().toIso8601String(),
      ));
      return _ok({"id": callId, "status": "active", "conversationId": conversationId});
    }
    return _err("CALL_NOT_FOUND", 404);
  }

  Future<ApiResponse> _callDecline(String callId) async {
    for (var i = 0; i < _calls.length; i++) {
      if (_calls[i].id == callId && _calls[i].status == "ringing") {
        _calls[i] = _calls[i].copyWith(status: "ended");
        return _ok({"id": callId, "status": "ended"});
      }
    }
    if (callId == "call-seed-incoming") {
      // Materialize as ended so the seed cannot ring again.
      _calls.add(_DemoCall(
        id: callId,
        conversationId: "conv-demo-user-amara",
        kind: "audio",
        status: "ended",
        outgoing: false,
        createdAt: DateTime.now().toIso8601String(),
      ));
      return _ok({"id": callId, "status": "ended"});
    }
    return _err("CALL_NOT_FOUND", 404);
  }

  Future<ApiResponse> _callHangUp(String callId) async {
    for (var i = 0; i < _calls.length; i++) {
      if (_calls[i].id == callId && _calls[i].status == "active") {
        _calls[i] = _calls[i].copyWith(status: "ended");
        return _ok({"id": callId, "status": "ended"});
      }
    }
    return _err("CALL_STATE_INVALID", 409);
  }

  /// /conversations/:id/calls/:callId/<suffix>
  String _callIdFromSuffix(String path, String suffix) {
    final withoutSuffix = path.substring(0, path.length - suffix.length);
    return withoutSuffix.split("/").last;
  }

  /// Production contract (postgres calls history): callerUserId + the
  /// server-projected `mine` flag. The old demo-only `outgoing` key is gone so
  /// the client cannot end up depending on a field production never sends.
  List<Map<String, dynamic>> _callsJson(String conversationId) => [
        for (final c in _calls.where((c) => c.conversationId == conversationId))
          {
            "id": c.id,
            "conversationId": c.conversationId,
            "callerUserId": c.outgoing ? me.id : _otherMemberId(conversationId),
            "mine": c.outgoing,
            "kind": c.kind,
            "status": c.status,
            "endReason": c.status == "ended"
                ? (c.outgoing ? "hangup" : "timeout")
                : null,
            // answeredAt is the server's answer marker the history screen uses
            // to separate answered calls from missed ones.
            "answeredAt": c.status == "ringing" ? null : c.createdAt,
            "startedAt": c.createdAt,
            "createdAt": c.createdAt,
          },
        // A seeded incoming ringing call so the incoming-call pickup flow can
        // be exercised (ChatThreadScreen checks history for a ringing call).
        // It appears only until it is answered or declined — both actions
        // materialize it into _calls so it cannot ring a second time.
        if (conversationId == "conv-demo-user-amara" &&
            !_calls.any((c) => c.id == "call-seed-incoming"))
          {
            "id": "call-seed-incoming",
            "conversationId": conversationId,
            "callerUserId": _otherMemberId(conversationId),
            "mine": false,
            "kind": "audio",
            "status": "ringing",
            "endReason": null,
            "answeredAt": null,
            "startedAt": DateTime.now().toIso8601String(),
            "createdAt": DateTime.now().toIso8601String(),
          },
      ];

  List<Map<String, dynamic>> _callEvents(
      String path, Map<String, String>? query) {
    // /conversations/:id/calls/:callId/events?sinceSeq=n
    final parts = path.split("/");
    // ["", "conversations", convId, "calls", callId, "events"]
    final callId = parts.length >= 6 ? parts[4] : "";
    final sinceSeq = int.tryParse(query?["sinceSeq"] ?? "0") ?? 0;
    for (final c in _calls) {
      if (c.id != callId) continue;
      if (c.status == "ringing" && sinceSeq < 1) {
        return [
          {"seq": 1, "callId": callId, "eventType": "invite", "payload": {"kind": c.kind}},
        ];
      }
      if (c.status == "active" && sinceSeq < 2) {
        return [
          {"seq": 2, "callId": callId, "eventType": "answer", "payload": {}},
        ];
      }
      if (c.status == "ended" && sinceSeq < 3) {
        return [
          {"seq": 3, "callId": callId, "eventType": "hangup", "payload": {"reason": "hung_up"}},
        ];
      }
      return const [];
    }
    if (callId == "call-seed-incoming" && sinceSeq < 1) {
      return [
        {"seq": 1, "callId": callId, "eventType": "invite", "payload": {"kind": "audio"}},
      ];
    }
    return const [];
  }

  // ------------------------------------------------------- notifications
  int _unreadNotifications() => _notifications
      .where((n) => !_readNotifications.contains("${n["id"]}"))
      .length;

  List<Map<String, dynamic>> _notificationsJson() => [
        for (final n in _notifications)
          {
            ...n,
            "readAt": _readNotifications.contains("${n["id"]}") ? n["createdAt"] : null,
          },
      ];

  /// Deterministic seed matching the production payload contract
  /// ({category, title, body, metadata, createdAt} + readAt) so the demo APK
  /// exercises list/badges/mark-read/filters exactly like the live API.
  void _seedNotifications() {
    if (_notifications.isNotEmpty) return;
    _notifications.addAll([
      {
        "id": "notif-demo-msg-1",
        "category": "message",
        "title": "New message from Amara",
        "body": "Are you coming today?",
        "metadata": {"conversationId": "conv-demo-user-amara"},
        "createdAt": "2026-01-15T08:12:00Z",
      },
      {
        "id": "notif-demo-pay-1",
        "category": "payment",
        "title": "Payment received",
        "body": "Mama sent you N5,000",
        "metadata": {},
        "createdAt": "2026-01-15T07:40:00Z",
      },
      {
        "id": "notif-demo-wallet-1",
        "category": "wallet",
        "title": "Wallet top-up successful",
        "body": "Your wallet was funded with N20,000",
        "metadata": {},
        "createdAt": "2026-01-14T20:00:00Z",
      },
      {
        "id": "notif-demo-biz-1",
        "category": "business",
        "title": "Order update",
        "body": "Your order from Ada's Boutique is ready",
        "metadata": {},
        "createdAt": "2026-01-14T18:05:00Z",
      },
      {
        "id": "notif-demo-sec-1",
        "category": "security",
        "title": "Security alert",
        "body": "Your password was changed",
        "metadata": {},
        "createdAt": "2026-01-13T21:30:00Z",
      },
      {
        "id": "notif-demo-dev-1",
        "category": "device",
        "title": "New device sign-in",
        "body": "OPPA was signed in on a new Android phone",
        "metadata": {},
        "createdAt": "2026-01-13T09:15:00Z",
      },
      {
        "id": "notif-demo-sup-1",
        "category": "support",
        "title": "Support update",
        "body": "Your report was reviewed by our team",
        "metadata": {},
        "createdAt": "2026-01-12T14:00:00Z",
      },
    ]);
  }

  Map<String, dynamic> _preferencesJson() => {
        for (final k in const ["message", "wallet", "payment", "security", "device", "business", "support"])
          k: _prefs[k] ?? true,
      };

  // --------------------------------------------------------------- misc
  /// Queues a pending offline message (used by the demo flow helper below).
  void queuePendingMessage({required String conversationId, required String body}) {
    _pendingSends.add({
      "id": "pending-${_epoch.microsecondsSinceEpoch}-${_pendingSends.length}",
      "conversationId": conversationId,
      "body": body,
      "createdAt": DateTime.now().toIso8601String(),
    });
  }
}

class _SentMessage {
  _SentMessage({
    required this.id,
    required this.conversationId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String body;
  final String createdAt;
}

class _DemoConversation {
  const _DemoConversation({
    required this.id,
    required this.title,
    required this.kind,
    required this.lastMessageAt,
  });

  final String id;
  final String title;
  final String kind;
  final String lastMessageAt;
}

class _DemoPerson {
  const _DemoPerson({
    required this.id,
    required this.name,
    required this.phone,
    required this.oppaId,
  });

  final String id;
  final String name;
  final String phone;
  final String oppaId;
}

class _DemoCall {
  _DemoCall({
    required this.id,
    required this.conversationId,
    required this.kind,
    required this.status,
    required this.outgoing,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String kind;
  final String status;
  final bool outgoing;
  final String createdAt;

  _DemoCall copyWith({String? status}) => _DemoCall(
        id: id,
        conversationId: conversationId,
        kind: kind,
        status: status ?? this.status,
        outgoing: outgoing,
        createdAt: createdAt,
      );
}
