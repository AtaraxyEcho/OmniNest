part of 'reader_view_content.dart';

/// 选区菜单、选区回指与调试辅助。
///
/// 从 ReaderViewContent 主体拆出，按职责独立成 part 以守住源码行数棘轮。
extension _ReaderViewContentSelection on _ReaderViewContentState {
  void clearSelection() {
    _selectedText = '';
    _clearSelectionKeyActions();
    if (!_selectionFocusNode.hasFocus) {
      widget.onSelectionActive?.call(false);
      return;
    }
    _selectionFocusNode.unfocus();
    widget.onSelectionActive?.call(false);
  }

  /// 选区结束即撤下键盘动作，避免页面按键命中已失效的选区闭包。
  void _clearSelectionKeyActions() {
    widget.onRegisterSelectionKeyActions?.call(null);
  }

  void _handleSelectionChanged(SelectedContent? selection) {
    _lastSelectionRawText = selection?.plainText ?? '';
    final selectedText = _lastSelectionRawText.trim();
    // 桌面端第一次点击会由 SelectableRegion 自己发出"选中已清空"的空事件。
    // 只接受非空事件会让 _selectedText 长期停在旧值，之后每一次单击都被
    // 当成"仅清除选中"消费掉，控制栏再也弹不出来。
    _updateSelectionText(selectedText);
    if (selectedText.isEmpty) {
      _hideMouseSelectionOverlay();
      _clearSelectionKeyActions();
    }
    widget.onSelectionActive?.call(selectedText.isNotEmpty);
  }

  /// 桌面鼠标划选松手：Flutter 的 SelectableRegion 在桌面 drag end 明确不弹
  /// selection overlay，这里把同一份统一浮条挂到应用 Overlay（锚点本就是全局坐标），
  /// 清选区、执行动作或卸载时统一撤下。
  void _showMouseSelectionOverlay() {
    final selectableRegion = _selectionAreaKey.currentState?.selectableRegion;
    final overlay = Overlay.maybeOf(context);
    if (selectableRegion == null || overlay == null || _selectedText.isEmpty) {
      return;
    }
    _hideMouseSelectionOverlay();
    final entry = OverlayEntry(
      builder:
          (overlayContext) => SizedBox.expand(
            child: _buildSelectionMenu(overlayContext, selectableRegion),
          ),
    );
    _mouseSelectionOverlay = entry;
    overlay.insert(entry);
  }

  void _hideMouseSelectionOverlay() {
    _mouseSelectionOverlay?.remove();
    _mouseSelectionOverlay = null;
  }

  Widget _buildSelectionMenu(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    // 卸载/路由替换期间 Flutter 仍可能重建上下文菜单，此时 Localizations 已不可用，
    // 直接返回空占位，避免在失活上下文上查本地化触发空断言。
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (!mounted || l10n == null) {
      return const SizedBox.shrink();
    }
    final range = _resolveSelectionRange(_selectedText);
    // 选中范围与已有高亮重叠时，高亮项切换为取消高亮（再次选中可移除而非只能重建）。
    final overlappingHighlights =
        range == null
            ? const <ReaderAnnotation>[]
            : widget.annotations
                .where(
                  (a) => a.startOffset < range.$2 && a.endOffset > range.$1,
                )
                .toList();
    final hasHighlightOverlap = overlappingHighlights.isNotEmpty;
    void removeOverlappingHighlights() {
      selectableRegionState.hideToolbar();
      selectableRegionState.clearSelection();
      for (final annotation in overlappingHighlights) {
        widget.onRemoveHighlight?.call(annotation);
      }
    }

    readerDebugLog(
      '[reader-selection][menu] '
      'mode=${widget.visibleBlocks != null ? 'page' : 'scroll'} '
      'rawLen=${_lastSelectionRawText.length} rawHash=${_debugTextHash(_lastSelectionRawText)} '
      'trimmedLen=${_selectedText.length} trimmedHash=${_debugTextHash(_selectedText)} '
      'range=${range == null ? 'null' : '(${range.$1}, ${range.$2})'} '
      'annotations=[${_debugDescribeAnnotations(widget.annotations)}] '
      'overlap=[${_debugDescribeAnnotations(overlappingHighlights)}]',
    );
    final colorPickerEnabled =
        range != null &&
        (widget.onHighlightColor != null ||
            (hasHighlightOverlap && widget.onUpdateAnnotationColor != null));
    final copyItem =
        selectableRegionState.contextMenuButtonItems
            .where((e) => e.type == ContextMenuButtonType.copy)
            .firstOrNull;
    final selectAllItem =
        selectableRegionState.contextMenuButtonItems
            .where((e) => e.type == ContextMenuButtonType.selectAll)
            .firstOrNull;
    // 彻底删除旧版“仅复制/全选”降级样式：即使极端跨页未命中偏移也统一呈现完整暗色毛玻璃工具条。
    if (!colorPickerEnabled) {
      widget.onRegisterSelectionKeyActions?.call(null);
      return ReaderSelectionColorToolbar(
        anchors: selectableRegionState.contextMenuAnchors,
        selectedColor: null,
        highlightEnabled: true,
        onSelectColor: (_) {},
        addAnnotationLabel: l10n.readerAddAnnotation,
        copyLabel:
            copyItem?.label ??
            MaterialLocalizations.of(context).copyButtonLabel,
        selectAllLabel:
            selectAllItem?.label ??
            MaterialLocalizations.of(context).selectAllButtonLabel,
        onCopy: () {
          _hideMouseSelectionOverlay();
          if (copyItem?.onPressed != null) {
            copyItem!.onPressed!();
          } else if (_selectedText.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: _selectedText));
            selectableRegionState.hideToolbar();
            selectableRegionState.clearSelection();
          }
        },
        onSelectAll:
            selectAllItem?.onPressed == null
                ? null
                : () {
                  _hideMouseSelectionOverlay();
                  selectAllItem!.onPressed!();
                },
      );
    }
    final selectedColor =
        hasHighlightOverlap
            ? overlappingHighlights.first.color.toUpperCase()
            : null;
    void selectColor(String colorHex) {
      final selectionRange = range;
      // clearSelection 会同步清空 _selectedText，命中文本必须在此之前捕获。
      final selectedText = _selectedText;
      selectableRegionState.hideToolbar();
      selectableRegionState.clearSelection();
      if (hasHighlightOverlap) {
        if (colorHex.toUpperCase() == selectedColor) {
          removeOverlappingHighlights();
        } else {
          for (final annotation in overlappingHighlights) {
            widget.onUpdateAnnotationColor?.call(annotation, colorHex);
          }
        }
        return;
      }
      widget.onHighlightColor?.call(
        selectedText,
        selectionRange.$1,
        selectionRange.$2,
        colorHex,
      );
    }

    widget.onRegisterSelectionKeyActions?.call(
      ReaderSelectionKeyActions(
        colors: ReaderHighlightPalette.colors,
        applyColor: selectColor,
        removeHighlight:
            hasHighlightOverlap && widget.onRemoveHighlight != null
                ? removeOverlappingHighlights
                : null,
      ),
    );
    return ReaderSelectionColorToolbar(
      anchors: selectableRegionState.contextMenuAnchors,
      selectedColor: selectedColor,
      onSelectColor: selectColor,
      addAnnotationLabel: l10n.readerAddAnnotation,
      copyLabel:
          copyItem?.label ?? MaterialLocalizations.of(context).copyButtonLabel,
      selectAllLabel:
          selectAllItem?.label ??
          MaterialLocalizations.of(context).selectAllButtonLabel,
      onCopy: () {
        _hideMouseSelectionOverlay();
        if (copyItem?.onPressed != null) {
          copyItem!.onPressed!();
        } else if (_selectedText.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: _selectedText));
          selectableRegionState.hideToolbar();
          selectableRegionState.clearSelection();
        }
      },
      onSelectAll:
          selectAllItem?.onPressed == null
              ? null
              : () {
                _hideMouseSelectionOverlay();
                selectAllItem!.onPressed!();
              },
      removeHighlightLabel:
          hasHighlightOverlap && widget.onRemoveHighlight != null
              ? (overlappingHighlights.any((a) => (a.note ?? '').isNotEmpty)
                  ? l10n.readerRemoveAnnotation
                  : l10n.readerRemoveHighlight)
              : null,
      onRemoveHighlight:
          hasHighlightOverlap && widget.onRemoveHighlight != null
              ? removeOverlappingHighlights
              : null,
      onSubmitInlineNote:
          widget.onAnnotateInline == null
              ? null
              : (note) {
                final selectedText = _selectedText;
                selectableRegionState.hideToolbar();
                selectableRegionState.clearSelection();
                widget.onAnnotateInline?.call(
                  selectedText,
                  range.$1,
                  range.$2,
                  note,
                );
              },
      onAnnotate:
          widget.onAnnotate == null
              ? null
              : () {
                final selectedText = _selectedText;
                selectableRegionState.hideToolbar();
                selectableRegionState.clearSelection();
                widget.onAnnotate?.call(selectedText, range.$1, range.$2);
              },
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
}
