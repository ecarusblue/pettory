export const PUSH_TYPES = ["hunger", "poop", "sick", "evolve"] as const;
export type PushType = (typeof PUSH_TYPES)[number];

export interface Subscription {
  id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  sleepStart: number | null; // local minutes since midnight
  sleepEnd: number | null;
  tzOffsetMinutes: number; // local = UTC + offset
  sentToday: Partial<Record<PushType, number>>;
  sentDay: number | null; // local day number the counts belong to
}

export interface ScheduledPush {
  id: number;
  subscriptionId: string;
  type: PushType;
  fireAt: number; // epoch ms
  dedupeKey: string | null;
  sentAt: number | null;
}

export interface ScheduleItem {
  type: PushType;
  fireAt: number;
  dedupeKey: string | null;
}

export interface SleepWindow {
  start: number | null;
  end: number | null;
}

/** web-push compatible: errors from send() carry statusCode (WebPushError does). */
export interface PushSender {
  send(
    sub: { endpoint: string; p256dh: string; auth: string },
    payload: string,
  ): Promise<void>;
}

export interface HttpRequest {
  method: string;
  body?: unknown;
  headers?: Record<string, string | undefined>;
  /** Client IP as seen by the HTTP glue (for rate limiting). */
  ip?: string;
}
export interface HttpResponse {
  status: number;
  body: unknown;
}
