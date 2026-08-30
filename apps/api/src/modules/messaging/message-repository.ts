export interface Message {
  id: string; conversationId: string; senderUserId: string; clientMessageId: string | null;
  messageType: string; body: string | null; metadata: Record<string, unknown>; createdAt: Date;
}
export interface MessageRepository {
  isMember(conversationId: string, userId: string): Promise<boolean>;
  list(conversationId: string, userId: string, limit: number, before?: string): Promise<Message[]>;
  send(conversationId: string, userId: string, input: { body?: string; messageType?: string; metadata?: Record<string, unknown>; clientMessageId?: string }): Promise<Message>;
}
