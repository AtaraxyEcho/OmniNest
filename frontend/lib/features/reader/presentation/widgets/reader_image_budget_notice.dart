import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：本章图片因超出单章数量或容量上限未加载时的集中提示。
///
/// 降级是逐张发生的，每张只剩自己的占位错误，读者看不出"少了 N 张"；
/// 计数由预处理在同一次提取里给出，这里只负责呈现与关闭。
class ReaderImageBudgetNotice extends StatelessWidget {
  const ReaderImageBudgetNotice({
    required this.count,
    required this.settings,
    required this.label,
    required this.hint,
    required this.dismissTooltip,
    required this.onDismiss,
    super.key,
  });

  final int count;
  final ReaderViewSettings settings;
  final String label;
  final String hint;
  final String dismissTooltip;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      // 子级已有 Text(label) 与 Text(hint)，再写 label 会让播报把标题重复一遍。
      child: Container(
        key: const Key('readerImageBudgetNotice'),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: settings.surfaceColor.withValues(alpha: 0.92),
          border: Border.all(
            color: settings.onSurfaceVariantColor.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: settings.onSurfaceColor,
                      fontSize: AppTypography.bodySmall,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: TextStyle(
                      color: settings.onSurfaceVariantColor,
                      fontSize: AppTypography.labelSmall,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: dismissTooltip,
              onPressed: onDismiss,
              // 关闭属逃生控件：视觉密度会按轴向从下限里扣，紧凑档实测只剩 40dp，
              // 因此不降密度，直接用 48 的最小约束。
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              icon: Icon(
                Icons.close,
                size: 18,
                color: settings.onSurfaceVariantColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 提示只在计数已知且大于 0 时出现。
///
/// SQLite 命中不会重跑图片提取，那一章的缺图数没有可靠来源；
/// 未知按"不提示"处理，而不是回显上一次提取时的旧计数。
bool shouldShowImageBudgetNotice(int? droppedImageCount) =>
    (droppedImageCount ?? 0) > 0;
