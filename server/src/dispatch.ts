import type { PushSender, PushType, ScheduledPush, Subscription } from "./types.ts";
import type { Store } from "./store.ts";
import { adjustForSleep, inSleepWindow, localDay } from "./sleep.ts";
import { countsForDay, underCap } from "./caps.ts";
import { buildPayload } from "./templates.ts";

/** A due push older than this is dropped (a stale "hungry" ping is worse than none). */
export const MAX_LATENESS_MS = 2 * 3_600_000;
/** Max rows claimed (and so sent) per run. */
export const DISPATCH_BATCH = 500;
/** One send() that takes longer is abandoned and treated as a transient failure. */
export const SEND_TIMEOUT_MS = 10_000;
/** Wall-clock budget of one run. Rows not reached are released for the next minute. Must stay well below CLAIM_STALE_MS. */
export const DISPATCH_BUDGET_MS = 40_000;
/** A claim older than this is a dead dispatcher's and may be taken over. */
export const CLAIM_STALE_MS = 5 * 60_000;

export interface DispatchResult {
  sent: number;
  deferredSleep: number;
  deferredCap: number;
  droppedStale: number;
  droppedDuplicate: number;
  subscriptionsDeleted: number;
  failedTransient: number;
  /** rows released unsent because the run budget ran out */
  releasedBudget: number;
  /** rows whose processing threw (DB error etc.); the batch continues */
  errors: number;
}

export interface DispatchOptions {
  sendTimeoutMs?: number;
  budgetMs?: number;
  staleClaimMs?: number;
  /** Wall clock for the budget (tests inject a fake). Default Date.now. */
  clock?: () => number;
}

const isUniqueViolation = (e: unknown) => {
  const x = e as { code?: string; message?: string } | null;
  return x?.code === "23505" || /duplicate key|unique constraint/i.test(x?.message ?? "");
};

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout>;
  const timeout = new Promise<never>((_, rej) => {
    timer = setTimeout(() => rej(Object.assign(new Error("send timeout"), { timeout: true })), ms);
  });
  return Promise.race([p, timeout]).finally(() => clearTimeout(timer));
}

export async function runDispatch(
  deps: { store: Store; sender: PushSender; now: () => number },
  opts: DispatchOptions = {},
): Promise<DispatchResult> {
  const { store, sender } = deps;
  const sendTimeout = opts.sendTimeoutMs ?? SEND_TIMEOUT_MS;
  const budget = opts.budgetMs ?? DISPATCH_BUDGET_MS;
  const clock = opts.clock ?? Date.now;
  const now = deps.now();
  const token = crypto.randomUUID();
  const r: DispatchResult = {
    sent: 0, deferredSleep: 0, deferredCap: 0, droppedStale: 0, droppedDuplicate: 0,
    subscriptionsDeleted: 0, failedTransient: 0, releasedBudget: 0, errors: 0,
  };
  const dead = new Set<string>();
  // One Subscription object per id, even if the store hands out per-row copies, so that
  // counters updated for one row are seen by the next (daily cap within a batch).
  const subs = new Map<string, Subscription>();
  const sentKeys = new Set<string>();
  const started = clock();

  const release = async (p: ScheduledPush) => {
    try { await store.releaseClaim(p.id, token); } catch { /* claim expires by itself */ }
  };
  /** Move a row; a unique clash means an identical pending row already exists, so this one is redundant. */
  const moveTo = async (p: ScheduledPush, at: number) => {
    try {
      await store.reschedule(p.id, at);
    } catch (e) {
      if (!isUniqueViolation(e)) throw e;
      await store.deletePush(p.id);
    }
  };

  const claimed = await store.claimDue(now, DISPATCH_BATCH, token, opts.staleClaimMs ?? CLAIM_STALE_MS);

  for (const { push, sub: rowSub } of claimed) {
    let sub = subs.get(rowSub.id);
    if (!sub) subs.set(rowSub.id, (sub = rowSub));
    if (dead.has(sub.id)) continue; // rows vanished with the subscription (cascade)
    if (clock() - started > budget) {
      await release(push);
      r.releasedBudget++;
      continue;
    }

    let sendDone = false;
    try {
      const win = { start: sub.sleepStart, end: sub.sleepEnd };

      if (now - push.fireAt > MAX_LATENESS_MS) {
        await store.deletePush(push.id);
        r.droppedStale++;
        continue;
      }
      // Same sick/evolve key must never go out twice (history: sentKeys here, unique index + replace_schedule in the DB).
      const dk = push.dedupeKey !== null ? `${sub.id}|${push.type}|${push.dedupeKey}` : null;
      if (dk !== null && sentKeys.has(dk)) {
        await store.deletePush(push.id);
        r.droppedDuplicate++;
        continue;
      }
      // Sleep window (e.g. settings changed after scheduling): move to wake + 30m.
      if (inSleepWindow(now, win, sub.tzOffsetMinutes)) {
        await moveTo(push, adjustForSleep(now, win, sub.tzOffsetMinutes));
        r.deferredSleep++;
        continue;
      }
      // Daily cap: push to the start of the next local day (then sleep-adjust).
      if (!underCap(sub, push.type, now)) {
        const day = localDay(now, sub.tzOffsetMinutes);
        const nextMidnight = (day + 1) * 86_400_000 - sub.tzOffsetMinutes * 60_000;
        await moveTo(push, adjustForSleep(nextMidnight, win, sub.tzOffsetMinutes));
        r.deferredCap++;
        continue;
      }

      try {
        await withTimeout(sender.send(sub, JSON.stringify(buildPayload(push.type))), sendTimeout);
      } catch (e) {
        const code = (e as { statusCode?: number } | null)?.statusCode;
        if (code === 404 || code === 410) {
          await store.deleteSubscription(sub.id);
          dead.add(sub.id);
          r.subscriptionsDeleted++;
        } else {
          // transient (incl. timeout): give the row back, it is retried next minute until it goes stale
          await release(push);
          r.failedTransient++;
        }
        continue;
      }
      sendDone = true;

      const day = localDay(now, sub.tzOffsetMinutes);
      const counts: Partial<Record<PushType, number>> = countsForDay(sub, day);
      counts[push.type] = (counts[push.type] ?? 0) + 1;
      sub.sentDay = day; // keep the shared in-memory copy current for later items in this batch
      sub.sentToday = counts;
      if (dk !== null) sentKeys.add(dk);
      r.sent++;
      try {
        await store.markSent(push.id, now, sub.id, day, counts, token);
      } catch {
        await store.markSent(push.id, now, sub.id, day, counts, token); // one retry; if it throws the row stays claimed (not re-sent before the claim goes stale)
      }
    } catch {
      // Row-level failure (DB error, ...): never abort the batch. Not logged with endpoint/keys.
      r.errors++;
      if (!sendDone) await release(push);
    }
  }
  try {
    await store.purgeSent(now);
  } catch {
    r.errors++;
  }
  return r;
}
