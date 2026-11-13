# petory

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## 웹 빌드·오프라인 캐시

```
flutter build web --release --no-web-resources-cdn --web-content-hash
```

- `--no-web-resources-cdn`: CanvasKit 을 `build/web/canvaskit/` 로 자체 포함(gstatic 호출 없음).
- `--web-content-hash`: 파일명에 해시를 넣고 `precache_manifest.json` 을 만든다. `web/app_sw.js` 가 이 매니페스트를 읽어
  앱 셸(index, main.dart.*.js, 글꼴, 아이콘, manifest, CanvasKit 1종)을 캐시하므로 별도 목록 생성 스크립트는 필요 없다.
- 글꼴(Noto Sans KR, Jua)은 `assets/fonts/` 에 번들(SIL OFL, 라이선스 `OFL-*.txt` 동봉).
- 배포 서버는 `index.html`, `flutter_bootstrap.js`, `app_sw.js`, `precache_manifest.json` 을 `Cache-Control: no-cache` 로,
  해시가 붙은 파일은 장기 캐시로 서빙할 것. `canvaskit/**` 은 해시가 없으므로 immutable 금지.
- 새 버전은 다음 실행(열린 탭을 모두 닫은 뒤)에 적용된다. `flutter run` 개발 서버에는 매니페스트가 없어 SW 설치가 실패하며 캐시되지 않는다.
