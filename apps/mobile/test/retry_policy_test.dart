import "package:flutter_test/flutter_test.dart";
import "package:oppa_mobile/core/api_client.dart";

void main() {
  group("endpoint-aware retry policy (ambiguous transport failures)", () {
    test("reads are always safe to retry", () {
      expect(retrySafetyFor("GET", "/wallet"), RetrySafety.safe);
      expect(retrySafetyFor("GET", "/conversations/c1/messages"), RetrySafety.safe);
      expect(retrySafetyFor("GET", "/notifications"), RetrySafety.safe);
    });

    test("deletes/puts are safe (idempotent by HTTP semantics)", () {
      expect(retrySafetyFor("DELETE", "/contacts/x"), RetrySafety.safe);
      expect(retrySafetyFor("PUT", "/notifications/preferences"), RetrySafety.safe);
    });

    test("keyed POSTs are safe: message sends carry clientMessageId", () {
      expect(retrySafetyFor("POST", "/conversations/c1/messages"), RetrySafety.safe);
    });

    test("order lifecycle POSTs are safe: single-transition server-side", () {
      expect(retrySafetyFor("POST", "/business/orders/o1/pay"), RetrySafety.safe,
          reason: "payment is single-transition (paid orders short-circuit)");
      expect(retrySafetyFor("POST", "/business/orders/o1/fulfill"), RetrySafety.safe,
          reason: "fulfillment is idempotent (already-fulfilled returns the record)");
      expect(retrySafetyFor("POST", "/business/orders/o1/cancel"), RetrySafety.safe,
          reason: "cancellation is single-transition (pending only)");
      // Order CREATION without a customer reference stays unsafe: a blind
      // retry after response loss could create two orders.
      expect(retrySafetyFor("POST", "/business/b1/orders"), RetrySafety.unsafe,
          reason: "customerOrderReference is optional, so creation is not unconditionally idempotent");
    });

    test("financial and auth POSTs are NEVER blindly retried", () {
      expect(retrySafetyFor("POST", "/payments/initialize"), RetrySafety.unsafe,
          reason: "double-submission could create two provider charges");
      expect(retrySafetyFor("POST", "/wallet/transfer"), RetrySafety.unsafe,
          reason: "challenge is consumed; a blind retry after response loss would 401 — but must not double-move money");
      expect(retrySafetyFor("POST", "/auth/otp/request"), RetrySafety.unsafe,
          reason: "could send a second SMS");
      expect(retrySafetyFor("POST", "/auth/otp/verify"), RetrySafety.unsafe);
      expect(retrySafetyFor("POST", "/auth/refresh"), RetrySafety.unsafe,
          reason: "refresh rotation is single-use; replay is a security event");
      expect(retrySafetyFor("POST", "/business"), RetrySafety.unsafe,
          reason: "could create two stores");
      expect(retrySafetyFor("POST", "/business/b1/products"), RetrySafety.unsafe,
          reason: "could create two products");
      expect(retrySafetyFor("POST", "/contacts"), RetrySafety.unsafe);
    });

    test("v1-prefixed paths classify identically", () {
      expect(retrySafetyFor("POST", "/v1/payments/initialize"), RetrySafety.unsafe);
      expect(retrySafetyFor("POST", "/v1/conversations/c1/messages"), RetrySafety.safe);
    });
  });
}
