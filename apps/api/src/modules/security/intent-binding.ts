import { createHash } from "node:crypto";

export type SensitiveIntent = Record<string, unknown>;

const MAX_INTENT_DEPTH = 6;
const MAX_INTENT_LENGTH = 4096;

function isPlainObject(value: unknown): value is SensitiveIntent {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const proto = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null;
}

function canonicalize(value: unknown, depth: number): string {
  if (depth > MAX_INTENT_DEPTH) throw new Error("INTENT_TOO_DEEP");
  if (value === null) return "null";
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("INTENT_VALUE_INVALID");
    return JSON.stringify(value);
  }
  if (typeof value === "boolean") return value ? "true" : "false";
  if (Array.isArray(value)) return "[" + value.map((v) => canonicalize(v, depth + 1)).join(",") + "]";
  if (isPlainObject(value)) {
    return "{" + Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalize(value[key], depth + 1)}`).join(",") + "}";
  }
  throw new Error("INTENT_VALUE_INVALID");
}

/**
 * Deterministic, stable serialization of an intent object. Sorting keys makes
 * the canonical form independent of key insertion order so client and server
 * always derive the same string to sign and hash.
 */
export function canonicalizeIntent(intent: SensitiveIntent): string {
  return canonicalize(intent, 0);
}

/** Hash of the canonical intent, stored with the step-up challenge. */
export function hashIntent(intent: SensitiveIntent): string {
  return createHash("sha256").update(canonicalizeIntent(intent)).digest("hex");
}

/**
 * Validates that a client-supplied intent is a bounded plain object before it
 * is canonicalized, hashed or persisted.
 */
export function assertValidIntent(intent: unknown): asserts intent is SensitiveIntent {
  if (!isPlainObject(intent)) throw new Error("INTENT_INVALID");
  const canonical = canonicalizeIntent(intent);
  if (canonical.length > MAX_INTENT_LENGTH) throw new Error("INTENT_TOO_LARGE");
}