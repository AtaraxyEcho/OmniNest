import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/residual_chrome_colors.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_block_text.dart';
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
    this.stylesheetCss = '',
    this.scrollController,
    this.scrollPhysics,
    this.initialScrollOffset,
    this.footer,
    this.footerExtent,
    this.blockExtents,
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

  /// 这本书在 [htmlContent] 所属章节生效的样式表全文。
  ///
  /// 只在 widget 自己解析正文时用到（[visibleBlocks] 为 null 的那条路径）：
  /// 样式表不进 htmlContent，走的是书级池 + 章节次序引用，漏传就等于关掉「跟随
  /// 原书」——同一段正文会按两套排版折行，块高与字符偏移随之漂。
  final String stylesheetCss;
  final ScrollController? scrollController;
  final ScrollPhysics? scrollPhysics;

  /// 初始滚动偏移量（仅在 scrollController 为 null 时生效）。
  /// 用于恢复阅读进度时设置 ListView 的起始位置。
  final double? initialScrollOffset;

  /// 章末条目（稿子的 `.chapter-end` + `.next-chapter`）。非空时替换末尾留白，
  /// 因此必须同时给出 [footerExtent]——懒建列表按确定高度算滚动范围。
  final Widget? footer;
  final double? footerExtent;

  /// 滚动列表末尾留白条目高度，同时作为该项的确定高度。
  static const double trailingSpacerHeight = 80.0;

  /// 标题槽位在高度表之外另留的余量。
  ///
  /// 块高由 TextPainter 量得，渲染侧 RenderParagraph 的 tight 行盒与之最多差
  /// 2px（reader_block_measure_render_matrix_test 就按这条容差把关）。标题字号
  /// 是正文的 1.25/1.63 倍且一档行高收到 1.25，差值落在放大行盒上最明显，固定
  /// itemExtent 便报 RenderFlex overflowed by 2.0 pixels。表格保持"量到的值"，
  /// 余量由渲染侧吸收。
  static const double headingSlotSlack = 2.0;

  /// 逐块确定高度，来自整章测得后的章节高度表。
  ///
  /// 懒构建的 SliverList 会用已构建项的均值外推未构建项，使 maxScrollExtent
  /// 随构建进度变化；深位置恢复按虚高范围 jumpTo 后，范围收缩会把落点钳到目标
  /// 之前。给出确定高度可让滚动范围与构建进度无关。null 表示高度表尚未覆盖
  /// 整章（itemExtentBuilder 不接受空洞高度），此时沿用列表自身估算。
  final List<double>? blockExtents;

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

  /// 行内代码相对正文的字号倍率。
  static const double codeFontScale = 0.9;

  /// 行内小标题相对正文的字号倍率。
  static const double headingSpanScale = 1.15;

  /// 上标/下标相对正文的字号倍率。
  static const double scriptSpanScale = 0.75;

  /// 根据 ReaderInlineSpan 的样式属性构建 TextStyle。
  ///
  /// 供分页引擎复用，确保测量与渲染的样式完全一致。凡是**影响字宽**的属性
  /// （字号、字族）都必须只在这里表达一次：渲染侧另抄一份时，同一块文本会
  /// 按一种宽度测量、按另一种宽度折行，行差直接变成页区间与字符偏移漂移。
  static TextStyle spanStyle(
    ReaderInlineSpan span,
    ReaderViewSettings settings,
  ) {
    final fontSize =
        span.isCode
            ? settings.fontSize * codeFontScale
            : span.isHeading
            ? settings.fontSize * headingSpanScale
            : span.isSuperscript || span.isSubscript
            ? settings.fontSize * scriptSpanScale
            : settings.fontSize;
    return TextStyle(
      fontFamily:
          span.isCode ? AppTypography.monoFamily : settings.resolvedFontFamily,
      fontFamilyFallback: span.isCode ? AppTypography.monoFamilyFallback : null,
      fontSize: fontSize,
      height: settings.lineHeight,
      // 与 ReaderViewSettings.bodyStyle 同源：稿子 `.article-column > p` 的 .025em。
      letterSpacing: fontSize * ReaderViewSettings.bodyLetterSpacingScale,
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
              ? ReaderGeneratedCoverColors.highlightTint.withValues(alpha: 0.30)
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

  /// 选区语料缓存：拖动选区会反复解析同一批块，块身份不变就不必重建整章文本与偏移表。
  List<ContentBlock>? _selectionCorpusBlocks;
  ChapterSearchCorpus? _selectionCorpus;
  List<int> _paragraphIndices = [];
  int _parseGeneration = 0;
  bool _isLoading = true;
  late final FocusNode _selectionFocusNode;
  String _selectedText = '';
  String _lastSelectionRawText = '';
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
    final chapter = (html: widget.htmlContent, css: widget.stylesheetCss);
    final result =
        (widget.htmlContent.length < 500 || kIsWeb)
            ? parseChapterPayload(chapter).blocks
            : (await compute(parseChapterPayload, chapter)).blocks;
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
    final extents = widget.blockExtents;
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
                          padding: ReaderChromeLayout.scrollContentInsets(
                            viewportHeight: MediaQuery.sizeOf(context).height,
                            frame:
                                ReaderChromeLayout.resolve(
                                  immersiveMode: widget.settings.immersiveMode,
                                  isPageMode: isPageMode,
                                  safePadding: MediaQuery.viewPaddingOf(
                                    context,
                                  ),
                                ).contentPadding,
                            immersiveMode: widget.settings.immersiveMode,
                            safePadding: MediaQuery.viewPaddingOf(context),
                          ),
                          itemCount: _blocks.length + 1,
                          itemExtentBuilder:
                              extents == null
                                  ? null
                                  : (index, creator) =>
                                      index < extents.length
                                          ? extents[index] +
                                              (_blocks[index] is HeadingBlock
                                                  ? ReaderViewContent
                                                      .headingSlotSlack
                                                  : 0.0)
                                          : (widget.footerExtent ??
                                              ReaderViewContent
                                                  .trailingSpacerHeight),
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: false,
                          itemBuilder: (context, index) {
                            if (index == _blocks.length) {
                              return widget.footer ??
                                  const SizedBox(
                                    height:
                                        ReaderViewContent.trailingSpacerHeight,
                                  );
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
      // 条目高度已由高度表定死时，槽位不能再被可用高度反向钳制；
      // 页框等真有界的上下文仍然钳制，避免整块溢出。
      clampImageSlotToConstraints: widget.blockExtents == null,
      onLinkTap: _launchUrl,
      onImageTap: _handleImageTap,
    );
    // 标题后的间距属于块自身的盒（ReaderContentBlockItem._heading），
    // 不再由包装层追加：包装层里的那一份测量侧看不见，每页会按标题数少算。
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
    _lastSelectionRawText = selection?.plainText ?? '';
    final selectedText = _lastSelectionRawText.trim();
    // 桌面端第一次点击会由 SelectableRegion 自己发出"选中已清空"的空事件。
    // 只接受非空事件会让 _selectedText 长期停在旧值，之后每一次单击都被
    // 当成"仅清除选中"消费掉，控制栏再也弹不出来。
    if (mounted) {
      setState(() => _selectedText = selectedText);
    } else {
      _selectedText = selectedText;
    }
    widget.onSelectionActive?.call(selectedText.isNotEmpty);
  }

  Widget _buildSelectionMenu(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    final range = _resolveSelectionRange(_selectedText);
    // 选中范围与已有高亮重叠时，高亮项切换为取消高亮（主流阅读器语义：
    // 再次选中已高亮文本应可移除高亮，而非只能重建）。
    final overlappingHighlights =
        range == null
            ? const <ReaderAnnotation>[]
            : widget.annotations
                .where(
                  (a) => a.startOffset < range.$2 && a.endOffset > range.$1,
                )
                .toList();
    final hasHighlightOverlap = overlappingHighlights.isNotEmpty;
    // 临时诊断日志：定位「取消高亮」与批注存储偏移的对齐问题。
    readerDebugLog(
      '[reader-selection][menu] '
      'mode=${widget.visibleBlocks != null ? 'page' : 'scroll'} '
      'rawLen=${_lastSelectionRawText.length} rawHash=${_debugTextHash(_lastSelectionRawText)} '
      'trimmedLen=${_selectedText.length} trimmedHash=${_debugTextHash(_selectedText)} '
      'range=${range == null ? 'null' : '(${range.$1}, ${range.$2})'} '
      'annotations=[${_debugDescribeAnnotations(widget.annotations)}] '
      'overlap=[${_debugDescribeAnnotations(overlappingHighlights)}]',
    );
    final items = <ContextMenuButtonItem>[
      ...selectableRegionState.contextMenuButtonItems,
      if (range != null && widget.onHighlight != null && !hasHighlightOverlap)
        ContextMenuButtonItem(
          label: AppLocalizations.of(context).readerHighlight,
          onPressed: () {
            final selectedText = _selectedText;
            selectableRegionState.hideToolbar();
            selectableRegionState.clearSelection();
            widget.onHighlight?.call(selectedText, range.$1, range.$2);
          },
        ),
      if (hasHighlightOverlap && widget.onRemoveHighlight != null)
        ContextMenuButtonItem(
          // 重叠批注含备注时按「取消批注」表述，纯高亮按「取消高亮」。
          label:
              overlappingHighlights.any((a) => (a.note ?? '').isNotEmpty)
                  ? AppLocalizations.of(context).readerRemoveAnnotation
                  : AppLocalizations.of(context).readerRemoveHighlight,
          onPressed: () {
            selectableRegionState.hideToolbar();
            selectableRegionState.clearSelection();
            for (final annotation in overlappingHighlights) {
              widget.onRemoveHighlight?.call(annotation);
            }
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

  /// 把选中的可绘制文本回指到块源字符域。
  ///
  /// 逐个 span 查找在真实正文里必然落空：一个自然段会被软换行拆成多行，内联加粗、链接、
  /// 代码各自切开 span，已有高亮的边界还会再切一次——跨这些边界的选区拿不到偏移，
  /// 高亮与批注按钮整体消失；章内重复出现的短词更会永远命中首次出现的位置。
  /// 这里改用整块连续文本加逐码元源偏移映射，命中区间直接由映射表给出。
  (int, int)? _resolveSelectionRange(String selectedText) {
    if (selectedText.isEmpty) {
      return null;
    }
    // 首行缩进是定宽 WidgetSpan，选到的行首会带一个 0xFFFC 对象替换字符：
    // 它不属于任何源文本 span，先去掉再回指源文本区间。
    final needle = selectedText.replaceAll('￼', '').trim();
    if (needle.isEmpty) {
      return null;
    }
    final candidates = <List<ContentBlock>>[
      _blocks,
      if (!identical(_rawBlocks, _blocks)) _rawBlocks,
    ];
    for (final blocks in candidates) {
      final range = _matchSelectionInBlocks(blocks, needle);
      if (range != null) {
        readerDebugLog(
          '[reader-selection][range] 命中 blocks=${blocks.length} '
          'range=(${range.$1}, ${range.$2})',
        );
        return range;
      }
    }
    readerDebugLog(
      '[reader-selection][range] 未命中任何块：候选 ${candidates.length} 组，'
      '选中 len=${needle.length} hash=${_debugTextHash(needle)}',
    );
    return null;
  }

  (int, int)? _matchSelectionInBlocks(
    List<ContentBlock> blocks,
    String needle,
  ) {
    return matchCorpusRange(
      _corpusFor(blocks),
      needle,
      anchorCharOffset: _viewportAnchorCharOffset(blocks),
    );
  }

  ChapterSearchCorpus _corpusFor(List<ContentBlock> blocks) {
    if (identical(_selectionCorpusBlocks, blocks) && _selectionCorpus != null) {
      return _selectionCorpus!;
    }
    final corpus = ChapterSearchCorpus.fromBlocks(blocks);
    _selectionCorpusBlocks = blocks;
    _selectionCorpus = corpus;
    return corpus;
  }

  /// 视口中心在块源字符域的位置，用来给章内重复出现的短词就近消歧。
  ///
  /// 按块确定高度累加定位，量不到（无高度表、列表未挂载）时返回 null，
  /// 调用方退回"取第一个命中"的旧行为。
  int? _viewportAnchorCharOffset(List<ContentBlock> blocks) {
    final controller = widget.scrollController;
    final extents = widget.blockExtents;
    if (controller == null ||
        !controller.hasClients ||
        extents == null ||
        extents.isEmpty) {
      return null;
    }
    final position = controller.position;
    final target = position.pixels + position.viewportDimension * 0.5;
    final limit =
        extents.length < blocks.length ? extents.length : blocks.length;
    var consumed = 0.0;
    var chars = 0;
    for (var i = 0; i < limit; i++) {
      if (consumed + extents[i] >= target) {
        return chars;
      }
      consumed += extents[i];
      chars += BlockClipper.blockCharCount(blocks[i]);
    }
    return chars;
  }

  String _debugTextHash(String text) {
    return text.hashCode.toRadixString(16);
  }

  String _debugDescribeAnnotations(List<ReaderAnnotation> annotations) {
    return annotations
        .map(
          (a) =>
              '${a.id.length > 8 ? a.id.substring(0, 8) : a.id}'
              ':${a.startOffset}..${a.endOffset}',
        )
        .join(', ');
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
        // 上限只用于区分"长按选词"（触摸长按约 600ms 后触发选择），
        // 不再要求短于 450ms，否则读到段落末尾的慢点会静默失去切换控制栏的能力。
        DateTime.now().difference(pointerDownAt) <=
            const Duration(milliseconds: 800);
    final hadSelection = _selectionWasActiveOnPointerDown;
    _resetPointerTracking();
    if (!isTapLike) {
      return;
    }

    scheduleMicrotask(() {
      if (!mounted || _suppressNextContentTap) {
        _suppressNextContentTap = false;
        return;
      }
      // 本次按下-抬起新产生了选区（小距离拖选或双击选词）：是选择手势而非点击，
      // 不得切换顶栏/底栏，否则选词过程中控制栏反复弹出遮挡内容。
      if (!hadSelection && _selectedText.isNotEmpty) {
        return;
      }
      // 残留选区下的单击：清除选中的同时继续切换控制栏，一次点击一个动作。
      if (hadSelection) {
        clearSelection();
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
