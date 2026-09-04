export interface Message {
  id: string; conversationId: string; senderUserId: string; clientMessageId: string | null;
  messageType: string; body: string | null; metadata: Record<string, unknown>; createdAt: Date;
  editedAt?: Date | null; deletedAt?: Date | null;
}

export interface MessageReceipt {
  userId: string;
  deliveredAt: Date | null;
  readAt: Date | null;
}

export interface MessageRepository {
  isMember(conversationId: string, userId: string): Promise<boolean>;
  list(conversationId: string, userId: string, limit: number, before?: string): Promise<Message[]>;
  send(conversationId: string, userId: string, input: { body?: string; messageType?: string; metadata?: Record<string, unknown>; clientMessageId?: string }): Promise<Message>;
  /** Marks every other member's messages delivered/read up to a message, for the caller. */
  markRead(conversationId: string, userId: string, upToMessageId?: string): Promise<number>;
  /** Receipts for one message (per member delivery/read state). */
  receipts(conversationId: string, messageId: string, userId: string): Promise<MessageReceipt[]>;
  /** Edits the caller's own text message; returns null when not owned/not found. */
  edit(conversationId: string, messageId: string, userId: string, body: string): Promise<Message | null>;
  /** Soft-deletes the caller's own message. */
  remove(conversationId: string, messageId: string, userId: string): Promise<boolean>;
  /** Unread count per conversation for the caller's chat list. */
  unreadCounts(userId: string): Promise<Array<{ conversationId: string; unread: number }>>;
}
