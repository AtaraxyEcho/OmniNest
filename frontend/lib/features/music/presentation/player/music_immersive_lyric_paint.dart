part of 'music_immersive_lyrics.dart';

/// 歌词行整行着色渲染。
extension _MusicImmersiveLyricPaint on _MusicLyricLineState {
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

    final auxRow = _buildAuxRow();
    // 原文与译文共用同一侧基线：左对齐按起始边，居中按中心，右对齐按末端。
    final crossAxisAlignment =
        widget.textAlign == TextAlign.center
            ? CrossAxisAlignment.center
            : widget.textAlign == TextAlign.right
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start;
    final translation =
        widget.settings.translationEnabled ? _translationText : null;
    if (translation == null) {
      if (auxRow == null) {
        return mainChild;
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxisAlignment,
        children: [mainChild, auxRow],
      );
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
    // 原文与译文共用同一侧基线：交叉轴对齐方式与上面一致。
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
        if (auxRow != null) auxRow,
      ],
    );
  }

  /// 在读行下方的时间标签（样例 `lyric-meta` 的胶囊部分）：波形图标 + 本行
  /// 起始时间。整行已挂跳转手势，标签不再挂二次手势，点击由整行的 `onTap`
  /// （跳回本句起点）承接。
  Widget? _buildAuxRow() {
    final spec = widget.spec;
    if (spec == null || !widget.active || spec.activeAuxReserve <= 0) {
      return null;
    }
    final scale = widget.scale;
    final accent = widget.accentColor ?? spec.activeTextColor;
    final height = spec.activeAuxReserve;
    final stampStyle = TextStyle(
      color: accent,
      fontSize: spec.activeAuxFontSize,
      height: 1.1,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6 * scale,
    );
    return Padding(
      padding: EdgeInsets.only(top: spec.activeAuxGap),
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              key: const ValueKey('music-lyric-aux-pill'),
              decoration: BoxDecoration(
                color: kMusicLyricAuxPillFill,
                borderRadius: BorderRadius.circular(height / 2),
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: kMusicLyricAuxPillBorderAlpha,
                  ),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 9 * scale),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.graphic_eq,
                      size: spec.activeAuxIconSize,
                      color: accent.withValues(alpha: 0.85),
                    ),
                    SizedBox(width: 5 * scale),
                    Text(
                      _formatLyricStamp(widget.line.position),
                      style: stampStyle,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
