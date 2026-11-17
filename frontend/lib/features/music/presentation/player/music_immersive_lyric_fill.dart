part of 'music_immersive_lyrics.dart';

/// 歌词逐字填充：折行度量、可视行切片与纵向渐变。
extension _MusicImmersiveLyricFill on _MusicLyricLineState {
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

  /// 用与真实排版相同的输入度量原文折行：可视行子串、行盒位置与行宽。
  ///
  /// 度量样式必须与环境 DefaultTextStyle 合并（字体族等继承属性影响折行），
  /// 行宽按裁剪后的子串实测（行尾空白不参与）。有词级数据时把每个词的
  /// 时长按字符重叠比例拆分到所在可视行，行间衔接按词级时长加权；词级数据
  /// 覆盖不足或完全缺失时回退按行宽加权。
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
    // 词级时长权重：词元按其字符区间与可视行区间的重叠占比拆分时长。整段记给
    // 起始可视行会让跨行的次行在被唱时锁在 0%，等权重轮到它时整块跳变。
    // 个别词与行文本对不上（标点、空白差异）只丢该词自身的归属，其余行仍按时间
    // 加权；只有匹配到的时长不足总演唱时长一半时才整体回退行宽加权。
    List<double>? timeWeights;
    var totalTime = 0.0;
    if (words.isNotEmpty) {
      final weights = List<double>.filled(lines.length, 0.0);
      var matchedTime = 0.0;
      var cursor = 0;
      for (final word in words) {
        // 空白词元只承载句末静默与词间空隙（`yrc` 用它表达间奏），不计入
        // 演唱时长：否则该行填充会拖着间奏慢慢爬，唱完了还没填满。
        if (word.isBlank) {
          continue;
        }
        final durationMs = word.duration.inMilliseconds.toDouble();
        totalTime += durationMs;
        final index = text.indexOf(word.text, cursor);
        if (index < 0) {
          continue;
        }
        final wordLength = math.max(word.text.length, 1);
        cursor = index + wordLength;
        matchedTime += durationMs;
        for (var k = 0; k < rawRanges.length; k++) {
          final (rangeStart, rangeEnd) = rawRanges[k];
          final overlap =
              math.min(index + wordLength, rangeEnd) -
              math.max(index, rangeStart);
          if (overlap > 0) {
            weights[k] += durationMs * overlap / wordLength;
          }
        }
      }
      if (matchedTime > 0 && matchedTime * 2 >= totalTime) {
        // 失配词的时长仍留在 totalTime 里（与 fillStateAt 的口径一致），按比例
        // 摊回各可视行，否则权重之和小于总时长，行尾永远填不满。
        if (matchedTime < totalTime) {
          final scale = totalTime / matchedTime;
          for (var k = 0; k < weights.length; k++) {
            weights[k] *= scale;
          }
        }
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
          if (timeWeight != null && timeWeight > 0) {
            final consumedTime = (fraction * totalTimeWeight -
                    timeConsumedBefore!)
                .clamp(0.0, timeWeight);
            progress = consumedTime / timeWeight;
          } else {
            // 无时长（整行无词级数据，或本可视行的词元全部失配）时按行宽兜底，
            // 锁在 0% 会让这一行唱完了仍停在非当前句色。
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
                    kMusicLyricFadeClear,
                    kMusicLyricFadeClear,
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
    return paint == _MusicLyricLineState._defaultPaint ? null : paint;
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
}
