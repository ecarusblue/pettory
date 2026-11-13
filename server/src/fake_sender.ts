import type { PushSender } from "./types.ts";

/** Test double. `failWith[endpoint] = 410` makes that endpoint throw like web-push does. */
export class FakeSender implements PushSender {
  sent: Array<{ endpoint: string; payload: string }> = [];
  failWith = new Map<string, number>();
  async send(sub: { endpoint: string }, payload: string) {
    const code = this.failWith.get(sub.endpoint);
    if (code !== undefined) throw Object.assign(new Error(`push failed ${code}`), { statusCode: code });
    this.sent.push({ endpoint: sub.endpoint, payload });
  }
}
