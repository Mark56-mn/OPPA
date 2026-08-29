const E164 = /^\+[1-9]\d{7,14}$/;

export function normalizePhone(input: string): string {
  const phone = input.trim().replace(/[\s()-]/g, "");
  if (!E164.test(phone)) throw new Error("PHONE_INVALID");
  return phone;
}
