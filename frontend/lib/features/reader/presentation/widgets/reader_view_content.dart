import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_annotations.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

class ReaderViewContent extends StatefulWidget {
  const ReaderViewContent({
    required this.htmlContent,
    required this.settings,
    this.itemId,
    this.annotations = const [],
    this.visibleBlocks,
    this.rawBlocks,
    this.scrollController,
    this.scrollPhysics,
    this.initialScrollOffset,
    this.isFirstBlockContinuation = false,
    this.onImageTap,
    this.onLinkTap,
    this.onHighlight,
    this.onAnnotate,
    this.onRemoveHighlight,
    this.onRemoveAnnotation,
    this.onSelectionActive,
    this.onTap,
    this.onRegisterClearSelection,
    super.key,
  });

  final String htmlContent;
  final ReaderViewSettings settings;

  /// 书籍 ID，用于从 SQLite 加载图片字节
  final String? itemId;
  final List<ReaderAnnotation> annotations;

  /// 当前页的 block 子集（用于分页模式下的页面切片渲染）。
  /// 为 null 时使用 htmlContent 解析的全量 blocks。
  final List<ContentBlock>? visibleBlocks;

  /// 全章原始 blocks（用于 _findTextOffset 批注偏移定位）。
  /// 仅在 visibleBlocks 非 null 时生效；为 null 时 fallback 到 visibleBlocks。
  final List<ContentBlock>? rawBlocks;
  final ScrollController? scrollController;
  final ScrollPhysics? scrollPhysics;

  /// 初始滚动偏移量（仅在 scrollController 为 null 时生效）。
  /// 用于恢复阅读进度时设置 ListView 的起始位置。
  final double? initialScrollOffset;

  /// 第一个 block 是否是段落续接（前一页段落的延续）。
  /// 为 true 时，第一个 block 的首行不加首行缩进。
  final bool isFirstBlockContinuation;
  final ValueChanged<String>? onImageTap;
  final ValueChanged<String>? onLinkTap;
  final void Function(String selectedText, int startOffset, int endOffset)?
  onHighlight;
  final void Function(String selectedText, int startOffset, int endOffset)?
  onAnnotate;
  final ValueChanged<ReaderAnnotation>? onRemoveHighlight;
  final ValueChanged<ReaderAnnotation>? onRemoveAnnotation;

  /// 选中状态变化回调（true=有选中文本，false=无选中）
  final ValueChanged<bool>? onSelectionActive;

  /// 未形成文本选区时点击正文的回调。
  final VoidCallback? onTap;

  /// 注册清除选中函数（子组件初始化时注册，父组件可调用）
  final void Function(VoidCallback fn)? onRegisterClearSelection;

  /// 根据 ReaderInlineSpan 的样式属性构建 TextStyle。
  ///
  /// 供分页引擎复用，确保测量与渲染的样式完全一致。
  static TextStyle spanStyle(
    ReaderInlineSpan span,
    ReaderViewSettings settings,
  ) {
    final fontSize =
        span.isHeading
            ? settings.fontSize * 1.15
            : span.isSuperscript || span.isSubscript
            ? settings.fontSize * 0.75
            : settings.fontSize;
    return TextStyle(
      fontFamily: settings.resolvedFontFamily,
      fontSize: fontSize,
      height: settings.lineHeight,
      fontWeight: span.isBold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: span.isItalic ? FontStyle.italic : FontStyle.normal,
      color: settings.onSurfaceColor.withValues(alpha: 0.90),
      decoration: TextDecoration.combine([
        if (span.isDeleted) TextDecoration.lineThrough,
        if (span.isUnderlined) TextDecoration.underline,
      ]),
      decorationColor: settings.onSurfaceColor.withValues(alpha: 0.90),
      backgroundColor:
          span.isMarked
              ? const Color(0xFFFFEB3B).withValues(alpha: 0.30)
              : null,
      fontFeatures: [
        if (span.isSuperscript) const FontFeature.superscripts(),
        if (span.isSubscript) const FontFeature.subscripts(),
      ],
    );
  }

  @override
  State<ReaderViewContent> createState() => _ReaderViewContentState();
}

class _ReaderViewContentState extends State<ReaderViewContent> {
  List<ContentBlock> _blocks = [];
  List<ContentBlock> _rawBlocks = [];
  List<int> _paragraphIndices = [];
  int _parseGeneration = 0;
  bool _isLoading = true;
  late final FocusNode _selectionFocusNode;
  String _selectedText = '';
  Offset? _pointerDownPosition;
  DateTime? _pointerDownAt;
  bool _pointerMoved = false;
  bool _selectionWasActiveOnPointerDown = false;
  bool _suppressNextContentTap = false;

  @override
  void initState() {
    super.initState();
    _selectionFocusNode = FocusNode(debugLabel: 'reader-selection');
    widget.onRegisterClearSelection?.call(clearSelection);
    if (widget.visibleBlocks != null) {
      _applyVisibleBlocks(notify: false);
    } else if (widget.rawBlocks != null && widget.rawBlocks!.isNotEmpty) {
      // 滚动模式：直接使用内容加载器已解析的 blocks，避免重复解析
      _applyRawBlocks(notify: false);
    } else {
      _parseContent();
    }
  }

  @override
  void didUpdateWidget(ReaderViewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visibleBlocks != null) {
      // 分页模式：visibleBlocks 变化时重新应用
      if (!identical(oldWidget.visibleBlocks, widget.visibleBlocks) ||
          !identical(oldWidget.annotations, widget.annotations)) {
        _applyVisibleBlocks(notify: false);
      }
    } else if (!identical(oldWidget.rawBlocks, widget.rawBlocks) &&
        widget.rawBlocks != null &&
        widget.rawBlocks!.isNotEmpty) {
      // 滚动模式：rawBlocks 变化时直接使用
      _applyRawBlocks(notify: false);
    } else if (oldWidget.htmlContent != widget.htmlContent) {
      _isLoading = true;
      _blocks = [];
      _paragraphIndices = [];
      if (widget.rawBlocks != null && widget.rawBlocks!.isNotEmpty) {
        _applyRawBlocks(notify: false);
      } else {
        _parseContent();
      }
    } else if (!identical(oldWidget.annotations, widget.annotations)) {
      // 批注列表变更但内容相同 — 基于原始块重新应用高亮
      _blocks = _applyAnnotations(_rawBlocks);
    }
  }

  @override
  void dispose() {
    _selectionFocusNode.dispose();
    super.dispose();
  }

  Future<void> _parseContent() async {
    final generation = ++_parseGeneration;
    // 小章节（<500 字符）同步解析，避免 isolate 开销；大章节在 isolate 中解析
    // Web 平台 compute 返回 JSArray，无法转为 Dart List，直接调用
    final result =
        (widget.htmlContent.length < 500 || kIsWeb)
            ? parseBlocks(widget.htmlContent)
            : await compute(parseBlocks, widget.htmlContent);
    // 检查是否已被更新的内容取代
    if (!mounted || generation != _parseGeneration) return;
    setState(() {
      _rawBlocks = result;
      _blocks = _applyAnnotations(result);
      _isLoading = false;
      _paragraphIndices = [];
      var pIndex = 0;
      for (final block in _blocks) {
        if (block is ParagraphBlock) {
          _paragraphIndices.add(pIndex++);
        } else {
          _paragraphIndices.add(-1);
        }
      }
    });
  }

  /// 分页模式：直接使用提供的 visibleBlocks，跳过 HTML 解析。
  void _applyVisibleBlocks({bool notify = true}) {
    final visible = widget.visibleBlocks!;
    _rawBlocks = widget.rawBlocks ?? visible;
    void apply() {
      _blocks = _applyAnnotations(visible);
      _isLoading = false;
      _paragraphIndices = [];
      var pIndex = 0;
      for (final block in _blocks) {
        if (block is ParagraphBlock) {
          _paragraphIndices.add(pIndex++);
        } else {
          _paragraphIndices.add(-1);
        }
      }
    }

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

  /// 滚动模式：直接使用内容加载器已解析的 rawBlocks，跳过重复 HTML 解析。
  void _applyRawBlocks({bool notify = true}) {
    final raw = widget.rawBlocks!;
    _rawBlocks = raw;
    void apply() {
      _blocks = _applyAnnotations(raw);
      _isLoading = false;
      _paragraphIndices = [];
      var pIndex = 0;
      for (final block in _blocks) {
        if (block is ParagraphBlock) {
          _paragraphIndices.add(pIndex++);
        } else {
          _paragraphIndices.add(-1);
        }
      }
    }

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

  List<ContentBlock> _applyAnnotations(List<ContentBlock> blocks) {
    return ReaderContentAnnotationProjector.apply(blocks, widget.annotations);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_blocks.isEmpty) {
      if (_isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            l10n.readerNoContent,
            style: TextStyle(
              color: widget.settings.onSurfaceVariantColor,
              fontSize: AppTypography.titleMedium,
            ),
          ),
        ),
      );
    }

    // 翻页模式（NeverScrollableScrollPhysics）：无额外 padding/spacer，避免高度不一致
    // 滚动模式：保留 padding 和末尾 spacer
    final isPageMode = widget.scrollPhysics is NeverScrollableScrollPhysics;
    final layout = ReaderControlLayout.resolve(
      viewport: MediaQuery.sizeOf(context),
      fontSize: widget.settings.fontSize,
      textScale: MediaQuery.textScalerOf(context).scale(1),
    );
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
                child:
                    isPageMode
                        ? SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (
                                var index = 0;
                                index < _blocks.length;
                                index++
                              )
                                RepaintBoundary(child: _buildBlock(index)),
                            ],
                          ),
                        )
                        : ListView.builder(
                          controller: widget.scrollController,
                          physics: widget.scrollPhysics,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          itemCount: _blocks.length + 1,
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: false,
                          itemBuilder: (context, index) {
                            if (index == _blocks.length) {
                              return const SizedBox(height: 80);
                            }
                            return RepaintBoundary(child: _buildBlock(index));
                          },
                        ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlock(int index) {
    final block = _blocks[index];
    final item = ReaderContentBlockItem(
      block: block,
      settings: widget.settings,
      itemId: widget.itemId ?? '',
      chapterId: widget.itemId ?? '',
      // 仅分页模式的首块可能是段落续接，避免后续块误去缩进。
      isFirstBlockContinuation: widget.isFirstBlockContinuation && index == 0,
      onLinkTap: _launchUrl,
      onImageTap: _handleImageTap,
    );
    // 翻页标题后保留额外间距，与分页引擎视觉一致。
    if (block is HeadingBlock) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [item, const SizedBox(height: 24)],
      );
    }
    return item;
  }

  void clearSelection() {
    _selectedText = '';
    if (!_selectionFocusNode.hasFocus) {
      widget.onSelectionActive?.call(false);
      return;
    }
    _selectionFocusNode.unfocus();
    widget.onSelectionActive?.call(false);
  }

  void _handleSelectionChanged(SelectedContent? selection) {
    final selectedText = selection?.plainText.trim() ?? '';
    if (selectedText.isNotEmpty) {
      if (mounted) {
        setState(() => _selectedText = selectedText);
      } else {
        _selectedText = selectedText;
      }
    }
    widget.onSelectionActive?.call(_selectedText.isNotEmpty);
  }

  Widget _buildSelectionMenu(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    final range = _resolveSelectionRange(_selectedText);
    final items = <ContextMenuButtonItem>[
      ...selectableRegionState.contextMenuButtonItems,
      if (range != null && widget.onHighlight != null)
        ContextMenuButtonItem(
          label: AppLocalizations.of(context).readerHighlight,
          onPressed: () {
            final selectedText = _selectedText;
            selectableRegionState.hideToolbar();
            selectableRegionState.clearSelection();
            widget.onHighlight?.call(selectedText, range.$1, range.$2);
          },
        ),
      if (range != null && widget.onAnnotate != null)
        ContextMenuButtonItem(
          label: AppLocalizations.of(context).readerAddAnnotation,
          onPressed: () {
            final selectedText = _selectedText;
            selectableRegionState.hideToolbar();
            selectableRegionState.clearSelection();
            widget.onAnnotate?.call(selectedText, range.$1, range.$2);
          },
        ),
    ];
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableRegionState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  (int, int)? _resolveSelectionRange(String selectedText) {
    if (selectedText.isEmpty) {
      return null;
    }
    final candidates = <ReaderInlineSpan>[
      ..._visibleTextSpans(),
      if (!identical(_rawBlocks, _blocks)) ..._textSpans(_rawBlocks),
    ];
    for (final span in candidates) {
      final localOffset = span.text.indexOf(selectedText);
      if (localOffset >= 0) {
        return (
          span.startOffset + localOffset,
          span.startOffset + localOffset + selectedText.length,
        );
      }
      final normalized = _findNormalizedOffset(span.text, selectedText);
      if (normalized != null) {
        return (
          span.startOffset + normalized,
          span.startOffset + normalized + selectedText.length,
        );
      }
    }
    return null;
  }

  int? _findNormalizedOffset(String source, String selectedText) {
    final normalizedSource = source.replaceAll(RegExp(r'\s+'), ' ');
    final normalizedSelection = selectedText.replaceAll(RegExp(r'\s+'), ' ');
    final normalizedOffset = normalizedSource.indexOf(normalizedSelection);
    if (normalizedOffset < 0) {
      return null;
    }
    var sourceOffset = 0;
    var normalizedIndex = 0;
    while (sourceOffset < source.length && normalizedIndex < normalizedOffset) {
      if (RegExp(r'\s').hasMatch(source[sourceOffset])) {
        while (sourceOffset < source.length &&
            RegExp(r'\s').hasMatch(source[sourceOffset])) {
          sourceOffset++;
        }
        normalizedIndex++;
      } else {
        sourceOffset++;
        normalizedIndex++;
      }
    }
    return sourceOffset;
  }

  Iterable<ReaderInlineSpan> _textSpans(List<ContentBlock> blocks) sync* {
    for (final block in blocks) {
      switch (block) {
        case ParagraphBlock(:final lines):
        case BlockquoteBlock(:final lines):
          for (final line in lines) {
            yield* line.spans;
          }
        case ListBlock(:final items):
          for (final item in items) {
            yield* item.spans;
          }
        case TableBlock(:final rows):
          for (final row in rows) {
            for (final cell in row.cells) {
              yield* cell;
            }
          }
        case HeadingBlock():
        case ImageBlock():
        case DividerBlock():
          break;
      }
    }
  }

  Iterable<ReaderInlineSpan> _visibleTextSpans() sync* {
    yield* _textSpans(_blocks);
  }

  void _launchUrl(String href) {
    _suppressNextContentTap = true;
    widget.onLinkTap?.call(href);
  }

  void _handleImageTap(String source) {
    _suppressNextContentTap = true;
    widget.onImageTap?.call(source);
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
    final pointerDownPosition = _pointerDownPosition;
    if (pointerDownPosition == null) {
      return;
    }
    if ((event.position - pointerDownPosition).distance > 12) {
      _pointerMoved = true;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    final pointerDownPosition = _pointerDownPosition;
    final pointerDownAt = _pointerDownAt;
    final isTapLike =
        pointerDownPosition != null &&
        pointerDownAt != null &&
        !_pointerMoved &&
        (event.position - pointerDownPosition).distance <= 12 &&
        DateTime.now().difference(pointerDownAt) <=
            const Duration(milliseconds: 450);
    final hadSelection = _selectionWasActiveOnPointerDown;
    _resetPointerTracking();
    if (!isTapLike) {
      return;
    }

    // 选中态下的首次点击仅清除选中，不切换控制栏；选中清除后再次点击恢复切换。
    if (hadSelection) {
      clearSelection();
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
