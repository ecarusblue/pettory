// Real Web Push sender. VAPID keys come from environment variables only.
// NOT exercised by the local tests (no real push service was contacted).
import webpush from "npm:web-push@3.6.7";
import type { PushSender } from "../../src/types.ts";

export function createWebPushSender(): PushSender {
  const pub = Deno.env.get("VAPID_PUBLIC_KEY");
  const priv = Deno.env.get("VAPID_PRIVATE_KEY");
  const subject = Deno.env.get("VAPID_SUBJECT"); // e.g. mailto:ops@your-domain
  if (!pub || !priv || !subject) throw new Error("VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY / VAPID_SUBJECT are required");
  webpush.setVapidDetails(subject, pub, priv);
  return {
    async send(sub, payload) {
      // WebPushError exposes .statusCode, which the dispatcher uses for 404/410 handling.
      await webpush.sendNotification(
        { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
        payload,
        { TTL: 3600, urgency: "normal", timeout: 8000 },
      );
    },
  };
}
