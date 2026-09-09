import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_annotations.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_image.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_selection_range.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_content.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 多章连续滚动视图。
///
/// 将窗口内章节拼成一条滚动轴：粘性章头 + 按块虚拟化的正文，
/// 顺序滚动不重建阅读页，仅更新锚点章。
class ReaderContinuousScrollView extends StatefulWidget {
  const ReaderContinuousScrollView({
    required this.controller,
    required this.settings,
    required this.scrollController,
    required this.itemId,
    required this.annotationsByChapter,
    this.onScrollPosition,
    this.onTap,
    this.onHighlight,
    this.onAnnotate,
    this.onSelectionActive,
    this.onLinkTap,
    this.onExpandWindow,
    super.key,
  });

  final ReaderContinuousScrollController controller;
  final ReaderViewSettings settings;
  final ScrollController scrollController;
  final String itemId;
  final Map<String, List<ReaderAnnotation>> annotationsByChapter;
  final void Function(ContinuousScrollPosition position)? onScrollPosition;
  final VoidCallback? onTap;
  final void Function(String text, int start, int end, String chapterId)?
  onHighlight;
  final void Function(String text, int start, int end, String chapterId)?
  onAnnotate;
  final ValueChanged<bool>? onSelectionActive;
  final ValueChanged<String>? onLinkTap;
  final void Function({required bool forward})? onExpandWindow;

  @override
  State<ReaderContinuousScrollView> createState() =>
      _ReaderContinuousScrollViewState();
}

class _ReaderContinuousScrollViewState
    extends State<ReaderContinuousScrollView> {
  final Map<int, TapGestureRecognizer> _recognizers = {};
  final Map<String, int> _imageRetryCounts = {};
  final Map<String, _ProjectedChapterCache> _projectionCache = {};
  late final FocusNode _selectionFocusNode;
  String _selectedText = '';
  Offset? _pointerDownPosition;
  DateTime? _pointerDownAt;
  bool _pointerMoved = false;
  bool _selectionWasActiveOnPointerDown = false;
  bool _suppressNextContentTap = false;
  String? _selectionChapterId;

  @override
  void initState() {
    super.initState();
    _selectionFocusNode = FocusNode(debugLabel: 'reader-continuous-selection');
    widget.scrollController.addListener(_handleScroll);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant ReaderContinuousScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_handleScroll);
      widget.scrollController.addListener(_handleScroll);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_handleScroll);
    widget.controller.removeListener(_handleControllerChanged);
    _clearRecognizers();
    _selectionFocusNode.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _clearRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _handleScroll() {
    if (!widget.scrollController.hasClients) {
      return;
    }
    final position = widget.scrollController.position;
    final contentY = position.pixels + _viewportAnchorY();
    final resolved = widget.controller.positionAtContentY(contentY);
    if (resolved != null) {
      widget.onScrollPosition?.call(resolved);
    }
    final onExpand = widget.onExpandWindow;
    if (onExpand == null) {
      return;
    }
    if (widget.controller.shouldExpandForward(
      position.pixels,
      position.viewportDimension,
    )) {
      onExpand(forward: true);
    } else if (widget.controller.shouldExpandBackward(position.pixels)) {
      onExpand(forward: false);
    }
  }

  double _viewportAnchorY() {
    final size = MediaQuery.sizeOf(context);
    final chrome = ReaderChromeLayout.resolve(
      immersiveMode: widget.settings.immersiveMode,
      isPageMode: false,
    );
    return (size.height - chrome.viewportVerticalReserve) * 0.25;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final layout = ReaderControlLayout.resolve(
      viewport: MediaQuery.sizeOf(context),
      fontSize: widget.settings.fontSize,
      textScale: MediaQuery.textScalerOf(context).scale(1),
    );
    final slivers = _buildSlivers(context, controller);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: layout.contentFrameWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.horizontalPadding),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handlePointerDown,
            onPointerMove: _handlePointerMove,
            onPointerUp: _handlePointerUp,
            onPointerCancel: (_) => _resetPointerTracking(),
            child: SelectionArea(
              focusNode: _selectionFocusNode,
              onSelectionChanged: _handleSelectionChanged,
              contextMenuBuilder: _buildSelectionMenu,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: CustomScrollView(
                  controller: widget.scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  slivers: slivers,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSlivers(
    BuildContext context,
    ReaderContinuousScrollController controller,
  ) {
    final slivers = <Widget>[];
    for (final entry in controller.entries) {
      final title = entry.title;
      slivers.add(
        SliverPersistentHeader(
          pinned: true,
          delegate: _ChapterHeaderDelegate(
            title: title,
            settings: widget.settings,
          ),
        ),
      );
      if (!entry.isReady) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.settings.accentColor,
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        final blockCount = entry.blocks.length;
        slivers.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  RepaintBoundary(child: _buildBlockItem(entry, index)),
              childCount: blockCount,
            ),
          ),
        );
      }
      slivers.add(
        SliverToBoxAdapter(child: SizedBox(height: entry.isReady ? 48 : 24)),
      );
    }
    return slivers;
  }

  Widget _buildBlockItem(ContinuousChapterEntry entry, int blockIndex) {
    if (blockIndex < 0 || blockIndex >= entry.blocks.length) {
      return const SizedBox.shrink();
    }
    final blocks = _blocksForRender(entry);
    if (blockIndex >= blocks.length) {
      return const SizedBox.shrink();
    }
    final projected = blocks[blockIndex];
    return switch (projected) {
      HeadingBlock(:final text, :final level) => _buildHeading(text, level),
      ParagraphBlock(:final lines, :final hasTrailingSpacing) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasTrailingSpacing)
            SizedBox(height: widget.settings.fontSize * 0.6),
          _buildParagraph(lines, entry.chapterId),
        ],
      ),
      ImageBlock block => _buildImage(block),
      DividerBlock() => _buildDivider(),
      BlockquoteBlock block => _buildBlockquote(block, entry.chapterId),
      ListBlock block => _buildList(block),
      TableBlock block => _buildTable(block),
    };
  }

  /// 整章批注投影缓存：blocks 身份或批注签名变化时才重算。
  List<ContentBlock> _blocksForRender(ContinuousChapterEntry entry) {
    final annotations =
        widget.annotationsByChapter[entry.chapterId] ?? const <ReaderAnnotation>[];
    final signature = _annotationSignature(annotations);
    final cached = _projectionCache[entry.chapterId];
    if (cached != null &&
        identical(cached.sourceBlocks, entry.blocks) &&
        cached.annotationSignature == signature) {
      return cached.projected;
    }
    final List<ContentBlock> projected;
    if (annotations.isEmpty) {
      projected = entry.blocks;
    } else {
      projected = ReaderContentAnnotationProjector.apply(
        entry.blocks,
        annotations,
      );
    }
    _projectionCache[entry.chapterId] = _ProjectedChapterCache(
      sourceBlocks: entry.blocks,
      annotationSignature: signature,
      projected: projected,
    );
    // 窗口收缩时清理远章缓存，避免泄漏。
    if (_projectionCache.length > 8) {
      final live = widget.controller.entries.map((e) => e.chapterId).toSet();
      _projectionCache.removeWhere((id, _) => !live.contains(id));
    }
    return projected;
  }

  static int _annotationSignature(List<ReaderAnnotation> annotations) {
    if (annotations.isEmpty) {
      return 0;
    }
    var hash = annotations.length;
    for (final a in annotations) {
      hash = Object.hash(hash, a.id, a.startOffset, a.endOffset);
    }
    return hash;
  }

  Widget _buildHeading(String text, int level) {
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

  Widget _buildParagraph(List<LineData> lines, String chapterId) {
    final allSpans = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineText = line.spans.map((s) => s.text).join();
      final hasIndent = lineText.startsWith('　　');
      if (i > 0) {
        allSpans.add(const TextSpan(text: '\n'));
      } else if (!hasIndent) {
        allSpans.add(const TextSpan(text: '　　'));
      }
      _collectSpans(allSpans, line.spans, chapterId);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(style: widget.settings.bodyStyle, children: allSpans),
        strutStyle: widget.settings.bodyStrutStyle(),
      ),
    );
  }

  void _collectSpans(
    List<InlineSpan> out,
    List<ReaderInlineSpan> spans,
    String chapterId,
  ) {
    for (final span in spans) {
      final style = ReaderViewContent.spanStyle(span, widget.settings);
      if (span.href != null) {
        out.add(
          TextSpan(
            text: span.text,
            style: style.copyWith(
              color: widget.settings.accentColor,
              decoration: TextDecoration.underline,
            ),
            recognizer: _recognizerFor(span.startOffset, chapterId, span.href!),
          ),
        );
        continue;
      }
      out.add(TextSpan(text: span.text, style: style));
    }
  }

  TapGestureRecognizer _recognizerFor(
    int startOffset,
    String chapterId,
    String href,
  ) {
    final key = Object.hash(chapterId, startOffset);
    return _recognizers.putIfAbsent(key, () {
      return TapGestureRecognizer()
        ..onTap = () {
          _suppressNextContentTap = true;
          widget.onLinkTap?.call(href);
        };
    });
  }

  Widget _buildImage(ImageBlock block) {
    return ReaderContentImage(
      block: block,
      itemId: widget.itemId,
      settings: widget.settings,
      retryCount: _imageRetryCounts[block.src] ?? 0,
      onTap: (_) {
        _suppressNextContentTap = true;
      },
      onRetry:
          () => setState(() {
            _imageRetryCounts[block.src] =
                (_imageRetryCounts[block.src] ?? 0) + 1;
          }),
    );
  }

  Widget _buildDivider() {
    final lineColor = widget.settings.onSurfaceVariantColor.withValues(
      alpha: 0.20,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          width: 96,
          child: Container(height: 0.5, color: lineColor),
        ),
      ),
    );
  }

  Widget _buildBlockquote(BlockquoteBlock block, String chapterId) {
    final allSpans = <InlineSpan>[];
    for (var i = 0; i < block.lines.length; i++) {
      if (i > 0) {
        allSpans.add(const TextSpan(text: '\n'));
      }
      _collectSpans(allSpans, block.lines[i].spans, chapterId);
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

  Widget _buildList(ListBlock block) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < block.items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: block.isOrdered ? '${i + 1}. ' : '• ',
                      style: widget.settings.bodyStyle,
                    ),
                    for (final span in block.items[i].spans)
                      TextSpan(
                        text: span.text,
                        style: ReaderViewContent.spanStyle(
                          span,
                          widget.settings,
                        ),
                      ),
                  ],
                ),
                strutStyle: widget.settings.bodyStrutStyle(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTable(TableBlock block) {
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
              Row(
                children: [
                  for (final cell in row.cells)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        cell.map((s) => s.text).join(),
                        style: widget.settings.bodyStyle.copyWith(
                          fontWeight:
                              row.isHeader ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _handleSelectionChanged(SelectedContent? selection) {
    final selectedText = selection?.plainText.trim() ?? '';
    if (selectedText.isNotEmpty) {
      _selectedText = selectedText;
      _selectionChapterId = _resolveSelectionChapterId(selectedText);
      if (mounted) {
        setState(() {});
      }
    } else {
      _selectedText = '';
      _selectionChapterId = null;
    }
    widget.onSelectionActive?.call(_selectedText.isNotEmpty);
  }

  /// 在窗口章节中查找包含选中文本的章，优先于锚点章。
  String? _resolveSelectionChapterId(String selectedText) {
    for (final entry in widget.controller.entries) {
      if (blocksContainSelection(entry.blocks, selectedText)) {
        return entry.chapterId;
      }
    }
    return widget.controller.anchorChapterId;
  }

  Widget _buildSelectionMenu(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    final chapterId = _selectionChapterId ?? widget.controller.anchorChapterId;
    final items = <ContextMenuButtonItem>[
      ...selectableRegionState.contextMenuButtonItems,
      if (_selectedText.isNotEmpty && chapterId != null) ...[
        if (widget.onHighlight != null)
          ContextMenuButtonItem(
            label: AppLocalizations.of(context).readerHighlight,
            onPressed: () {
              final text = _selectedText;
              final range = _estimateRange(text, chapterId);
              selectableRegionState.hideToolbar();
              selectableRegionState.clearSelection();
              widget.onHighlight?.call(text, range.$1, range.$2, chapterId);
            },
          ),
        if (widget.onAnnotate != null)
          ContextMenuButtonItem(
            label: AppLocalizations.of(context).readerAddAnnotation,
            onPressed: () {
              final text = _selectedText;
              final range = _estimateRange(text, chapterId);
              selectableRegionState.hideToolbar();
              selectableRegionState.clearSelection();
              widget.onAnnotate?.call(text, range.$1, range.$2, chapterId);
            },
          ),
      ],
    ];
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableRegionState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  (int, int) _estimateRange(String selectedText, String chapterId) {
    final entry = widget.controller.entryFor(chapterId);
    if (entry == null) {
      return (0, selectedText.length);
    }
    final range = resolveSelectionRangeInBlocks(entry.blocks, selectedText);
    return range ?? (0, selectedText.length);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) {
      _resetPointerTracking();
      return;
    }
    _pointerDownPosition = event.position;
    _pointerDownAt = DateTime.now();
    _pointerMoved = false;
    _selectionWasActiveOnPointerDown = _selectedText.isNotEmpty;
    _suppressNextContentTap = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final down = _pointerDownPosition;
    if (down == null) {
      return;
    }
    if ((event.position - down).distance > 12) {
      _pointerMoved = true;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    final down = _pointerDownPosition;
    final downAt = _pointerDownAt;
    final isTapLike =
        down != null &&
        downAt != null &&
        !_pointerMoved &&
        (event.position - down).distance <= 12 &&
        DateTime.now().difference(downAt) <= const Duration(milliseconds: 450);
    final hadSelection = _selectionWasActiveOnPointerDown;
    _resetPointerTracking();
    if (!isTapLike) {
      return;
    }
    if (hadSelection) {
      _selectedText = '';
      _selectionFocusNode.unfocus();
      widget.onSelectionActive?.call(false);
      return;
    }
    scheduleMicrotask(() {
      if (!mounted || _suppressNextContentTap) {
        _suppressNextContentTap = false;
        return;
      }
      widget.onTap?.call();
    });
  }

  void _resetPointerTracking() {
    _pointerDownPosition = null;
    _pointerDownAt = null;
    _pointerMoved = false;
    _selectionWasActiveOnPointerDown = false;
  }
}

class _ProjectedChapterCache {
  const _ProjectedChapterCache({
    required this.sourceBlocks,
    required this.annotationSignature,
    required this.projected,
  });

  final List<ContentBlock> sourceBlocks;
  final int annotationSignature;
  final List<ContentBlock> projected;
}

class _ChapterHeaderDelegate extends SliverPersistentHeaderDelegate {
  _ChapterHeaderDelegate({required this.title, required this.settings});

  final String title;
  final ReaderViewSettings settings;

  @override
  double get minExtent => 36;

  @override
  double get maxExtent => 36;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final labelColor = settings.onSurfaceColor.withValues(alpha: 0.42);
    return ColoredBox(
      color: settings.surfaceColor,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: labelColor,
            height: 1.4,
            letterSpacing: 0.3,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ChapterHeaderDelegate oldDelegate) {
    return oldDelegate.title != title || oldDelegate.settings != settings;
  }
}
