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
    required this.bookDesk,
    required this.bookDeskText,
    required this.paperEdge,
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

  /// 双页书本模式下正文纸页以外的桌面底色。
  final Color bookDesk;

  /// 双页书本模式控制栏在桌面底色上的文字色。
  final Color bookDeskText;

  /// 双页纸叠边缘色（样例 `--paper-edge`）。
  final Color paperEdge;

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
    surface: Color(0xFFF6F1E4),
    elevated: Color(0xFFFFFFFF),
    onSurface: Color(0xFF2B2620),
    onSurfaceVariant: Color(0xFF6D685E),
    faint: Color(0xFFA19B8F),
    line: Color(0x1C2B2620),
    accent: Color(0xFF246D62),
    accentSoft: Color(0x1C246D62),
    controlSurface: Color(0xFFFAF6EC),
    bookDesk: Color(0xFF1B1F22),
    bookDeskText: Color(0xFFE8ECEA),
    paperEdge: Color(0xFFE4DCC8),
    glass: Color(0xD6FFFFFF),
    glassSolid: Color(0xFFFAFAF7),
    shadow: Color(0x1F1C211D),
    selection: Color(0x663F7CAC),
    annotation: Color(0xFFFFD65A),
  );

  /// 稿子 `.reader` 基线（index.css:52），也是稿子的默认档。
  static const eyeCare = ReaderReadingPalette(
    id: 'eyeCare',
    surface: Color(0xFFEAD9B6),
    elevated: Color(0xFFF2E5C9),
    onSurface: Color(0xFF3D2F1B),
    onSurfaceVariant: Color(0xFF725E44),
    faint: Color(0xFF9F8B6D),
    line: Color(0x1F3D2F1B),
    accent: Color(0xFF337F70),
    accentSoft: Color(0x1F337F70),
    controlSurface: Color(0xFFF0E1C2),
    bookDesk: Color(0xFF2A2118),
    bookDeskText: Color(0xFFE8ECEA),
    paperEdge: Color(0xFFD6C196),
    glass: Color(0xD1FAF7EF),
    glassSolid: Color(0xFFF5F1E8),
    shadow: Color(0x242F2B23),
    selection: Color(0x665E7C52),
    annotation: Color(0xFFEBCB62),
  );

  /// 稿子 `.theme-night`（index.css:101）。
  static const dark = ReaderReadingPalette(
    id: 'dark',
    surface: Color(0xFF1C2024),
    elevated: Color(0xFF23282D),
    onSurface: Color(0xFFC9CDC8),
    onSurfaceVariant: Color(0xFF8F9691),
    faint: Color(0xFF606763),
    line: Color(0x1AEBF0E8),
    accent: Color(0xFF8CC5B2),
    accentSoft: Color(0x1F8CC5B2),
    controlSurface: Color(0xFF22272B),
    bookDesk: Color(0xFF0B0D0F),
    bookDeskText: Color(0xFFE8ECEA),
    paperEdge: Color(0xFF14171A),
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
    bookDesk: Color(0xFF1B1F22),
    bookDeskText: Color(0xFFE8ECEA),
    paperEdge: Color(0xFFD5DED0),
    glass: Color(0xD6EDF2EA),
    glassSolid: Color(0xFFEDF2EA),
    shadow: Color(0x211E2E24),
    selection: Color(0x66568A64),
    annotation: Color(0xFFE2C75D),
  );

  /// 桌面毛玻璃浮层（样例 `.bk-pop`）的暗色玻璃底，四档色板共用同一层桌面 chrome。
  static const desktopPopoverGlass = Color(0xF01A1E22);

  /// 桌面毛玻璃浮层上的主文字色（比夜间纸面文字更亮）。
  static const desktopPopoverOnSurface = Color(0xFFEFF2F5);

  /// 桌面毛玻璃浮层上的次级文字色（与 [ReaderPanelColors.darkGlass] 同源）。
  static const desktopPopoverMuted = Color(0xFFAAB4BE);

  /// 选区浮动工具条（样例 `.sel-pop`）的暗色胶囊底。
  static const selectionToolbarSurface = Color(0xFF1C2125);

  /// 选区浮动工具条的主强调色（保存批注与聚焦描边）。
  static const selectionToolbarAccent = Color(0xFFF2D36B);

  /// 强调色圆角角标上的反白文字。
  static const onAccentInk = Color(0xFF0E1412);

  /// 书内搜索命中词的半透明强调底（`<mark class="hit">`）。
  static const searchHit = Color(0x738CC5B2);

  /// 护眼暖色滤镜的暖色基色；强度由 `warmth` 调制。
  static const comfortWarmTint = Color(0xFFFF9628);

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

/// 面板语义色板：自动适配桌面暗色毛玻璃浮层与移动端纸面抽屉，
/// 彻底消除浅色/护眼/绿色主题下深色墨字绘制在暗色玻璃上的可读性异常。
@immutable
class ReaderPanelColors {
  const ReaderPanelColors({
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.faint,
    required this.line,
    required this.controlFill,
    required this.controlActiveFill,
    required this.cardSurface,
    required this.accent,
    required this.accentSoft,
    required this.isDarkGlass,
  });

  final Color onSurface;
  final Color onSurfaceVariant;
  final Color faint;
  final Color line;
  final Color controlFill;
  final Color controlActiveFill;
  final Color cardSurface;
  final Color accent;
  final Color accentSoft;
  final bool isDarkGlass;

  factory ReaderPanelColors.darkGlass({required Color accentColor}) {
    final accent =
        accentColor.computeLuminance() < 0.28
            ? Color.lerp(accentColor, Colors.white, 0.36)!
            : accentColor;
    return ReaderPanelColors(
      onSurface: const Color(0xFFEFF2F5),
      onSurfaceVariant: const Color(0xFFAAB4BE),
      faint: const Color(0xFF727D88),
      line: Colors.white.withValues(alpha: 0.11),
      controlFill: Colors.white.withValues(alpha: 0.08),
      controlActiveFill: Colors.white.withValues(alpha: 0.20),
      cardSurface: Colors.white.withValues(alpha: 0.06),
      accent: accent,
      accentSoft: accent.withValues(alpha: 0.20),
      isDarkGlass: true,
    );
  }

  factory ReaderPanelColors.fromPalette(ReaderReadingPalette palette) {
    return ReaderPanelColors(
      onSurface: palette.onSurface,
      onSurfaceVariant: palette.onSurfaceVariant,
      faint: palette.faint,
      line: palette.line,
      controlFill: palette.onSurface.withValues(alpha: 0.06),
      controlActiveFill: palette.elevated,
      cardSurface: palette.surface,
      accent: palette.accent,
      accentSoft: palette.accentSoft,
      isDarkGlass: false,
    );
  }

  static ReaderPanelColors resolve(
    BuildContext context,
    ReaderReadingPalette palette,
  ) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ReaderPanelSurfaceScope>();
    if (scope?.darkGlass ?? false) {
      return ReaderPanelColors.darkGlass(accentColor: palette.accent);
    }
    return ReaderPanelColors.fromPalette(palette);
  }
}

class ReaderPanelSurfaceScope extends InheritedWidget {
  const ReaderPanelSurfaceScope({
    required this.darkGlass,
    required super.child,
    super.key,
  });

  final bool darkGlass;

  /// 是否处于桌面暗色毛玻璃浮层内，供只做取色分支的浮层组件直接判定。
  static bool isDarkGlass(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ReaderPanelSurfaceScope>();
    return scope?.darkGlass ?? false;
  }

  @override
  bool updateShouldNotify(ReaderPanelSurfaceScope oldWidget) =>
      oldWidget.darkGlass != darkGlass;
}
