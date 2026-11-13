import '../domain/domain.dart';

/// 한국어 문자열 모음 (다국어 확장 대비 외부화).
class Ko {
  Ko._();
  static const appName = '펫토리';

  // 온보딩
  static const onboardTitle = '어떤 알을 만날래요?';
  static const onboardPickEgg = '알을 골라 주세요';
  static const nameLabel = '이름';
  static const nameHint = '이름을 지어 주세요';
  static const defaultName = '몽이';
  static const start = '시작하기';
  static String eggName(Species s) => switch (s) {
    Species.eggA => '민트 알',
    Species.eggB => '살구 알',
    Species.eggC => '하늘 알',
  };
  static String eggSemantics(Species s, bool selected) =>
      '${eggName(s)}${selected ? ', 선택됨' : ''}';

  // 부화
  static const hatchTitle = '알이 흔들려요';
  static String hatchHint(int left) => '알을 톡톡 두드려 보세요 ($left번 남음)';
  static const hatchAuto = '두드리지 않아도 곧 부화해요';
  static const hatchedTitle = '짠! 태어났어요';
  static const skip = '건너뛰기';
  static const continueBtn = '만나러 가기';

  // 홈 게이지/상태
  static const hunger = '배고픔';
  static const happiness = '행복';
  static const fatigue = '피로';
  static String gaugeValue(String label, int v) => '$label $v/4';
  static String poopCount(int n) => n == 0 ? '똥 없음' : '똥 $n개';
  static const healthy = '건강';
  static const sickLabel = '아픔';
  static String stageName(Stage s) => switch (s) {
    Stage.egg => '알',
    Stage.baby => '아기',
    Stage.child => '어린이',
    Stage.teen => '청소년',
    Stage.adult => '성체',
  };
  static String tierName(Tier t) => switch (t) {
    Tier.excellent => '우수형',
    Tier.normal => '보통형',
    Tier.neglect => '방치형',
  };
  static const sleepingNow = '쿨쿨 자는 중';

  // 케어 버튼
  static const feed = '밥';
  static const snack = '간식';
  static const play = '놀아주기';
  static const cleanPoop = '똥 치우기';
  static const sleep = '재우기';
  static const wake = '깨우기';
  static const medicine = '약 주기';

  static String careError(CareError e) => switch (e) {
    CareError.asleep => '자는 중이에요. 먼저 깨워 주세요.',
    CareError.alreadySleeping => '이미 자고 있어요.',
    CareError.notAsleep => '자고 있지 않아요.',
    CareError.alreadyRested => '아직 졸리지 않대요.',
    CareError.dailyLimit => '오늘은 더 할 수 없어요.',
    CareError.notSick => '아프지 않아요.',
    CareError.left => '이미 떠난 친구예요.',
  };

  // 진화/떠남
  static String evolved(String name, Stage s) =>
      '$name이(가) ${stageName(s)}(으)로 자랐어요!';
  static String adultDecided(String name, Tier t) =>
      '$name의 성체 모습이 정해졌어요: ${tierName(t)}';
  static const ok = '확인';
  static String leftTitle(String name) => '$name이(가) 먼 여행을 떠났어요';
  static const leftBody = '함께한 시간은 추억 상자에 소중히 남았어요.\n새 알과 다시 시작할 수 있어요.';
  static const newEgg = '새 알 만나기';

  // 복귀 안내 (FR-9)
  static String awayTitle(String name) => '$name이(가) 기다렸어요';
  static const awayHeading = '자리를 비운 동안';
  static String awayElapsed(int minutes) => '${durationDH(minutes)} 만에 돌아왔어요';
  static const awayConfirm = '확인했어요';
  static const awayUnchanged = '그대로예요';
  static String awayStat(String label, int before, int after) =>
      '$label $before칸 → $after칸';
  static String awayDown(int n) => '$n칸 줄었어요';
  static String awayUp(int n) => '$n칸 늘었어요';
  static String awayPoopNow(int after) => '똥 $after개';
  static String awayPoopUp(int n) => '똥이 $n개 늘었어요';
  static String awayPoopDown(int n) => '똥이 $n개 줄었어요';
  static const awaySickStarted = '몸이 안 좋아졌어요. 약을 챙겨 주세요';
  static const awaySickStill = '아직 아파요. 약을 챙겨 주세요';
  static const awayHealthy = '건강해요';
  static const awayRecovered = '건강을 되찾았어요';
  static const awayEvolutionNote = '그사이 자라난 모습이 있어요. 확인하면 차례로 보여 드릴게요.';
  static String awayEvolutionCount(int n) => '성장 소식 $n건';
  static String awayLeftTitle(String name) => '$name이(가) 먼 여행을 떠났어요';
  static String awayLeftBody(String elapsed) =>
      '$elapsed 동안 만나지 못했어요. 아픈 채로 오래 기다리다 길을 나섰나 봐요. '
      '자책하지 않아도 괜찮아요. 함께한 시간은 추억 상자에 소중히 남았어요.';
  static String awayLastState(String stats) => '마지막 모습: $stats';
  static const awayLeftConfirm = '다음으로';

  // 홈 하단 내비
  static const navHome = '홈';
  static const navDex = '도감';
  static const navSettings = '설정';

  // 놀아주기 선택 / 미니게임
  static const playSheetTitle = '어떻게 놀아 줄까요?';
  static const playBasic = '기본 놀아주기';
  static const playBasicDesc = '행복 +1';
  static const playMinigame = '미니게임';
  static const playMinigameDesc = '반응속도 게임 · 행복 +0~2';
  static const playLimitReached =
      '오늘은 충분히 놀았어요. 하루 5번까지만 놀 수 있어요. 내일 또 놀아 주세요.';
  static String playsLeft(int left, int limit) => '오늘 남은 놀아주기 $left/$limit';

  static const mgTitle = '반응속도 게임';
  static String mgIntro(int rounds) =>
      '신호가 바뀌면 최대한 빨리 화면을 탭하세요. 모두 $rounds라운드예요. '
      '신호 전에 탭하면 그 라운드는 실패예요.';
  static const mgStart = '시작';
  static String mgRound(int n, int total) => '라운드 $n/$total';
  static const mgWaiting = '기다려요…';
  static const mgWaitingHint = '신호가 바뀔 때까지 탭하지 마세요';
  static const mgSignal = '지금 탭!';
  static const mgSignalAnnounce = '신호가 바뀌었어요. 지금 탭하세요!';
  static String mgHit(int ms) => '${ms}ms';
  static const mgEarly = '너무 일찍 탭했어요 (실패)';
  static const mgMissed = '놓쳤어요 (실패)';
  static const mgNextRound = '다음 라운드';
  static const mgShowResult = '결과 보기';
  static const mgResultTitle = '결과';
  static String mgAverage(int ms) => '평균 반응시간 ${ms}ms';
  static const mgAverageNone = '성공한 라운드가 없어요';
  static String mgRoundLine(int n, String text) => '$n라운드: $text';
  static String mgHappinessGain(int gain) => '행복 +$gain';
  static const mgGainNone = '이번엔 행복이 오르지 않았어요';
  static String mgCurrentHappiness(int v) => '현재 행복 $v/4';
  static const mgNotApplied = '결과를 적용하지 못했어요';
  static const mgBackHome = '홈으로';
  static const mgPad = '반응 영역';

  // 도감 / 추억
  static const dexTitle = '도감';
  static const dexTab = '도감';
  static const memoryTab = '추억';
  static String dexProgress(int n, int total) => '수집 $n/$total';
  static const dexLocked = '???';
  static const dexLockedSemantics = '아직 만나지 못한 모습';
  static String dexUnlockedSemantics(String label, String date) =>
      '$label, 획득 $date';
  static String dexFormLabel(Species sp, Stage st, [Tier? tier]) => tier == null
      ? '${eggName(sp)} ${stageName(st)}'
      : '${eggName(sp)} ${stageName(st)} ${tierName(tier)}';
  static String dexAcquired(String date) => '획득 $date';
  static const memoryEmpty = '아직 떠난 친구가 없어요.\n함께한 친구는 이곳에 소중히 남아요.';
  static String memorySubtitle(Species sp, Stage st) =>
      '${eggName(sp)} · 도달 단계 ${stageName(st)}';
  static String memoryTogether(String duration) => '함께한 기간 $duration';
  static String durationDH(int minutes) {
    final d = minutes ~/ 1440;
    final h = (minutes % 1440) ~/ 60;
    if (d > 0 && h > 0) return '$d일 $h시간';
    if (d > 0) return '$d일';
    if (h > 0) return '$h시간';
    return '1시간 미만';
  }

  // 설정
  static const settings = '설정';
  static const sleepStart = '취침 시작';
  static const sleepEnd = '기상';
  static const notify = '알림';
  static const sound = '사운드';
  static const resetData = '데이터 초기화';
  static const resetConfirmTitle = '정말 초기화할까요?';
  static const resetConfirmBody = '펫과 모든 기록이 삭제돼요. 되돌릴 수 없어요.';
  static const cancel = '취소';
  static const reset = '초기화';
  // 알림 권한 / 설치 안내
  static const pushAskTitle = '알림을 받아 볼까요?';
  static const pushAskBody =
      '친구가 출출하거나 불편할 때, 곧 자라날 때 한 번씩 조용히 알려 드려요. 하루에 몇 번 넘지 않아요.';
  static const pushAllow = '알림 받기';
  static const pushLater = '나중에';
  static const pushInstallTitle = '홈 화면에 추가해 주세요';
  static const pushInstallBody =
      'iPhone과 iPad에서는 홈 화면에 추가한 앱으로 열어야 알림을 받을 수 있어요.\n\n'
      '1. Safari 아래쪽의 공유 버튼을 눌러요.\n'
      '2. "홈 화면에 추가"를 골라요.\n'
      '3. 홈 화면의 펫토리 아이콘으로 다시 열어 주세요.';
  static const pushDeniedNote = '브라우저 설정에서 알림을 허용해 주세요.';
  static const devOptions = '개발자 옵션';
  static const speed = '시간 가속 배율';
  static const speedNote = '1 = 실시간, 2016 = 7일을 약 5분에';
}
