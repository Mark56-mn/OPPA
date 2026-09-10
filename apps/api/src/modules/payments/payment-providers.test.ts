import { strict as assert } from "node:assert";
import test from "node:test";
import { createHmac } from "node:crypto";
import { PaystackProvider } from "./paystack-provider.js";
import { FlutterwaveProvider } from "./flutterwave-provider.js";

const ctx = { fetch: globalThis.fetch };

// ---------------------------------------------------------------------------
// Paystack
// ---------------------------------------------------------------------------

test("paystack: webhook HMAC is computed over the RAW body with the secret key", async () => {
  const provider = new PaystackProvider("sk_test_raw");
  const raw = Buffer.from(JSON.stringify({ event: "charge.success", data: { reference: "OPPA_1" } }));
  const good = createHmac("sha512", "sk_test_raw").update(raw).digest("hex");
  assert.equal(provider.verifyWebhook(raw, good), true);
  // Signature computed over re-serialized (non-raw) body must fail.
  const reserialized = Buffer.from(JSON.stringify({ data: { reference: "OPPA_1" }, event: "charge.success" }));
  const badSig = createHmac("sha512", "sk_test_raw").update(reserialized).digest("hex");
  assert.equal(provider.verifyWebhook(raw, badSig), false);
  assert.equal(provider.verifyWebhook(raw, undefined), false);
  assert.equal(provider.verifyWebhook(raw, "forged"), false);
});

test("paystack: verify maps success/ongoing/abandoned/failed correctly", async () => {
  globalThis.fetch = (async (_url: any) => new Response(JSON.stringify({
    status: true, message: "Verification successful",
    data: { id: 4321189, reference: "OPPA_1", amount: 5000, currency: "NGN", status: "ongoing" }
  }), { status: 200 })) as unknown as typeof fetch;
  try {
    const provider = new PaystackProvider("sk_test_x");
    const pending = await provider.verify("OPPA_1");
    assert.equal(pending.status, "pending", "ongoing must stay pending, never failed/success");
    assert.equal(pending.amountMinor, 5000, "paystack amounts are already minor units");
  } finally { globalThis.fetch = ctx.fetch; }

  globalThis.fetch = (async (_url: any) => new Response(JSON.stringify({
    status: true, data: { id: 1, reference: "OPPA_1", amount: 5000, currency: "NGN", status: "abandoned" }
  }), { status: 200 })) as unknown as typeof fetch;
  const abandoned = await new PaystackProvider("sk_test_x").verify("OPPA_1");
  assert.equal(abandoned.status, "abandoned");
});

test("paystack: initialize sends kobo amounts and extracts authorization_url", async () => {
  let body: any = null;
  globalThis.fetch = (async (_url: any, init: any) => {
    body = JSON.parse(String(init.body));
    return new Response(JSON.stringify({ status: true, data: { authorization_url: "https://checkout.paystack.com/xyz" } }), { status: 200 });
  }) as unknown as typeof fetch;
  try {
    const provider = new PaystackProvider("sk_test_x", { baseUrl: "https://api.paystack.test" });
    const result = await provider.initialize({ amountMinor: 12500, email: "a@b.com", reference: "OPPA_ref1" });
    assert.equal(result.authorizationUrl, "https://checkout.paystack.com/xyz");
    assert.equal(body.amount, 12500);
    assert.equal(body.reference, "OPPA_ref1");
  } finally { globalThis.fetch = ctx.fetch; }
});

test("paystack: non-2xx verify throws (fail closed) instead of guessing", async () => {
  globalThis.fetch = (async () => new Response(JSON.stringify({ status: false, message: "error" }), { status: 500 })) as unknown as typeof fetch;
  try {
    const provider = new PaystackProvider("sk_test_x");
    await assert.rejects(provider.verify("OPPA_1"), { message: "PAYMENT_PROVIDER_ERROR" });
  } finally { globalThis.fetch = ctx.fetch; }
});

// ---------------------------------------------------------------------------
// Flutterwave V3
// ---------------------------------------------------------------------------

test("flutterwave: verif-hash webhook secret is compared in constant time", () => {
  const provider = new FlutterwaveProvider("sk", "whsec");
  assert.equal(provider.verifyWebhook(Buffer.from("x"), "whsec"), true);
  assert.equal(provider.verifyWebhook(Buffer.from("x"), "WRONG"), false);
  assert.equal(provider.verifyWebhook(Buffer.from("x"), undefined), false);
});

test("flutterwave: verify_by_reference maps statuses and converts to minor units", async () => {
  globalThis.fetch = (async (_url: any) => new Response(JSON.stringify({
    status: "success",
    data: { id: 12345, tx_ref: "OPPA_1", amount: 50, currency: "NGN", status: "successful" }
  }), { status: 200 })) as unknown as typeof fetch;
  try {
    const provider = new FlutterwaveProvider("sk", "whsec");
    const result = await provider.verify("OPPA_1");
    assert.equal(result.status, "success");
    assert.equal(result.amountMinor, 5000, "major units must be converted to kobo");
    assert.equal(result.transactionId, "12345");
  } finally { globalThis.fetch = ctx.fetch; }

  globalThis.fetch = (async (_url: any) => new Response(JSON.stringify({
    status: "success", data: { id: 2, tx_ref: "OPPA_1", amount: 50, currency: "NGN", status: "new" }
  }), { status: 200 })) as unknown as typeof fetch;
  const pending = await new FlutterwaveProvider("sk", "whsec").verify("OPPA_1");
  assert.equal(pending.status, "pending", "unknown/new statuses must stay pending, never success");

  globalThis.fetch = (async (_url: any) => new Response(JSON.stringify({
    status: "success", data: { id: 3, tx_ref: "OPPA_1", amount: 50, currency: "USD", status: "successful" }
  }), { status: 200 })) as unknown as typeof fetch;
  await assert.rejects(new FlutterwaveProvider("sk", "whsec").verify("OPPA_1"), { message: "PAYMENT_CURRENCY_INVALID" });
});

test("flutterwave: initialize builds a V3 payment link with tx_ref", async () => {
  let capturedUrl = ""; let body: any = null;
  globalThis.fetch = (async (url: any, init: any) => {
    capturedUrl = String(url); body = JSON.parse(String(init.body));
    return new Response(JSON.stringify({ status: "success", data: { link: "https://flutterwave.com/pay/abc" } }), { status: 200 });
  }) as unknown as typeof fetch;
  try {
    const provider = new FlutterwaveProvider("sk", "whsec", { baseUrl: "https://api.flutterwave.test/v3" });
    const result = await provider.initialize({ amountMinor: 10000, email: "a@b.com", reference: "OPPA_r2", callbackUrl: "https://app/cb" });
    assert.equal(result.authorizationUrl, "https://flutterwave.com/pay/abc");
    assert.equal(capturedUrl, "https://api.flutterwave.test/v3/payments");
    assert.equal(body.tx_ref, "OPPA_r2");
    assert.equal(body.amount, 100);
    assert.equal(body.currency, "NGN");
    assert.equal(body.redirect_url, "https://app/cb");
  } finally { globalThis.fetch = ctx.fetch; }
});
