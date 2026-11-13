import type { PushType } from "./types.ts";

// Fixed copy. Gentle, non-pressuring tone (no guilt, urgency, or "your pet is
// suffering"). Never contains a character name: the server does not have one.
const TITLE = "펫토리";
const BODY: Record<PushType, string> = {
  hunger: "친구가 출출해할 때가 됐어요. 편할 때 한번 살펴봐 주세요.",
  poop: "주변이 조금 어질러졌어요. 여유 될 때 치워 주세요.",
  sick: "친구가 조금 불편해 보여요. 시간 될 때 확인해 주세요.",
  evolve: "친구에게 작은 변화가 곧 찾아올 것 같아요.",
};

export interface PushPayload {
  v: 1;
  type: PushType;
  title: string;
  body: string;
  tag: string; // lets the Service Worker collapse repeats of one type
}

export function buildPayload(type: PushType): PushPayload {
  return { v: 1, type, title: TITLE, body: BODY[type], tag: `petory-${type}` };
}
