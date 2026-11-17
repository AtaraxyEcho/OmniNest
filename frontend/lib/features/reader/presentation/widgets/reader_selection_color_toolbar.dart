import 'package:flutter/material.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_highlight_color_bar.dart';

/// 阅读器选区工具栏：5 色选点 + 批注 + 系统文本动作。
///
/// 颜色点由调用方解释（新建、换色或取消高亮），本组件只负责锚定与排版。
class ReaderSelectionColorToolbar extends StatelessWidget {
  const ReaderSelectionColorToolbar({
    required this.anchors,
    required this.selectedColor,
    required this.onSelectColor,
    required this.addAnnotationLabel,
    required this.contextMenuButtonItems,
    this.onAnnotate,
    super.key,
  });

  final TextSelectionToolbarAnchors anchors;
  final String? selectedColor;
  final ValueChanged<String> onSelectColor;
  final String addAnnotationLabel;
  final List<ContextMenuButtonItem> contextMenuButtonItems;
  final VoidCallback? onAnnotate;

  @override
  Widget build(BuildContext context) {
    return AdaptiveTextSelectionToolbar(
      anchors: anchors,
      children: [
        Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(10),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReaderHighlightColorBar(
                  selectedColor: selectedColor,
                  onSelect: onSelectColor,
                ),
                if (onAnnotate != null)
                  TextButton(
                    onPressed: onAnnotate,
                    child: Text(addAnnotationLabel),
                  ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    for (final item in contextMenuButtonItems)
                      if (item.label != null)
                        TextButton(
                          onPressed: item.onPressed,
                          child: Text(item.label!),
                        ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
