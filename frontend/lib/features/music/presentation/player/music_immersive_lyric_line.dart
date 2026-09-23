part of 'music_immersive_lyrics.dart';

/// 单行歌词渲染：滚动与多行两种形态共用，原文与译文各自一个渐变遮罩。
class _MusicLyricLine extends StatefulWidget {
  const _MusicLyricLine({
    required this.line,
    required this.active,
    required this.hovered,
    required this.scale,
    required this.fontSize,
    required this.activeFontSize,
    required this.settings,
    required this.textAlign,
    required this.scrollMode,
    this.spec,
    this.relativeIndex = 0,
    this.blockWidth,
    this.blockAnchor = Alignment.center,
    this.preview = false,
    this.focusBand = false,
    this.gradientAllowed = true,
    this.fillAnimation,
    required this.onEnter,
    required this.onExit,
    required this.onTap,
    required this.onMenu,
    super.key,
  });

  final MusicLyricLine line;
  final bool active;
  final bool hovered;
  final double scale;

  /// 常规行字号（px，已含用户设置的字号，不再乘设备缩放）。
  final double fontSize;

  /// 在读行字号（px）：滚动形态与常规行相同，多行形态可更大。
  final double activeFontSize;
  final PortalLyricVisualSettings settings;
  final TextAlign textAlign;

  /// 复刻参数（桌面沉浸舞台传入）：为 null 时沿用用户设置的通用排版。
  final MusicLyricSpec? spec;

  /// 该行与在读行的行号差（负值在前、正值在后）。
  final int relativeIndex;

  /// 文字块的锚点：居左/居中/居右，与歌词位置设置一致。
  final Alignment blockAnchor;
  final bool scrollMode;

  /// 文字块宽度（居左/居右形态传入）：各行按同一宽度渲染，
  final double? blockWidth;

  /// 拖动预览命中行：轻微放大以示"松手将跳到这里"。
  final bool preview;

  /// 焦点带高亮（仅滚动形态的在读行）。
  final bool focusBand;

  /// 是否允许逐行渐变遮罩：超长歌词关闭以控制图层数量。
  final bool gradientAllowed;

  /// 逐字填充动画（0..1）：仅滚动形态的当前播放行且行内含词级数据时传入；
  final Animation<double>? fillAnimation;

  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onTap;

  /// 长按/右键打开行菜单（复制歌词、歌词延迟微调），参数为触发点全局坐标。
  final ValueChanged<Offset> onMenu;

  @override
  State<_MusicLyricLine> createState() => _MusicLyricLineState();
}

class _MusicLyricLineState extends State<_MusicLyricLine>
    with SingleTickerProviderStateMixin {
  /// 默认双色（纯白）：与该值一致时视为用户未改色，回落样例常量。
  static const LyricPaint _defaultPaint = LyricPaint.solid(0xFFFFFFFF);

  late final AnimationController _breathingController;
  bool _motionDisabled = false;

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      value: 0.25,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionDisabled = MediaQuery.disableAnimationsOf(context);
    _syncBreathing();
  }

  @override
  void didUpdateWidget(covariant _MusicLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.scrollMode != widget.scrollMode ||
        oldWidget.settings.breathingEnabled !=
            widget.settings.breathingEnabled) {
      _syncBreathing();
    }
  }

  @override
  void dispose() {
    _breathingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 滚动歌词不使用呼吸动画（与逐字填充争夺注意力，且为持续动画噪音）。
    final breathingEnabled =
        widget.settings.breathingEnabled && !widget.scrollMode;
    if (!widget.active || !breathingEnabled) {
      return _buildLine(0);
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _breathingController,
        builder: (context, _) {
          final breathing =
              _motionDisabled
                  ? 0.5
                  : Curves.easeInOutSine.transform(_breathingController.value);
          return _buildLine(breathing);
        },
      ),
    );
  }

  Widget _buildLine(double breathing) {
    final fontSize = widget.active ? widget.activeFontSize : widget.fontSize;
    final content = _buildPaintedLine(
      fontSize,
      active: widget.active,
      hasTranslation: _translationText != null,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => widget.onEnter(),
      onExit: (_) => widget.onExit(),
      child: Semantics(
        button: true,
        selected: widget.active,
        child: GestureDetector(
          // 整行可点；长按或右键打开行菜单。
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPressStart: (details) => widget.onMenu(details.globalPosition),
          onSecondaryTapUp: (details) => widget.onMenu(details.globalPosition),
          child: SizedBox.expand(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 在读行底衬：向外扩张而文字与其他行同基线。
                if (widget.active && _activeLineDecoration != null)
                  Positioned(
                    top: widget.spec!.activeLinePaddingY,
                    bottom: widget.spec!.activeLinePaddingY,
                    left: -widget.spec!.activeLinePaddingX,
                    right: -widget.spec!.activeLinePaddingX,
                    child: IgnorePointer(
                      child: DecoratedBox(decoration: _activeLineDecoration!),
                    ),
                  ),
                // 焦点带：在焦点行后叠一层低强度横向提亮（可开关）。
                if (widget.focusBand)
                  const Positioned.fill(child: _LyricFocusBand()),
                Align(
                  // 块锚点随歌词位置设置，各行共享同一侧基线。
                  alignment: widget.blockAnchor,
                  child: SizedBox(
                    width: widget.blockWidth,
                    child: _buildBody(content, breathing),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 行主体（缩放/位移包装后的文字内容）。
  Widget _buildBody(Widget content, double breathing) {
    return Transform.translate(
      key: widget.active ? const ValueKey('music-lyric-reactive-motion') : null,
      offset:
          widget.active
              ? Offset(
                0,
                -2.4 *
                    breathing *
                    widget.scale *
                    (widget.settings.breathingEnabled && !widget.scrollMode
                        ? 1
                        : 0),
              )
              : Offset.zero,
      child: Transform.scale(
        key:
            widget.active
                ? const ValueKey('music-lyric-reactive-transform')
                : null,
        scale: _lineScale(breathing),
        child: content,
      ),
    );
  }

  /// 行整体缩放：只保留在读行；非在读行不缩放（会裁掉首尾文字）。
  double _lineScale(double breathing) {
    if (widget.active) {
      final breathingScale =
          widget.settings.breathingEnabled && !widget.scrollMode
              ? 0.985 + breathing * 0.055
              : 1.0;
      return breathingScale * (widget.spec?.activeLineScale ?? 1);
    }
    return 1;
  }

  /// 与文本样式同源的强制 strut：字体自身行高常大于 `fontSize × height`，
  /// 不强制会撑破行槽。
  StrutStyle _strutFor(TextStyle style) {
    return StrutStyle(
      fontSize: style.fontSize,
      height: style.height,
      fontWeight: style.fontWeight,
      forceStrutHeight: true,
    );
  }

  /// 按指定画法渲染整行：上下渐变经逐行重复着色器作用，折行的每一行
  /// 与译文行各自完整走一遍渐变，不共享渐变区间。
  Widget _buildPaintedLine(
    double fontSize, {
    required bool active,
    required bool hasTranslation,
  }) {
    final resolved = _resolveColors(active: active);
    final spec = widget.spec;
    final textStyle = TextStyle(
      // 渐变用 srcIn 遮罩替换文字色，文字本体保持不透明白。
      color: resolved.gradient ? Colors.white : resolved.main.first,
      fontSize: fontSize,
      height:
          spec == null
              ? _lyricLineHeight
              : (active ? spec.activeLineHeight : spec.lineHeight),
      fontWeight:
          spec == null
              ? (active ? FontWeight.w800 : FontWeight.w500)
              : (active ? spec.activeFontWeight : spec.fontWeight),
      // 样例在读原文带白色外发光 `drop-shadow-[0_0_24px_rgba(255,255,255,A)]`。
      shadows:
          spec != null && active && spec.activeLineGlowAlpha > 0
              ? <Shadow>[
                Shadow(
                  color: Colors.white.withValues(
                    alpha: spec.activeLineGlowAlpha,
                  ),
                  blurRadius: spec.activeLineGlowBlur,
                ),
              ]
              : null,
    );
    Widget paint(
      Widget child, {
      Key? maskKey,
      List<Color>? colors,
      required TextStyle style,
    }) {
      if (!resolved.gradient) {
        return child;
      }
      final lineHeight = (style.fontSize ?? 14) * (style.height ?? 1.2);
      return ShaderMask(
        // 每行文本各自一个遮罩，键必须唯一（同一 Column 的兄弟节点不允许重键）。
        key: maskKey ?? const ValueKey('music-lyric-text-gradient'),
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) {
          // 上下渐变按可视行重复：折行的每一行与译文行各自完整走一遍
          // 渐变，而不是整块文本共用一个渐变区间。
          final raw = bounds.height / lineHeight;
          final lines = math.max(1, raw.round());
          final period = bounds.height / lines;
          return ui.Gradient.linear(
            bounds.topLeft,
            bounds.topLeft + Offset(0, period),
            colors ?? resolved.main,
            null,
            TileMode.repeated,
          );
        },
        child: child,
      );
    }

    final text = Text(
      widget.line.text,
      key: active ? const ValueKey('music-lyric-active') : null,
      maxLines: 3,
      overflow: TextOverflow.visible,
      textAlign: widget.textAlign,
      strutStyle: _strutFor(textStyle),
      style: textStyle,
    );
    final fillEnabled = widget.fillAnimation != null && active;
    final mainChild =
        fillEnabled
            ? _buildFilledText(
              text,
              fillKey: const ValueKey('music-lyric-word-fill'),
              layeredKey: const ValueKey('music-lyric-word-fill-layered'),
              activePaint: (gradient: resolved.gradient, colors: resolved.main),
              inactivePaint: _fillInactivePaint(),
            )
            : paint(text, style: textStyle);

    final translation =
        widget.settings.translationEnabled ? _translationText : null;
    if (translation == null) {
      return mainChild;
    }
    final extraStyle = textStyle.copyWith(
      // 译文单独取色：样例原文与译文是两级色。
      color: resolved.gradient ? Colors.white : resolved.translation.first,
      fontSize:
          spec == null
              ? fontSize * _translationFontScale
              : (active
                  ? spec.activeTranslationFontSize
                  : spec.translationFontSize),
      fontWeight:
          spec == null
              ? (active ? FontWeight.w600 : FontWeight.w400)
              : (active
                  ? spec.activeTranslationFontWeight
                  : spec.translationFontWeight),
      height:
          spec == null
              ? _translationLineHeight
              : (active
                  ? spec.activeTranslationLineHeight
                  : spec.translationLineHeight),
      // 外发光只属于在读原文，译文不带。
      shadows: null,
    );
    final translationText = Text(
      translation,
      key: active ? const ValueKey('music-lyric-translation') : null,
      maxLines: 2,
      overflow: TextOverflow.visible,
      textAlign: widget.textAlign,
      strutStyle: _strutFor(extraStyle),
      style: extraStyle,
    );
    // 译文不做逐字填充：主流方案仅原文参与卡拉OK推进，译文跟随在读行
    // 整行切换读色（在读色 / 非当前句色，含上下渐变画法）。
    final translationChild = paint(
      translationText,
      maskKey: const ValueKey('music-lyric-translation-gradient'),
      colors: resolved.translation,
      style: extraStyle,
    );
    // 原文与译文共用同一侧基线：左对齐按起始边，居中按中心，右对齐按末端。
    final crossAxisAlignment =
        widget.textAlign == TextAlign.center
            ? CrossAxisAlignment.center
            : widget.textAlign == TextAlign.right
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        mainChild,
        SizedBox(
          // 复刻形态下译文间距必须取样例值，否则行槽高度与内容对不上。
          height:
              spec == null
                  ? _translationGap
                  : (active ? spec.activeTranslationGap : spec.translationGap),
        ),
        translationChild,
      ],
    );
  }

  /// 逐字填充的单行渲染：已唱部分用读色、未唱部分用非当前句色。
  ///
  /// 渐变与填充都以"可视行"为单位：原文折行后按排版度量切分为逐行渲染，
  /// 每个可视行各自套完整的上下渐变，填充按词级时长在各可视行间衔接
  /// （第一行唱完第二行立刻开始，无词级数据回退按行宽加权），不再整块
  /// 文本共用一道渐变与一道填充边界。
  /// 遮罩内为文字加上下墨迹边距，使遮罩矩形覆盖 y / g 等下伸字形；
  /// 在读/非当前句两层使用同一墨迹边距与样式，且每层只包一次边距，
  /// 字形完全对齐。行状态切换为原地更新（无 AnimatedSwitcher 交叉
  /// 淡化），不会出现双份叠字。
  Widget _buildFilledText(
    Text text, {
    required Key fillKey,
    required Key layeredKey,
    required ({bool gradient, List<Color> colors}) activePaint,
    required ({bool gradient, List<Color> colors}) inactivePaint,
  }) {
    final data = text.data ?? '';
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }
    final baseStyle = text.style!;
    final inkPad = (baseStyle.fontSize ?? 14) * 0.14;
    // 行号后缀键从基础键的字符串值派生：直接插值 Key 对象会混入其
    // toString 的类型与哈希片段，导致测试无法按可预期键名定位。
    final fillKeyBase = fillKey is ValueKey<String> ? fillKey.value : 'fill';
    final layeredKeyBase =
        layeredKey is ValueKey<String> ? layeredKey.value : 'layered';
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _resolveFillLines(
          context,
          data,
          DefaultTextStyle.of(context).style,
          baseStyle,
          text.strutStyle,
          text.textAlign ?? TextAlign.start,
          text.maxLines ?? 1,
          constraints.maxWidth,
          widget.line.words,
        );
        // 行盒实际宽度：上游紧约束（块宽/槽宽）会覆盖 SizedBox 的收缩宽度，
        // 填充边界必须按真实渲染盒宽换算，否则非整块宽的行会被等比压缩。
        final boxWidth =
            constraints.hasTightWidth
                ? constraints.maxWidth
                : math.max(layout.widest, 0.0);
        return SizedBox(
          width: layout.widest,
          height: 2 * inkPad + layout.tops.last + layout.heights.last,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var index = 0; index < layout.lines.length; index++)
                Positioned(
                  top: layout.tops[index],
                  left: 0,
                  right: 0,
                  height: layout.heights[index] + 2 * inkPad,
                  child: _buildFilledLineSlice(
                    index: index,
                    lineText: layout.lines[index],
                    baseStyle: baseStyle,
                    strutStyle: text.strutStyle,
                    textAlign: text.textAlign ?? TextAlign.start,
                    inkPad: inkPad,
                    lineHeight: layout.heights[index],
                    boxWidth: boxWidth,
                    glyphWidth: layout.widths[index],
                    consumedBefore: layout.consumed[index],
                    totalGlyphWidth: layout.totalWidth,
                    timeWeight: layout.timeWeights?[index],
                    timeConsumedBefore: layout.consumedTime?[index],
                    totalTimeWeight: layout.totalTime,
                    fillKey:
                        index == 0
                            ? fillKey
                            : ValueKey<String>('$fillKeyBase-$index'),
                    layeredKey:
                        index == 0
                            ? layeredKey
                            : ValueKey<String>('$layeredKeyBase-$index'),
                    activePaint: activePaint,
                    inactivePaint: inactivePaint,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 逐行填充布局的缓存：同一文本、样式与宽度约束下避免每帧重新排版。
  _FillLineLayout? _fillLineLayoutCache;

  /// 用与真实排版相同的输入度量原文折行：可视行子串、行盒位置与行宽。
  ///
  /// 度量样式必须与环境 DefaultTextStyle 合并（字体族等继承属性影响折行），
  /// 行宽按裁剪后的子串实测（行尾空白不参与）。有词级数据时把每个词的
  /// 时长按字符区间归集到所在可视行，行间衔接按词级时长加权；词缺失或
  /// 匹配失败时回退按行宽加权。
  _FillLineLayout _resolveFillLines(
    BuildContext context,
    String text,
    TextStyle ambientStyle,
    TextStyle style,
    StrutStyle? strutStyle,
    TextAlign textAlign,
    int maxLines,
    double maxWidth,
    List<MusicLyricWord> words,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    final effectiveStyle = ambientStyle.merge(style);
    final cacheKey = Object.hash(
      text,
      maxWidth,
      effectiveStyle.fontSize,
      effectiveStyle.height,
      effectiveStyle.fontWeight,
      effectiveStyle.fontFamily,
      scaler.toString(),
      maxLines,
      identityHashCode(words),
    );
    final cached = _fillLineLayoutCache;
    if (cached != null && cached.cacheKey == cacheKey) {
      return cached;
    }
    final direction = Directionality.of(context);
    final painter = TextPainter(
      text: TextSpan(text: text, style: effectiveStyle),
      textAlign: textAlign,
      textDirection: direction,
      textScaler: scaler,
      strutStyle: strutStyle,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    final metrics = painter.computeLineMetrics();
    final lines = <String>[];
    final tops = <double>[];
    final heights = <double>[];
    final widths = <double>[];
    final rawRanges = <(int, int)>[];
    var start = 0;
    var top = 0.0;
    for (final metric in metrics) {
      if (start >= text.length) {
        break;
      }
      final range = painter.getLineBoundary(TextPosition(offset: start));
      final end = range.end.clamp(start + 1, text.length);
      final piece = text.substring(start, end).trim();
      final rangeStart = start;
      start = end;
      if (piece.isEmpty) {
        continue;
      }
      final piecePainter = TextPainter(
        text: TextSpan(text: piece, style: effectiveStyle),
        textDirection: direction,
        textScaler: scaler,
        strutStyle: strutStyle,
      )..layout();
      lines.add(piece);
      tops.add(top);
      heights.add(metric.height);
      widths.add(piecePainter.width);
      rawRanges.add((rangeStart, end));
      top += metric.height;
      piecePainter.dispose();
    }
    painter.dispose();
    final widest = widths.fold(0.0, math.max);
    final consumed = <double>[];
    var sum = 0.0;
    for (final width in widths) {
      consumed.add(sum);
      sum += width;
    }
    // 词级时长权重：每个词按其字符起点归入所在可视行。任一词匹配失败
    // 即整体放弃时间加权，回退行宽加权，避免部分行权重缺失造成跳变。
    List<double>? timeWeights;
    var totalTime = 0.0;
    if (words.isNotEmpty) {
      final weights = List<double>.filled(lines.length, 0.0);
      var matchedAll = true;
      var cursor = 0;
      for (final word in words) {
        if (word.text.isEmpty) {
          continue;
        }
        final index = text.indexOf(word.text, cursor);
        if (index < 0) {
          matchedAll = false;
          break;
        }
        cursor = index + word.text.length;
        totalTime += word.duration.inMilliseconds;
        for (var k = 0; k < rawRanges.length; k++) {
          final (rangeStart, rangeEnd) = rawRanges[k];
          if (index >= rangeStart && index < rangeEnd) {
            weights[k] += word.duration.inMilliseconds;
            break;
          }
        }
      }
      if (matchedAll && totalTime > 0) {
        timeWeights = weights;
      } else {
        totalTime = 0;
      }
    }
    final consumedTime = <double>[];
    if (timeWeights != null) {
      var timeSum = 0.0;
      for (final weight in timeWeights) {
        consumedTime.add(timeSum);
        timeSum += weight;
      }
    }
    final layout = _FillLineLayout(
      cacheKey: cacheKey,
      lines: lines,
      tops: tops,
      heights: heights,
      widths: widths,
      consumed: consumed,
      totalWidth: sum,
      widest: widest,
      timeWeights: timeWeights,
      totalTime: totalTime,
      consumedTime: timeWeights == null ? null : consumedTime,
    );
    _fillLineLayoutCache = layout;
    return layout;
  }

  /// 单个可视行的填充渲染：底层整行非当前句色、顶层在读色按该行边界
  /// 裁切；上下渐变在该行行盒内完整走一遍。字形起点按实际渲染盒宽与
  /// 文本排列推导。
  Widget _buildFilledLineSlice({
    required int index,
    required String lineText,
    required TextStyle baseStyle,
    required StrutStyle? strutStyle,
    required TextAlign textAlign,
    required double inkPad,
    required double lineHeight,
    required double boxWidth,
    required double glyphWidth,
    required double consumedBefore,
    required double totalGlyphWidth,
    required double? timeWeight,
    required double? timeConsumedBefore,
    required double totalTimeWeight,
    required Key fillKey,
    required Key layeredKey,
    required ({bool gradient, List<Color> colors}) activePaint,
    required ({bool gradient, List<Color> colors}) inactivePaint,
  }) {
    final solidPair = !activePaint.gradient && !inactivePaint.gradient;
    final inkPadding = EdgeInsets.symmetric(vertical: inkPad);
    double glyphLeft;
    if (textAlign == TextAlign.center) {
      glyphLeft = (boxWidth - glyphWidth) / 2;
    } else if (textAlign == TextAlign.right || textAlign == TextAlign.end) {
      glyphLeft = boxWidth - glyphWidth;
    } else {
      glyphLeft = 0;
    }
    glyphLeft = math.max(0.0, glyphLeft);
    final activeLineText = Text(
      lineText,
      key: index == 0 ? const ValueKey('music-lyric-active') : null,
      maxLines: 1,
      overflow: TextOverflow.visible,
      textAlign: textAlign,
      strutStyle: strutStyle,
      style: baseStyle.copyWith(
        color: activePaint.gradient ? Colors.white : activePaint.colors.first,
      ),
    );
    final inactiveLineText = Text(
      lineText,
      maxLines: 1,
      overflow: TextOverflow.visible,
      textAlign: textAlign,
      strutStyle: strutStyle,
      style: baseStyle.copyWith(
        color:
            inactivePaint.gradient ? Colors.white : inactivePaint.colors.first,
      ),
    );
    Widget fillMask(Widget child) {
      return AnimatedBuilder(
        animation: widget.fillAnimation!,
        builder: (context, child) {
          final fraction = widget.fillAnimation!.value.clamp(0.0, 1.0);
          // 行间衔接按词级时长加权：整段已唱时长扣减前面各行后得到本行
          // 局部进度，保证次行在演唱到达时立刻开始点亮；无词级数据时
          // 回退按行宽加权。边界换算到行盒坐标。
          final double progress;
          if (timeWeight != null) {
            final consumedTime = (fraction * totalTimeWeight -
                    timeConsumedBefore!)
                .clamp(0.0, timeWeight);
            progress = timeWeight <= 0 ? 0.0 : consumedTime / timeWeight;
          } else {
            final consumed = (fraction * totalGlyphWidth - consumedBefore)
                .clamp(0.0, glyphWidth);
            progress = glyphWidth <= 0 ? 0.0 : consumed / glyphWidth;
          }
          final boundary =
              (glyphLeft + progress * glyphWidth) / math.max(boxWidth, 1);
          // 纯色组合：单层 srcIn 遮罩直接替换颜色——左在读色、右非当前句色
          final maskColors =
              solidPair
                  ? <Color>[
                    activePaint.colors.first,
                    activePaint.colors.first,
                    inactivePaint.colors.first,
                    inactivePaint.colors.first,
                  ]
                  : const <Color>[
                    Colors.white,
                    Colors.white,
                    Color(0x00000000),
                    Color(0x00000000),
                  ];
          return ShaderMask(
            // 单层与双层模式分别挂键，便于测试区分填充的画法分支。
            key: solidPair ? fillKey : layeredKey,
            blendMode: solidPair ? BlendMode.srcIn : BlendMode.dstIn,
            shaderCallback:
                (bounds) => LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: maskColors,
                  stops: <double>[0.0, boundary, boundary, 1.0],
                ).createShader(bounds),
            // 墨迹边距由调用方包一次：此处再包会与双层分支的内层边距叠加，
            // 在读层整体下移一个边距，两层字形错位形成"叠字"。
            child: child,
          );
        },
        child: child,
      );
    }

    if (solidPair) {
      // 单层横向遮罩：左在读色、右非当前句色；文字只包一次墨迹边距。
      return fillMask(
        _paintLineVertical(
          Padding(padding: inkPadding, child: activeLineText),
          activePaint,
          inkPad,
          lineHeight,
        ),
      );
    }
    // 双层叠加：底层整行非当前句色，顶层在读色按边界裁切；两层使用同一
    // 墨迹边距，保证字形完全对齐。expand 使两层铺满行盒：填充边界按行盒
    // 宽度换算，若让文字收缩排布，非最宽行的遮罩箱体变窄会压缩边界位置。
    return Stack(
      fit: StackFit.expand,
      children: [
        _paintLineVertical(
          Padding(padding: inkPadding, child: inactiveLineText),
          inactivePaint,
          inkPad,
          lineHeight,
        ),
        fillMask(
          _paintLineVertical(
            Padding(padding: inkPadding, child: activeLineText),
            activePaint,
            inkPad,
            lineHeight,
          ),
        ),
      ],
    );
  }

  /// 逐字填充的未唱色：复刻形态优先取用户非当前句色，通用形态取用户
  /// 非当前句色，默认双色回落样例常量。
  ({bool gradient, List<Color> colors}) _fillInactivePaint() {
    final spec = widget.spec;
    if (spec == null) {
      final legacy = _resolveColors(active: false);
      return (gradient: legacy.gradient, colors: legacy.main);
    }
    final inactiveOverride = _paintOverride(widget.settings.inactivePaint);
    if (inactiveOverride != null) {
      return (
        gradient: inactiveOverride.isGradient && widget.gradientAllowed,
        colors: <Color>[
          for (final value in inactiveOverride.colors) Color(value),
        ],
      );
    }
    return (gradient: false, colors: <Color>[spec.textColor]);
  }

  /// 逐行上下渐变：渐变只在该可视行的行盒内走完一遍，[textTop] 为行内
  /// 文字区距行盒顶部的墨迹边距，[textHeight] 为行盒高。
  Widget _paintLineVertical(
    Widget child,
    ({bool gradient, List<Color> colors}) resolved,
    double textTop,
    double textHeight,
  ) {
    if (!resolved.gradient) {
      return child;
    }
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback:
          (bounds) => ui.Gradient.linear(
            Offset(bounds.left, bounds.top + textTop),
            Offset(bounds.left, bounds.top + textTop + textHeight),
            resolved.colors,
            null,
            TileMode.clamp,
          ),
      child: child,
    );
  }

  String? get _translationText {
    final translation = widget.line.translation?.trim();
    return translation == null || translation.isEmpty ? null : translation;
  }

  /// 在读行的底衬色带；居中布局不做底衬时返回 null。
  /// 样例的左侧竖向强调条已整体移除：在纯音乐等短歌词下它读起来只是一根
  /// 与内容无关的白线，而在多行下它与底衬色带表达同一件事实（当前行）。
  BoxDecoration? get _activeLineDecoration {
    final spec = widget.spec;
    if (spec == null) {
      return null;
    }
    final background =
        widget.settings.activeLineBackgroundEnabled
            ? spec.activeLineBackgroundColor
            : null;
    if (background == null) {
      return null;
    }
    return BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(spec.activeLineRadius),
    );
  }

  /// 该行的两种颜色画法（原文与译文各一组）。
  ///
  /// 复刻形态优先消费用户双色（在读色/非当前句色）：默认纯白视为未改色，
  /// 回落样例常量，保证"恢复默认 = 样例色"；改色后保留样例的按距离
  /// 不透明度档位（颜色 × 档位相乘）。
  ({bool gradient, List<Color> main, List<Color> translation}) _resolveColors({
    required bool active,
  }) {
    final spec = widget.spec;
    if (spec == null) {
      final legacy = _resolveLineColors(active: active);
      return (
        gradient: legacy.gradient,
        main: legacy.colors,
        translation: legacy.colors,
      );
    }
    final blockOpacity =
        active ? 1.0 : musicLyricLineOpacity(spec, widget.relativeIndex);
    final translationExtra =
        active ? 1.0 : spec.translationAlpha(widget.relativeIndex);
    // 非在读行不再靠缩放给反馈，改用明度：拖动预览比普通悬停更亮。
    final hoverLift =
        widget.active
            ? 0.0
            : widget.preview
            ? 0.45
            : (widget.hovered ? 0.34 : 0.0);
    Color dim(Color base, double extra) {
      final dimmed = base.withValues(alpha: base.a * blockOpacity * extra);
      return hoverLift > 0 ? Color.lerp(dimmed, base, hoverLift)! : dimmed;
    }

    if (active) {
      final override = _paintOverride(widget.settings.currentPaint);
      if (override != null) {
        return (
          gradient: override.isGradient && widget.gradientAllowed,
          main: <Color>[
            for (final value in override.colors) dim(Color(value), 1),
          ],
          translation: <Color>[
            for (final value in override.colors) dim(Color(value), 1),
          ],
        );
      }
      return (
        gradient: false,
        main: <Color>[dim(spec.activeTextColor, 1)],
        translation: <Color>[dim(spec.activeTranslationColor, 1)],
      );
    }
    final inactiveOverride = _paintOverride(widget.settings.inactivePaint);
    if (inactiveOverride != null) {
      return (
        gradient: inactiveOverride.isGradient && widget.gradientAllowed,
        main: <Color>[
          for (final value in inactiveOverride.colors) dim(Color(value), 1),
        ],
        translation: <Color>[
          for (final value in inactiveOverride.colors)
            dim(Color(value), translationExtra),
        ],
      );
    }
    return (
      gradient: false,
      main: <Color>[dim(spec.textColor, 1)],
      translation: <Color>[dim(spec.translationColor, translationExtra)],
    );
  }

  /// 用户改过色时返回该画法，默认纯白视为未改色返回 null。
  LyricPaint? _paintOverride(LyricPaint paint) {
    return paint == _defaultPaint ? null : paint;
  }

  /// 通用色板（非复刻形态）：在读行用在读色（满亮），其余行（已唱与未唱）
  ({bool gradient, List<Color> colors}) _resolveLineColors({
    required bool active,
  }) {
    final settings = widget.settings;
    final paint = active ? settings.currentPaint : settings.inactivePaint;
    final opacity = active ? 1.0 : settings.inactiveOpacity.clamp(0.0, 1.0);
    final hoverLift = !widget.active && widget.hovered ? 0.34 : 0.0;
    Color resolve(int value) {
      final base = Color(value);
      final dimmed = base.withValues(alpha: base.a * opacity);
      return hoverLift > 0 ? Color.lerp(dimmed, base, hoverLift)! : dimmed;
    }

    return (
      gradient: paint.isGradient && widget.gradientAllowed,
      colors: paint.colors.map(resolve).toList(growable: false),
    );
  }

  void _syncBreathing() {
    if (widget.scrollMode) {
      _breathingController.stop();
      return;
    }
    if (!widget.active ||
        !widget.settings.breathingEnabled ||
        _motionDisabled) {
      _breathingController.stop();
      return;
    }
    if (!_breathingController.isAnimating) {
      _breathingController.repeat(reverse: true);
    }
  }
}

/// 折行填充的逐行度量：可视行子串、行盒几何与行宽权重。
///
/// [cacheKey] 覆盖文本、样式与宽度约束，命中时跳过重新排版。
class _FillLineLayout {
  const _FillLineLayout({
    required this.cacheKey,
    required this.lines,
    required this.tops,
    required this.heights,
    required this.widths,
    required this.consumed,
    required this.totalWidth,
    required this.widest,
    required this.timeWeights,
    required this.totalTime,
    required this.consumedTime,
  });

  final Object cacheKey;

  /// 每个可视行的裁剪后子串。
  final List<String> lines;

  /// 每行行盒相对首行顶部的纵向偏移。
  final List<double> tops;

  /// 每行行盒高度（strut 强制一致）。
  final List<double> heights;

  /// 每行实测字形宽度。
  final List<double> widths;

  /// 每行之前所有行的字形宽度累计，用于把整段填充比例换算到本行。
  final List<double> consumed;

  /// 全部可视行的字形宽度合计。
  final double totalWidth;

  /// 最宽可视行的宽度（行盒宽度）。
  final double widest;

  /// 每个可视行的词级时长权重（毫秒）；无词级数据或匹配失败时为 null，
  /// 行间衔接回退按行宽加权。
  final List<double>? timeWeights;

  /// 词级时长权重合计（毫秒）；[timeWeights] 为 null 时为 0。
  final double totalTime;

  /// 每行之前所有行的词级时长累计（毫秒）；[timeWeights] 为 null 时为 null。
  final List<double>? consumedTime;
}

/// 焦点带：在读行背后的一层低强度横向提亮，向两端淡出。
class _LyricFocusBand extends StatelessWidget {
  const _LyricFocusBand();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                const Color(0x00FFFFFF),
                Colors.white.withValues(alpha: 0.07),
                Colors.white.withValues(alpha: 0.07),
                const Color(0x00FFFFFF),
              ],
              stops: const <double>[0, 0.18, 0.82, 1],
            ),
          ),
        ),
      ),
    );
  }
}
