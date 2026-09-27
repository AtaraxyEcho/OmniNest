import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';

/// 阅读模块空态：水平居中、贴内容区顶部，与书库空态位置一致；宽度收束避免撑成通栏。
class ReaderEmptyState extends StatelessWidget {
  const ReaderEmptyState({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.action,
    super.key,
  });

  /// 空态卡片锚点，便于测试锁定收束后的实际尺寸。
  static const Key cardKey = Key('reader_empty_state_card');

  /// 空态卡片最大宽度，约束桌面与整页空态下的视觉范围。
  static const double maxWidth = 380;

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: Container(
          key: cardKey,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: rc.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: rc.outlineVariant.withValues(alpha: 0.8)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: rc.surfaceContainerHighest,
                  border: Border.all(
                    color: rc.outlineVariant.withValues(alpha: 0.8),
                  ),
                ),
                child: Icon(icon, color: rc.onPrimaryContainer, size: 20),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: rc.onSurface,
                  fontSize: AppTypography.titleMedium,
                  height: 22 / 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: rc.onSurfaceVariant,
                  fontSize: AppTypography.bodyMedium,
                  height: 18 / 13,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}
