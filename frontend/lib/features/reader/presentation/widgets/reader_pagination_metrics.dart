part of 'reader_pagination_engine.dart';

/// 负责阅读内容块的像素高度测量与文本样式转换。
abstract final class _ReaderPaginationMetrics {
  static double headingHeight(
    String text,
    int level,
    double effectiveWidth,
    ReaderViewSettings settings,
    double textScale,
  ) {
    // 渲染侧标题继承环境 textScaler，测量必须同样放大：否则大字体下
    // 标题条目被确定高度裁掉。
    final baseSize =
        (level == 1 ? settings.fontSize * 1.5 : settings.fontSize * 1.25) *
        textScale;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: settings.resolvedFontFamily,
          fontSize: baseSize,
          height: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: effectiveWidth);
    // 与 ReaderContentBlockItem._heading 的 Padding(top:8, bottom:8) 对齐。
    return 8 + painter.height + 8;
  }

  /// 图片固定槽位高度：与 ReaderContentImage 的渲染槽一致。
  ///
  /// 槽位在解码前后保持不变，测高与真实布局零漂移；640 上限接近手机
  /// 端既有视觉量级（0.78 视口），纯宽度公式使测高无需视口参数。
  static double imageSlotHeight(double effectiveWidth) {
    return math.min(effectiveWidth * 1.35, 640);
  }

  static double imageHeight(double effectiveWidth, String? caption) {
    // 与 ReaderContentImage 一致：Padding 24*2 + 容器边框 1*2 + 固定槽位 + 可选题注。
    // 边框计入是必须的：Container 会把 BoxDecoration.padding（边框宽度）加进自身
    // 尺寸，漏算会让每个图片位置比真实布局少 2px，多图章节累积成明显位置漂移。
    var height = imageSlotHeight(effectiveWidth) + 48 + 2;
    final captionText = caption?.trim() ?? '';
    if (captionText.isNotEmpty) {
      // 题注：top 10 + TextPainter（与渲染 Text 同字号/字形）。
      final painter = TextPainter(
        text: TextSpan(
          text: captionText,
          style: const TextStyle(
            fontSize: AppTypography.bodyMedium,
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: null,
      )..layout(maxWidth: effectiveWidth);
      height += 10 + painter.height;
    }
    return height;
  }

  /// 分割线块高：`Padding(上下)` + `Stack`，Stack 取最高子项（带字形的容器），
  /// 而不是那条 0.5 的细线。常量与渲染共用，避免一侧改窄后静默裁字。
  /// 分割线块高：`Padding(上下)` + `Stack`，Stack 取最高子项（带字形的容器），
  /// 而不是那条 0.5 的细线。常量与渲染共用，避免一侧改窄后静默裁字。
  static const dividerHeight =
      ReaderContentBlockItem.dividerVerticalPadding * 2 +
      ReaderContentBlockItem.dividerGlyphSize;

  static double listHeight(
    List<ListItemData> items,
    double effectiveWidth,
    ReaderViewSettings settings,
    double textScale,
  ) {
    var height = 8.0;
    final textWidth = effectiveWidth - 24;
    for (final item in items) {
      final spans = lineTextSpans(item.spans, settings, textScale);
      if (spans.isEmpty) {
        height += 4;
        continue;
      }
      final painter = TextPainter(
        text: TextSpan(
          children: spans,
          style: baseStyle(settings, settings.fontSize * textScale),
        ),
        strutStyle: settings.bodyStrutStyle(textScale: textScale),
        textDirection: TextDirection.ltr,
        maxLines: null,
      )..layout(maxWidth: textWidth);
      height += painter.height + 4;
    }
    return height + 8;
  }

  static double tableHeight(
    List<TableRowData> rows,
    double effectiveWidth,
    ReaderViewSettings settings,
    double textScale,
  ) {
    var height = 12.0;
    for (final row in rows) {
      var maxCellHeight = 0.0;
      for (final cell in row.cells) {
        final spans = lineTextSpans(cell, settings, textScale);
        if (spans.isEmpty) continue;
        final painter = TextPainter(
          text: TextSpan(
            children: spans,
            style: baseStyle(settings, settings.fontSize * textScale),
          ),
          strutStyle: settings.bodyStrutStyle(textScale: textScale),
          textDirection: TextDirection.ltr,
          maxLines: null,
        )..layout(maxWidth: effectiveWidth);
        if (painter.height > maxCellHeight) {
          maxCellHeight = painter.height;
        }
      }
      height += maxCellHeight + 12;
    }
    return height + 12;
  }

  static TextStyle baseStyle(ReaderViewSettings settings, double fontSize) {
    return TextStyle(
      fontFamily: settings.resolvedFontFamily,
      fontSize: fontSize,
      height: settings.lineHeight,
    );
  }

  static List<TextSpan> lineTextSpans(
    List<ReaderInlineSpan> spans,
    ReaderViewSettings settings,
    double textScale,
  ) {
    if (spans.isEmpty) return const [];
    return spans.map((span) {
      final style = ReaderViewContent.spanStyle(span, settings).copyWith(
        fontSize:
            (span.isCode ? settings.fontSize * 0.9 : settings.fontSize) *
            textScale,
        fontFamily:
            span.isCode
                ? AppTypography.monoFamily
                : settings.resolvedFontFamily,
        fontFamilyFallback:
            span.isCode ? AppTypography.monoFamilyFallback : null,
      );
      return TextSpan(text: span.text, style: style);
    }).toList();
  }
}
