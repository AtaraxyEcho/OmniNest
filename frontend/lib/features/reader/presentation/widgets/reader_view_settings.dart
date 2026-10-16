import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_stylesheet.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/platform/platform_capabilities.dart';

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
  /// 桌面端与已保存偏好看不见此分支。
  final bool mobileDefaults;

  ReaderViewSettings withMobileDefaults() {
    if (mobileDefaults || paletteId != ReaderReadingPalette.dark.id) {
      return this;
    }
    return copyWith(
      // ignore: font_size_whitelist
      fontSize: 19,
      lineHeight: 1.85,
    );
  }

  ReaderReadingPalette get palette => ReaderReadingPalette.fromId(paletteId);
  Color get surfaceColor => palette.surface;
  Color get elevatedColor => palette.elevated;
  Color get onSurfaceColor => palette.onSurface;
  Color get onSurfaceVariantColor => palette.onSurfaceVariant;
  Color get faintColor => palette.faint;
  Color get lineColor => palette.line;
  Color get accentColor => palette.accent;
  Color get accentSoftColor => palette.accentSoft;
  Color get controlSurfaceColor => palette.controlSurface;
  Color get glassColor => palette.glass;
  Color get glassSolidColor => palette.glassSolid;
  Color get shadowColor => palette.shadow;
  Color get selectionColor => palette.selection;
  bool get isDark => paletteId == ReaderReadingPalette.dark.id;

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
  /// 4.1–4.2:1，不到正文 AA 的 4.5。按稿子自己对引用块的写法把强调色往墨色折
  /// 20%，四档纸底下都过 4.5（reader_reading_palette_test 把关）。
  Color get chapterKintColor =>
      Color.lerp(accentColor, onSurfaceColor, 0.2) ?? accentColor;

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
    );
  }

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

    final rawFontSize = (migrated['fontSize'] as num?)?.toDouble() ?? 18.0;
    final rawLineHeight = (migrated['lineHeight'] as num?)?.toDouble() ?? 1.8;
    final rawPaletteId = migrated['paletteId'] as String? ?? 'dark';
    final rawFontFamily = migrated['fontFamily'] as String? ?? 'serif';
    const allowedFonts = ['serif', 'sans', 'system'];
    const allowedTurnModes = ['slide', 'cover', 'fade'];
    final rawTurnMode = migrated['pageTurnMode'] as String? ?? 'slide';
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
    );
  }

  static const _settingsVersion = 6;

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

  /// 段落对齐方式。书没表达时沿用稿子的两端对齐。
  TextAlign paragraphAlign(ParagraphStyleSpec? bookStyle) {
    final expressed = bookStyle?.textAlign;
    if (followBookTypesetting && expressed != null) return expressed;
    return TextAlign.justify;
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

class ReaderViewSettingsPanel extends StatelessWidget {
  const ReaderViewSettingsPanel({
    required this.settings,
    required this.onSettingsChanged,
    this.pageModeEnabled,
    this.mobile = false,
    super.key,
  });

  final ReaderViewSettings settings;
  final ValueChanged<ReaderViewSettings> onSettingsChanged;

  /// 是否提供翻页模式；null 时跟随 [supportsPageMode]（Web 恒 false）。
  final bool? pageModeEnabled;

  /// 移动壳层：开关换成样例 .env-switch 胶囊，整行作为点按目标。
  /// 工位皮肤保持直角开关，两种形态不共用一套几何。
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final showPageMode = pageModeEnabled ?? supportsPageMode;
    final showPageTurn = showPageMode && settings.readingMode == 'page';
    final l10n = AppLocalizations.of(context);
    // 稿子 `.sheet-appearance` 的分区顺序与分隔：阅读方式 → 字号 → 字体+行距 →
    // 阅读背景，每段 `.setting-section` 上沿一条 --line 发丝线，首段不画。
    // 音量键翻页是本产品特有开关（稿子没有键盘控件），排在最后同一段式。
    // 沉浸模式不再出现在设置里：chrome 的显隐由点按正文控制，页脚已有开关。
    final sections = <Widget>[
      if (showPageMode)
        _SettingSection(
          settings: settings,
          first: true,
          label: l10n.readerReadingMode,
          value:
              settings.readingMode == 'scroll'
                  ? l10n.readerModeScroll
                  : l10n.readerModePage,
          child: _SampleSegmented(
            settings: settings,
            labels: [l10n.readerModeScroll, l10n.readerModePage],
            selectedIndex: settings.readingMode == 'scroll' ? 0 : 1,
            onChanged:
                (index) => onSettingsChanged(
                  settings.copyWith(
                    readingMode: index == 0 ? 'scroll' : 'page',
                  ),
                ),
          ),
        ),
      if (showPageTurn)
        _SettingSection(
          settings: settings,
          first: !showPageMode,
          label: l10n.readerPageTransition,
          child: _SampleSegmented(
            settings: settings,
            labels: [
              l10n.readerTransitionSlide,
              l10n.readerTransitionCover,
              l10n.readerTransitionFade,
            ],
            selectedIndex: const [
              'slide',
              'cover',
              'fade',
            ].indexOf(settings.pageTurnMode),
            onChanged:
                (index) => onSettingsChanged(
                  settings.copyWith(
                    pageTurnMode: const ['slide', 'cover', 'fade'][index],
                  ),
                ),
          ),
        ),
      _SettingSection(
        settings: settings,
        label: l10n.readerFontSize,
        value: '${settings.fontSize.round()}px',
        child: _FontSizeRange(
          settings: settings,
          value: settings.fontSize,
          onChanged: (v) => onSettingsChanged(settings.copyWith(fontSize: v)),
        ),
      ),
      _SettingSection(
        settings: settings,
        // 稿子把字体与行距并排放在 `.setting-grid`（0.82fr / 1.18fr，间隙 12）。
        child: _FontAndLineHeightGrid(
          settings: settings,
          onSettingsChanged: onSettingsChanged,
        ),
      ),
      _buildThemeSection(context, l10n),
      _SettingSection(
        settings: settings,
        label: l10n.readerFollowBookTypesetting,
        // 开关名比它的实际作用域宽（只管缩进·段距·对齐，字号字体行距恒归读者），
        // 说明放在段名下而不是开关行里：移动态整行 excludeSemantics，
        // 挂在行内会被读屏吞掉，作为段的兄弟节点才念得到。
        hint: l10n.readerFollowBookTypesettingHint,
        child: _buildFollowBookTypesettingRow(context, l10n),
      ),
      if (PlatformCapabilities.current().supportsVolumeKeyPageTurn)
        _SettingSection(
          settings: settings,
          label: l10n.readerVolumeKeyPaging,
          child: _buildVolumeKeyPagingRow(context, l10n),
        ),
    ];
    // 稿子 `.sheet-appearance`：段与段自带发丝线，尾部留 safe-bottom + 14。
    // 抽屉外壳由 ReaderAdaptivePanelFrame 画，这里只交滚动本体。
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections,
      ),
    );
  }

  static String _themeName(AppLocalizations l10n, int index) {
    return switch (index) {
      0 => l10n.readerThemeLight,
      1 => l10n.readerThemeEyeCare,
      2 => l10n.readerThemeDark,
      _ => l10n.readerThemeGreen,
    };
  }

  Widget _buildThemeSection(BuildContext context, AppLocalizations l10n) {
    // 稿子 `.theme-picker` 没有固定高：色板 48 + 间隙 6 + 9px 档名，四格等高
    // 由结构保证，写死 66 会在档名行高变化时溢出 1px。
    return _SettingSection(
      settings: settings,
      label: l10n.readerTheme,
      child: Row(
        children: List.generate(ReaderReadingPalette.values.length, (i) {
          final theme = ReaderReadingPalette.values[i];
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == 3 ? 0 : 10),
              child: _ThemeOption(
                theme: theme,
                localizedName: _themeName(l10n, i),
                selected: settings.themeIndex == i,
                // 稿子的档名恒为 --muted，选中只靠描边与光环；这里额外把
                // 当前档名转强调色，是给色弱用户的第二通道（光环是纯亮度差）。
                labelColor:
                    settings.themeIndex == i
                        ? settings.accentColor
                        : settings.onSurfaceVariantColor,
                onTap:
                    () => onSettingsChanged(settings.copyWith(themeIndex: i)),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// 跟随原书排版开关：书的样式表与内联 `style` 参与层叠。
  Widget _buildFollowBookTypesettingRow(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return _buildToggleRow(
      context,
      icon: Icons.format_size_rounded,
      label: l10n.readerFollowBookTypesetting,
      value: settings.followBookTypesetting,
      onChanged:
          (v) => onSettingsChanged(settings.copyWith(followBookTypesetting: v)),
    );
  }

  Widget _buildVolumeKeyPagingRow(BuildContext context, AppLocalizations l10n) {
    return _buildToggleRow(
      context,
      icon: Icons.volume_up_rounded,
      label: l10n.readerVolumeKeyPaging,
      value: settings.volumeKeyPaging,
      onChanged:
          (v) => onSettingsChanged(settings.copyWith(volumeKeyPaging: v)),
    );
  }

  /// 开关行：工位保持直角开关；移动壳层换成样例胶囊，并把整行做成点按目标
  /// （胶囊本体 34×20，低于次级控件触控下限）。
  Widget _buildToggleRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final children = <Widget>[
      Icon(icon, color: settings.onSurfaceVariantColor, size: 20),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: settings.onSurfaceVariantColor,
            fontSize: AppTypography.bodyMedium,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      _buildToggleSwitch(value, onChanged),
    ];
    if (!mobile) {
      return Row(children: children);
    }
    // excludeSemantics：行内胶囊自带 button+toggled 节点，不屏蔽会念两遍。
    return Semantics(
      button: true,
      toggled: value,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(children: children),
        ),
      ),
    );
  }

  Widget _buildToggleSwitch(bool value, ValueChanged<bool> onChanged) {
    return ReaderToggleSwitch(
      settings: settings,
      mobile: mobile,
      value: value,
      onChanged: onChanged,
    );
  }
}

/// 阅读设置里的开关：工位保持直角开关，移动壳层换成样例 .env-switch 胶囊。
///
/// 颜色全部来自阅读调色板（面板底与正文色由用户选的调色板决定），
/// 不跟全局极性表，否则浅色纸面 + 深色环境会配出看不见的旋钮。
class ReaderToggleSwitch extends StatelessWidget {
  const ReaderToggleSwitch({
    required this.settings,
    required this.mobile,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final ReaderViewSettings settings;
  final bool mobile;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (!mobile) {
      return WorkstationSwitch(value: value, onChanged: onChanged);
    }
    // 样例 .env-switch：轨道是面板上的墨色低透明档，开=强调色；
    // 旋钮与所在面反相——强调色亮时用画布色，面板亮时用近白 + 投影。
    final lightPanel = settings.controlSurfaceColor.computeLuminance() > 0.5;
    return MobilePillSwitch(
      value: value,
      onChanged: onChanged,
      trackOn: settings.accentColor,
      trackOff: settings.onSurfaceColor.withValues(alpha: 0.16),
      knobOn: settings.surfaceColor,
      knobOff: lightPanel ? const Color(0xFFFFFFFF) : const Color(0xFFF6F6F2),
      knobShadow: lightPanel ? _lightPanelKnobShadow : null,
    );
  }
}

/// 样例浅态 `.env-switch::after` 的旋钮投影：`0 1px 3px rgba(26,29,27,.25)`。
const List<BoxShadow> _lightPanelKnobShadow = [
  BoxShadow(color: Color(0x401A1D1B), offset: Offset(0, 1), blurRadius: 3),
];

/// 稿子 `.setting-section`：上下 14/16 内边距，段间一条 --line 发丝线，首段不画。
/// 标签行 `.setting-label`：11/600 段名在左，强调色 10px 当前值在右，下沿 11 间隙。
class _SettingSection extends StatelessWidget {
  const _SettingSection({
    required this.settings,
    required this.child,
    this.label,
    this.value,
    this.hint,
    this.first = false,
  });

  final ReaderViewSettings settings;
  final Widget child;
  final String? label;
  final String? value;

  /// 段名之下的一行作用域说明：只给"名字比实际作用域宽"的项用。
  final String? hint;

  /// 稿子 `.setting-section:first-of-type { border-top: 0 }`。
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration:
          first
              ? null
              : BoxDecoration(
                border: Border(top: BorderSide(color: settings.lineColor)),
              ),
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: EdgeInsets.only(bottom: hint == null ? 11 : 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label!,
                      style: TextStyle(
                        color: settings.onSurfaceColor,
                        fontSize: AppTypography.labelSmall,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (value != null)
                    Text(
                      value!,
                      style: TextStyle(
                        color: settings.accentColor,
                        fontSize: AppTypography.labelMicro,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Text(
                hint!,
                style: TextStyle(
                  color: settings.onSurfaceVariantColor,
                  fontSize: AppTypography.labelMicro,
                  height: 1.35,
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// 稿子 `.segmented`：3 内边距、3 间隙、r13 槽底（墨色 6%）；
/// 选项 38 高、r10、10px，选中面换成纸面并加 0 3 10 投影。
/// `.setting-grid .segmented button` 再收一档：padding 0 5、9px。
class _SampleSegmented extends StatelessWidget {
  const _SampleSegmented({
    required this.settings,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.dense = false,
  });

  final ReaderViewSettings settings;
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: settings.onSurfaceColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: _SegmentOption(
                label: labels[i],
                selected: i == selectedIndex,
                settings: settings,
                dense: dense,
                onTap: () => onChanged(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentOption extends StatelessWidget {
  const _SegmentOption({
    required this.label,
    required this.selected,
    required this.settings,
    required this.onTap,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final ReaderViewSettings settings;
  final VoidCallback onTap;

  /// 稿子 `.setting-grid .segmented button`：格子挤，字号与横向 padding 各降一档。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 38),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: dense ? 5 : 8),
          decoration: BoxDecoration(
            color: selected ? settings.elevatedColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow:
                selected
                    ? [
                      BoxShadow(
                        color: settings.shadowColor.withValues(alpha: 0.48),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                    : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  selected
                      ? settings.onSurfaceColor
                      : settings.onSurfaceVariantColor,
              fontSize:
                  dense ? AppTypography.labelNano : AppTypography.labelMicro,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// 稿子 `.range-control`：`32px 1fr 32px` 三列，两端是 13px 与 21px 衬线的大 A，
/// 中间滑杆取强调色；字号档位 16..26，默认 19。
class _FontSizeRange extends StatelessWidget {
  const _FontSizeRange({
    required this.settings,
    required this.value,
    required this.onChanged,
  });

  final ReaderViewSettings settings;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    // 存档允许 12..32，稿子滑杆只有 16..26：越界的历史值按端点显示，
    // 用户一动滑杆就回到稿子档位。
    final clamped = value.clamp(16.0, 26.0);
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            'A',
            textAlign: TextAlign.center,
            style: TextStyle(
              // 稿子 `.range-control > span` 两端都是衬线，只是 13 与 21 两档。
              fontFamily: AppTypography.serifFamily,
              fontFamilyFallback: AppTypography.serifFamilyFallback,
              color: settings.onSurfaceVariantColor,
              fontSize: AppTypography.bodyMedium,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: settings.accentColor,
              inactiveTrackColor: settings.onSurfaceColor.withValues(
                alpha: 0.12,
              ),
              thumbColor: settings.accentColor,
              overlayColor: settings.accentColor.withValues(alpha: 0.18),
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
            ),
            child: AppSlider(
              value: clamped,
              min: 16,
              max: 26,
              divisions: 10,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 32,
          child: Text(
            'A',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTypography.serifFamily,
              fontFamilyFallback: AppTypography.serifFamilyFallback,
              color: settings.onSurfaceColor,
              // 稿子 `.range-control strong` 就是 21px 衬线大 A。
              fontSize: 21, // ignore: font_size_whitelist
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// 稿子 `.setting-grid`：字体占 0.82 份、行距占 1.18 份并排，间隙 12，
/// 各自的标签高 17。行距是三档分段（1.6 / 1.85 / 2.1）。
class _FontAndLineHeightGrid extends StatelessWidget {
  const _FontAndLineHeightGrid({
    required this.settings,
    required this.onSettingsChanged,
  });

  final ReaderViewSettings settings;
  final ValueChanged<ReaderViewSettings> onSettingsChanged;

  static const List<double> _lineHeights = <double>[1.6, 1.85, 2.1];
  static const List<String> _familyValues = <String>['serif', 'sans', 'system'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 存档里可能是三档之外的旧值（例如 1.7）：按最近的一档显示选中，
    // 点选即归到稿子档位。
    var nearest = 0;
    for (var i = 1; i < _lineHeights.length; i++) {
      if ((settings.lineHeight - _lineHeights[i]).abs() <
          (settings.lineHeight - _lineHeights[nearest]).abs()) {
        nearest = i;
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 82,
          child: _GridField(
            settings: settings,
            label: l10n.readerFontFamily,
            child: _SampleSegmented(
              settings: settings,
              dense: true,
              labels: [
                l10n.readerFontSerif,
                l10n.readerFontSans,
                l10n.readerFontSystem,
              ],
              selectedIndex: _familyValues.indexOf(settings.fontFamily),
              onChanged:
                  (index) => onSettingsChanged(
                    settings.copyWith(fontFamily: _familyValues[index]),
                  ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 118,
          child: _GridField(
            settings: settings,
            label: l10n.readerLineHeight,
            child: _SampleSegmented(
              settings: settings,
              dense: true,
              labels: const ['1.6', '1.85', '2.1'],
              selectedIndex: nearest,
              onChanged:
                  (index) => onSettingsChanged(
                    settings.copyWith(lineHeight: _lineHeights[index]),
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GridField extends StatelessWidget {
  const _GridField({
    required this.settings,
    required this.label,
    required this.child,
  });

  final ReaderViewSettings settings;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 17,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: settings.onSurfaceColor,
              fontSize: AppTypography.labelSmall,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 11),
        child,
      ],
    );
  }
}

/// 稿子 `.theme-dot`：色板占满等分格、48 高、r13、1px --line；选中换成 2px
/// 强调色描边并外加 3px 强调软底光环，格内一枚 16 的勾，标签 9px。
class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.theme,
    required this.localizedName,
    required this.selected,
    required this.labelColor,
    required this.onTap,
  });

  final ReaderReadingPalette theme;
  final String localizedName;
  final bool selected;
  final Color labelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: localizedName,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 48,
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  // 稿子 `.theme-dot > span` 未选中用该档自己的 --line 描边，
                  // 色板是预览另一档纸面，不能借当前档的线色。
                  color: selected ? theme.accent : theme.line,
                  width: selected ? 2 : 1,
                ),
                boxShadow:
                    selected
                        ? [BoxShadow(color: theme.accentSoft, spreadRadius: 3)]
                        : null,
              ),
              child:
                  selected
                      ? Center(
                        child: Icon(
                          Icons.check_rounded,
                          color: theme.accent,
                          size: 16,
                        ),
                      )
                      : null,
            ),
            const SizedBox(height: 6),
            Text(
              localizedName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: labelColor,
                fontSize: AppTypography.labelNano,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
