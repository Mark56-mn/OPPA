import { strict as assert } from "node:assert";
import test from "node:test";
import { normalizePhone } from "./phone.js";

test("normalizes common formatting", () => {
  assert.equal(normalizePhone("+234 801-234-5678"), "+2348012345678");
});

test("rejects non-E164 phone numbers", () => {
  assert.throws(() => normalizePhone("08012345678"), /PHONE_INVALID/);
});
