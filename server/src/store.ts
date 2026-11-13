import type { ScheduleItem, ScheduledPush, PushType, Subscription } from "./types.ts";

/** Thrown by upsertSubscription when the endpoint exists with a different auth secret. */
export class SubscriptionConflictError extends Error {
  constructor() {
    super("subscription_conflict");
  }
}

export interface Store {
  getByEndpoint(endpoint: string): Promise<Subscription | null>;
  /**
   * Upsert by endpoint. Keeps sent counters of an existing row.
   * MUST throw SubscriptionConflictError (never overwrite) if the endpoint exists with a different auth.
   */
  upsertSubscription(s: {
    endpoint: string; p256dh: string; auth: string;
    sleepStart: number | null; sleepEnd: number | null; tzOffsetMinutes: number;
  }): Promise<Subscription>;
  updateSettings(id: string, s: Partial<Pick<Subscription, "sleepStart" | "sleepEnd" | "tzOffsetMinutes">>): Promise<void>;
  deleteSubscription(id: string): Promise<void>;
  /** Atomically replace all UNSENT rows; skip items already sent. Returns stored count. */
  replaceSchedule(subId: string, items: ScheduleItem[]): Promise<number>;
  /**
   * Atomically claim due, unsent rows (fire_at <= now) for one dispatcher run.
   * Rows already claimed by another run are skipped unless that claim is older than staleClaimMs
   * (dead dispatcher). SQL: FOR UPDATE SKIP LOCKED.
   */
  claimDue(nowMs: number, limit: number, token: string, staleClaimMs: number): Promise<Array<{ push: ScheduledPush; sub: Subscription }>>;
  /** Give a claimed row back (transient send failure / run budget exhausted). No-op if the token no longer owns it. */
  releaseClaim(pushId: number, token: string): Promise<void>;
  /** Moves the row; clears its claim. */
  reschedule(pushId: number, fireAt: number): Promise<void>;
  deletePush(pushId: number): Promise<void>;
  /** Mark sent (clears the claim) and persist the subscription's counters. With a token, only if the claim is still ours. */
  markSent(pushId: number, nowMs: number, subId: string, day: number, counts: Partial<Record<PushType, number>>, token?: string): Promise<void>;
  purgeSent(nowMs: number): Promise<void>;
}

/** In-memory Store used by tests and for local experiments. Mirrors the SQL semantics. */
export type MemPush = ScheduledPush & { claimedAt?: number | null; claimToken?: string | null };

export class MemoryStore implements Store {
  subs = new Map<string, Subscription>();
  pushes: MemPush[] = [];
  private seq = 0;

  async getByEndpoint(endpoint: string) {
    return [...this.subs.values()].find((s) => s.endpoint === endpoint) ?? null;
  }
  async upsertSubscription(s: Parameters<Store["upsertSubscription"]>[0]) {
    const ex = await this.getByEndpoint(s.endpoint);
    if (ex) {
      if (ex.auth !== s.auth) throw new SubscriptionConflictError();
      Object.assign(ex, s);
      return ex;
    }
    const sub: Subscription = { id: `sub-${++this.seq}`, ...s, sentToday: {}, sentDay: null };
    this.subs.set(sub.id, sub);
    return sub;
  }
  async updateSettings(id: string, s: Partial<Subscription>) {
    const sub = this.subs.get(id);
    if (sub) Object.assign(sub, s);
  }
  async deleteSubscription(id: string) {
    this.subs.delete(id);
    this.pushes = this.pushes.filter((p) => p.subscriptionId !== id);
  }
  async replaceSchedule(subId: string, items: ScheduleItem[]) {
    // Sent rows and rows a dispatcher is sending right now are kept (and block re-adding the same item).
    const inFlight = (p: MemPush) => p.sentAt !== null || (p.claimedAt ?? null) !== null;
    const sent = this.pushes.filter((p) => p.subscriptionId === subId && inFlight(p));
    this.pushes = this.pushes.filter((p) => p.subscriptionId !== subId || inFlight(p));
    let stored = 0;
    for (const it of [...items].sort((a, b) => a.fireAt - b.fireAt)) {
      const already = sent.some((s) =>
        s.type === it.type &&
        (it.dedupeKey !== null ? s.dedupeKey === it.dedupeKey : s.fireAt === it.fireAt));
      const dup = this.pushes.some((p) =>
        p.subscriptionId === subId && p.sentAt === null && p.type === it.type && p.fireAt === it.fireAt);
      // mirrors unique (subscription_id, type, dedupe_key): one row per key
      const keyDup = it.dedupeKey !== null && this.pushes.some((p) =>
        p.subscriptionId === subId && p.type === it.type && p.dedupeKey === it.dedupeKey);
      if (already || dup || keyDup) continue;
      this.pushes.push({ id: ++this.seq, subscriptionId: subId, type: it.type, fireAt: it.fireAt, dedupeKey: it.dedupeKey, sentAt: null });
      stored++;
    }
    return stored;
  }
  async claimDue(nowMs: number, limit: number, token: string, staleClaimMs: number) {
    // No await between select and claim: atomic w.r.t. other runs on the same event loop.
    const rows = this.pushes
      .filter((p) => p.sentAt === null && p.fireAt <= nowMs && this.subs.has(p.subscriptionId) &&
        (p.claimedAt == null || p.claimedAt < nowMs - staleClaimMs))
      .sort((a, b) => a.fireAt - b.fireAt || a.id - b.id)
      .slice(0, limit);
    for (const p of rows) { p.claimedAt = nowMs; p.claimToken = token; }
    return rows.map((push) => ({ push: { ...push }, sub: this.subs.get(push.subscriptionId)! }));
  }
  async releaseClaim(pushId: number, token: string) {
    const p = this.pushes.find((x) => x.id === pushId);
    if (p && p.claimToken === token) { p.claimedAt = null; p.claimToken = null; }
  }
  async reschedule(pushId: number, fireAt: number) {
    const p = this.pushes.find((x) => x.id === pushId);
    if (p) { p.fireAt = fireAt; p.claimedAt = null; p.claimToken = null; }
  }
  async deletePush(pushId: number) {
    this.pushes = this.pushes.filter((p) => p.id !== pushId);
  }
  async markSent(pushId: number, nowMs: number, subId: string, day: number, counts: Partial<Record<PushType, number>>, token?: string) {
    const p = this.pushes.find((x) => x.id === pushId);
    if (p && p.sentAt === null && (token === undefined || p.claimToken === token)) {
      p.sentAt = nowMs; p.claimedAt = null; p.claimToken = null;
    }
    const s = this.subs.get(subId);
    if (s) { s.sentDay = day; s.sentToday = counts; }
  }
  async purgeSent(nowMs: number) {
    const D = 86_400_000;
    this.pushes = this.pushes.filter((p) =>
      p.sentAt === null || (p.dedupeKey === null ? p.sentAt >= nowMs - 2 * D : p.sentAt >= nowMs - 60 * D));
  }
  unsent(subId: string) {
    return this.pushes.filter((p) => p.subscriptionId === subId && p.sentAt === null);
  }
}
