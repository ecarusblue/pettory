import 'package:material_ui/material_ui.dart';

import '../app/game_controller.dart';
import '../domain/domain.dart';
import '../l10n/ko.dart';
import 'pet_painter.dart';
import 'theme.dart';

/// 도감에 담기는 성장 단계(알 단계는 부화 시 baby 로 기록되므로 제외).
const dexStages = [Stage.baby, Stage.child, Stage.teen];

/// 도감 전체 형태 수: 알 종류 × (단계 3 + 성체 티어 3).
int get dexTotal =>
    Species.values.length * (dexStages.length + Tier.values.length);

/// 컨트롤러가 저장하는 도감 키 (game_controller 의 _unlock 과 같은 형식).
String dexKey(Species sp, Stage st, [Tier? tier]) => tier == null
    ? '${sp.name}_${st.name}'
    : '${sp.name}_${st.name}_${tier.name}';

String formatDate(int epochMinutes, int tzOffsetMinutes) {
  final d = DateTime.fromMillisecondsSinceEpoch(
    (epochMinutes + tzOffsetMinutes) * 60000,
    isUtc: true,
  );
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}.${two(d.month)}.${two(d.day)}';
}

/// 도감 + 추억 화면 (FR-7).
class DexScreen extends StatelessWidget {
  const DexScreen({super.key, required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Semantics(header: true, child: const Text(Ko.dexTitle)),
          backgroundColor: PetoryColors.bg,
          foregroundColor: PetoryColors.text,
          bottom: const TabBar(
            labelColor: PetoryColors.text,
            indicatorColor: PetoryColors.accent,
            tabs: [
              Tab(text: Ko.dexTab),
              Tab(text: Ko.memoryTab),
            ],
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => TabBarView(
                  children: [
                    _DexTab(controller: controller),
                    _MemoryTab(controller: controller),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DexTab extends StatelessWidget {
  const _DexTab({required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tz = controller.settings.tzOffsetMinutes;
    final unlocked = {for (final d in controller.data.dex) d.key: d.unlockedAt};
    var count = 0;
    for (final sp in Species.values) {
      for (final st in dexStages) {
        if (unlocked.containsKey(dexKey(sp, st))) count++;
      }
      for (final tier in Tier.values) {
        if (unlocked.containsKey(dexKey(sp, Stage.adult, tier))) count++;
      }
    }
    final total = dexTotal;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(
          label: Ko.dexProgress(count, total),
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Ko.dexProgress(count, total), style: t.titleMedium),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : count / total,
                  minHeight: 12,
                  color: PetoryColors.accent,
                  backgroundColor: PetoryColors.empty,
                ),
              ),
            ],
          ),
        ),
        for (final sp in Species.values) ...[
          const SizedBox(height: 20),
          Semantics(
            header: true,
            child: Text(Ko.eggName(sp), style: t.titleMedium),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final st in dexStages)
                _DexCell(
                  species: sp,
                  stage: st,
                  unlockedAt: unlocked[dexKey(sp, st)],
                  tz: tz,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final tier in Tier.values)
                _DexCell(
                  species: sp,
                  stage: Stage.adult,
                  tier: tier,
                  unlockedAt: unlocked[dexKey(sp, Stage.adult, tier)],
                  tz: tz,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DexCell extends StatelessWidget {
  const _DexCell({
    required this.species,
    required this.stage,
    required this.unlockedAt,
    required this.tz,
    this.tier,
  });
  final Species species;
  final Stage stage;
  final Tier? tier;
  final int? unlockedAt;
  final int tz;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isUnlocked = unlockedAt != null;
    final label = Ko.dexFormLabel(species, stage, tier);
    final date = isUnlocked ? formatDate(unlockedAt!, tz) : '';
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Semantics(
          label: isUnlocked
              ? Ko.dexUnlockedSemantics(label, date)
              : Ko.dexLockedSemantics,
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              color: PetoryColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isUnlocked ? PetoryColors.text : PetoryColors.empty,
                width: isUnlocked ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 64,
                  width: 64,
                  child: CustomPaint(
                    painter: PetPainter(
                      stage: stage,
                      species: species,
                      tier: tier,
                      silhouette: !isUnlocked,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // 성체는 등급을 글자로도 표시(색·표식 외)
                Text(
                  isUnlocked
                      ? (tier != null
                            ? '${Ko.stageName(stage)} ${Ko.tierName(tier!)}'
                            : Ko.stageName(stage))
                      : Ko.dexLocked,
                  style: t.titleSmall,
                  textAlign: TextAlign.center,
                ),
                if (isUnlocked)
                  Text(
                    Ko.dexAcquired(date),
                    style: t.bodySmall,
                    textAlign: TextAlign.center,
                  )
                else
                  const Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: PetoryColors.empty,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemoryTab extends StatelessWidget {
  const _MemoryTab({required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final list = [...controller.data.memories]
      ..sort((a, b) => b.leftAt.compareTo(a.leftAt)); // 최신순
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            liveRegion: true,
            child: Text(
              Ko.memoryEmpty,
              textAlign: TextAlign.center,
              style: t.bodyLarge,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = list[i];
        final together = Ko.durationDH(m.leftAt - m.bornAt);
        return Semantics(
          container: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PetoryColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PetoryColors.text, width: 2),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: ExcludeSemantics(
                    child: CustomPaint(
                      painter: PetPainter(
                        stage: m.maxStage,
                        species: m.species,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name, style: t.titleMedium),
                      Text(Ko.memorySubtitle(m.species, m.maxStage)),
                      Text(Ko.memoryTogether(together)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
