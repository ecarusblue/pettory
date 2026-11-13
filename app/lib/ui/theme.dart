import 'package:material_ui/material_ui.dart';

import '../domain/domain.dart';

class PetoryColors {
  PetoryColors._();
  static const bg = Color(0xFFE9F7EF);
  static const text = Color(0xFF1F2A44);
  static const accent = Color(0xFFFF7A66);
  static const card = Color(0xFFFFFFFF);
  static const hunger = Color(0xFFE08A1E);
  static const happy = Color(0xFFE5547A);
  static const tired = Color(0xFF3F7CD8);
  static const empty = Color(0xFFB9C4D6);

  static Color species(Species s) => switch (s) {
    Species.eggA => const Color(0xFF7FD6B0),
    Species.eggB => const Color(0xFFFFC48A),
    Species.eggC => const Color(0xFF8EC9F5),
  };
}

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: PetoryColors.accent,
        brightness: Brightness.light,
      ).copyWith(
        primary: const Color(0xFFD9503C), // 흰 글씨 대비 4.5:1 이상
        onPrimary: Colors.white,
        surface: PetoryColors.bg,
        onSurface: PetoryColors.text,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: PetoryColors.bg,
    // 본문 Noto Sans KR, 제목 Jua — 둘 다 assets/fonts 에 번들(CDN 폴백 없음)
    fontFamily: 'NotoSansKR',
    textTheme: _titleInJua(
      Typography.blackMountainView.apply(
        fontFamily: 'NotoSansKR',
        bodyColor: PetoryColors.text,
        displayColor: PetoryColors.text,
      ),
    ),
  );
}

TextTheme _titleInJua(TextTheme t) => t.copyWith(
  displayLarge: t.displayLarge?.copyWith(fontFamily: 'Jua'),
  displayMedium: t.displayMedium?.copyWith(fontFamily: 'Jua'),
  displaySmall: t.displaySmall?.copyWith(fontFamily: 'Jua'),
  headlineLarge: t.headlineLarge?.copyWith(fontFamily: 'Jua'),
  headlineMedium: t.headlineMedium?.copyWith(fontFamily: 'Jua'),
  headlineSmall: t.headlineSmall?.copyWith(fontFamily: 'Jua'),
  titleLarge: t.titleLarge?.copyWith(fontFamily: 'Jua'),
);
