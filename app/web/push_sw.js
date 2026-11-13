// 푸시 수신 전용 service worker. 페이로드 계약: server/API.md { v:1, type, title, body, tag }.
// 등록 방식: Flutter 기본 SW(flutter_service_worker.js, 스코프 ./)와 충돌하지 않도록
// lib/data/push_browser_web.dart 가 이 파일을 별도 스코프 ./push-scope/ 에 등록한다(importScripts 통합 대신 분리 선택:
// Flutter SW 가 빌드마다 바뀌고 deprecated 라 결합하지 않는 편이 안전하며, 푸시 수신에는 스코프 일치가 필요 없다).

// 서버 페이로드의 title/body 를 그대로 쓴다. 아래는 페이로드가 비었거나 깨졌을 때의 폴백이며
// 키는 서버 type 이름(hunger|poop|sick|evolve)이고 문구는 server/src/templates.ts 와 같다.
const TITLE = '펫토리';
const FALLBACK_BODY = {
  hunger: '친구가 출출해할 때가 됐어요. 편할 때 한번 살펴봐 주세요.',
  poop: '주변이 조금 어질러졌어요. 여유 될 때 치워 주세요.',
  sick: '친구가 조금 불편해 보여요. 시간 될 때 확인해 주세요.',
  evolve: '친구에게 작은 변화가 곧 찾아올 것 같아요.',
};
const DEFAULT_BODY = '친구가 기다리고 있어요.';

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = {};
  }
  if (!data || typeof data !== 'object') data = {};
  const type = typeof data.type === 'string' ? data.type : null;
  const title = typeof data.title === 'string' && data.title ? data.title : TITLE;
  const body =
    typeof data.body === 'string' && data.body ? data.body : FALLBACK_BODY[type] || DEFAULT_BODY;
  const tag = typeof data.tag === 'string' && data.tag ? data.tag : `petory-${type || 'general'}`;

  event.waitUntil(
    (async () => {
      // 앱이 포커스/가시 상태(열려 있는 창)면 표시 생략
      const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      if (wins.some((c) => c.focused || c.visibilityState === 'visible')) return;
      await self.registration.showNotification(title, {
        body,
        icon: new URL('icons/Icon-192.png', self.registration.scope.replace(/push-scope\/$/, '')).href,
        tag, // 같은 종류는 하나로 합침
        data: { type },
      });
    })(),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const appUrl = new URL('./', self.registration.scope.replace(/push-scope\/$/, '')).href;
  event.waitUntil(
    (async () => {
      const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const c of wins) {
        if ('focus' in c) return c.focus();
      }
      return self.clients.openWindow(appUrl);
    })(),
  );
});
