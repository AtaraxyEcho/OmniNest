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
    // 渲染侧标题继承环境 textScaler，测量必须同样放大：框架的 TextScaler 只放大
    // fontSize，字距与行高原样透传，所以这里也只能 copyWith 字号。样式本身取自
    // ReaderContentBlockItem.headingStyle，两处各写一份就会折出不同的行数。
    final authored = ReaderContentBlockItem.headingStyle(settings, level);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: authored.copyWith(
          fontSize:
              ReaderContentBlockItem.headingFontSize(
                level: level,
                fontSize: settings.fontSize,
              ) *
              textScale,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: effectiveWidth);
    // 与标题条目的 Padding 逐项对齐：上 14 + 文本 + 下 8 + 块后间距 24。
    return ReaderContentBlockItem.headingTopPadding +
        painter.height +
        ReaderContentBlockItem.headingBottomPadding +
        ReaderContentBlockItem.headingBottomSpacing;
  }

  /// 图片固定槽位高度：与 ReaderContentImage 的渲染槽一致。
  ///
  /// 槽位在解码前后保持不变，测高与真实布局零漂移；640 上限接近手机
  /// 端既有视觉量级（0.78 视口），纯宽度公式使测高无需视口参数。
  static double imageSlotHeight(double effectiveWidth) {
    return math.min(effectiveWidth * 1.35, 640);
  }

  /// 槽位之外要预留的高度：上下内边距 48 + 容器边框 2 再留 4，题注另留一行。
  static const double _imageChromeReserve = 54.0;
  static const double _imageCaptionReserve = 32.0;

  /// 题注行高倍率：渲染与测量共用，见 [imageHeight] 的题注分支。
  static const double captionLineHeight = 1.4;

  /// 把图片槽位收进可用高度；[availableHeight] 非正或无界表示不钳制。
  ///
  /// 渲染侧（`ReaderContentImage`）与测量侧共用这一条：页框给的高度是有限的，
  /// 引擎若仍按宽度公式记 690px，就会把一页算成超预算（链装页与预算对账都跟着错），
  /// 而渲染其实已经收缩放得下。滚动列表拿到的是无界高度，走原公式。
  static double clampImageSlot({
    required double slot,
    required double availableHeight,
    required bool hasCaption,
  }) {
    if (!availableHeight.isFinite || availableHeight <= 0) return slot;
    final bounded =
        availableHeight -
        _imageChromeReserve -
        (hasCaption ? _imageCaptionReserve : 0.0);
    return bounded > 0 && slot > bounded ? bounded : slot;
  }

  static double imageHeight(
    double effectiveWidth,
    String? caption, {
    double textScale = 1.0,
    double availableHeight = 0.0,
  }) {
    // 与 ReaderContentImage 一致：Padding 24*2 + 容器边框 1*2 + 固定槽位 + 可选题注。
    // 边框计入是必须的：Container 会把 BoxDecoration.padding（边框宽度）加进自身
    // 尺寸，漏算会让每个图片位置比真实布局少 2px，多图章节累积成明显位置漂移。
    final captionText = caption?.trim() ?? '';
    var height =
        clampImageSlot(
          slot: imageSlotHeight(effectiveWidth),
          availableHeight: availableHeight,
          hasCaption: captionText.isNotEmpty,
        ) +
        48 +
        2;
    if (captionText.isNotEmpty) {
      // 题注：top 10 + TextPainter（与渲染 Text 同字号/字形，字号同样受文字缩放影响：
      // 渲染侧的 Text 继承环境 textScaler，测量不乘就在大字号下少算一截，图注被裁）。
      // 行高必须显式取同一个常量：渲染侧的 Text 不写 height 时会并入主题的题注行距，
      // 测量按字体固有行高就会少算几个像素，图片块于是每块都差出一截。
      final painter = TextPainter(
        text: TextSpan(
          text: captionText,
          style: TextStyle(
            fontSize: AppTypography.bodyMedium * textScale,
            fontStyle: FontStyle.italic,
            height: captionLineHeight,
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

  /// 表格块高 = 上下外边距 + 各行高。与装页逐行扣的是同一份行高表。
  static double tableHeight(
    List<TableRowData> rows,
    ReaderViewSettings settings,
    double textScale,
  ) {
    return ReaderContentBlockItem.tableVerticalPadding * 2 +
        tableRowHeights(
          rows,
          settings,
          textScale,
        ).fold(0.0, (sum, height) => sum + height);
  }

  /// 每一行占的高度：一行不折行的文字 + 单元格上下内边距 + 该行下边框。
  ///
  /// 渲染把整张表放进横向滚动容器，单元格因此**不折行**；按列宽折行的测量会多算行数。
  /// 表格按行跨页时，装页与测量都只能经由这里取数，两处各写一份就会在页底少一行。
  static List<double> tableRowHeights(
    List<TableRowData> rows,
    ReaderViewSettings settings,
    double textScale,
  ) {
    final heights = <double>[];
    for (final row in rows) {
      var maxCellHeight = 0.0;
      for (final cell in row.cells) {
        final spans = lineTextSpans(cell, settings, textScale);
        if (spans.isEmpty) continue;
        final painter = TextPainter(
          text: TextSpan(
            children: spans,
            style: settings.measurementBaseStyle(textScale: textScale),
          ),
          strutStyle: settings.bodyStrutStyle(textScale: textScale),
          textDirection: TextDirection.ltr,
          maxLines: null,
        )..layout();
        if (painter.height > maxCellHeight) {
          maxCellHeight = painter.height;
        }
      }
      heights.add(
        maxCellHeight +
            ReaderContentBlockItem.tableCellVerticalPadding * 2 +
            ReaderContentBlockItem.tableRowBorderWidth,
      );
    }
    return heights;
  }

  /// 段落逐行实际占据的高度：取相邻行行顶的推进量，末行取段落总高减末行行顶。
  ///
  /// 不能直接累加 `LineMetrics.height`：同一行里混用字族（行内代码、上标）时它按
  /// 该行字号的倍率算，而 `RenderParagraph` 按 strut 的行距推进，实测每条等宽行少
  /// 约 3px。累加值因此比渲染矮，滚动侧的确定高度会把多出来的部分裁掉，翻页侧按
  /// 短了的口径塞页。推进量之和恒等于 `painter.height`，与渲染占据同源。
  static List<double> lineHeightsFromTops(
    List<double> lineTops,
    double totalHeight,
  ) {
    if (lineTops.isEmpty) return const [];
    return [
      for (var i = 0; i < lineTops.length; i++)
        math.max(
          0.0,
          (i + 1 < lineTops.length ? lineTops[i + 1] : totalHeight) -
              (i == 0 ? 0.0 : lineTops[i]),
        ),
    ];
  }

  static List<TextSpan> lineTextSpans(
    List<ReaderInlineSpan> spans,
    ReaderViewSettings settings,
    double textScale,
  ) {
    if (spans.isEmpty) return const [];
    return spans.map((span) {
      // 字号与字族一律取自 spanStyle：渲染侧继承环境 textScaler 时会把字号和
      // 字距一起放大，测量按同一系数缩放才不会出现"按一种宽度折行、按另一种
      // 宽度绘制"。在这里改写 fontSize 会抹掉上标/小标题/行内代码的字号。
      final style = ReaderViewContent.spanStyle(span, settings);
      return TextSpan(text: span.text, style: scaleStyle(style, textScale));
    }).toList();
  }

  /// 按缩放系数放大 TextStyle 中受文字缩放影响的度量。
  ///
  /// 只放大 fontSize：框架的 `TextStyle.getTextStyle` 对 letterSpacing/wordSpacing
  /// 原样透传，把它们一起乘会让测量比渲染宽，折行行数两侧分叉。
  static TextStyle scaleStyle(TextStyle style, double textScale) {
    if (textScale == 1.0) return style;
    return style.copyWith(fontSize: (style.fontSize ?? 0) * textScale);
  }
}
