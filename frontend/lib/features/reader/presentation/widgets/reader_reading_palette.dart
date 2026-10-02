import 'package:flutter/material.dart';

/// 实际阅读画布使用的独立色板。
@immutable
class ReaderReadingPalette {
  const ReaderReadingPalette({
    required this.id,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.accent,
    required this.controlSurface,
    required this.selection,
    required this.annotation,
  });

  final String id;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color accent;
  final Color controlSurface;
  final Color selection;
  final Color annotation;

  static const light = ReaderReadingPalette(
    id: 'light',
    surface: Color(0xFFF7F7F5),
    onSurface: Color(0xFF20211F),
    onSurfaceVariant: Color(0xFF555852),
    accent: Color(0xFF315F8C),
    controlSurface: Color(0xFFF1F2EF),
    selection: Color(0x663F7CAC),
    annotation: Color(0xFFFFD65A),
  );

  static const eyeCare = ReaderReadingPalette(
    id: 'eyeCare',
    surface: Color(0xFFE7E1D4),
    onSurface: Color(0xFF282720),
    onSurfaceVariant: Color(0xFF59564B),
    accent: Color(0xFF536B48),
    controlSurface: Color(0xFFDDD7CA),
    selection: Color(0x665E7C52),
    annotation: Color(0xFFEBCB62),
  );

  static const dark = ReaderReadingPalette(
    id: 'dark',
    surface: Color(0xFF121313),
    onSurface: Color(0xFFE8E9E5),
    onSurfaceVariant: Color(0xFFB8BBB4),
    accent: Color(0xFF9CCAF2),
    controlSurface: Color(0xFF1B1D1D),
    selection: Color(0x665F9FCE),
    annotation: Color(0xFFD8B94F),
  );

  static const green = ReaderReadingPalette(
    id: 'green',
    surface: Color(0xFFDCE8DC),
    onSurface: Color(0xFF202A21),
    onSurfaceVariant: Color(0xFF4C5B4D),
    accent: Color(0xFF356C47),
    controlSurface: Color(0xFFD2DFD2),
    selection: Color(0x66568A64),
    annotation: Color(0xFFE2C75D),
  );

  /// 样例 ReaderFocus 的夜间玻璃配色：深玻璃底 + 暖白衬线正文 + lime 强调。
  static const nightGlass = ReaderReadingPalette(
    id: 'nightGlass',
    surface: Color(0xFF171A17),
    onSurface: Color(0xFFE0E0D8),
    onSurfaceVariant: Color(0xFFA6ACA4),
    accent: Color(0xFFD5F17D),
    controlSurface: Color(0x14FFFFFF),
    selection: Color(0x66D5F17D),
    annotation: Color(0xFFE8C46B),
  );

  static const values = [light, eyeCare, dark, green, nightGlass];

  static ReaderReadingPalette fromId(String id) {
    return values.firstWhere((palette) => palette.id == id, orElse: () => dark);
  }

  static String idFromLegacyIndex(int index) {
    return values[index.clamp(0, values.length - 1)].id;
  }

  static int legacyIndexFromId(String id) {
    final index = values.indexWhere((palette) => palette.id == id);
    return index < 0 ? 2 : index;
  }
}
