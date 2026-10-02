import 'package:flutter/material.dart';

import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/core/widgets/omni_icons.dart';

/// living-glass 空态族：描边图标 + 衬线标题 + 引导句 + 可选行动。
///
/// 移动壳层各空间（Library/Files/搜索）共用；标题用 Instrument Serif，
/// 描述与行动用环境色阶，区别于工位 MobileInlineState。
class EnvEmptyState extends StatelessWidget {
  const EnvEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    super.key,
  });

  final OmniIconsData icon;
  final String title;
  final String message;

  /// 行动按钮文案；为空时不渲染行动。
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 紧凑形态：用于轨道内空态（高度受限场景）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 18 : 34),
      // 宽度取满宿主可用宽：Column 默认收缩到最宽子项，放任其 shrink-wrap
      // 时整块会贴左，提示词看起来未居中。
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            OmniIcon(
              icon: icon,
              size: compact ? 26 : 36,
              color: const Color(0x4DFFFFFF),
            ),
            SizedBox(height: compact ? 10 : 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MobileEnvColors.ink,
                fontFamily: AppTypography.serifFamily,
                fontFamilyFallback: AppTypography.serifFamilyFallback,
                fontSize:
                    compact
                        ? AppTypography.titleLarge
                        : AppTypography.headlineSmall,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MobileEnvColors.inkMuted,
                fontSize: AppTypography.labelSmall,
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: MobileEnvColors.accent,
                  minimumSize: const Size(48, 40),
                  textStyle: const TextStyle(
                    fontSize: AppTypography.labelSmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
