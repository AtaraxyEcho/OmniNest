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
    this.accentColor,
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

  /// 时间参考行的强调色（样例 `text-primary`）：只在在读行的 `lyric-meta`
  /// 行使用，非复刻形态不渲染该行。
  final Color? accentColor;

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
                // 焦点带：在焦点行后叠一层低强度横向提亮（可开关）。
                if (widget.focusBand)
                  const Positioned.fill(child: _LyricFocusBand()),
                Align(
                  // 块锚点随歌词位置设置，各行共享同一侧基线。
                  alignment: widget.blockAnchor,
                  child: SizedBox(
                    width: widget.blockWidth,
                    child: _buildBandedBody(content, breathing),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 在读行底衬：以本行内容为基准向外扩张（负 inset 且舞台不裁剪），
  /// 文字仍与其他行同基线。
  ///
  /// 此前底衬按整行槽上下钉 `activeLinePaddingY`：行槽里含行距、译文预留与
  /// 时间标签位，纯音乐这类单行短歌词会画出比文字高出一大截、并随时间标签
  /// 开关漂移的色块（观感上「不是矩形」）。样例的 `active-lyric-box` 是包住
  /// 本行内容（原文 + 译文 + lyric-meta）的盒子，因此按内容取高。
  Widget _buildBandedBody(Widget content, double breathing) {
    final body = _buildBody(content, breathing);
    final spec = widget.spec;
    final decoration = widget.active ? _activeLineDecoration : null;
    if (spec == null || decoration == null) {
      return body;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -spec.activeLinePaddingY,
          bottom: -spec.activeLinePaddingY,
          left: -spec.activeLinePaddingX,
          right: -spec.activeLinePaddingX,
          child: IgnorePointer(child: DecoratedBox(decoration: decoration)),
        ),
        body,
      ],
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

  /// 逐行填充布局的缓存：同一文本、样式与宽度约束下避免每帧重新排版。
  _FillLineLayout? _fillLineLayoutCache;

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
