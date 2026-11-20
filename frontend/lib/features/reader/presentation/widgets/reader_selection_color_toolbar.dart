import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_highlight_color_bar.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';

/// 阅读器选区浮动工具条（1:1 对齐样例 `.sel-pop`）：
/// 暗色圆角胶囊（`#1C2125` + r12 + 细白边 + 柔投影），横向排布：
/// 4 色圆点 | 竖分割线 | 批注/笔记 | 复制等系统动作。
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
          elevation: 12,
          shadowColor: Colors.black.withValues(alpha: 0.50),
          color: ReaderReadingPalette.selectionToolbarSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 2,
              children: [
                ReaderHighlightColorBar(
                  selectedColor: selectedColor,
                  onSelect: onSelectColor,
                ),
                Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                if (onAnnotate != null)
                  _SelActionButton(
                    icon: Icons.edit_outlined,
                    label: addAnnotationLabel,
                    onPressed: onAnnotate!,
                  ),
                for (final item in contextMenuButtonItems)
                  if (item.label != null && item.onPressed != null)
                    _SelActionButton(
                      label: item.label!,
                      onPressed: item.onPressed!,
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SelActionButton extends StatelessWidget {
  const _SelActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(7),
      hoverColor: Colors.white.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: AppTypography.labelMedium,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
