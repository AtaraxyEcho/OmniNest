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

  /// 按指定画法渲染整行：上下渐变必须逐行各自作用，共用会让译文整行
  /// 落在渐变的下半段。
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
    Widget paint(Widget child, {Key? maskKey, List<Color>? colors}) {
      if (!resolved.gradient) {
        return child;
      }
      return ShaderMask(
        // 每行文本各自一个遮罩，键必须唯一（同一 Column 的兄弟节点不允许重键）。
        key: maskKey ?? const ValueKey('music-lyric-text-gradient'),
        blendMode: BlendMode.srcIn,
        shaderCallback:
            (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors ?? resolved.main,
            ).createShader(bounds),
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
              inactivePaint: _fillInactivePaint(translation: false),
            )
            : paint(text);

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
    // 译文与原文共用同一填充比例，在读时同步点亮。
    final translationChild =
        fillEnabled
            ? _buildFilledText(
              translationText,
              fillKey: const ValueKey('music-lyric-translation-word-fill'),
              layeredKey: const ValueKey(
                'music-lyric-translation-word-fill-layered',
              ),
              activePaint: (
                gradient: resolved.gradient,
                colors: resolved.translation,
              ),
              inactivePaint: _fillInactivePaint(translation: true),
            )
            : paint(
              translationText,
              maskKey: const ValueKey('music-lyric-translation-gradient'),
              colors: resolved.translation,
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
  Widget _buildFilledText(
    Text text, {
    required Key fillKey,
    required Key layeredKey,
    required ({bool gradient, List<Color> colors}) activePaint,
    required ({bool gradient, List<Color> colors}) inactivePaint,
  }) {
    final solidPair = !activePaint.gradient && !inactivePaint.gradient;
    final baseStyle = text.style!;
    final inactiveText = Text(
      text.data ?? '',
      maxLines: text.maxLines,
      overflow: text.overflow,
      textAlign: text.textAlign,
      strutStyle: text.strutStyle,
      style: baseStyle.copyWith(
        color:
            inactivePaint.gradient ? Colors.white : inactivePaint.colors.first,
      ),
    );
    Widget maskHorizontal(Widget child) {
      return AnimatedBuilder(
        animation: widget.fillAnimation!,
        builder: (context, _) {
          final fraction = widget.fillAnimation!.value.clamp(0.0, 1.0);
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
                  stops: <double>[0.0, fraction, fraction, 1.0],
                ).createShader(bounds),
            child: child,
          );
        },
      );
    }

    if (solidPair) {
      // 单层横向遮罩：左在读色、右非当前句色。
      return maskHorizontal(text);
    }
    // 双层叠加：底层整行非当前句色，顶层在读色按边界裁切。
    return Stack(
      children: [
        _paintVertical(inactiveText, inactivePaint),
        maskHorizontal(_paintVertical(text, activePaint)),
      ],
    );
  }

  /// 逐字填充的未唱色：复刻形态优先取用户非当前句色，通用形态取用户
  /// 非当前句色，默认双色回落样例常量。
  ({bool gradient, List<Color> colors}) _fillInactivePaint({
    required bool translation,
  }) {
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
    return (
      gradient: false,
      colors: <Color>[translation ? spec.translationColor : spec.textColor],
    );
  }

  /// 按颜色画法渲染文本：上下渐变套 srcIn 竖向遮罩，纯色直接着色。
  Widget _paintVertical(
    Widget child,
    ({bool gradient, List<Color> colors}) resolved,
  ) {
    if (!resolved.gradient) {
      return child;
    }
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback:
          (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: resolved.colors,
          ).createShader(bounds),
      child: child,
    );
  }

  String? get _translationText {
    final translation = widget.line.translation?.trim();
    return translation == null || translation.isEmpty ? null : translation;
  }

  /// 在读行的底衬与左侧强调条；居中布局两者都不做时返回 null。
  BoxDecoration? get _activeLineDecoration {
    final spec = widget.spec;
    if (spec == null) {
      return null;
    }
    final background = spec.activeLineBackgroundColor;
    final accent = spec.activeLineAccentColor;
    if (background == null && accent == null) {
      return null;
    }
    return BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(spec.activeLineRadius),
      border:
          accent == null
              ? null
              : Border(
                left: BorderSide(
                  color: accent,
                  width: spec.activeLineAccentWidth,
                ),
              ),
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
