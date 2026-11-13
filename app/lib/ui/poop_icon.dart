import 'package:material_ui/material_ui.dart';

/// 똥 아이콘. 번들 글꼴에 이모지가 없어 직접 그린다 (시안의 SVG와 같은 모양).
class PoopIcon extends StatelessWidget {
  const PoopIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(size: Size.square(size), painter: _PoopPainter()),
    );
  }
}

class _PoopPainter extends CustomPainter {
  static const _dark = Color(0xFF8B5E3C);
  static const _light = Color(0xFF9C6B46);
  static const _eye = Color(0xFF1F2A44);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 48;
    Rect r(double l, double t, double rr, double b) =>
        Rect.fromLTRB(l * s, t * s, rr * s, b * s);
    RRect rr(Rect rect, double radius) =>
        RRect.fromRectAndRadius(rect, Radius.circular(radius * s));

    final dark = Paint()..color = _dark;
    final light = Paint()..color = _light;
    canvas.drawRRect(rr(r(8, 34, 40, 44), 5), dark);
    canvas.drawRRect(rr(r(13, 26, 35, 34), 5), light);
    canvas.drawRRect(rr(r(18, 18, 30, 26), 5), dark);
    final tip = Path()
      ..moveTo(24 * s, 8 * s)
      ..quadraticBezierTo(28 * s, 12 * s, 26 * s, 16 * s)
      ..quadraticBezierTo(24 * s, 18 * s, 22 * s, 16 * s)
      ..quadraticBezierTo(20 * s, 12 * s, 24 * s, 8 * s)
      ..close();
    canvas.drawPath(tip, light);
    final eye = Paint()..color = _eye;
    canvas.drawCircle(Offset(20 * s, 38 * s), 2 * s, eye);
    canvas.drawCircle(Offset(28 * s, 38 * s), 2 * s, eye);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
