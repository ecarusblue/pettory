import 'package:material_ui/material_ui.dart';

import '../l10n/ko.dart';
import 'theme.dart';

/// 4칸 게이지. 색 외에 아이콘 모양(채움/윤곽)과 "n/4" 숫자로 값을 표시한다.
class Gauge extends StatelessWidget {
  const Gauge({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.filledIcon,
    required this.emptyIcon,
  });
  final String label;
  final int value;
  final Color color;
  final IconData filledIcon;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: Ko.gaugeValue(label, value),
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: Theme.of(context).textTheme.titleSmall),
          ),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                i < value ? filledIcon : emptyIcon,
                size: 28,
                color: i < value ? color : PetoryColors.empty,
              ),
            ),
          const SizedBox(width: 4),
          Text('$value/4', style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// 상태 아이콘 칩 (똥 개수 / 건강).
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.icon,
    required this.text,
    required this.semanticsLabel,
    this.alert = false,
  });
  final Widget icon;
  final String text;
  final String semanticsLabel;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: PetoryColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: alert ? PetoryColors.accent : PetoryColors.empty,
            width: alert ? 3 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 6),
            Text(text, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}
