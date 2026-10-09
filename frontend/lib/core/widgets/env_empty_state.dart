import 'package:flutter/material.dart';

import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';

/// living-glass 空态族：描边图标 + 衬线标题 + 引导句 + 可选行动。
///
/// 移动壳层各空间（Library/Files/搜索）共用；标题用 Instrument Serif，
/// 描述与行动用环境色阶，区别于工位 MobileInlineState。
class EnvEmptyState extends StatelessWidget {
  const EnvEmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    super.key,
  });

  final OmniIconsData icon;
  final String title;

  /// 引导句；无对应文案时可缺省，此时只排图标与标题。
  final String? message;

  /// 行动按钮文案；为空时不渲染行动。
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 紧凑形态：用于轨道内空态（高度受限场景）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, compact ? 18 : 38, 20, 10),
      // 宽度取满宿主可用宽：Column 默认收缩到最宽子项，放任其 shrink-wrap
      // 时整块会贴左，提示词看起来未居中。
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 原型 .empty-action：54 r18 强调色 8% 图块 + 同色描边图标。
            Container(
              width: compact ? 40 : 54,
              height: compact ? 40 : 54,
              decoration: BoxDecoration(
                color: context.env.accentInk.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(compact ? 14 : 18),
              ),
              alignment: Alignment.center,
              child: OmniIcon(
                icon: icon,
                size: compact ? 18 : 24,
                color: context.env.accentInk,
              ),
            ),
            SizedBox(height: compact ? 10 : 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.env.ink,
                fontFamily: AppTypography.serifFamily,
                fontFamilyFallback: AppTypography.serifFamilyFallback,
                // 原型 .empty-action strong 为衬线 400 字重 20 号；紧凑档
                // 沿用标题号。
                fontSize: compact ? AppTypography.titleLarge : 20,
                fontWeight: FontWeight.w400,
                height: 1.1,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.env.inkMuted,
                  fontSize: 9, // ignore: font_size_whitelist
                  height: 1.55,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 13),
              // 原型是酸绿实底小钮（9px 深墨字），不是纯文本链接。
              MobilePressable(
                semanticLabel: actionLabel!,
                onTap: onAction,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.env.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    actionLabel!,
                    style: TextStyle(
                      fontSize: 9, // ignore: font_size_whitelist
                      fontWeight: FontWeight.w700,
                      color: context.env.onAccent,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
