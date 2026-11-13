{{flutter_js}}
{{flutter_build_config}}

// 외부 CDN 차단: CanvasKit 은 앱과 같은 출처(canvaskit/)에서, 글리프 폴백 글꼴은 같은 출처의 존재하지 않는 경로로
// 돌린다(엔진 기본값은 Google 글꼴 서버라 이용자 IP 가 Google 로 전달됨). 폴백 요청은 404 로 끝나고
// 엔진이 몇 번 재시도 후 포기한다. 번들 글꼴(NotoSansKR, Jua)에 없는 문자(이모지 등)는 네모(tofu)로 보인다.
// Flutter 기본 서비스워커(flutter_service_worker.js)는 deprecated 라 등록하지 않고, 캐시는 app_sw.js 가 담당한다.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
    fontFallbackBaseUrl: new URL('no-external-fonts/', document.baseURI).href,
  },
});
