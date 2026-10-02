import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 右下角全书进度指示器。
///
/// 普通阅读模式下常驻显示，不跟随控制栏显隐。
/// 显示当前章节进度百分比或页码信息；[sampleChrome] 为样例
/// ReaderFocus 形态（底部 3px 进度线 + 百分比文字）。
class ReaderProgressIndicator extends StatelessWidget {
  const ReaderProgressIndicator({
    required this.settings,
    required this.progress,
    this.currentPage,
    this.totalPages,
    this.sampleChrome = false,
    super.key,
  });

  final ReaderViewSettings settings;
  final double progress;
  final int? currentPage;
  final int? totalPages;

  /// 样例 ReaderFocus 形态（移动壳层）。
  final bool sampleChrome;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100);
    final text =
        currentPage != null && totalPages != null
            ? '${currentPage! + 1}/$totalPages'
            : '${percent.toStringAsFixed(1)}%';

    if (sampleChrome) {
      return Positioned(
        left: 20,
        right: 20,
        bottom: 10 + MediaQuery.viewPaddingOf(context).bottom,
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 3,
                  color: settings.accentColor,
                  backgroundColor: settings.onSurfaceColor.withValues(
                    alpha: 0.12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${percent.round()}%',
              style: TextStyle(
                color: settings.onSurfaceVariantColor.withValues(alpha: 0.70),
                // ignore: font_size_whitelist
                fontSize: 9,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.2,
              ),
            ),
          ],
        ),
      );
    }

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
