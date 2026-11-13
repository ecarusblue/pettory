// 푸시 경로(직렬화, HTTP 클라이언트, 컨트롤러 분기, 서버 시각 방어) 테스트.
// 실제 브라우저 Push/서비스 워커 동작은 여기서 검증하지 못한다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:petory/app/game_controller.dart';
import 'package:petory/data/game_save.dart';
import 'package:petory/data/pet_repository.dart';
import 'package:petory/data/push_browser.dart';
import 'package:petory/data/push_client.dart';
import 'package:petory/data/push_config.dart';
import 'package:petory/domain/domain.dart';
import 'package:petory/l10n/ko.dart';
import 'package:petory/ui/push_prompt.dart';
import 'package:petory/ui/settings_screen.dart';

final DateTime t0 = DateTime.utc(2026, 11, 14, 12);
int minutesOf(DateTime d) => d.millisecondsSinceEpoch ~/ 60000;

const sub = PushSubscriptionInfo(
  endpoint: 'https://fcm.googleapis.com/fcm/send/abc',
  p256dh: 'BPxxxxxxxxxxxxxxxx',
  auth: 'authauthauth',
);

class FakeBrowser implements PushBrowser {
  FakeBrowser({
    this.supported = true,
    this.isIos = false,
    this.isStandalone = false,
    this.permission = PushPermission.defaultState,
    this.grantOnRequest = true,
  });
  @override
  bool supported;
  @override
  bool isIos;
  @override
  bool isStandalone;
  @override
  PushPermission permission;
  bool grantOnRequest;
  int requests = 0;
  int subscribes = 0;
  int unsubscribes = 0;
  String? usedVapid;

  @override
  Future<PushPermission> requestPermission() async {
    requests++;
    permission = grantOnRequest
        ? PushPermission.granted
        : PushPermission.denied;
    return permission;
  }

  @override
  Future<PushSubscriptionInfo?> subscribe(String vapidPublicKey) async {
    subscribes++;
    usedVapid = vapidPublicKey;
    if (permission != PushPermission.granted) return null;
    // 구독 해제 뒤 새로 구독하면 새 endpoint
    if (unsubscribes == 0) return sub;
    return PushSubscriptionInfo(
      endpoint: 'https://fcm.googleapis.com/fcm/send/e100',
      p256dh: sub.p256dh,
      auth: sub.auth,
    );
  }

  @override
  Future<void> unsubscribe() async => unsubscribes++;
}

Future<GameController> boot(
  FakePushScheduleClient push,
  FakeBrowser browser, {
  bool enabled = true,
  DateTime? now,
  bool seed = true,
  InMemoryPetRepository? repo,
}) async {
  repo ??= InMemoryPetRepository();
  final start = now ?? t0;
  if (seed) {
    final ms = start.millisecondsSinceEpoch;
    await repo.save(
      GameSave(
        pet: PetState.newborn(
          name: '비밀이름',
          species: Species.eggA,
          birthAt: minutesOf(start),
        ),
        clock: ClockAnchor(realMs: ms, virtualMs: ms, speed: 1),
      ),
    );
  }
  final c = GameController(
    repo: repo,
    push: push,
    browser: browser,
    pushEnabled: enabled,
    vapidPublicKey: 'VAPIDKEY',
    now: () => start,
  );
  await c.init();
  await Future<void>.delayed(Duration.zero);
  return c;
}

void main() {
  const serverTypes = {'hunger', 'poop', 'sick', 'evolve'};
  final keyRe = RegExp(r'^[A-Za-z0-9:_-]{1,32}$');
  final offsetRe = RegExp(r'(Z|[+-]\d\d:?\d\d)$');

  group('직렬화 (server/API.md)', () {
    final p = PetState.newborn(
      name: '비밀이름',
      species: Species.eggA,
      birthAt: 29_000_000,
    );
    final cfg = const Settings(sleepStart: 0, sleepEnd: 0);

    test(
      '알림 항목: type 은 서버 값, fireAt 은 오프셋 포함 ISO, sick/evolve 는 dedupeKey',
      () {
        final list = nextNotifications(p, cfg, p.birthAt);
        expect(
          list.map((e) => e.type),
          containsAll([NotifyType.sick, NotifyType.evolve]),
        );
        expect(list.length, lessThanOrEqualTo(16));
        for (final e in list) {
          final j = e.toJson();
          expect(serverTypes, contains(j['type']));
          expect(j['fireAt'] as String, matches(offsetRe));
          expect(
            DateTime.parse(j['fireAt'] as String).millisecondsSinceEpoch,
            e.fireAt * 60000,
          );
          if (e.type == NotifyType.sick || e.type == NotifyType.evolve) {
            expect(j['dedupeKey'], matches(keyRe), reason: e.type.name);
          }
          if (j.containsKey('dedupeKey')) {
            expect(j['dedupeKey'], matches(keyRe));
          }
          expect(jsonEncode(j).contains('비밀이름'), isFalse);
        }
      },
    );

    test('dedupeKey 는 같은 상태에서 다시 계산해도 같고, 단계/펫이 다르면 다르다', () {
      final a = nextNotifications(p, cfg, p.birthAt);
      final b = nextNotifications(p, cfg, p.birthAt + 5);
      String key(List<Scheduled> l, NotifyType t) =>
          l.firstWhere((e) => e.type == t).dedupeKey!;
      expect(key(a, NotifyType.sick), key(b, NotifyType.sick));
      expect(key(a, NotifyType.evolve), key(b, NotifyType.evolve));
      final other = PetState.newborn(
        name: 'x',
        species: Species.eggA,
        birthAt: 29_100_000,
      );
      final c = nextNotifications(other, cfg, other.birthAt);
      expect(key(c, NotifyType.evolve), isNot(key(a, NotifyType.evolve)));
      expect(key(a, NotifyType.evolve), startsWith('stage:2:'));
      expect(key(a, NotifyType.sick), startsWith('sick:'));
    });

    test('hunger/poop 은 dedupeKey 생략', () {
      final list = nextNotifications(p, cfg, p.birthAt);
      for (final e in list.where(
        (e) => e.type == NotifyType.hunger || e.type == NotifyType.poop,
      )) {
        expect(e.toJson().containsKey('dedupeKey'), isFalse);
      }
    });

    test('NotifyType 이름이 서버 type 과 일치', () {
      expect(NotifyType.values.map((e) => e.name).toSet(), serverTypes);
    });
  });

  group('HttpPushScheduleClient', () {
    late List<http.Request> reqs;
    late HttpPushScheduleClient client;
    late int putStatus;
    late int timeStatus;

    setUp(() {
      reqs = [];
      putStatus = 200;
      timeStatus = 200;
      client = HttpPushScheduleClient(
        baseUrl: 'https://x.test/functions/v1/',
        client: MockClient((r) async {
          reqs.add(r);
          if (r.method == 'GET') {
            return http.Response(
              jsonEncode({
                'now': '2026-11-13T12:34:56.789Z',
                'epochMs': 1794573296789,
              }),
              timeStatus,
            );
          }
          if (r.method == 'PUT' && putStatus != 200) {
            return http.Response(
              jsonEncode({'error': 'subscription_not_found'}),
              putStatus,
            );
          }
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );
    });

    test('POST /subscribe: endpoint/keys/sleep/tz, 이름 없음', () async {
      await client.subscribe(sub, const Settings());
      final r = reqs.single;
      expect(r.method, 'POST');
      expect(r.url.toString(), 'https://x.test/functions/v1/subscribe');
      expect(r.headers['content-type'], contains('application/json'));
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      expect(b['endpoint'], sub.endpoint);
      expect(b['keys'], {'p256dh': sub.p256dh, 'auth': sub.auth});
      expect(b['sleepStart'], 23 * 60);
      expect(b['sleepEnd'], 7 * 60);
      expect(b['tzOffsetMinutes'], 540);
      expect(b.keys.toSet(), {
        'endpoint',
        'keys',
        'sleepStart',
        'sleepEnd',
        'tzOffsetMinutes',
      });
    });

    test('PUT /schedule: endpoint+auth+items', () async {
      await client.replaceSchedule(sub, [
        const Scheduled(
          NotifyType.sick,
          29_000_000,
          dedupeKey: 'sick:29000000',
        ),
      ], settings: const Settings());
      final r = reqs.single;
      expect(r.method, 'PUT');
      expect(r.url.path, '/functions/v1/schedule');
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      expect(b['endpoint'], sub.endpoint);
      expect(b['auth'], sub.auth);
      final item = (b['items'] as List).single as Map<String, dynamic>;
      expect(item['type'], 'sick');
      expect(item['fireAt'] as String, matches(offsetRe));
      expect(item['dedupeKey'], 'sick:29000000');
    });

    test('빈 목록도 PUT (전체 삭제)', () async {
      await client.replaceSchedule(sub, const []);
      expect((jsonDecode(reqs.single.body) as Map)['items'], isEmpty);
    });

    test('PUT 이 404 면 /subscribe 로 재등록 후 한 번 재시도', () async {
      putStatus = 404;
      await expectLater(
        client.replaceSchedule(sub, const [], settings: const Settings()),
        throwsA(isA<PushHttpException>()),
      );
      expect(reqs.map((r) => '${r.method} ${r.url.path}'), [
        'PUT /functions/v1/schedule',
        'POST /functions/v1/subscribe',
        'PUT /functions/v1/schedule',
      ]);
    });

    test('DELETE /subscribe: endpoint+auth 본문', () async {
      await client.unsubscribe(sub);
      final r = reqs.single;
      expect(r.method, 'DELETE');
      expect(r.url.path, '/functions/v1/subscribe');
      expect(jsonDecode(r.body), {'endpoint': sub.endpoint, 'auth': sub.auth});
    });

    test('GET /time: epochMs 파싱, 실패/예외는 null', () async {
      expect(await client.serverTimeMs(), 1794573296789);
      expect(reqs.single.url.path, '/functions/v1/time');
      timeStatus = 500;
      expect(await client.serverTimeMs(), isNull);
      final broken = HttpPushScheduleClient(
        baseUrl: 'https://x.test',
        client: MockClient((r) async => throw const SocketException('offline')),
      );
      expect(await broken.serverTimeMs(), isNull);
    });

    test('서버 오류 응답은 PushHttpException', () async {
      final c = HttpPushScheduleClient(
        baseUrl: 'https://x.test',
        client: MockClient(
          (r) async => http.Response('{"error":"invalid_request"}', 400),
        ),
      );
      await expectLater(
        c.subscribe(sub, const Settings()),
        throwsA(
          isA<PushHttpException>()
              .having((e) => e.statusCode, 'status', 400)
              .having((e) => e.error, 'error', 'invalid_request'),
        ),
      );
    });
  });

  group('PushConfig', () {
    test('둘 다 있어야 enabled', () {
      expect(const PushConfig().enabled, isFalse);
      expect(const PushConfig(baseUrl: 'https://a').enabled, isFalse);
      expect(const PushConfig(vapidPublicKey: 'k').enabled, isFalse);
      expect(
        const PushConfig(baseUrl: 'https://a', vapidPublicKey: 'k').enabled,
        isTrue,
      );
    });
  });

  group('컨트롤러: 권한 분기와 구독', () {
    test('설정이 없으면 disabled, 구독/전송 호출 없음', () async {
      final push = FakePushScheduleClient();
      final c = await boot(
        push,
        FakeBrowser(permission: PushPermission.granted),
        enabled: false,
      );
      expect(c.pushStatus, PushStatus.disabled);
      c.care(CareAction.feed);
      await Future<void>.delayed(Duration.zero);
      expect(push.subscribeCalls, isEmpty);
      expect(push.calls, isEmpty);
      c.dispose();
    });

    test('iOS + 홈 화면 미설치 -> needsInstall, 권한 요청 안 함', () async {
      final b = FakeBrowser(supported: false, isIos: true, isStandalone: false);
      final c = await boot(FakePushScheduleClient(), b, seed: false);
      expect(c.pushStatus, PushStatus.needsInstall);
      expect(await c.enablePush(), PushStatus.needsInstall);
      expect(b.requests, 0);
      c.dispose();
    });

    test('iOS standalone 은 권한 요청 가능', () async {
      final b = FakeBrowser(isIos: true, isStandalone: true);
      final c = await boot(FakePushScheduleClient(), b, seed: false);
      expect(c.pushStatus, PushStatus.canAsk);
      c.dispose();
    });

    test('canAsk -> enablePush: 권한 요청, 구독, POST /subscribe, PUT 예약', () async {
      final push = FakePushScheduleClient();
      final b = FakeBrowser();
      final c = await boot(push, b);
      expect(c.pushStatus, PushStatus.canAsk);
      expect(push.subscribeCalls, isEmpty);
      expect(await c.enablePush(), PushStatus.active);
      expect(b.requests, 1);
      expect(b.usedVapid, 'VAPIDKEY');
      expect(push.subscribeCalls.single.endpoint, sub.endpoint);
      expect(push.calls, isNotEmpty);
      c.dispose();
    });

    test('거부하면 구독하지 않고 denied', () async {
      final push = FakePushScheduleClient();
      final b = FakeBrowser(grantOnRequest: false);
      final c = await boot(push, b);
      expect(await c.enablePush(), PushStatus.denied);
      expect(push.subscribeCalls, isEmpty);
      c.dispose();
    });

    test('앱 실행마다 /subscribe 재호출 (이미 허용된 경우)', () async {
      final push = FakePushScheduleClient();
      final b = FakeBrowser(permission: PushPermission.granted);
      final repo = InMemoryPetRepository();
      final c1 = await boot(push, b, repo: repo);
      expect(push.subscribeCalls, hasLength(1));
      c1.dispose();
      final c2 = await boot(push, b, repo: repo, seed: false);
      expect(push.subscribeCalls, hasLength(2));
      c2.dispose();
    });

    test('알림 토글 끄기 -> DELETE + 브라우저 구독 해제, 이후 PUT 없음, 다시 켜면 재등록', () async {
      final push = FakePushScheduleClient();
      final b = FakeBrowser(permission: PushPermission.granted);
      final c = await boot(push, b);
      final putsBefore = push.calls.length;
      expect(await c.setNotifyEnabled(false), PushStatus.active);
      expect(c.settings.notifyEnabled, isFalse);
      expect(push.unsubscribeCalls, hasLength(1));
      expect(b.unsubscribes, 1);
      c.care(CareAction.feed);
      await Future<void>.delayed(Duration.zero);
      expect(push.calls.length, putsBefore);
      await c.setNotifyEnabled(true);
      expect(c.settings.notifyEnabled, isTrue);
      expect(push.subscribeCalls, hasLength(2));
      c.dispose();
    });

    test('알림 끈 상태로 시작하면 /subscribe 를 부르지 않는다', () async {
      final push = FakePushScheduleClient();
      final repo = InMemoryPetRepository();
      final ms = t0.millisecondsSinceEpoch;
      await repo.save(
        GameSave(
          pet: PetState.newborn(
            name: 'a',
            species: Species.eggA,
            birthAt: minutesOf(t0),
          ),
          settings: const Settings(notifyEnabled: false),
          clock: ClockAnchor(realMs: ms, virtualMs: ms, speed: 1),
        ),
      );
      final c = await boot(
        push,
        FakeBrowser(permission: PushPermission.granted),
        repo: repo,
        seed: false,
      );
      expect(push.subscribeCalls, isEmpty);
      c.dispose();
    });

    test('설치 필요/거부 상태에서 토글 켜기는 설정을 바꾸지 않고 상태를 돌려준다', () async {
      final repo = InMemoryPetRepository();
      final ms = t0.millisecondsSinceEpoch;
      await repo.save(
        GameSave(
          pet: PetState.newborn(
            name: 'a',
            species: Species.eggA,
            birthAt: minutesOf(t0),
          ),
          settings: const Settings(notifyEnabled: false),
          clock: ClockAnchor(realMs: ms, virtualMs: ms, speed: 1),
        ),
      );
      final c = await boot(
        FakePushScheduleClient(),
        FakeBrowser(supported: false, isIos: true),
        repo: repo,
        seed: false,
      );
      expect(await c.setNotifyEnabled(true), PushStatus.needsInstall);
      expect(c.settings.notifyEnabled, isFalse);
      c.dispose();
    });

    test('초기화(resetAll)는 서버 구독을 DELETE', () async {
      final push = FakePushScheduleClient();
      final c = await boot(
        push,
        FakeBrowser(permission: PushPermission.granted),
      );
      await c.resetAll();
      expect(push.unsubscribeCalls, hasLength(1));
      c.dispose();
    });

    test(
      '409 subscription_conflict: 브라우저 구독 해제 후 새 구독(새 endpoint)으로 재시도',
      () async {
        final push = FakePushScheduleClient()
          ..conflictOnEndpoints.add(sub.endpoint);
        final b = FakeBrowser(permission: PushPermission.granted);
        final c = await boot(push, b);
        expect(b.unsubscribes, 1);
        expect(b.subscribes, 2);
        expect(push.subscribeCalls.last.endpoint, endsWith('e100'));
        expect(c.pushSubscription!.endpoint, endsWith('e100'));
        expect(push.calls, isNotEmpty);
        c.dispose();
      },
    );

    test('429 rate_limited: 앱은 계속 동작하고 5분 백오프 후 재시도', () async {
      final push = FakePushScheduleClient()..failStatus = 429;
      final c = await boot(
        push,
        FakeBrowser(permission: PushPermission.granted),
      );
      push.failStatus = null;
      for (var i = 0; i < 299; i++) {
        c.refresh();
      }
      await Future<void>.delayed(Duration.zero);
      expect(push.calls, isEmpty); // 백오프 중
      for (var i = 0; i < 61; i++) {
        c.refresh();
      }
      await Future<void>.delayed(Duration.zero);
      expect(push.calls, isNotEmpty);
      c.dispose();
    });

    test('전송 실패는 앱을 멈추지 않고, 다음 sync 에서 복구', () async {
      final push = FakePushScheduleClient()..failSchedule = true;
      final c = await boot(
        push,
        FakeBrowser(permission: PushPermission.granted),
      );
      c.care(CareAction.feed);
      await Future<void>.delayed(Duration.zero);
      expect(push.calls, isEmpty);
      push.failSchedule = false;
      await c.syncSchedule();
      expect(push.calls, isNotEmpty);
      c.dispose();
    });

    test('서버로 가는 모든 본문에 캐릭터 이름이 없다', () async {
      final push = FakePushScheduleClient();
      final c = await boot(
        push,
        FakeBrowser(permission: PushPermission.granted),
      );
      c.care(CareAction.feed);
      await c.syncSchedule();
      final bodies = [
        for (final s in push.subscribeCalls)
          jsonEncode(HttpPushScheduleClient.subscribeBody(s, c.settings)),
        for (final call in push.calls)
          jsonEncode(
            HttpPushScheduleClient.scheduleBody(
              call.subscription,
              call.schedule,
              c.settings,
            ),
          ),
      ];
      expect(bodies, isNotEmpty);
      expect(bodies.join().contains('비밀이름'), isFalse);
      c.dispose();
    });
  });

  group('미래 시계 방어 (GET /time, checkClock)', () {
    Future<(GameController, DateTime Function(), void Function(Duration))>
    start(FakePushScheduleClient push) async {
      var now = t0;
      final repo = InMemoryPetRepository();
      final ms = t0.millisecondsSinceEpoch;
      await repo.save(
        GameSave(
          pet: PetState.newborn(
            name: 'a',
            species: Species.eggA,
            birthAt: minutesOf(t0),
          ),
          clock: ClockAnchor(realMs: ms, virtualMs: ms, speed: 1),
        ),
      );
      final c = GameController(
        repo: repo,
        push: push,
        pushEnabled: true,
        vapidPublicKey: 'k',
        now: () => now,
      );
      await c.init();
      return (c, () => now, (Duration d) => now = now.add(d));
    }

    test('시작 시 이미 미래로 돌려져 있으면 서버 시각 기준', () async {
      final push = FakePushScheduleClient()
        ..serverTime = () => t0.millisecondsSinceEpoch;
      final repo = InMemoryPetRepository();
      final ms = t0.millisecondsSinceEpoch;
      await repo.save(
        GameSave(
          pet: PetState.newborn(
            name: 'a',
            species: Species.eggA,
            birthAt: minutesOf(t0),
          ),
          clock: ClockAnchor(realMs: ms, virtualMs: ms, speed: 1),
        ),
      );
      final c = GameController(
        repo: repo,
        push: push,
        pushEnabled: true,
        vapidPublicKey: 'k',
        now: () => t0.add(const Duration(days: 10)),
      );
      await c.init();
      expect(c.pet!.left, isFalse);
      expect((c.nowMinute - minutesOf(t0)).abs(), lessThan(2));
      c.dispose();
    });

    test('편차 60분 이내는 기기 시각 그대로', () async {
      final push = FakePushScheduleClient()
        ..serverTime = () => t0.millisecondsSinceEpoch;
      final (c, _, adv) = await start(push);
      adv(const Duration(minutes: 59));
      expect(c.nowMinute, minutesOf(t0) + 59);
      adv(const Duration(minutes: 2)); // 61분 초과
      expect(c.nowMinute, lessThan(minutesOf(t0) + 5));
      c.dispose();
    });

    test('서버 시각을 못 받으면(오프라인) 기존 동작', () async {
      final push = FakePushScheduleClient(); // serverTime null
      final (c, _, adv) = await start(push);
      adv(const Duration(days: 2));
      expect(c.nowMinute, minutesOf(t0) + 2 * 1440);
      c.dispose();
    });

    test('푸시 비활성 빌드는 서버 시각을 조회하지 않는다', () async {
      var asked = false;
      final push = FakePushScheduleClient()
        ..serverTime = () {
          asked = true;
          return t0.millisecondsSinceEpoch;
        };
      final c = GameController(
        repo: InMemoryPetRepository(),
        push: push,
        now: () => t0,
      );
      await c.init();
      expect(asked, isFalse);
      c.dispose();
    });
  });

  group('UI', () {
    testWidgets('설정: 개발자 옵션은 showDevOptions=false(릴리스)에서 숨김', (tester) async {
      final c = await tester.runAsync(
        () => boot(
          FakePushScheduleClient(),
          FakeBrowser(),
          enabled: false,
          seed: false,
        ),
      ) as GameController;
      for (final show in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(controller: c, showDevOptions: show),
          ),
        );
        await tester.pump();
        expect(find.text(Ko.devOptions), show ? findsOneWidget : findsNothing);
      }
      c.dispose();
    });

    testWidgets('iOS 미설치: 설치 안내 다이얼로그 (권한 요청 없음)', (tester) async {
      final b = FakeBrowser(supported: false, isIos: true);
      final c = await tester.runAsync(
        () => boot(FakePushScheduleClient(), b, seed: false),
      ) as GameController;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showPushPrompt(ctx, c),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text(Ko.pushInstallTitle), findsOneWidget);
      expect(b.requests, 0);
      c.dispose();
    });

    testWidgets('권한 요청 가능: 안내 후 허용 탭에서만 requestPermission', (tester) async {
      final b = FakeBrowser();
      final push = FakePushScheduleClient();
      final c = await tester.runAsync(() => boot(push, b)) as GameController;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showPushPrompt(ctx, c),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text(Ko.pushAskTitle), findsOneWidget);
      expect(b.requests, 0);
      await tester.runAsync(() async {
        await tester.tap(find.text(Ko.pushAllow));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(b.requests, 1);
      expect(push.subscribeCalls, hasLength(1));
      c.dispose();
    });

    testWidgets('나중에를 누르면 요청하지 않는다 / 비활성 빌드는 아무것도 안 보임', (tester) async {
      final b = FakeBrowser();
      final c = await tester.runAsync(
        () => boot(FakePushScheduleClient(), b),
      ) as GameController;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showPushPrompt(ctx, c),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Ko.pushLater));
      await tester.pumpAndSettle();
      expect(b.requests, 0);
      c.dispose();

      final off = await tester.runAsync(
        () => boot(FakePushScheduleClient(), FakeBrowser(), enabled: false),
      ) as GameController;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showPushPrompt(ctx, off),
              child: const Text('go2'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go2'));
      await tester.pumpAndSettle();
      expect(find.text(Ko.pushAskTitle), findsNothing);
      expect(find.text(Ko.pushInstallTitle), findsNothing);
      off.dispose();
    });
  });

  group('web 자산', () {
    final sw = File('web/push_sw.js').readAsStringSync();
    test('push_sw.js 는 서버 type 키 폴백과 페이로드 title/body/tag 사용, 보이는 창이면 생략', () {
      for (final t in serverTypes) {
        expect(RegExp('\\b$t\\s*:').hasMatch(sw), isTrue, reason: t);
      }
      expect(sw.contains('hungry'), isFalse);
      expect(
        sw.contains('data.title') &&
            sw.contains('data.body') &&
            sw.contains('data.tag'),
        isTrue,
      );
      expect(sw.contains("visibilityState === 'visible'"), isTrue);
      expect(sw.contains('notificationclick'), isTrue);
    });

    test('등록 코드는 별도 스코프로 push_sw.js 를 등록', () {
      final web = File('lib/data/push_browser_web.dart').readAsStringSync();
      expect(
        web.contains("'push_sw.js'") && web.contains('push-scope/'),
        isTrue,
      );
    });
  });
}
