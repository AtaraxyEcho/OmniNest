import 'package:flutter/material.dart';

/// 阅读生成式封面配色（按标题哈希稳定取色）。
class ReaderGeneratedCoverColors {
  const ReaderGeneratedCoverColors._();

  static const List<(Color, Color)> palettes = [
    (Color(0xFF2C1A0E), Color(0xFF8B4513)),
    (Color(0xFF0F1E2E), Color(0xFF2A4A6E)),
    (Color(0xFF2A1E0A), Color(0xFF7A5A1A)),
    (Color(0xFF1C2E1C), Color(0xFF3A5A3A)),
    (Color(0xFF1A1A2C), Color(0xFF3A3A6E)),
  ];

  static const Color coverText = Color(0xFFEEEDE9);
  static const Color highlightTint = Color(0xFFFFEB3B);
}

/// 影视播放与继续观看的零散 chrome 色。
class MovieChromeColors {
  const MovieChromeColors._();

  static const Color continueLabelOnImage = Color(0xE6FFFFFF);
  static const Color playerTopBarScrim = Color(0xC7000000);
  static const Color trackChipBackground = Color(0xFF2A2A36);
  static const Color trackChipText = Color(0xFFC3C0FF);
  static const Color progressTrack = Color(0x66000000);
  static const Color collectionCardScrim = Color(0x4D000000);
}

/// Portal 标题压字阴影/底色。
class PortalHeroColors {
  const PortalHeroColors._();

  static const Color titleBackdrop = Color(0xF21A2228);
}
