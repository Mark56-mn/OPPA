export type SmsDeliveryStatus = "queued" | "submitted" | "delivered" | "failed" | "unknown";

export interface SendSmsInput {
  to: string;
  message: string;
  senderId?: string;
  callbackUrl?: string;
}

export interface SendSmsResult {
  provider: string;
  providerMessageId?: string;
  status: SmsDeliveryStatus;
}

export interface SmsProvider {
  readonly name: string;
  send(input: SendSmsInput): Promise<SendSmsResult>;
}
