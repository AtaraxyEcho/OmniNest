import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_image.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
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

  /// 与 [ReaderViewContent.spanStyle] 同源，供测量与渲染共用。
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
      HeadingBlock(:final text, :final level) => _heading(text, level),
      ParagraphBlock(:final lines, :final hasTrailingSpacing) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasTrailingSpacing)
            SizedBox(height: widget.settings.fontSize * 0.6),
          _paragraph(lines),
        ],
      ),
      ImageBlock block => ReaderContentImage(
        block: block,
        itemId: widget.itemId,
        settings: widget.settings,
        retryCount: _imageRetry,
        onTap: (_) => widget.onImageTap?.call(block.src),
        onRetry: () => setState(() => _imageRetry++),
      ),
      DividerBlock() => _divider(),
      BlockquoteBlock block => _blockquote(block),
      ListBlock block => _list(block),
      TableBlock block => _table(block),
    };
  }

  Widget _heading(String text, int level) {
    final baseSize =
        level == 1
            ? widget.settings.fontSize * 1.5
            : widget.settings.fontSize * 1.25;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: widget.settings.resolvedFontFamily,
          color: widget.settings.onSurfaceColor.withValues(alpha: 0.90),
          fontSize: baseSize,
          height: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _paragraph(List<LineData> lines) {
    final allSpans = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineText = line.spans.map((s) => s.text).join();
      final hasIndent = lineText.startsWith('　　');
      if (i > 0) {
        final prevIsEmpty = lines[i - 1].spans.isEmpty;
        if (line.isNewParagraph && !prevIsEmpty) {
          allSpans.add(TextSpan(text: hasIndent ? '\n' : '\n　　'));
        } else {
          allSpans.add(const TextSpan(text: '\n'));
        }
      } else if (!hasIndent && !widget.isFirstBlockContinuation) {
        allSpans.add(const TextSpan(text: '　　'));
      }
      _collectSpans(allSpans, line.spans);
      _trimTrailingSpaces(allSpans);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(style: widget.settings.bodyStyle, children: allSpans),
        strutStyle: widget.settings.bodyStrutStyle(),
      ),
    );
  }

  void _collectSpans(List<InlineSpan> out, List<ReaderInlineSpan> spans) {
    for (final span in spans) {
      var style = ReaderContentBlockItem.spanStyle(span, widget.settings);
      if (span.backgroundColor != null) {
        style = style.copyWith(backgroundColor: span.backgroundColor);
      }
      if (span.isCode) {
        style = style.copyWith(
          fontFamily: AppTypography.monoFamily,
          fontFamilyFallback: AppTypography.monoFamilyFallback,
          fontSize: widget.settings.fontSize * 0.9,
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

  void _trimTrailingSpaces(List<InlineSpan> spans) {
    if (spans.isEmpty) {
      return;
    }
    final last = spans.last;
    if (last is TextSpan && last.text != null) {
      final trimmed = last.text!.trimRight();
      if (trimmed.length != last.text!.length) {
        spans[spans.length - 1] = TextSpan(
          text: trimmed,
          style: last.style,
          recognizer: last.recognizer,
        );
      }
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
      padding: const EdgeInsets.symmetric(vertical: 24),
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
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blockquote(BlockquoteBlock block) {
    final allSpans = <InlineSpan>[];
    for (var i = 0; i < block.lines.length; i++) {
      if (i > 0) {
        allSpans.add(const TextSpan(text: '\n'));
      }
      _collectSpans(allSpans, block.lines[i].spans);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.only(left: 16, top: 12, bottom: 12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: widget.settings.accentColor.withValues(alpha: 0.6),
              width: 3,
            ),
          ),
          color: widget.settings.onSurfaceVariantColor.withValues(alpha: 0.06),
        ),
        child: Text.rich(
          TextSpan(style: widget.settings.bodyStyle, children: allSpans),
          strutStyle: widget.settings.bodyStrutStyle(),
        ),
      ),
    );
  }

  Widget _list(ListBlock block) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < block.items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
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
    if (block.rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in block.rows)
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: widget.settings.onSurfaceVariantColor.withValues(
                        alpha: 0.15,
                      ),
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final cell in row.cells)
                      Container(
                        constraints: const BoxConstraints(minWidth: 60),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color:
                              row.isHeader
                                  ? widget.settings.onSurfaceVariantColor
                                      .withValues(alpha: 0.08)
                                  : null,
                        ),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              for (final span in cell)
                                _listOrTableSpan(
                                  span,
                                  weight:
                                      row.isHeader
                                          ? FontWeight.w700
                                          : span.isBold
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                ),
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
      ),
    );
  }
}
