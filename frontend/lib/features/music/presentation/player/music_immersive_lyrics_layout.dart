part of 'music_immersive_lyrics.dart';

/// 字号下限/上限（px）：px 即最终字号，不再乘设备 scale。
const double _minLyricFontSizePx = 12;
const double _maxLyricFontSizePx = 48;

/// 行内文本行高倍数：三端一致，不随设置变化。
const double _lyricLineHeight = 1.18;

/// 翻译行字号比例、行高倍数与与原文的间距。
const double _translationFontScale = 0.62;
const double _translationLineHeight = 1.2;
const double _translationGap = 4;

/// 歌词排版度量器：实测整块宽度、最大折行数并缓存，行槽高度据此预留。
///
/// 桌面滚动歌词要求"文字居左、整块居中"：各行必须按同一宽度渲染才能共享
/// 同一侧基线，而列表是懒加载的（无法用 IntrinsicWidth 跨行测量），只能实测
/// 最宽一行。折行数用于行槽高度——行槽等高，必须按最坏一行预留。
/// 度量按词表实例 + 字号 + 可用宽度为缓存键，曲目或设置变化才重算。
class _MusicLyricsLayout {
  Object? _metricsKey;
  double? _blockWidthValue;
  int _maxTextLines = 1;
  int _maxTranslationLines = 1;

  /// 统一块宽：滚动形态返回实测值（含 1px 舍入保护），其余返回 null
  /// （各行按内容收窄）。
  double? get blockWidth => _blockWidthValue;

  /// 全部歌词按基准字号渲染时的最大折行数（含测量上限截断）。
  int get maxTextLines => _maxTextLines;

  /// 译文行的最大折行数。
  int get maxTranslationLines => _maxTranslationLines;

  /// 测量词表排版：整块宽度、逐行宽度与最大折行数，命中缓存时跳过。
  void syncMetrics({
    required List<MusicLyricLine> lyrics,
    required double availableWidth,
    required bool scrollMode,
    required int fontSizePx,
    required int currentFontSizePx,
    required TextDirection textDirection,
    required TextStyle ambientStyle,
    required TextScaler textScaler,
    MusicLyricSpec? spec,
  }) {
    if (!availableWidth.isFinite || availableWidth <= 0) {
      return;
    }
    // 滚动歌词按统一块宽渲染：居中时块居中、居左/居右时贴对应边缘，
    // 三种锚点下各行都共享同一侧基线（居中锚点的文本仍按宿主排列）。
    final key = (
      lyrics: lyrics,
      availableWidth: availableWidth,
      scrollMode: scrollMode,
      fontSizePx: fontSizePx,
      currentFontSizePx: currentFontSizePx,
      ambientStyle: ambientStyle,
      textScaler: textScaler,
      spec: spec,
    );
    if (key == _metricsKey) {
      return;
    }
    final baseFont =
        spec?.fontSize ??
        _fontPx(
          fontSizePx,
          currentFontSizePx,
          active: false,
          scrollMode: scrollMode,
        );
    final activeFont =
        spec?.activeFontSize ??
        _fontPx(
          fontSizePx,
          currentFontSizePx,
          active: true,
          scrollMode: scrollMode,
        );
    final baseHeight = spec?.lineHeight ?? _lyricLineHeight;
    final activeHeight = spec?.activeLineHeight ?? _lyricLineHeight;
    final translationFont =
        spec?.translationFontSize ?? baseFont * _translationFontScale;
    final translationHeight =
        spec?.translationLineHeight ?? _translationLineHeight;
    var widest = 0.0;
    var maxLines = 1;
    var maxTranslationLineCount = 1;
    for (final line in lyrics) {
      // 逐行按最宽字重测量：滚动形态在读行是 w800、其余 w500，
      // 取两者较大值可同时覆盖填充遮罩的实测边界。
      final measurements = <(double, int)>[
        _measureText(
          line.text,
          fontSize: baseFont,
          fontWeight: spec?.fontWeight ?? FontWeight.w800,
          maxWidth: availableWidth,
          textDirection: textDirection,
          ambientStyle: ambientStyle,
          textScaler: textScaler,
          height: baseHeight,
        ),
        if (spec == null)
          _measureText(
            line.text,
            fontSize: baseFont,
            fontWeight: FontWeight.w500,
            maxWidth: availableWidth,
            textDirection: textDirection,
            ambientStyle: ambientStyle,
            textScaler: textScaler,
            height: baseHeight,
          ),
        if (activeFont != baseFont)
          _measureText(
            line.text,
            fontSize: activeFont,
            fontWeight: spec?.activeFontWeight ?? FontWeight.w800,
            maxWidth: availableWidth,
            textDirection: textDirection,
            ambientStyle: ambientStyle,
            textScaler: textScaler,
            height: activeHeight,
          ),
      ];
      var mainWidth = 0.0;
      for (final (width, lines) in measurements) {
        mainWidth = math.max(mainWidth, width);
        maxLines = math.max(maxLines, lines);
      }
      final translation = line.translation?.trim();
      var translationWidth = 0.0;
      if (translation != null && translation.isNotEmpty) {
        final measured = _measureText(
          translation,
          fontSize: translationFont,
          fontWeight: spec?.translationFontWeight ?? FontWeight.w600,
          maxWidth: availableWidth,
          textDirection: textDirection,
          ambientStyle: ambientStyle,
          textScaler: textScaler,
          height: translationHeight,
        );
        translationWidth = measured.$1;
        maxTranslationLineCount = math.max(
          maxTranslationLineCount,
          measured.$2,
        );
      }
      widest = math.max(widest, math.max(mainWidth, translationWidth));
    }
    _metricsKey = key;
    _maxTextLines = maxLines;
    _maxTranslationLines = maxTranslationLineCount;
    // +1 为舍入保护：文字宽度与容器宽度相等时，浮点误差会让最后一字折行。
    _blockWidthValue =
        !scrollMode || widest <= 0
            ? null
            : math.min(widest + 1, availableWidth);
  }

  /// 行高 = 内容高度（在读行与翻译行中较高者）+ 行距空隙，并做上下限保护。
  /// [extraLineCount] 为每行需预留的附加行数（当前只有译文）。
  double contentSlotHeight(
    PortalLyricVisualSettings settings, {
    required bool scrollMode,
    required int extraLineCount,
    MusicLyricSpec? spec,
  }) {
    // 复刻形态：行高与行距完全取自样例，但按实测折行数预留高度，避免
    // 长句折行后溢出行槽。
    if (spec != null) {
      final mainLines = math.max(1, _maxTextLines);
      final mainBox = math.max(
        spec.activeFontSize * spec.activeLineHeight * mainLines,
        spec.fontSize * spec.lineHeight * mainLines,
      );
      final transLines = math.max(1, _maxTranslationLines);
      final translationBox =
          extraLineCount > 0
              ? math.max(
                spec.activeTranslationFontSize *
                    spec.activeTranslationLineHeight *
                    transLines,
                spec.translationFontSize *
                    spec.translationLineHeight *
                    transLines,
              )
              : 0.0;
      // 逐字填充遮罩的墨迹边距由行内容向外溢出（歌词行 Stack 不裁剪），
      // 不占用行槽高度，避免行距被撑大。
      return (mainBox + translationBox + spec.lineGap)
          .clamp(24.0, 480.0)
          .toDouble();
    }
    final baseFont = lineFontSize(
      settings,
      active: false,
      scrollMode: scrollMode,
    );
    final activeFont = lineFontSize(
      settings,
      active: true,
      scrollMode: scrollMode,
    );
    // 附加行按实测折行数预留同样的高度与间距。
    final transLines = math.max(1, _maxTranslationLines);
    double extraReserve(double font) =>
        extraLineCount *
        transLines *
        (font * _translationFontScale * _translationLineHeight +
            _translationGap);
    // 折行数取最坏一行：行槽等高，长句折行后不能压到相邻行。
    final mainLines = math.max(1, _maxTextLines);
    final content = math.max(
      activeFont * _lyricLineHeight * mainLines + extraReserve(activeFont),
      baseFont * _lyricLineHeight * mainLines + extraReserve(baseFont),
    );
    // 逐字填充遮罩的墨迹边距由行内容向外溢出（歌词行 Stack 不裁剪），
    // 不占用行槽高度；另加 2px 余量吸收 strut 与字体真实行高的亚像素差。
    // 行距 1.0 = 行间保留一个字高的空隙；只作用于空隙，不放大整行高度。
    final gap = baseFont * settings.lineSpacing;
    return (content + gap + 2).clamp(24.0, 320.0).toDouble();
  }

  /// 单行字号：px 即最终字号；多行形态的在读行用独立 px。
  /// 传入复刻参数时完全按样例字号取值。
  double lineFontSize(
    PortalLyricVisualSettings settings, {
    required bool active,
    required bool scrollMode,
    MusicLyricSpec? spec,
  }) {
    if (spec != null) {
      return active ? spec.activeFontSize : spec.fontSize;
    }
    return _fontPx(
      settings.fontSizePx,
      settings.currentFontSizePx,
      active: active,
      scrollMode: scrollMode,
    );
  }

  static double _fontPx(
    int fontSizePx,
    int currentFontSizePx, {
    required bool active,
    required bool scrollMode,
  }) {
    // 字号以 px 为准（用户看到的即最终字号）：滚动形态所有行同号，
    // 多行形态在读行用独立 px。
    if (!active || scrollMode) {
      return fontSizePx.toDouble().clamp(
        _minLyricFontSizePx,
        _maxLyricFontSizePx,
      );
    }
    return currentFontSizePx.toDouble().clamp(
      _minLyricFontSizePx,
      _maxLyricFontSizePx,
    );
  }

  /// 测量一段文本，返回（宽度, 折行数）。
  (double, int) _measureText(
    String text, {
    required double fontSize,
    required FontWeight fontWeight,
    required double maxWidth,
    required TextDirection textDirection,
    required TextStyle ambientStyle,
    required TextScaler textScaler,
    double height = _lyricLineHeight,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: ambientStyle.merge(
          TextStyle(fontSize: fontSize, height: height, fontWeight: fontWeight),
        ),
      ),
      maxLines: 3,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    // 折行时 TextPainter.width 是被钳制到 maxWidth 的排版宽度，不是真实
    // 最宽行；块宽必须取实际行度量，否则块被撑到可用宽度、填充边界映射
    // 与行盒不一致。
    final metrics = painter.computeLineMetrics();
    var width = 0.0;
    for (final metric in metrics) {
      width = math.max(width, metric.width);
    }
    painter.dispose();
    return (width, math.max(1, metrics.length));
  }
}
