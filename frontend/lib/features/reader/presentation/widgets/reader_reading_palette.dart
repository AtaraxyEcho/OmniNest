import 'package:flutter/material.dart';

/// 实际阅读画布使用的独立色板。
///
/// 角色与值取自移动端阅读器稿 `src/index.css`：`.reader` 基线（= 米黄档，稿子
/// 没有 `.theme-sepia` 类，米黄就是基线）与 `.theme-paper` / `.theme-sage` /
/// `.theme-night` 三段类切换。四档对应 light=paper、eyeCare=sepia（稿子默认档）、
/// green=sage、dark=night。`selection`/`annotation` 稿子里没有（它不做选区与
/// 高亮），沿用应用既有值。
@immutable
class ReaderReadingPalette {
  const ReaderReadingPalette({
    required this.id,
    required this.surface,
    required this.elevated,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.faint,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.controlSurface,
    required this.glass,
    required this.glassSolid,
    required this.shadow,
    required this.selection,
    required this.annotation,
  });

  final String id;

  /// `--page`：正文画布底。
  final Color surface;

  /// `--page-elevated`：图标舱、卡片这类浮在画布上的实底。
  final Color elevated;
  final Color onSurface;
  final Color onSurfaceVariant;

  /// `--faint`：进度尾注、禁用态这类三级信息。
  final Color faint;

  /// `--line`：压在画布上的发丝描边。
  final Color line;
  final Color accent;

  /// `--accent-soft`：强调色的低透明铺底（主操作钮、引用条）。
  final Color accentSoft;

  /// 控制层底色：面板框、顶/底栏和弹出菜单共用。必须实底，这些面直接压在正文上。
  final Color controlSurface;

  /// `--glass`：底栏玻璃条的半透明底，只用在真有 backdrop 模糊的那一层。
  final Color glass;

  /// `--glass-solid`：底部抽屉的实底。
  final Color glassSolid;

  /// `--shadow`：浮层投影与图标舱阴影的着色。
  final Color shadow;
  final Color selection;
  final Color annotation;

  /// 稿子 `.theme-paper`（index.css:73）。
  static const light = ReaderReadingPalette(
    id: 'light',
    surface: Color(0xFFFAF9F5),
    elevated: Color(0xFFFFFFFF),
    onSurface: Color(0xFF252624),
    onSurfaceVariant: Color(0xFF6D706C),
    faint: Color(0xFFA1A39E),
    line: Color(0x1C1F231F),
    accent: Color(0xFF246D62),
    accentSoft: Color(0x1C246D62),
    controlSurface: Color(0xFFFAFAF7),
    glass: Color(0xD6FFFFFF),
    glassSolid: Color(0xFFFAFAF7),
    shadow: Color(0x1F1C211D),
    selection: Color(0x663F7CAC),
    annotation: Color(0xFFFFD65A),
  );

  /// 稿子 `.reader` 基线（index.css:52），也是稿子的默认档。
  static const eyeCare = ReaderReadingPalette(
    id: 'eyeCare',
    surface: Color(0xFFF4F0E6),
    elevated: Color(0xFFF8F5EC),
    onSurface: Color(0xFF2D2D2A),
    onSurfaceVariant: Color(0xFF77736A),
    faint: Color(0xFFA7A197),
    line: Color(0x1F433E34),
    accent: Color(0xFF337F70),
    accentSoft: Color(0x1F337F70),
    controlSurface: Color(0xFFF5F1E8),
    glass: Color(0xD1FAF7EF),
    glassSolid: Color(0xFFF5F1E8),
    shadow: Color(0x242F2B23),
    selection: Color(0x665E7C52),
    annotation: Color(0xFFEBCB62),
  );

  /// 稿子 `.theme-night`（index.css:101）。
  static const dark = ReaderReadingPalette(
    id: 'dark',
    surface: Color(0xFF151918),
    elevated: Color(0xFF1D2220),
    onSurface: Color(0xFFE6E8E2),
    onSurfaceVariant: Color(0xFF9B9F99),
    faint: Color(0xFF666C67),
    line: Color(0x1AEBF0E8),
    accent: Color(0xFF9EC7A5),
    accentSoft: Color(0x1F9EC7A5),
    controlSurface: Color(0xFF1D2220),
    glass: Color(0xDB191E1C),
    glassSolid: Color(0xFF1D2220),
    shadow: Color(0x52000000),
    selection: Color(0x665F9FCE),
    annotation: Color(0xFFD8B94F),
  );

  /// 稿子 `.theme-sage`（index.css:87）。
  static const green = ReaderReadingPalette(
    id: 'green',
    surface: Color(0xFFE9EEE5),
    elevated: Color(0xFFF0F3ED),
    onSurface: Color(0xFF29322C),
    onSurfaceVariant: Color(0xFF69736B),
    faint: Color(0xFF98A097),
    line: Color(0x1F2A3A30),
    accent: Color(0xFF39765E),
    accentSoft: Color(0x1F39765E),
    controlSurface: Color(0xFFEDF2EA),
    glass: Color(0xD6EDF2EA),
    glassSolid: Color(0xFFEDF2EA),
    shadow: Color(0x211E2E24),
    selection: Color(0x66568A64),
    annotation: Color(0xFFE2C75D),
  );

  static const values = [light, eyeCare, dark, green];

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
