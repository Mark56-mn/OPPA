import assert from "node:assert/strict";
import test from "node:test";
import { CallsService } from "./calls-service.js";
import type { CallRecord, CallEvent, CallsStore } from "./calls-service.js";

function makeCall(overrides: Partial<CallRecord> = {}): CallRecord {
  return {
    id: "c1",
    conversationId: "conv1",
    callerUserId: "u1",
    kind: "audio",
    status: "ringing",
    endReason: null,
    startedAt: new Date(),
    answeredAt: null,
    endedAt: null,
    metadata: {},
    ...overrides
  };
}

class FakeStore implements CallsStore {
  calls = new Map<string, CallRecord>();
  recentCount = 0;
  events: CallEvent[] = [];
  startCalls = 0;

  async startCall(input: { conversationId: string; callerId: string; kind: "audio" | "video" }) {
    this.startCalls += 1;
    const call = makeCall({
      id: `call${this.startCalls}`,
      conversationId: input.conversationId,
      callerUserId: input.callerId,
      kind: input.kind
    });
    this.calls.set(call.id, call);
    return { call, inviteSeq: 1 };
  }
  async answerCall(conversationId: string, callId: string, userId: string) {
    const call = this.calls.get(callId);
    if (!call || call.conversationId !== conversationId || call.callerUserId === userId) return null;
    if (call.status !== "ringing") return null;
    call.status = "active";
    call.answeredAt = new Date();
    return call;
  }
  async declineCall(conversationId: string, callId: string, userId: string, reason: "declined" | "busy") {
    const call = this.calls.get(callId);
    if (!call || call.conversationId !== conversationId || call.status !== "ringing") return null;
    if (call.callerUserId === userId) call.endReason = "cancelled";
    else call.endReason = reason;
    call.status = "ended";
    call.endedAt = new Date();
    return call;
  }
  async hangUp(conversationId: string, callId: string, userId: string) {
    const call = this.calls.get(callId);
    if (!call || call.conversationId !== conversationId || call.status === "ended") return null;
    if (call.status === "ringing" && call.callerUserId === userId) call.endReason = "cancelled";
    else if (call.status === "ringing") call.endReason = "declined";
    else call.endReason = "hung_up";
    call.status = "ended";
    call.endedAt = new Date();
    return call;
  }
  async history(conversationId: string, _userId: string, limit: number) {
    return [...this.calls.values()].filter(c => c.conversationId === conversationId).slice(0, limit);
  }
  async eventsSince(_conversationId: string, _callId: string, _userId: string, sinceSeq: number) {
    return this.events.filter(e => e.seq > sinceSeq);
  }
  async signalCall(_c: string, _call: string, _u: string, eventType: string) {
    this.events.push({ seq: this.events.length + 1, callId: _call, eventType, payload: {}, createdAt: new Date() });
    return this.events.length;
  }
  async timeoutStaleRinging(_now: Date) { return 0; }
  async countRecentCalls(_callerId: string, _since: Date) { return this.recentCount; }
}

test("calls: rejects invalid kind and metadata before touching the store", async () => {
  const store = new FakeStore();
  const calls = new CallsService(store);
  await assert.rejects(calls.start("conv1", "u1", "videox"), /CALL_KIND_INVALID/);
  await assert.rejects(calls.start("conv1", "u1", ["audio"]), /CALL_KIND_INVALID/);
  await assert.rejects(calls.start("conv1", "u1", "audio", [1]), /CALL_METADATA_INVALID/);
  assert.equal(store.startCalls, 0);
});

test("calls: rate-limits ring spam per caller", async () => {
  const store = new FakeStore();
  store.recentCount = 5;
  const calls = new CallsService(store);
  await assert.rejects(calls.start("conv1", "u1", "audio"), /CALL_RATE_LIMITED/);
  assert.equal(store.startCalls, 0);
  store.recentCount = 4;
  await calls.start("conv1", "u1", "audio");
  assert.equal(store.startCalls, 1);
});

test("calls: answer/decline/hangup enforce not-found for absent calls", async () => {
  const calls = new CallsService(new FakeStore());
  await assert.rejects(calls.answer("conv1", "missing", "u2"), /CALL_NOT_FOUND/);
  await assert.rejects(calls.decline("conv1", "missing", "u2", false), /CALL_NOT_FOUND/);
  await assert.rejects(calls.hangUp("conv1", "missing", "u2"), /CALL_NOT_FOUND/);
});

test("calls: callee can answer a ringing call", async () => {
  const store = new FakeStore();
  const { call } = await new CallsService(store).start("conv1", "u1", "video");
  const answered = await new CallsService(store).answer("conv1", call.id, "u2");
  assert.equal(answered.status, "active");
  assert.ok(answered.answeredAt);
});

test("calls: caller decline is a cancel; busy flag is preserved", async () => {
  const store = new FakeStore();
  const service = new CallsService(store);
  const { call } = await service.start("conv1", "u1", "audio");
  const cancelled = await service.decline("conv1", call.id, "u1", false);
  assert.equal(cancelled.endReason, "cancelled");
  const { call: c2 } = await service.start("conv1", "u1", "audio");
  const busy = await service.decline("conv1", c2.id, "u2", true);
  assert.equal(busy.endReason, "busy");
});

test("calls: hangup maps ringing-caller to cancelled and active to hung_up", async () => {
  const store = new FakeStore();
  const service = new CallsService(store);
  const { call } = await service.start("conv1", "u1", "audio");
  const cancelled = await service.hangUp("conv1", call.id, "u1");
  assert.equal(cancelled.endReason, "cancelled");
  const { call: c2 } = await service.start("conv1", "u1", "audio");
  await service.answer("conv1", c2.id, "u2");
  const hungUp = await service.hangUp("conv1", c2.id, "u2");
  assert.equal(hungUp.endReason, "hung_up");
});

test("calls: history caps limit and clamps invalid values", async () => {
  const store = new FakeStore();
  for (let i = 0; i < 3; i += 1) {
    const { call } = await new CallsService(store).start("conv1", "u1", "audio");
    store.calls.get(call.id)!.status = "ended";
  }
  const service = new CallsService(store);
  const all = await service.history("conv1", "u1", 2);
  assert.equal(all.length, 2);
  const clamped = await service.history("conv1", "u1", 10_000);
  assert.ok(clamped.length <= 25);
});

test("calls: poll validates cursor range", async () => {
  const calls = new CallsService(new FakeStore());
  await assert.rejects(calls.poll("conv1", "c1", "u1", -1), /CALL_CURSOR_INVALID/);
  await assert.rejects(calls.poll("conv1", "c1", "u1", Number.MAX_SAFE_INTEGER + 1), /CALL_CURSOR_INVALID/);
  const events = await calls.poll("conv1", "c1", "u1", 0);
  assert.deepEqual(events, []);
});

test("calls: signal validates event type and payload shape", async () => {
  const calls = new CallsService(new FakeStore());
  await assert.rejects(calls.signal("conv1", "c1", "u1", "invite"), /CALL_SIGNAL_INVALID/);
  await assert.rejects(calls.signal("conv1", "c1", "u1", "answer", [1]), /CALL_PAYLOAD_INVALID/);
  const seq = await calls.signal("conv1", "c1", "u1", "answer", { sdp: "v=0" });
  assert.equal(seq, 1);
});

test("calls: sweep uses ring-timeout cutoff", async () => {
  let captured!: Date;
  const store = new FakeStore();
  store.timeoutStaleRinging = async (now: Date) => {
    captured = now;
    return 3;
  };
  const swept = await new CallsService(store).sweepStale();
  assert.equal(swept, 3);
  assert.ok(captured.getTime() <= Date.now() - 2 * 60_000);
});
