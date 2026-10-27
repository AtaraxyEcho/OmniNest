import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_stylesheet.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_image.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_table_block_view.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_content.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 单个正文块的统一渲染（连续滚动与翻页共用）。
///
/// 样式与 [ReaderViewContent.spanStyle] 同源；链接/图片手势由本组件自行持有。
class ReaderContentBlockItem extends StatefulWidget {
  const ReaderContentBlockItem({
    required this.block,
    required this.settings,
    required this.itemId,
    required this.chapterId,
    this.onLinkTap,
    this.onImageTap,
    this.isFirstBlockContinuation = false,
    this.clampImageSlotToConstraints = true,
    super.key,
  });

  final ContentBlock block;
  final ReaderViewSettings settings;
  final String itemId;
  final String chapterId;
  final ValueChanged<String>? onLinkTap;
  final ValueChanged<String>? onImageTap;

  /// 续接页首块不加首行缩进（翻页模式切页时使用）。
  final bool isFirstBlockContinuation;

  /// 图片槽位是否按可用高度钳制（滚动列表用确定高度时必须关掉）。
  final bool clampImageSlotToConstraints;

  /// 标题块之后的额外段间距，与滚动列表条目高度同源。
  ///
  /// 这条间距属于标题块自身的盒（由标题条目的下内边距产生），因此必须
  /// 同时进入滚动高度表与翻页装页：只有一侧计入会让块实际占据的高度与表不符，
  /// 字符偏移↔像素映射按标题数累积漂移，翻页则按短了 24px 的口径塞标题。
  static const double headingBottomSpacing = 24.0;

  /// 标题条目的上、下内边距（`headingBottomSpacing` 叠在下内边距之后）。
  ///
  /// 取稿子 `.article-column h1` 的 `margin: 14px 0 32px`：上边距 14，下边距由
  /// `8 + 24` 合成本来就是 32。`headingHeight` 逐项引用这两个常量，改这里不必动测量。
  static const double headingTopPadding = 14.0;
  static const double headingBottomPadding = 8.0;

  /// 分割线条目的上下留白与中央字形高度。
  ///
  /// 分割线的块高不是那条细线，而是 `Padding` + `Stack` 里最高的子项；
  /// 测高侧必须引用这两个常量，否则改渲染一侧会静默让高度表偏小。
  static const double dividerVerticalPadding = 24.0;
  static const double dividerGlyphSize = 16.0;

  /// 引用块按稿子 `.article-column blockquote`：外边距 30/32、内衬上下各 4、左内缩 22。
  static const double blockquoteOuterTopPadding = 30.0;
  static const double blockquoteOuterBottomPadding = 32.0;
  static const double blockquoteInnerVerticalPadding = 4.0;
  static const double blockquoteInnerLeftPadding = 22.0;

  /// 强调条：3px 宽、圆角 3、上下各内缩 3px（稿子 `::before` 的 `top/bottom: 3px`），
  /// 纯强调色且**没有底色**（稿子的引用块只有条，没有面板底）。
  static const double blockquoteBarWidth = 3.0;
  static const double blockquoteBarInset = 3.0;
  static const double blockquoteBarRadius = 3.0;

  /// 列表条目外层留白与单项底间距。
  static const double listVerticalPadding = 8.0;
  static const double listItemBottomSpacing = 4.0;

  /// 列表符号列宽度，同时是正文可用宽度的扣减量。
  static const double listMarkerColumnWidth = 24.0;

  /// 表格外层留白、单元格纵向留白与行底边框宽度。
  ///
  /// 表格高度是"逐行相加"的，这三项每行都出现一次；渲染与测量各写一份字面量时，
  /// 改一侧会让整表高度静默偏差，行数越多偏差越大。
  static const double tableVerticalPadding = 12.0;
  static const double tableCellVerticalPadding = 6.0;
  static const double tableRowBorderWidth = 1.0;

  /// 块的文字行之外、由渲染条目自身加上的固定高度。
  ///
  /// 翻页装页按视觉行逐行累加，这一份必须单独加上：漏算的一页在页底报
  /// RenderFlex 溢出，多算的白丢一行。原子块（标题、图片、分隔线、表格）
  /// 的同类间距已经折进 `measureBlockHeight`，这里返回 0，避免两处各算一遍。
  ///
  /// 段落间距取 `ReaderViewSettings.paragraphSpacingScale`：渲染条目里那段
  /// SizedBox 用的是同一个表达式，书表达过段距时两侧才不会再次分叉。
  static double blockChromeHeight(
    ContentBlock block,
    ReaderViewSettings settings,
  ) =>
      blockLeadingChrome(block, settings) +
      blockTrailingChrome(block, settings);

  /// 页头收取的那一份：块在这一页起头时先扣掉，再逐行判预算。
  ///
  /// 引用块的盒子上留白只属于**首段**（`hasTopPadding` 由裁剪侧按片段给），
  /// 跨页引用的续页不再画它，装页也不该收；一次收取整块的留白会让续页白丢 24px。
  static double blockLeadingChrome(
    ContentBlock block,
    ReaderViewSettings settings,
  ) {
    return switch (block) {
      ParagraphBlock(:final hasTrailingSpacing, :final style) =>
        settings.fontSize *
            settings.paragraphSpacingScaleFor(
              bookStyle: style,
              hasTrailingSpacing: hasTrailingSpacing,
            ),
      BlockquoteBlock(:final hasTopPadding) =>
        hasTopPadding
            ? blockquoteOuterTopPadding + blockquoteInnerVerticalPadding
            : 0.0,
      // 列表的每行间距在装页里按行收取，两处外留白整份留在页头：旧口径如此，
      // 拆开只会让跨页列表的两头各少一份，白丢一页的行。
      ListBlock(:final items) =>
        listVerticalPadding * 2 + listItemBottomSpacing * items.length,
      _ => 0.0,
    };
  }

  /// 页尾收取的那一份：只有把块的最后一行放在本页的那一页才扣。
  ///
  /// 段前间距是**前一块之后**的留白（`_foldParagraphTopMargins` 已把它折进前一段的
  /// 尾距），渲染条目把它画在文字行之前，所以归在页头那份里。
  static double blockTrailingChrome(
    ContentBlock block,
    ReaderViewSettings settings,
  ) {
    return switch (block) {
      BlockquoteBlock(:final style, :final hasBottomPadding) =>
        hasBottomPadding
            // 引用块自己的下外边距按块级量收取，且只随最后一份：`hasTrailingSpacing`
            // 是 `<br><br>` 的正文信号，跟书在 blockquote 上写的间距无关。
            ? blockquoteOuterBottomPadding +
                blockquoteInnerVerticalPadding +
                settings.fontSize *
                    settings.paragraphSpacingScaleFor(
                      bookStyle: style,
                      hasTrailingSpacing: false,
                    )
            : 0.0,
      _ => 0.0,
    };
  }

  /// 标题相对正文的字号倍率：测量折行与渲染必须取同一份，否则标题占的
  /// 行数两侧不一致，块高差直接落进页区间。
  ///
  /// 一档倍率来自稿子 `.article-column h1` 的 `clamp(31px, 8vw, 43px)`：手机基线取到
  /// 下界 31px，正文默认 19px，折成倍率约 1.63。阅读器按**用户的字号**缩放而不是
  /// 按视口，所以只取这个比值、不复刻 clamp；稿子只写了 h1，h2 及更深沿用原档位。
  static const double headingLevel1Scale = 1.63;
  static const double headingLevel2Scale = 1.25;

  /// 行高、字重与字距同样只有 h1 由稿子给出（`line-height: 1.25`、`font-weight: 600`、
  /// `letter-spacing: -0.04em`），h2 及更深维持阅读器既有档位。
  static const double headingLevel1LineHeight = 1.25;
  static const double headingLineHeight = 1.4;
  static const FontWeight headingLevel1FontWeight = FontWeight.w600;
  static const FontWeight headingDeeperFontWeight = FontWeight.w700;
  static const double headingLevel1LetterSpacingScale = -0.04;

  static double headingFontSize({
    required int level,
    required double fontSize,
  }) => fontSize * (level == 1 ? headingLevel1Scale : headingLevel2Scale);

  /// 标题样式的唯一出处：绘制与分页测量都只能经由这里取数。
  ///
  /// 字距按未缩放的字号折算，与框架 `TextScaler` 只放大 `fontSize`、原样透传
  /// `letterSpacing` 的行为一致；测量侧要放大时同样只 `copyWith(fontSize:)`，
  /// 另写一份 TextStyle 就会在系统字号缩放 ≠ 1 时折出不同的行数。
  static TextStyle headingStyle(ReaderViewSettings settings, int level) {
    final fontSize = headingFontSize(level: level, fontSize: settings.fontSize);
    return TextStyle(
      fontFamily: settings.resolvedFontFamily,
      color: settings.onSurfaceColor.withValues(alpha: 0.90),
      fontSize: fontSize,
      height: level == 1 ? headingLevel1LineHeight : headingLineHeight,
      letterSpacing:
          fontSize * (level == 1 ? headingLevel1LetterSpacingScale : 0.0),
      fontWeight:
          level == 1 ? headingLevel1FontWeight : headingDeeperFontWeight,
    );
  }

  /// 行内样式入口，与分页测量共用同一份实现。
  static TextStyle spanStyle(
    ReaderInlineSpan span,
    ReaderViewSettings settings,
  ) => ReaderViewContent.spanStyle(span, settings);

  @override
  State<ReaderContentBlockItem> createState() => _ReaderContentBlockItemState();
}

class _ReaderContentBlockItemState extends State<ReaderContentBlockItem> {
  int _imageRetry = 0;
  final Map<int, TapGestureRecognizer> _recognizers = {};

  @override
  void dispose() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.block) {
      HeadingBlock(:final text, :final level, :final align) => _heading(
        text,
        level,
        align,
      ),
      ParagraphBlock(:final lines, :final hasTrailingSpacing, :final style) =>
        _paragraphBlock(
          lines: lines,
          style: style,
          hasTrailingSpacing: hasTrailingSpacing,
        ),
      ImageBlock block => ReaderContentImage(
        block: block,
        itemId: widget.itemId,
        settings: widget.settings,
        retryCount: _imageRetry,
        onTap: (_) => widget.onImageTap?.call(block.src),
        onRetry: () => setState(() => _imageRetry++),
        clampSlotToConstraints: widget.clampImageSlotToConstraints,
      ),
      DividerBlock() => _divider(),
      BlockquoteBlock block => _blockquote(block),
      ListBlock block => _list(block),
      TableBlock block => _table(block),
    };
  }

  Widget _heading(String text, int level, TextAlign? bookAlign) {
    return Padding(
      padding: const EdgeInsets.only(
        top: ReaderContentBlockItem.headingTopPadding,
        bottom:
            ReaderContentBlockItem.headingBottomPadding +
            ReaderContentBlockItem.headingBottomSpacing,
      ),
      child: Text(
        text,
        style: ReaderContentBlockItem.headingStyle(widget.settings, level),
        // 对齐由开关决定是否接管；高度只看文本行数，居中不会改变行数，
        // 所以测量侧不需要跟着改。
        textAlign: widget.settings.headingAlign(bookAlign),
      ),
    );
  }

  /// 段前间距与正文的装配。间距倍率取自 `paragraphSpacingScaleFor`，为 0 时不加。
  Widget _paragraphBlock({
    required List<LineData> lines,
    required ParagraphStyleSpec? style,
    required bool hasTrailingSpacing,
  }) {
    final spacing =
        widget.settings.fontSize *
        widget.settings.paragraphSpacingScaleFor(
          bookStyle: style,
          hasTrailingSpacing: hasTrailingSpacing,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (spacing > 0) SizedBox(height: spacing),
        _paragraph(lines, style),
      ],
    );
  }

  Widget _paragraph(List<LineData> lines, ParagraphStyleSpec? style) {
    // 书的行高倍率只在跟随档生效，且必须与测量侧取同一份（见 `lineHeightScaleFor`）。
    final lineHeightScale = widget.settings.lineHeightScaleFor(style);
    return Text.rich(
      TextSpan(
        style: widget.settings.bodyStyleWith(lineHeightScale: lineHeightScale),
        children: _lineSpans(
          lines,
          textScale: MediaQuery.textScalerOf(context).scale(1.0),
        ),
      ),
      // 稿子 `.article-column > p` 是 text-align: justify + text-justify:
      // inter-ideograph；Flutter 3.47 没有 text-justify 这一档，只能按词两端
      // 对齐，中文混排的大缝比稿子明显。书表达过对齐时由层叠接管。
      textAlign: widget.settings.paragraphAlign(style),
      strutStyle: widget.settings.bodyStrutStyle(
        lineHeightScale: lineHeightScale,
      ),
    );
  }

  /// 段落与引用块共用的绘制文本装配。
  ///
  /// 行间是否补换行、是否补首行缩进一律走 [paragraphGap]，与测量侧
  /// `_ReaderPaginationTextLayout.measureVisualLines` 是同一条规则：两处各写一份
  /// 时，同一块会按带缩进的文本折行、按不带缩进的文本绘制，行差落在页区间和
  /// 字符偏移上。空行只在**本行确有内容**时修剪行尾空格，否则会连带把刚补出的
  /// 缩进剪掉，与测量侧的文本长度不再等距。
  ///
  /// [textScale] 取环境缩放：缩进盒子不是文本，框架不会替它放大，两侧必须
  /// 按同一个倍数换算宽度。
  List<InlineSpan> _lineSpans(List<LineData> lines, {double textScale = 1}) {
    final allSpans = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final gap = paragraphGap(
        isFirstLine: i == 0,
        isNewParagraph: line.isNewParagraph,
        previousLineIsEmpty: i > 0 && lines[i - 1].spans.isEmpty,
        isBlockContinuation: widget.isFirstBlockContinuation,
        startsWithFullWidthIndent: lineStartsWithFullWidthIndent(line.spans),
        indentChars: widget.settings.firstLineIndentChars(line.style),
        isSoftWrap: line.softWrap,
      );
      allSpans.addAll(
        paragraphGapSpans(
          gap,
          indentWidth: widget.settings.indentBoxWidth(
            indentChars: gap.indentChars,
            blockquote: _isQuote,
            textScale: textScale,
          ),
        ),
      );
      _collectSpans(allSpans, line.spans);
      if (line.spans.isNotEmpty) {
        trimTrailingSpacesInSpans(allSpans);
      }
    }
    return allSpans;
  }

  /// 本条目正在绘制的块是否为引用块：引用块的字号比正文大 1px。
  bool get _isQuote => widget.block is BlockquoteBlock;

  void _collectSpans(List<InlineSpan> out, List<ReaderInlineSpan> spans) {
    for (final span in spans) {
      // 字号、字族已在 spanStyle 内表达（含行内代码），此处只补不影响字宽的绘制属性。
      var style = ReaderContentBlockItem.spanStyle(span, widget.settings);
      if (span.backgroundColor != null) {
        style = style.copyWith(backgroundColor: span.backgroundColor);
      }
      if (span.isCode) {
        style = style.copyWith(
          backgroundColor:
              span.backgroundColor ??
              widget.settings.onSurfaceVariantColor.withValues(alpha: 0.08),
        );
      }
      if (span.href != null) {
        out.add(
          TextSpan(
            text: span.text,
            style: style.copyWith(
              color: widget.settings.accentColor,
              decoration: TextDecoration.underline,
            ),
            recognizer: _recognizerFor(span.startOffset, span.href!),
          ),
        );
        continue;
      }
      out.add(TextSpan(text: span.text, style: style));
    }
  }

  TapGestureRecognizer _recognizerFor(int startOffset, String href) {
    final key = Object.hash(widget.chapterId, startOffset, href);
    return _recognizers.putIfAbsent(key, () {
      return TapGestureRecognizer()..onTap = () => widget.onLinkTap?.call(href);
    });
  }

  Widget _divider() {
    final lineColor = widget.settings.onSurfaceVariantColor.withValues(
      alpha: 0.20,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: ReaderContentBlockItem.dividerVerticalPadding,
      ),
      child: Center(
        child: SizedBox(
          width: 96,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(height: 0.5, color: lineColor),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: widget.settings.surfaceColor,
                child: Icon(
                  Icons.auto_stories_rounded,
                  color: widget.settings.onSurfaceVariantColor.withValues(
                    alpha: 0.36,
                  ),
                  size: ReaderContentBlockItem.dividerGlyphSize,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blockquote(BlockquoteBlock block) {
    final bookSpacing =
        widget.settings.fontSize *
        widget.settings.paragraphSpacingScaleFor(
          bookStyle: block.style,
          hasTrailingSpacing: false,
        );
    // 盒子的上下留白属于整个引用而不是每一段：拆段后只有带标记的那一侧画，
    // 相邻两段因此是相接的（竖条与底色连成一条），不会各凭空多出 48px。
    final spacing = block.hasBottomPadding ? bookSpacing : 0.0;
    final outerTop =
        block.hasTopPadding
            ? ReaderContentBlockItem.blockquoteOuterTopPadding
            : 0.0;
    final outerBottom =
        block.hasBottomPadding
            ? ReaderContentBlockItem.blockquoteOuterBottomPadding + spacing
            : 0.0;
    final innerTop =
        block.hasTopPadding
            ? ReaderContentBlockItem.blockquoteInnerVerticalPadding
            : 0.0;
    final innerBottom =
        block.hasBottomPadding
            ? ReaderContentBlockItem.blockquoteInnerVerticalPadding
            : 0.0;
    return Padding(
      // 书在 blockquote 上写过的下外边距加在引用盒之外，与 `blockChromeHeight`
      // 收取的是同一个表达式；强调条只跟着文字盒，不跟着外边距拉长。
      padding: EdgeInsets.only(top: outerTop, bottom: outerBottom),
      child: Padding(
        padding: EdgeInsets.only(top: innerTop, bottom: innerBottom),
        child: Stack(
          children: [
            // 稿子的强调条是 3px 圆角胶囊、上下各内缩 3px，且引用块没有底色。
            Positioned(
              left: 0,
              top: ReaderContentBlockItem.blockquoteBarInset,
              bottom: ReaderContentBlockItem.blockquoteBarInset,
              child: Container(
                width: ReaderContentBlockItem.blockquoteBarWidth,
                decoration: BoxDecoration(
                  color: widget.settings.accentColor,
                  borderRadius: BorderRadius.circular(
                    ReaderContentBlockItem.blockquoteBarRadius,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                left: ReaderContentBlockItem.blockquoteInnerLeftPadding,
              ),
              child: Text.rich(
                TextSpan(
                  // 稿子：引用文字比正文大 1px、行高固定 1.75、色偏强调色。
                  style: widget.settings
                      .blockquoteStyle(
                        lineHeightScale: widget.settings.lineHeightScaleFor(
                          block.style,
                        ),
                      )
                      .copyWith(color: widget.settings.quoteTextColor),
                  children: _lineSpans(
                    block.lines,
                    textScale: MediaQuery.textScalerOf(context).scale(1.0),
                  ),
                ),
                // 引用块默认起始对齐（正文默认两端对齐），只有书在 blockquote 上表达过
                // 对齐且读者开了跟随原书时才接管。
                textAlign: widget.settings.blockquoteAlign(block.style),
                strutStyle: widget.settings.blockquoteStrutStyle(
                  lineHeightScale: widget.settings.lineHeightScaleFor(
                    block.style,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(ListBlock block) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: ReaderContentBlockItem.listVerticalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < block.items.length; i++)
            Padding(
              padding: const EdgeInsets.only(
                bottom: ReaderContentBlockItem.listItemBottomSpacing,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: ReaderContentBlockItem.listMarkerColumnWidth,
                    child: Text(
                      block.isOrdered ? '${i + 1}.' : '•',
                      style: TextStyle(
                        color: widget.settings.onSurfaceColor.withValues(
                          alpha: 0.70,
                        ),
                        fontSize: widget.settings.fontSize,
                        height: widget.settings.lineHeight,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          for (final span in block.items[i].spans)
                            _listOrTableSpan(span),
                        ],
                      ),
                      strutStyle: widget.settings.bodyStrutStyle(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  InlineSpan _listOrTableSpan(ReaderInlineSpan span, {FontWeight? weight}) {
    var style = ReaderContentBlockItem.spanStyle(span, widget.settings);
    if (span.backgroundColor != null) {
      style = style.copyWith(backgroundColor: span.backgroundColor);
    }
    if (weight != null) {
      style = style.copyWith(fontWeight: weight);
    }
    if (span.href != null) {
      return TextSpan(
        text: span.text,
        style: style.copyWith(
          color: widget.settings.accentColor,
          decoration: TextDecoration.underline,
        ),
        recognizer: _recognizerFor(span.startOffset, span.href!),
      );
    }
    return TextSpan(text: span.text, style: style);
  }

  Widget _table(TableBlock block) {
    return ReaderTableBlockView(
      rows: block.rows,
      settings: widget.settings,
      spanBuilder: _listOrTableSpan,
    );
  }
}
