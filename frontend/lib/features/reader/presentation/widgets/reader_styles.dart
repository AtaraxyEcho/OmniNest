import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';

/// 根据内容宽度计算文字缩放因子。
/// 960px 以下不缩放，2560px 以上最大 1.25x。
double readerTextScale(double width) {
  if (width <= 960) return 1.0;
  final t = ((width - 960) / 1600).clamp(0.0, 1.0);
  return 1.0 + 0.25 * t;
}

/// 应用缩放后的字号，最小不低于 12。
double rs(double width, double base) =>
    base * readerTextScale(width) < 12 ? 12 : base * readerTextScale(width);

/// 根据内容宽度计算阅读器网格列数。
int readerGridColumnCount(double width) {
  if (width >= 3200) return 12;
  if (width >= 2400) return 8;
  if (width >= 1800) return 6;
  if (width >= 1500) return 5;
  if (width >= 1180) return 4;
  if (width >= 760) return 3;
  if (width >= 560) return 3;
  return 2;
}

/// 根据系统文字缩放为封面卡片预留元数据高度。
double readerGridChildAspectRatio(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  if (scale >= 1.75) return 0.52;
  if (scale >= 1.3) return 0.60;
  return 0.68;
}

/// 类型标签徽章。
class ReaderBadge extends StatelessWidget {
  const ReaderBadge({
    required this.label,
    required this.color,
    this.backgroundColor,
    this.foregroundColor,
    super.key,
  });

  final String label;
  final Color color;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor ?? color,
          fontSize: AppTypography.labelSmall,
          height: 14 / 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
