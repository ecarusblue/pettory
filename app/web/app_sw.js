// 앱 셸 오프라인 캐시 서비스워커 (스코프 ./, push_sw.js 는 ./push-scope/ 에서 따로 동작하므로 충돌 없음).
// 갱신 전략: 설치 때 precache_manifest.json(flutter build web --web-content-hash 산출물)의 해시로 캐시 이름을 만들고,
// 새 버전은 기본적으로 대기 → 열린 탭이 모두 닫힌 다음 실행에 교체되며 그때 구버전 캐시를 지운다.
// 사용자가 '다시 시작'을 누르면 페이지가 SKIP_WAITING 메시지를 보내 즉시 교체한다(app 의 업데이트 안내).
'use strict';

const PREFIX = 'petory-shell-';
const META = 'petory-meta';
const CURRENT = 'current-cache'; // 활성 SW 가 쓰는 캐시 이름
const PENDING = 'pending-cache'; // 설치 끝난 대기 SW 의 캐시 이름(활성화될 때 CURRENT 가 됨)
// 앱 셸로 미리 받지 않는 것: 자기 자신·푸시 SW·deprecated 스텁·버전 파일·디버그 심볼, canvaskit 은 아래에서 따로 고름.
const SKIP = /^(app_sw\.js|push_sw\.js|flutter_service_worker\.js|version\.json|precache_manifest\.json)$|\.symbols$|\.map$/;
// 브라우저가 쓰는 CanvasKit 변종만 미리 받는다(엔진이 chromium 변종을 고르는 조건과 동일). 나머지는 쓰일 때 런타임 캐시.
const CHROMIUM_CK = typeof Intl.v8BreakIterator !== 'undefined' && typeof Intl.Segmenter !== 'undefined';

function wanted(url) {
  if (SKIP.test(url)) return false;
  if (url.startsWith('canvaskit/')) {
    const m = /^canvaskit\/(chromium\/)?canvaskit\.(js|wasm)$/.exec(url);
    return !!m && !!m[1] === CHROMIUM_CK;
  }
  return true;
}

function hashString(s) {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0;
  return h.toString(36);
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      // 매니페스트가 없으면(예: flutter run 개발 서버) 설치 실패 → 캐시하지 않음.
      const res = await fetch('precache_manifest.json', { cache: 'no-cache' });
      if (!res.ok) throw new Error('precache_manifest.json ' + res.status);
      const list = (await res.json()).entries.filter((e) => wanted(e.url));
      const name = PREFIX + hashString(list.map((e) => e.url + ':' + e.hash).sort().join('|'));
      const meta = await caches.open(META);
      if (await caches.has(name)) {
        await meta.put(PENDING, new Response(name));
        // 지금 쓰는 캐시와 내용이 같다면(스크립트 URL 만 바뀐 경우) 기다릴 이유가 없다: 바로 교체해 '새 버전' 안내가 뜨지 않게 한다.
        if ((await readMeta(CURRENT)) === name) await self.skipWaiting();
        return;
      }
      const cache = await caches.open(name);
      try {
        // 하나라도 실패하면 전체 실패(반쪽 캐시 방지). 'reload' 로 HTTP 캐시를 우회해 새 파일을 받는다.
        await Promise.all(list.map((e) => cache.add(new Request(e.url, { cache: 'reload' }))));
      } catch (err) {
        await caches.delete(name);
        throw err;
      }
      await meta.put(PENDING, new Response(name));
    })(),
  );
});

async function readMeta(key) {
  const r = await (await caches.open(META)).match(key);
  return r ? r.text() : null;
}

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const name = (await readMeta(PENDING)) || (await readMeta(CURRENT));
      if (name) await (await caches.open(META)).put(CURRENT, new Response(name));
      for (const k of await caches.keys()) {
        if (k.startsWith(PREFIX) && k !== name) await caches.delete(k);
      }
      await self.clients.claim();
    })(),
  );
});

// 페이지의 '새 버전으로 다시 시작' 요청: 대기 중인 이 워커를 바로 활성화한다.
self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  // 푸시 SW, 서버 API 호출, 범위 요청(Range)은 건드리지 않는다.
  if (/\/(push_sw\.js|app_sw\.js)$/.test(url.pathname) || url.pathname.includes('/push-scope/') || req.headers.has('range')) return;
  // 버전 확인용 파일(precache_manifest.json 등)은 항상 네트워크로: 캐시하면 새 버전을 영영 못 알아본다.
  if (SKIP.test(url.pathname.split('/').pop())) return;
  event.respondWith(
    (async () => {
      const name = await readMeta(CURRENT);
      const cache = name ? await caches.open(name) : null;
      const key = req.mode === 'navigate' ? new URL('index.html', self.registration.scope).href : req;
      const hit = cache && (await cache.match(key));
      if (hit) return hit;
      try {
        const res = await fetch(req);
        // 미리 받지 않은 같은 출처 정적 파일(다른 CanvasKit 변종 등)은 처음 쓰일 때 캐시.
        if (cache && res.ok && res.type === 'basic' && req.mode !== 'navigate') cache.put(req, res.clone());
        return res;
      } catch (err) {
        if (req.mode === 'navigate' && cache) {
          const shell = await cache.match(key);
          if (shell) return shell;
        }
        throw err;
      }
    })(),
  );
});
