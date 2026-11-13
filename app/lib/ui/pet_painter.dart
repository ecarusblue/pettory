import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../domain/domain.dart';
import 'theme.dart';

// '#' 몸, 'k' 눈/입(어두운색), 'w' 하이라이트, '.' 빈칸
const _egg = [
  '....##....',
  '..######..',
  '.########.',
  '.##w#####.',
  '##########',
  '#####w####',
  '##########',
  '##########',
  '.########.',
  '.########.',
  '..######..',
];
const _baby = [
  '..######..',
  '.########.',
  '.#k####k#.',
  '.########.',
  '.###kk###.',
  '..######..',
];
const _child = [
  '.#......#.',
  '.##....##.',
  '.########.',
  '##k####k##',
  '##########',
  '##########',
  '.###kk###.',
  '..######..',
];
const _teen = [
  '.#......#.',
  '.##....##.',
  '.########.',
  '##k####k##',
  '##########',
  '##########',
  '.###kk###.',
  '.########.',
  '.##....##.',
  '.##....##.',
];
const _adult = [
  '#.#....#.#',
  '####..####',
  '.########.',
  '##k####k##',
  '##########',
  '##########',
  '.###kk###.',
  '.########.',
  '.########.',
  '.##....##.',
  '.##....##.',
];

List<String> spriteFor(Stage s) => switch (s) {
  Stage.egg => _egg,
  Stage.baby => _baby,
  Stage.child => _child,
  Stage.teen => _teen,
  Stage.adult => _adult,
};

/// 임시 픽셀 스프라이트 페인터 (외주 아트 도착 전 자리표시자).
class PetPainter extends CustomPainter {
  PetPainter({
    required this.stage,
    required this.species,
    this.sick = false,
    this.asleep = false,
    this.tier,
    this.silhouette = false,
  });
  final Stage stage;
  final Species species;
  final bool sick;
  final bool asleep;
  final Tier? tier;

  /// 미해금 표시용: 단색 실루엣(눈·하이라이트·등급 표식 없음).
  final bool silhouette;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = spriteFor(stage);
    final cols = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final cell = (size.width / cols).clamp(0, size.height / rows.length);
    final w = cell * cols, h = cell * rows.length;
    final ox = (size.width - w) / 2, oy = (size.height - h) / 2;
    var body = PetoryColors.species(species);
    if (sick) body = Color.lerp(body, const Color(0xFFB8C98A), 0.55)!;
    if (silhouette) body = PetoryColors.empty;
    final bodyP = Paint()..color = body;
    final darkP = Paint()..color = silhouette ? body : PetoryColors.text;
    final whiteP = Paint()..color = silhouette ? body : const Color(0xCCFFFFFF);
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        final c = rows[y][x];
        if (c == '.') continue;
        var p = switch (c) {
          'k' => darkP,
          'w' => whiteP,
          _ => bodyP,
        };
        var rect = Rect.fromLTWH(
          ox + x * cell,
          oy + y * cell,
          cell + 0.5,
          cell + 0.5,
        );
        if (c == 'k' && asleep && stage != Stage.egg) {
          // 감은 눈: 가로선
          rect = Rect.fromLTWH(
            rect.left,
            rect.top + cell * 0.6,
            rect.width,
            cell * 0.4,
          );
        }
        canvas.drawRect(rect, p);
      }
    }
    if (!silhouette && tier != null && stage == Stage.adult) {
      // 성체 등급 표식 (색 외에 모양): 우수=별, 보통=동그라미, 방치=네모
      final mark = Paint()..color = PetoryColors.accent;
      final c = Offset(ox + w - cell, oy + cell);
      switch (tier!) {
        case Tier.excellent:
          canvas.drawPath(_star(c, cell * 1.1), mark);
        case Tier.normal:
          canvas.drawCircle(c, cell * 0.8, mark);
        case Tier.neglect:
          canvas.drawRect(
            Rect.fromCenter(center: c, width: cell * 1.4, height: cell * 1.4),
            mark,
          );
      }
    }
  }

  Path _star(Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : r * 0.45;
      final a = -1.5708 + i * 0.6283185;
      final p = Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(PetPainter o) =>
      o.stage != stage ||
      o.species != species ||
      o.sick != sick ||
      o.asleep != asleep ||
      o.tier != tier ||
      o.silhouette != silhouette;
}
