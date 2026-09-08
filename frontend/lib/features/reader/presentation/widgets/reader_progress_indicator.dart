import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 右下角全书进度指示器。
///
/// 普通阅读模式下常驻显示，不跟随控制栏显隐。
/// 显示当前章节进度百分比或页码信息。
class ReaderProgressIndicator extends StatelessWidget {
  const ReaderProgressIndicator({
    required this.settings,
    required this.progress,
    this.currentPage,
    this.totalPages,
    super.key,
  });

  final ReaderViewSettings settings;
  final double progress;
  final int? currentPage;
  final int? totalPages;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100);
    final text =
        currentPage != null && totalPages != null
            ? '${currentPage! + 1}/$totalPages'
            : '${percent.toStringAsFixed(1)}%';

    return Positioned(
      right: 16,
      bottom: 16 + MediaQuery.viewPaddingOf(context).bottom,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: settings.surfaceColor.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: settings.onSurfaceVariantColor.withValues(alpha: 0.10),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: settings.onSurfaceVariantColor.withValues(alpha: 0.70),
            fontSize: AppTypography.labelSmall,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
