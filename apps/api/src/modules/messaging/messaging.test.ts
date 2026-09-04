import assert from "node:assert/strict";
import test from "node:test";
import type { AddressInfo } from "node:net";
import express from "express";
import { errorHandler } from "../../http/error-handler.js";
import { createConversationRouter } from "./conversation-routes.js";
import { createMessagingRouter } from "./messaging-routes.js";
import type { ConversationRepository } from "./conversation-repository.js";
import type { Message, MessageReceipt, MessageRepository } from "./message-repository.js";

function message(overrides: Partial<Message> = {}): Message {
  return {
    id: "m1", conversationId: "c1", senderUserId: "u2", clientMessageId: null,
    messageType: "text", body: "hello", metadata: {}, createdAt: new Date(),
    editedAt: null, deletedAt: null, ...overrides
  };
}

function messageRepo(calls: Array<Record<string, unknown>>, overrides: Partial<MessageRepository> = {}): MessageRepository {
  return {
    async isMember(conversationId, userId) { calls.push({ isMember: { conversationId, userId } }); return true; },
    async list(conversationId, userId, limit, before) { calls.push({ list: { conversationId, userId, limit, before } }); return [message()]; },
    async send(conversationId, userId, input) { calls.push({ send: { conversationId, userId, ...input } }); return message({ senderUserId: userId }); },
    async markRead(conversationId, userId, upToMessageId) { calls.push({ markRead: { conversationId, userId, upToMessageId } }); return 3; },
    async receipts(conversationId, messageId, userId) { calls.push({ receipts: { conversationId, messageId, userId } }); return [] as MessageReceipt[]; },
    async edit(conversationId, messageId, userId, body) { calls.push({ edit: { conversationId, messageId, userId, body } }); return message({ body, editedAt: new Date() }); },
    async remove(conversationId, messageId, userId) { calls.push({ remove: { conversationId, messageId, userId } }); return true; },
    async unreadCounts(userId) { calls.push({ unreadCounts: { userId } }); return [{ conversationId: "c1", unread: 2 }]; },
    ...overrides
  };
}

function conversationRepo(calls: Array<Record<string, unknown>>, overrides: Partial<ConversationRepository> = {}): ConversationRepository {
  return {
    async listForUser(userId) { calls.push({ listForUser: { userId } }); return []; },
    async createDirect(userId, otherUserId) { calls.push({ createDirect: { userId, otherUserId } }); return { id: "c-direct" }; },
    async createGroup(userId, title, memberUserIds) { calls.push({ createGroup: { userId, title, memberUserIds } }); return { id: "c-group", kind: "group", title }; },
    async addMember(conversationId, actorId, newMemberId) { calls.push({ addMember: { conversationId, actorId, newMemberId } }); return { ok: true }; },
    async leave(conversationId, userId) { calls.push({ leave: { conversationId, userId } }); return { ok: true }; },
    ...overrides
  };
}

async function listen(app: express.Express): Promise<{ url: string; close: () => Promise<void> }> {
  const server = await new Promise<import("node:http").Server>((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });
  const { port } = server.address() as AddressInfo;
  return { url: `http://127.0.0.1:${port}`, close: () => new Promise((resolve) => server.close(() => resolve())) };
}

function appFor(conversations: ConversationRepository, messages: MessageRepository) {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => { req.auth = { userId: "u1", sessionId: "s1" }; next(); });
  app.use("/conversations", createConversationRouter(conversations, messages));
  app.use("/", createMessagingRouter(messages));
  app.use(errorHandler);
  return app;
}

test("group creation requires a valid title and members", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const app = appFor(conversationRepo(calls), messageRepo(calls));
  const srv = await listen(app);
  try {
    const noTitle = await fetch(`${srv.url}/conversations/groups`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ title: "  ", memberUserIds: ["u2"] })
    });
    assert.equal(noTitle.status, 400);
    const noMembers = await fetch(`${srv.url}/conversations/groups`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ title: "Team", memberUserIds: [] })
    });
    assert.equal(noMembers.status, 400);
    const ok = await fetch(`${srv.url}/conversations/groups`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ title: "Team", memberUserIds: ["u2", "u3"] })
    });
    assert.equal(ok.status, 201);
    assert.ok(calls.some((c) => "createGroup" in c));
  } finally { await srv.close(); }
});

test("adding a member and leaving delegate to the repository", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const app = appFor(conversationRepo(calls), messageRepo(calls));
  const srv = await listen(app);
  try {
    const add = await fetch(`${srv.url}/conversations/c1/members`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ userId: "u2" })
    });
    assert.equal(add.status, 201);
    const leave = await fetch(`${srv.url}/conversations/c1/leave`, { method: "POST" });
    assert.equal(leave.status, 200);
    assert.ok(calls.some((c) => "addMember" in c));
    assert.ok(calls.some((c) => "leave" in c));
  } finally { await srv.close(); }
});

test("mark-read only touches the caller's receipts and validates input", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const app = appFor(conversationRepo(calls), messageRepo(calls));
  const srv = await listen(app);
  try {
    const ok = await fetch(`${srv.url}/conversations/c1/read`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ upToMessageId: "m9" })
    });
    assert.equal(ok.status, 200);
    const body = await ok.json() as { updated: number };
    assert.equal(body.updated, 3);
    assert.deepEqual(calls.find((c) => "markRead" in c), { markRead: { conversationId: "c1", userId: "u1", upToMessageId: "m9" } });
  } finally { await srv.close(); }
});

test("edit succeeds for the owner and fails closed with 404 otherwise", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const app = appFor(conversationRepo(calls), messageRepo(calls, {
    async edit(conversationId, messageId, userId, body) {
      calls.push({ edit: { conversationId, messageId, userId, body } });
      return userId === "u1" ? message({ body, editedAt: new Date() }) : null;
    }
  }));
  const srv = await listen(app);
  try {
    const owner = await fetch(`${srv.url}/conversations/c1/messages/m1`, {
      method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify({ body: "edited" })
    });
    assert.equal(owner.status, 200);
    const empty = await fetch(`${srv.url}/conversations/c1/messages/m1`, {
      method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify({ body: "   " })
    });
    assert.equal(empty.status, 400);
  } finally { await srv.close(); }
});

test("delete returns 404 when the message is not owned by the caller", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const app = appFor(conversationRepo(calls), messageRepo(calls, {
    async remove(conversationId, messageId, userId) {
      calls.push({ remove: { conversationId, messageId, userId } });
      return userId === "u1";
    }
  }));
  const srv = await listen(app);
  try {
    const ok = await fetch(`${srv.url}/conversations/c1/messages/m1`, { method: "DELETE" });
    assert.equal(ok.status, 204);
  } finally { await srv.close(); }
});
