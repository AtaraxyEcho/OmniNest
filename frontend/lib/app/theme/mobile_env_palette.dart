import 'package:flutter/material.dart';

/// 移动环境配色的两极性表。
///
/// [MobileEnvPalette.dark] 逐值等于 `MobileEnvColors`（环境基准不变，迁移期两处并存）；
/// [MobileEnvPalette.light] 是同一批角色的纸面同位物，其 α 按"等对比反解"上调而非同名照抄：
/// 亮度是非线性的，同 α 的深墨在纸面上的对比只有同 α 白字在暗底上的一半上下
/// （换算表见 docs/2026-10-08/013 §F4，取值基色用本仓浅色 surface `#F7F8F6`）。
///
/// 角色约定（浅色分支的硬约束）：
/// - 填充与其上的文字必须成对使用（`buttonInk`/`onButtonInk`、`selectionBar`/`onSelectionBar`），
///   只翻其中一侧会得到"深底深字"；
/// - [accent] 只做填充，永远配 [onAccent] 深字；文字/图标/发丝线/细进度条用 [accentInk]，
///   因为酸绿在纸面上只有 1.18:1。
@immutable
class MobileEnvPalette extends ThemeExtension<MobileEnvPalette> {
  const MobileEnvPalette({
    required this.brightness,
    required this.stage,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.ink40,
    required this.white52,
    required this.white46,
    required this.white43,
    required this.white70,
    required this.white78,
    required this.line13,
    required this.line10,
    required this.line07,
    required this.line09,
    required this.line15,
    required this.line25,
    required this.line12,
    required this.accent,
    required this.accentInk,
    required this.onAccent,
    required this.onAccentDeep,
    required this.segmentBg,
    required this.iconButtonGlass,
    required this.posterPlayBg,
    required this.posterPlayFg,
    required this.searchOverlayBg,
    required this.surfaceGlass,
    required this.surfaceRaised,
    required this.surfaceTint,
    required this.navGlass,
    required this.sheetSolid,
    required this.focusGradientStart,
    required this.focusGradientEnd,
    required this.avatarBg,
    required this.avatarFg,
    required this.bookMiniBg,
    required this.bookMiniFg,
    required this.bookMiniSpine,
    required this.folderGlyph,
    required this.folderGlyphBg,
    required this.storageProgressFill,
    required this.storageCloud,
    required this.storageCloudBg,
    required this.readerCoverBg,
    required this.readerCoverSpine,
    required this.readerCoverFg,
    required this.selectionBar,
    required this.onSelectionBar,
    required this.buttonInk,
    required this.onButtonInk,
  });

  /// 该极性的明暗档，供第三方编辑器等需要 ThemeData.brightness 的场合使用。
  final Brightness brightness;
  final Color stage;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color ink40;
  final Color white52;
  final Color white46;
  final Color white43;
  final Color white70;
  final Color white78;
  final Color line13;
  final Color line10;
  final Color line07;
  final Color line09;
  final Color line15;

  /// 强中性叠加：把手、加号舱描边这类需要明显可见的 25% 档。
  final Color line25;
  final Color line12;
  final Color accent;

  /// 强调色的"墨"用法：暗态仍是酸绿，浅态换成深青（`AppThemePalette.light.primary`）。
  final Color accentInk;
  final Color onAccent;
  final Color onAccentDeep;
  final Color segmentBg;
  final Color iconButtonGlass;
  final Color posterPlayBg;
  final Color posterPlayFg;
  final Color searchOverlayBg;
  final Color surfaceGlass;
  final Color surfaceRaised;

  /// 低透明表面着色：列表行底、格内图标片。
  final Color surfaceTint;
  final Color navGlass;
  final Color sheetSolid;
  final Color focusGradientStart;
  final Color focusGradientEnd;
  final Color avatarBg;
  final Color avatarFg;
  final Color bookMiniBg;
  final Color bookMiniFg;
  final Color bookMiniSpine;
  final Color folderGlyph;
  final Color folderGlyphBg;
  final Color storageProgressFill;
  final Color storageCloud;
  final Color storageCloudBg;
  final Color readerCoverBg;
  final Color readerCoverSpine;
  final Color readerCoverFg;
  final Color selectionBar;
  final Color onSelectionBar;
  final Color buttonInk;
  final Color onButtonInk;

  /// 与 `MobileEnvColors` 逐值相同的环境基准。
  static const MobileEnvPalette dark = MobileEnvPalette(
    brightness: Brightness.dark,
    stage: Color(0xFF0B1110),
    ink: Color(0xFFF6F6F2),
    inkMuted: Color(0xBFF6F6F2),
    inkFaint: Color(0x94F6F6F2),
    ink40: Color(0x66F6F6F2),
    white52: Color(0x85FFFFFF),
    white46: Color(0x75FFFFFF),
    white43: Color(0x6EFFFFFF),
    white70: Color(0xB3FFFFFF),
    white78: Color(0xC7FFFFFF),
    line13: Color(0x21FFFFFF),
    line10: Color(0x1AFFFFFF),
    line07: Color(0x12FFFFFF),
    line09: Color(0x17FFFFFF),
    line15: Color(0x26FFFFFF),
    line25: Color(0x40FFFFFF),
    line12: Color(0x1FFFFFFF),
    accent: Color(0xFFD5F17D),
    accentInk: Color(0xFFD5F17D),
    onAccent: Color(0xFF172014),
    onAccentDeep: Color(0xFF151C13),
    segmentBg: Color(0xB8141C1A),
    iconButtonGlass: Color(0x52121817),
    posterPlayBg: Color(0xE6F9F9F4),
    posterPlayFg: Color(0xFF101513),
    searchOverlayBg: Color(0xF00A0F0E),
    surfaceGlass: Color(0xB8121918),
    surfaceRaised: Color(0x8F111816),
    surfaceTint: Color(0x0BFFFFFF),
    navGlass: Color(0xC70E1413),
    sheetSolid: Color(0xFF171E1C),
    focusGradientStart: Color(0xC2101615),
    focusGradientEnd: Color(0x7D1B2421),
    avatarBg: Color(0xFFD6C0A9),
    avatarFg: Color(0xFF2C211A),
    bookMiniBg: Color(0xFFD8CFB5),
    bookMiniFg: Color(0xFF27261F),
    bookMiniSpine: Color(0xFF948F7D),
    folderGlyph: Color(0xFF91BAF2),
    folderGlyphBg: Color(0x2B4C84D2),
    storageProgressFill: Color(0xFF8FB6EC),
    storageCloud: Color(0xFFB9D2FF),
    storageCloudBg: Color(0x295D8EE0),
    readerCoverBg: Color(0xFFD5CCAD),
    readerCoverSpine: Color(0xFF827D6C),
    readerCoverFg: Color(0xFF2C2C26),
    selectionBar: Color(0xFFD9EF91),
    onSelectionBar: Color(0xFF162014),
    buttonInk: Color(0xFFF6F6F2),
    onButtonInk: Color(0xFF141A18),
  );

  /// 纸面同位物：中性墨/线按等对比反解上调 α，表面族换成浅色 surface，
  /// 彩色插画族（头像、书脊、封面、文件夹、存储条）与酸绿填充保持原值。
  static const MobileEnvPalette light = MobileEnvPalette(
    brightness: Brightness.light,
    stage: Color(0xFFF7F8F6),
    ink: Color(0xFF1A1D1B),
    inkMuted: Color(0xD91A1D1B),
    inkFaint: Color(0xB81A1D1B),
    ink40: Color(0x8A1A1D1B),
    white52: Color(0xAB1A1D1B),
    white46: Color(0x9C1A1D1B),
    white43: Color(0x941A1D1B),
    white70: Color(0xD11A1D1B),
    white78: Color(0xDE1A1D1B),
    line13: Color(0x2B1A1D1B),
    line10: Color(0x211A1D1B),
    line07: Color(0x141A1D1B),
    line09: Color(0x1C1A1D1B),
    line15: Color(0x331A1D1B),
    line25: Color(0x561A1D1B),
    line12: Color(0x291A1D1B),
    accent: Color(0xFFD5F17D),
    accentInk: Color(0xFF0B6B61),
    onAccent: Color(0xFF172014),
    onAccentDeep: Color(0xFF151C13),
    segmentBg: Color(0xB8F7F8F6),
    iconButtonGlass: Color(0x52F7F8F6),
    posterPlayBg: Color(0xE61A1D1B),
    posterPlayFg: Color(0xFFF7F8F6),
    searchOverlayBg: Color(0xF0F7F8F6),
    surfaceGlass: Color(0xB8F7F8F6),
    surfaceRaised: Color(0x8FF7F8F6),
    surfaceTint: Color(0x0D1A1D1B),
    navGlass: Color(0xC7F7F8F6),
    sheetSolid: Color(0xFFF7F8F6),
    focusGradientStart: Color(0xC2F7F8F6),
    focusGradientEnd: Color(0x7DF7F8F6),
    avatarBg: Color(0xFFD6C0A9),
    avatarFg: Color(0xFF2C211A),
    bookMiniBg: Color(0xFFD8CFB5),
    bookMiniFg: Color(0xFF27261F),
    bookMiniSpine: Color(0xFF948F7D),
    folderGlyph: Color(0xFF91BAF2),
    folderGlyphBg: Color(0x2B4C84D2),
    storageProgressFill: Color(0xFF8FB6EC),
    storageCloud: Color(0xFFB9D2FF),
    storageCloudBg: Color(0x295D8EE0),
    readerCoverBg: Color(0xFFD5CCAD),
    readerCoverSpine: Color(0xFF827D6C),
    readerCoverFg: Color(0xFF2C2C26),
    selectionBar: Color(0xFFD9EF91),
    onSelectionBar: Color(0xFF162014),
    buttonInk: Color(0xFF1A1D1B),
    onButtonInk: Color(0xFFF7F8F6),
  );

  static MobileEnvPalette resolve(Brightness brightness) {
    return brightness == Brightness.light ? light : dark;
  }

  /// 只认宿主显式注册的实例；未注册一律取暗基准。
  ///
  /// 不按亮度推断：桌面端与媒体托管页在浅色根主题下同样会读到 light，
  /// 而它们的字面量尚未接入极性表，翻转会留下浅底暗字的混合态。
  static MobileEnvPalette of(BuildContext context) {
    return Theme.of(context).extension<MobileEnvPalette>() ?? dark;
  }

  /// 令牌表按整体切换，不做逐色插值：亮度过渡期取任一档都不会出现"深底深字"的中间态。
  @override
  MobileEnvPalette copyWith() => this;

  @override
  MobileEnvPalette lerp(covariant MobileEnvPalette? other, double t) {
    if (other == null) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

extension MobileEnvPaletteContext on BuildContext {
  /// 当前极性的环境配色表。
  MobileEnvPalette get env => MobileEnvPalette.of(this);
}

/// 注册极性表到主题。
///
/// `ThemeData.copyWith(extensions:)` 整体替换扩展集，因此必须带上既有扩展，
/// 否则模块调色板（Photos/Files/Reader 等）会被抹掉。
extension MobileEnvPaletteTheme on ThemeData {
  ThemeData withEnvPalette(MobileEnvPalette palette) {
    return copyWith(extensions: [...extensions.values, palette]);
  }
}
