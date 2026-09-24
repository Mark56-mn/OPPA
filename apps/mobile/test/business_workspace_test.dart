import "package:flutter_test/flutter_test.dart";

import "package:oppa_mobile/core/demo_backend.dart";

/// The business workspace MUST actually work: creating a business has to
/// persist, own its own catalogue/orders/roster, and survive navigation.
///
/// These tests run against the in-process backend the demo APK uses. Before
/// the fix they failed: POST /business returned an id that GET /business never
/// listed, and every sub-screen silently fell back to the seed store — so
/// "creation" only looked like it worked.
void main() {
  late DemoBackend api;

  setUp(() => api = DemoBackend(latency: Duration.zero));

  Future<List<Map<String, dynamic>>> businesses() async {
    final r = await api.get("/business");
    expect(r.isSuccess, isTrue, reason: "${r.errorCode}");
    return (((r.body as Map)["businesses"] as List))
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  group("business creation", () {
    test("a created business is listed afterwards and survives reloads", () async {
      final before = await businesses();
      expect(before.length, 1, reason: "one seed store");

      final created = await api.post("/business", body: {"name": "Mama's Kitchen"});
      expect(created.isSuccess, isTrue, reason: "${created.errorCode}");
      final id = "${(created.body as Map)["id"]}";
      expect(id, isNotEmpty);

      final after = await businesses();
      expect(after.length, 2);
      expect(after.any((b) => b["id"] == id), isTrue,
          reason: "the new business must appear in the switcher");
      // Reloading (e.g. reopening the switcher) still shows it.
      expect((await businesses()).any((b) => b["id"] == id), isTrue);

      // The seed store is untouched.
      expect(after.any((b) => b["id"] == "biz-demo-spices"), isTrue);
    });

    test("a blank or oversized name is refused and creates nothing", () async {
      final blank = await api.post("/business", body: {"name": "   "});
      expect(blank.isSuccess, isFalse);
      expect(blank.errorCode, "BUSINESS_NAME_INVALID");

      final long = await api.post("/business", body: {"name": "x" * 121});
      expect(long.errorCode, "BUSINESS_NAME_INVALID");

      expect((await businesses()).length, 1,
          reason: "rejected names must not leave a stray store behind");
    });

    test("a new store starts empty: no inherited products, orders or staff", () async {
      final created = await api.post("/business", body: {"name": "New Store"});
      final id = "${(created.body as Map)["id"]}";

      final products = await api.get("/business/$id/products");
      expect((((products.body as Map)["products"]) as List), isEmpty,
          reason: "a fresh store must not inherit another store's catalogue");

      final orders = await api.get("/business/$id/orders");
      expect((((orders.body as Map)["orders"]) as List), isEmpty);

      final staff = await api.get("/business/$id/staff");
      final roster = ((staff.body as Map)["staff"]) as List;
      expect(roster.length, 1, reason: "only the owner row is created");
      expect((roster.first as Map)["role"], "owner");

      // ...while the seed store keeps its own data.
      final seedProducts = await api.get("/business/biz-demo-spices/products");
      expect((((seedProducts.body as Map)["products"]) as List), isNotEmpty);
    });

    test("an unknown business id is a real 404, never the seed store", () async {
      final r = await api.get("/business/biz-does-not-exist/products");
      expect(r.isSuccess, isFalse);
      expect(r.errorCode, "BUSINESS_NOT_FOUND");
    });
  });

  group("product management", () {
    test("add, edit, archive and restore a product", () async {
      final created =
          await api.post("/business", body: {"name": "Product Test Store"});
      final id = "${(created.body as Map)["id"]}";

      final added = await api.post("/business/$id/products",
          body: {"name": "Jollof Rice", "priceMinor": 250000});
      expect(added.isSuccess, isTrue, reason: "${added.errorCode}");
      final productId = "${(added.body as Map)["id"]}";

      // Edit: name + price are persisted, not just echoed.
      final edited = await api.patch("/business/$id/products/$productId",
          body: {"name": "Party Jollof Rice", "priceMinor": 300000});
      expect(edited.isSuccess, isTrue, reason: "${edited.errorCode}");

      final listed = await api.get("/business/$id/products");
      final product = (((listed.body as Map)["products"]) as List)
          .whereType<Map>()
          .firstWhere((p) => p["id"] == productId);
      expect(product["name"], "Party Jollof Rice");
      expect(product["priceMinor"], 300000);
      expect(product["status"], "active");

      // Archive hides it from customers...
      final archived = await api.patch("/business/$id/products/$productId",
          body: {"status": "archived"});
      expect(archived.isSuccess, isTrue);
      final activeOnly = await api.get("/business/$id/products");
      expect((activeOnly.body as Map)["products"], isEmpty,
          reason: "archived products must not be offered to customers");

      // ...and restore brings it back.
      final restored = await api.patch("/business/$id/products/$productId",
          body: {"status": "active"});
      expect(restored.isSuccess, isTrue);
      expect(((await api.get("/business/$id/products")).body as Map)["products"],
          isNotEmpty);
    });

    test("invalid product edits are rejected with the documented codes", () async {
      final added = await api.post("/business/biz-demo-spices/products",
          body: {"name": "Temp", "priceMinor": 1000});
      final productId = "${(added.body as Map)["id"]}";

      expect(
          (await api.patch("/business/biz-demo-spices/products/$productId",
                  body: {"priceMinor": 0}))
              .errorCode,
          "BUSINESS_PRODUCT_PRICE_INVALID");
      expect(
          (await api.patch("/business/biz-demo-spices/products/$productId",
                  body: {"name": "  "}))
              .errorCode,
          "BUSINESS_PRODUCT_NAME_INVALID");
      expect(
          (await api.patch("/business/biz-demo-spices/products/$productId",
                  body: {"status": "deleted"}))
              .errorCode,
          "BUSINESS_PRODUCT_STATUS_INVALID");
      // A product of another business is not reachable by id: the caller is
      // not staff there, so the server refuses before touching the row (same
      // behaviour as PostgresBusinessRepository.updateProduct).
      expect(
          (await api.patch("/business/biz-other/products/$productId",
                  body: {"name": "Stolen"}))
              .errorCode,
          "BUSINESS_PERMISSION_DENIED");
    });
  });

  group("business profile", () {
    test("renaming persists and is reflected by a fresh read", () async {
      final renamed = await api.patch("/business/biz-demo-spices",
          body: {"name": "Mama's Kitchen", "description": "Home cooking"});
      expect(renamed.isSuccess, isTrue, reason: "${renamed.errorCode}");

      final read = await api.get("/business/biz-demo-spices");
      expect((read.body as Map)["name"], "Mama's Kitchen");
      expect((read.body as Map)["description"], "Home cooking");

      // And the change is visible in the switcher's list.
      final listed = await businesses();
      expect(listed.firstWhere((b) => b["id"] == "biz-demo-spices")["name"],
          "Mama's Kitchen");
    });

    test("a blank rename is refused", () async {
      final r = await api.patch("/business/biz-demo-spices", body: {"name": " "});
      expect(r.isSuccess, isFalse);
      expect(r.errorCode, "BUSINESS_NAME_INVALID");
    });
  });

  group("merchant chat hand-off", () {
    test("opening a direct conversation with a customer returns it (idempotent)", () async {
      final first =
          await api.post("/conversations/direct", body: {"userId": "demo-user-amara"});
      expect(first.isSuccess, isTrue, reason: "${first.errorCode}");
      final id = (first.body as Map)["id"];

      final second =
          await api.post("/conversations/direct", body: {"userId": "demo-user-amara"});
      expect((second.body as Map)["id"], id,
          reason: "a second tap must reuse the conversation, not fork it");
    });
  });

  group("analytics isolation", () {
    test("each store reports only its own orders and revenue", () async {
      final seed = await api.get("/business/biz-demo-spices/analytics");
      final seedBody = seed.body as Map;
      expect(seedBody["ordersTotal"], greaterThan(0));

      final fresh = await api.post("/business", body: {"name": "Empty Store"});
      final id = "${(fresh.body as Map)["id"]}";
      final freshAnalytics = await api.get("/business/$id/analytics");
      expect((freshAnalytics.body as Map)["ordersTotal"], 0);
      expect((freshAnalytics.body as Map)["revenueMinor"], 0);
    });
  });
}

