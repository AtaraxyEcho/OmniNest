import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/reader/presentation/theme/reader_space_colors.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_stylesheet.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/platform/platform_capabilities.dart';
part 'reader_view_settings_sections.dart';
part 'reader_view_settings_panel.dart';

class ReaderViewSettings {
  ReaderViewSettings({
    this.fontFamily = 'serif',
    this.fontSize = 18.0,
    this.lineHeight = 1.8,
    String? paletteId,
    int? themeIndex,
    this.readingMode = 'scroll',
    this.immersiveMode = false,
    this.pageTurnMode = 'slide',
    this.volumeKeyPaging = true,
    this.followBookTypesetting = false,
    this.mobileDefaults = false,
    this.justify = true,
    this.marginPreset = 'standard',
    this.brightness = 100,
    this.warmth = 0,
    this.autoNight = false,
  }) : paletteId =
           paletteId ?? ReaderReadingPalette.idFromLegacyIndex(themeIndex ?? 2);

  final String fontFamily;
  final double fontSize;
  final double lineHeight;
  final String paletteId;

  int get themeIndex => ReaderReadingPalette.legacyIndexFromId(paletteId);

  /// 阅读模式：'scroll' | 'page'。
  final String readingMode;
  final bool immersiveMode;

  /// 翻页动画样式：'slide' | 'cover' | 'fade'。
  final String pageTurnMode;

  /// 音量键翻页：移动端将音量键映射为翻页命令，默认开启。
  final bool volumeKeyPaging;

  /// 跟随原书排版：书自己的样式表与内联 `style` 参与层叠，优先级低于用户在
  /// 本面板上拧过的项，高于阅读器默认档。默认关闭——刚定稿的样例排版是所有人的
  /// 起点，一本样式表写乱的书不该把已经读顺的版面顶掉。
  final bool followBookTypesetting;

  /// 移动壳层默认值：暗档正文改用样例的衬线 19/1.85。
  /// 桌面端与已保存偏好看不见此分支。落盘后不再重复套用，避免每次进书盖掉读者拧过的档位。
  final bool mobileDefaults;

  /// 两端对齐开关（对齐样例 `ReaderView.tsx` 的 `justify`）。
  ///
  /// 默认开启以保持既有正文版式：旧版本正文恒为两端对齐，改成默认关闭会让
  /// 所有未设置过的读者看到版式突变。
  final bool justify;

  /// 页边距档位：'narrow' | 'standard' | 'wide'。
  final String marginPreset;

  /// 阅读亮度（30..100，对齐样例 `prefs.bright`）。
  final int brightness;

  /// 护眼暖色强度（0..60，对齐样例 `prefs.warm`）。
  final int warmth;

  /// 夜间自动切换（20:00–06:00 自动切夜间主题，对齐样例 `prefs.autoNight`）。
  final bool autoNight;

  static bool isNightHour([DateTime? now]) {
    final h = (now ?? DateTime.now()).hour;
    return h >= 20 || h < 6;
  }

  ReaderViewSettings withMobileDefaults() {
    if (mobileDefaults || paletteId != ReaderReadingPalette.dark.id) {
      return this;
    }
    return copyWith(
      // ignore: font_size_whitelist
      fontSize: 19,
      lineHeight: 1.85,
      mobileDefaults: true,
    );
  }

  ReaderReadingPalette get palette =>
      autoNight && isNightHour()
          ? ReaderReadingPalette.dark
          : ReaderReadingPalette.fromId(paletteId);
  Color get paperEdgeColor => palette.paperEdge;
  Color get surfaceColor => palette.surface;
  Color get elevatedColor => palette.elevated;
  Color get onSurfaceColor => palette.onSurface;
  Color get onSurfaceVariantColor => palette.onSurfaceVariant;
  Color get faintColor => palette.faint;
  Color get lineColor => palette.line;
  Color get accentColor => palette.accent;
  Color get accentSoftColor => palette.accentSoft;
  Color get controlSurfaceColor => palette.controlSurface;
  Color get bookDeskColor => palette.bookDesk;
  Color get bookDeskTextColor => palette.bookDeskText;
  bool get usesBookDesk => readingMode == 'page' && pageTurnMode != 'slide';
  Color get readerCanvasColor => usesBookDesk ? bookDeskColor : surfaceColor;
  Color get glassColor => palette.glass;
  Color get glassSolidColor => palette.glassSolid;
  Color get shadowColor => palette.shadow;
  Color get selectionColor => palette.selection;
  bool get isDark => palette.id == ReaderReadingPalette.dark.id;

  String? get resolvedFontFamily =>
      fontFamily == 'serif' ? 'NotoSerifSC' : null;

  /// 正文字距相对字号的倍率，稿子 `.article-column > p` 的 `letter-spacing: .025em`。
  ///
  /// 正文样式、行内样式与分页测量的基准样式共用这一份：字距不同则同一串文字的
  /// 行宽不同，断页与字符偏移都会漂。
  static const double bodyLetterSpacingScale = 0.025;

  /// 正文样式：字距按稿子 `.article-column > p` 的 `letter-spacing: .025em`，
  /// 分页引擎的 `ReaderViewContent.spanStyle` 必须跟着同一份，否则测量与渲染
  /// 的行长不一致，断页会漂。
  TextStyle get bodyStyle => bodyStyleWith();

  /// 正文字体样式，按本书在这一段表达过的行高倍率放大行距。
  ///
  /// 绘制与测量都只能经由这里取行高：两侧各乘一份，同一块就会折出不同行数。
  TextStyle bodyStyleWith({double lineHeightScale = 1}) => TextStyle(
    fontFamily: resolvedFontFamily,
    // 无衬线正文可能遇到 GB2312 之外的生僻字：回落到保留全量的衬线字体，
    // 而不是依赖平台字体（Web 端没有稳定的系统中文字体）。
    fontFamilyFallback: AppTypography.fontFamilyFallback,
    fontSize: fontSize,
    height: lineHeight * lineHeightScale,
    letterSpacing: fontSize * bodyLetterSpacingScale,
    color: onSurfaceColor,
  );

  /// 分页测量用的正文基准样式。
  ///
  /// 直接由 [bodyStyle] 派生，只放大 fontSize：框架的 `TextStyle.getTextStyle`
  /// 对 textScaler 也只放大 fontSize（letterSpacing/wordSpacing 原样透传），
  /// 另写一份样式就会在系统字号缩放 ≠ 1 时与渲染折不同的行——而字距差每字不到
  /// 0.3px，行高容差测不出来，只能靠"两侧同一个表达式"封住。
  TextStyle measurementBaseStyle({
    double textScale = 1,
    double lineHeightScale = 1,
  }) => bodyStyleWith(
    lineHeightScale: lineHeightScale,
  ).copyWith(fontSize: fontSize * textScale);

  /// 返回与正文渲染及分页测量一致的行高约束。
  StrutStyle bodyStrutStyle({
    double textScale = 1,
    double lineHeightScale = 1,
  }) => StrutStyle(
    fontFamily: resolvedFontFamily,
    fontSize: fontSize * textScale,
    height: lineHeight * lineHeightScale,
    forceStrutHeight: true,
  );

  /// 引用块的文字样式：稿子是 `calc(+1px)` 字号与 `line-height: 1.75`。
  ///
  /// 与 [measurementBaseStyle]、[bodyStrutStyle] 一样必须**两侧同源**：绘制用 1.75 行高
  /// 而测量仍按正文行高折行时，引用块每页的行数会与装页算出的不一致，页底直接裁字。
  TextStyle blockquoteStyle({
    double textScale = 1,
    double lineHeightScale = 1,
  }) => bodyStyleWith(lineHeightScale: lineHeightScale).copyWith(
    fontSize: (fontSize + blockquoteFontDeltaPx) * textScale,
    height: blockquoteLineHeight * lineHeightScale,
  );

  /// 引用块行高约束，与 [blockquoteStyle] 同一份字号与行高。
  StrutStyle blockquoteStrutStyle({
    double textScale = 1,
    double lineHeightScale = 1,
  }) => StrutStyle(
    fontFamily: resolvedFontFamily,
    fontSize: (fontSize + blockquoteFontDeltaPx) * textScale,
    height: blockquoteLineHeight * lineHeightScale,
    forceStrutHeight: true,
  );

  /// 稿子 `.article-column blockquote` 的字色：`color-mix(in srgb, ink 84%, accent)`。
  Color get quoteTextColor =>
      Color.lerp(onSurfaceColor, accentColor, 0.16) ?? onSurfaceColor;

  /// 章序标签（稿子 `.chapter-kicker`）：11px、700 字重、`.24em` 字距、强调色。
  ///
  /// 它是翻页页头那行章名，不是正文块：章序只进 chrome，不往正文里注入合成文本，
  /// 所以不进字符域、不参与装页预算。
  static const double chapterKickerFontSize = 11.0;
  static const double chapterKickerLetterSpacingScale = 0.24;

  /// 标签字色：稿子的 `--accent` 压在米黄（`eyeCare`）与葱绿（`green`）纸底上只有
  /// 4.1–4.2:1，不到正文 AA 的 4.5。按稿子自己对引用块的写法把强调色往墨色折，
  /// 折比从 20% 起按 5% 递增到实际达标，色板换值后仍由对比度不变量兜底
  /// （reader_reading_palette_test 把关）。
  Color get chapterKintColor {
    var mix = 0.2;
    while (mix < 0.95 &&
        _contrastRatio(
              Color.lerp(accentColor, onSurfaceColor, mix) ?? onSurfaceColor,
              surfaceColor,
            ) <
            4.5) {
      mix += 0.05;
    }
    return Color.lerp(accentColor, onSurfaceColor, mix.clamp(0.0, 1.0)) ??
        accentColor;
  }

  static double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  TextStyle chapterKickerStyle() => TextStyle(
    fontSize: chapterKickerFontSize,
    color: chapterKintColor,
    fontWeight: FontWeight.w700,
    letterSpacing: chapterKickerFontSize * chapterKickerLetterSpacingScale,
    height: 1.4,
  );

  ReaderViewSettings copyWith({
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    String? paletteId,
    int? themeIndex,
    String? readingMode,
    bool? immersiveMode,
    String? pageTurnMode,
    bool? volumeKeyPaging,
    bool? followBookTypesetting,
    bool? mobileDefaults,
    bool? justify,
    String? marginPreset,
    int? brightness,
    int? warmth,
    bool? autoNight,
  }) {
    return ReaderViewSettings(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      paletteId:
          paletteId ??
          (themeIndex == null
              ? this.paletteId
              : ReaderReadingPalette.idFromLegacyIndex(themeIndex)),
      readingMode: readingMode ?? this.readingMode,
      immersiveMode: immersiveMode ?? this.immersiveMode,
      pageTurnMode: pageTurnMode ?? this.pageTurnMode,
      volumeKeyPaging: volumeKeyPaging ?? this.volumeKeyPaging,
      followBookTypesetting:
          followBookTypesetting ?? this.followBookTypesetting,
      mobileDefaults: mobileDefaults ?? this.mobileDefaults,
      justify: justify ?? this.justify,
      marginPreset: marginPreset ?? this.marginPreset,
      brightness: (brightness ?? this.brightness).clamp(30, 100),
      warmth: (warmth ?? this.warmth).clamp(0, 60),
      autoNight: autoNight ?? this.autoNight,
    );
  }

  /// 在翻页与滚动之间切换阅读模式。
  ///
  /// 正文阅读器与漫画阅读器共用这一条判据，避免快捷键在某一侧退化成静默空实现。
  ReaderViewSettings withReadingModeToggled() {
    return copyWith(readingMode: readingMode == 'page' ? 'scroll' : 'page');
  }

  /// 按字段值比较，而不是对象身份。
  ///
  /// 排版测量缓存以本对象为键：父组件每次 `build` 都可能 `copyWith` 出内容完全
  /// 相同的新实例，身份比较会让 64 条视觉行缓存整批失效、每帧重跑 TextPainter。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ReaderViewSettings &&
        other.fontFamily == fontFamily &&
        other.fontSize == fontSize &&
        other.lineHeight == lineHeight &&
        other.paletteId == paletteId &&
        other.readingMode == readingMode &&
        other.immersiveMode == immersiveMode &&
        other.pageTurnMode == pageTurnMode &&
        other.volumeKeyPaging == volumeKeyPaging &&
        other.followBookTypesetting == followBookTypesetting &&
        other.mobileDefaults == mobileDefaults &&
        other.justify == justify &&
        other.marginPreset == marginPreset &&
        other.brightness == brightness &&
        other.warmth == warmth &&
        other.autoNight == autoNight;
  }

  @override
  int get hashCode => Object.hash(
    fontFamily,
    fontSize,
    lineHeight,
    paletteId,
    readingMode,
    immersiveMode,
    pageTurnMode,
    volumeKeyPaging,
    followBookTypesetting,
    mobileDefaults,
    justify,
    marginPreset,
    brightness,
    warmth,
    autoNight,
  );

  Map<String, dynamic> toJson() => {
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'paletteId': paletteId,
    'themeIndex': themeIndex,
    'readingMode': readingMode,
    'immersiveMode': immersiveMode,
    'pageTurnMode': pageTurnMode,
    'volumeKeyPaging': volumeKeyPaging,
    'followBookTypesetting': followBookTypesetting,
    'mobileDefaults': mobileDefaults,
    'justify': justify,
    'marginPreset': marginPreset,
    'brightness': brightness,
    'warmth': warmth,
    'autoNight': autoNight,
    'version': _settingsVersion,
  };

  factory ReaderViewSettings.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 0;
    // 版本迁移：逐步升级旧版本数据到最新结构
    var migrated = Map<String, dynamic>.from(json);
    if (version < 1) {
      // v0 → v1：新增 immersiveMode 字段，使用默认值
      migrated['immersiveMode'] ??= false;
    }
    if (version < 3) {
      // v1/v2 → v3：pageTransition 重命名为 pageTurnMode，移除 scroll 值
      final oldTransition = migrated.remove('pageTransition') as String?;
      if (oldTransition != null && oldTransition != 'scroll') {
        migrated['pageTurnMode'] = oldTransition;
      }
      migrated.remove('pageTransition');
    }
    if (version < 4) {
      final legacyThemeIndex = migrated['themeIndex'] as int? ?? 2;
      migrated['paletteId'] = ReaderReadingPalette.idFromLegacyIndex(
        legacyThemeIndex,
      );
    }
    if (version < 5) {
      // v4 → v5：新增 volumeKeyPaging 字段，默认开启
      migrated['volumeKeyPaging'] ??= true;
    }
    if (version < 6) {
      // v5 → v6：新增 followBookTypesetting，默认不跟随原书
      migrated['followBookTypesetting'] ??= false;
    }
    if (version < 7) {
      // v6 → v7：新增 mobileDefaults 标记，旧偏好视为未套用移动壳层默认
      migrated['mobileDefaults'] ??= false;
    }
    if (version < 8) {
      // v7 → v8：新增对齐、页边距、亮度、护眼暖色与自动夜间字段
      migrated['justify'] ??= true;
      migrated['marginPreset'] ??= 'standard';
      migrated['brightness'] ??= 100;
      migrated['warmth'] ??= 0;
      migrated['autoNight'] ??= false;
    }

    final rawFontSize = (migrated['fontSize'] as num?)?.toDouble() ?? 18.0;
    final rawLineHeight = (migrated['lineHeight'] as num?)?.toDouble() ?? 1.8;
    final rawPaletteId = migrated['paletteId'] as String? ?? 'dark';
    final rawFontFamily = migrated['fontFamily'] as String? ?? 'serif';
    const allowedFonts = ['serif', 'sans', 'system'];
    const allowedTurnModes = ['slide', 'cover', 'fade'];
    const allowedMargins = ['narrow', 'standard', 'wide'];
    final rawTurnMode = migrated['pageTurnMode'] as String? ?? 'slide';
    final rawMargin = migrated['marginPreset'] as String? ?? 'standard';
    return ReaderViewSettings(
      fontFamily:
          allowedFonts.contains(rawFontFamily) ? rawFontFamily : 'serif',
      fontSize: rawFontSize.clamp(12.0, 32.0),
      lineHeight: rawLineHeight.clamp(1.0, 3.0),
      paletteId: ReaderReadingPalette.fromId(rawPaletteId).id,
      readingMode:
          supportsPageMode
              ? (migrated['readingMode'] as String? ?? 'scroll')
              : 'scroll',
      immersiveMode: migrated['immersiveMode'] as bool? ?? false,
      pageTurnMode:
          allowedTurnModes.contains(rawTurnMode) ? rawTurnMode : 'slide',
      volumeKeyPaging: migrated['volumeKeyPaging'] as bool? ?? true,
      followBookTypesetting:
          migrated['followBookTypesetting'] as bool? ?? false,
      mobileDefaults: migrated['mobileDefaults'] as bool? ?? false,
      justify: migrated['justify'] as bool? ?? false,
      marginPreset: allowedMargins.contains(rawMargin) ? rawMargin : 'standard',
      brightness: ((migrated['brightness'] as num?)?.round() ?? 100).clamp(
        30,
        100,
      ),
      warmth: ((migrated['warmth'] as num?)?.round() ?? 0).clamp(0, 60),
      autoNight: migrated['autoNight'] as bool? ?? false,
    );
  }

  static const _settingsVersion = 8;

  /// 段落首行缩进的字数：跟随原书且书表达过时按书的，否则用阅读器默认档。
  ///
  /// 测量与绘制都只能经由这里取缩进，两侧各算一份会让同一块按两种宽度折行。
  int firstLineIndentChars(ParagraphStyleSpec? bookStyle) {
    final expressed = bookStyle?.firstLineIndentChars;
    if (followBookTypesetting && expressed != null) return expressed;
    return defaultFirstLineIndentChars;
  }

  /// 首行缩进盒子的宽度（逻辑像素）。
  ///
  /// 缩进由定宽 WidgetSpan 表达，不再由全角空格的字宽决定：CJK 下两个字宽必须
  /// 量出来，而两端对齐会把行首空白折成零宽。测量侧的 textScale 与绘制侧继承的
  /// 环境缩放同源，两侧只能经由这里换算，各算一份会让同一块折出不同行数。
  double indentBoxWidth({
    required int indentChars,
    bool blockquote = false,
    double textScale = 1,
  }) {
    if (indentChars <= 0) {
      return 0;
    }
    return baseFontSize(blockquote: blockquote) * textScale * indentChars;
  }

  /// 「跟随书籍样式」打开时，本书在这一段表达过的行高倍率。
  ///
  /// 读者的行距设置不能被书顶掉，只能在读者的行距之上再乘这一份；开关关闭时
  /// 恒为 1，块级的 `lineHeightScale` 一寸都不参与。
  double lineHeightScaleFor(ParagraphStyleSpec? bookStyle) =>
      followBookTypesetting ? (bookStyle?.lineHeightScale ?? 1.0) : 1.0;

  /// 正文与引用块的有效基准字号（未叠加环境缩放）。
  double baseFontSize({bool blockquote = false}) =>
      blockquote ? fontSize + blockquoteFontDeltaPx : fontSize;

  /// 段落尾间距相对字号的倍率，0 表示这一块不加间距。
  ///
  /// 跟随原书时按两档书的表达取：`margin-bottom` 倍率、源文本空白行折出的留白，
  /// 同一处只花一份（取较大者，口径同解析期的 margin 折叠）；书的段距优先，因为这类书
  /// 就是靠段距分段，读者侧的 `<br><br>` 信号本来不该参与。两者都没有才回到阅读器档：
  /// 有 `<br><br>` 信号用默认倍率，否则 0，段落只靠首行缩进区分。
  ///
  /// 测量、装页与渲染三处都只能经由这里取值：各写一份时同一块会在两侧加上不同的间距，
  /// 页底与条目确定高度都按短了的那份算。
  double paragraphSpacingScaleFor({
    required ParagraphStyleSpec? bookStyle,
    required bool hasTrailingSpacing,
  }) {
    final expressed = bookStyle?.paragraphSpacingScale;
    final blankGap = _blankLineSpacingScale(bookStyle);
    if (followBookTypesetting) {
      if (expressed != null) {
        return blankGap > expressed ? blankGap : expressed;
      }
      if (blankGap > 0) return blankGap;
    }
    return hasTrailingSpacing ? defaultParagraphSpacingScale : 0.0;
  }

  /// 源文本空行折出的段距倍率：一行白算读者的一个行高，最多 [maxBlankLineGapLines] 行。
  ///
  /// 关掉开关恒为 0——默认档不因为一本书用不用空行分段而改变它看到的留白。
  double _blankLineSpacingScale(ParagraphStyleSpec? bookStyle) {
    if (!followBookTypesetting) return 0.0;
    final gapLines = bookStyle?.paragraphBlankGapLines ?? 0;
    if (gapLines <= 0) return 0.0;
    final capped =
        gapLines > maxBlankLineGapLines ? maxBlankLineGapLines : gapLines;
    return capped * lineHeight;
  }

  /// 段落对齐方式：受 justify 开关控制；跟随原书排版且书表达过时优先按原书。
  TextAlign paragraphAlign(ParagraphStyleSpec? bookStyle) {
    final expressed = bookStyle?.textAlign;
    if (followBookTypesetting && expressed != null) return expressed;
    return justify ? TextAlign.justify : TextAlign.start;
  }

  /// 引用块的对齐：只在跟随原书且书表达过时采纳，否则维持现状的起始对齐。
  ///
  /// 不能复用 [paragraphAlign]——正文默认两端对齐，引用块一直是起始对齐，
  /// 借用会把关掉开关的读者也改掉。null 交给 RenderParagraph 按文字方向取值。
  TextAlign? blockquoteAlign(ParagraphStyleSpec? bookStyle) {
    return followBookTypesetting ? bookStyle?.textAlign : null;
  }

  /// 标题的对齐：这本书在这个 `h*` 上写过（或从祖先继承到）才接管。
  ///
  /// 与 [blockquoteAlign] 同一口径：关掉开关时返回 null，条目仍按文字方向取起始侧，
  /// 版面一寸不动。居中是中文书页码标题最常见的版式，丢掉它等于开关对标题无效。
  TextAlign? headingAlign(TextAlign? bookAlign) {
    return followBookTypesetting ? bookAlign : null;
  }
}
