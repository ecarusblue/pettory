import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../domain/domain.dart';
import '../l10n/ko.dart';
import 'pet_painter.dart';
import 'theme.dart';

/// 스탯에서 읽는 기분 (표정용, 저장하지 않는 파생 값).
PetMood moodOf(PetState pet) {
  if (pet.asleep || pet.sick) return PetMood.neutral;
  if (pet.hunger <= 1 || pet.happiness <= 1) return PetMood.sad;
  if (pet.hunger >= 3 && pet.happiness >= 3) return PetMood.happy;
  return PetMood.neutral;
}

/// 홈 화면의 캐릭터 무대: 표정, 밤 배경(수면), 쓰다듬기·케어 반응(폴짝 + 말풍선).
///
/// 반응은 [reactionSerial] 이 바뀔 때 한 번 재생되고 끝난다(무한 애니메이션 없음).
class PetStage extends StatefulWidget {
  const PetStage({
    super.key,
    required this.pet,
    required this.semanticsLabel,
    this.reaction,
    this.reactionSerial = 0,
  });
  final PetState pet;
  final String semanticsLabel;

  /// 케어 직후 보여 줄 말풍선 문구.
  final String? reaction;
  final int reactionSerial;

  @override
  State<PetStage> createState() => _PetStageState();
}

class _PetStageState extends State<PetStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  String? _bubble;

  @override
  void didUpdateWidget(PetStage old) {
    super.didUpdateWidget(old);
    if (widget.reactionSerial != old.reactionSerial &&
        widget.reaction != null) {
      _play(widget.reaction!);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _play(String text) {
    setState(() => _bubble = text);
    _anim.forward(from: 0);
  }

  void _pet() {
    final p = widget.pet;
    _play(
      p.asleep
          ? Ko.petAsleep
          : p.sick
          ? Ko.petSick
          : Ko.petHappy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pet = widget.pet;
    final night = pet.asleep;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final mood = moodOf(pet);
    final moodText = switch (mood) {
      PetMood.happy => ', ${Ko.moodHappy}',
      PetMood.sad => ', ${Ko.moodSad}',
      PetMood.neutral => '',
    };
    return Semantics(
      label: '${widget.semanticsLabel}$moodText',
      button: true,
      hint: Ko.petHint,
      onTap: _pet,
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('pet-stage'),
        behavior: HitTestBehavior.opaque,
        onTap: _pet,
        child: Container(
          height: 244,
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          decoration: BoxDecoration(
            color: night ? const Color(0xFF26324F) : null,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 240,
              height: 220,
              child: AnimatedBuilder(
                animation: _anim,
                builder: (context, _) {
                  final v = _anim.value;
                  // 폴짝: 앞 40% 구간에서 한 번 뛰었다 내려온다.
                  final hop = reduceMotion || v == 0 || v > 0.4
                      ? 0.0
                      : -14 * math.sin(v / 0.4 * math.pi);
                  // 말풍선: 재생 중에만 보이고 끝 20% 에서 사라진다.
                  final show = _anim.isAnimating && _bubble != null;
                  final fade = v < 0.8 ? 1.0 : (1 - v) / 0.2;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Transform.translate(
                        offset: Offset(0, hop),
                        child: CustomPaint(
                          size: const Size(240, 220),
                          painter: PetPainter(
                            stage: pet.stage,
                            species: pet.species,
                            sick: pet.sick,
                            asleep: pet.asleep,
                            tier: pet.adultTier,
                            mood: mood,
                          ),
                        ),
                      ),
                      if (pet.asleep && !show)
                        const Positioned(
                          top: 0,
                          right: 8,
                          child: Text(
                            'Zzz',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      if (show)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Opacity(
                              opacity: fade.clamp(0.0, 1.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: PetoryColors.card,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: PetoryColors.text,
                                    width: 2,
                                  ),
                                ),
                                child: Text(
                                  _bubble!,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
