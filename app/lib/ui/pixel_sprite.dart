import 'package:material_ui/material_ui.dart';

/// 미니게임용 8x8 픽셀 그림. 글자 하나가 한 칸이고 '.' 은 빈칸이다.
enum Sprite { apple, cookie, poop, ball, fish, heart, star }

const _grids = <Sprite, List<String>>{
  Sprite.apple: [
    '....g...',
    '...g....',
    '.rrrrrr.',
    'rrwrrrrr',
    'rrwrrrrr',
    'rrrrrrrr',
    '.rrrrrr.',
    '..rr.rr.',
  ],
  Sprite.cookie: [
    '..tttt..',
    '.ttkttt.',
    'tttttktt',
    'tktttttt',
    'ttttkttt',
    'tttktttt',
    '.tttttt.',
    '..tttt..',
  ],
  Sprite.poop: [
    '....b...',
    '...bbb..',
    '..bwbbb.',
    '.bbbbbb.',
    '.bkbbkb.',
    'bbbbbbbb',
    'bbbbbbbb',
    '.bbbbbb.',
  ],
  Sprite.ball: [
    '..pppp..',
    '.ppwppp.',
    'ppwppppp',
    'pppppppp',
    'pppppppp',
    'pppppppp',
    '.pppppp.',
    '..pppp..',
  ],
  Sprite.fish: [
    '........',
    '..cccc.c',
    '.ccwkccc',
    'cccccccc',
    '.cccccc.',
    '..cccc.c',
    '........',
    '........',
  ],
  Sprite.heart: [
    '........',
    '.pp..pp.',
    'pppppppp',
    'pppppppp',
    '.pppppp.',
    '..pppp..',
    '...pp...',
    '........',
  ],
  Sprite.star: [
    '...yy...',
    '...yy...',
    'yyyyyyyy',
    '.yyyyyy.',
    '..yyyy..',
    '.yyyyyy.',
    '.yy..yy.',
    '........',
  ],
};

const _palette = <String, Color>{
  'k': Color(0xFF1F2A44),
  'w': Color(0xFFFFFFFF),
  'r': Color(0xFFE5483A),
  'g': Color(0xFF4CAF6A),
  'y': Color(0xFFF2C14E),
  'b': Color(0xFF8A5A2B),
  'p': Color(0xFFE5547A),
  'c': Color(0xFF8EC9F5),
  't': Color(0xFFC9A06B),
};

/// [size] x [size] 안에 스프라이트를 꽉 채워 그린다.
class PixelSprite extends StatelessWidget {
  const PixelSprite(this.sprite, {super.key, this.size = 40});
  final Sprite sprite;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _SpritePainter(sprite),
    ),
  );
}

class _SpritePainter extends CustomPainter {
  _SpritePainter(this.sprite);
  final Sprite sprite;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = _grids[sprite]!;
    final cell = size.width / 8;
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        final color = _palette[rows[y][x]];
        if (color == null) continue;
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5),
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SpritePainter old) => old.sprite != sprite;
}

/// 숨은 공 찾기의 컵(위가 좁은 사다리꼴, 8x8 격자가 아니라 경로로 그린다).
class CupShape extends StatelessWidget {
  const CupShape({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size(size, size * 1.1), painter: _CupPainter()),
  );
}

class _CupPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = Path()
      ..moveTo(w * .16, 0)
      ..lineTo(w * .84, 0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFFE5547A));
    canvas.drawRect(
      Rect.fromLTWH(w * .16, 0, w * .68, h * .1),
      Paint()..color = const Color(0xFFF28AA6),
    );
    canvas.drawRect(
      Rect.fromLTWH(w * .26, h * .25, w * .1, h * .55),
      Paint()..color = const Color(0x73FFFFFF),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, h * .9, w, h * .1),
      Paint()..color = const Color(0xFFB93A5E),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF1F2A44),
    );
  }

  @override
  bool shouldRepaint(_CupPainter old) => false;
}
