import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';

class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 780;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontSize: AppTypography.headlineMedium,
                height: 36 / 28,
                color: c.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: AppTypography.bodyLarge,
                height: 21 / 14,
                color: c.onSurfaceVariant,
              ),
            ),
          ],
        );

        if (!isWide || trailing == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              if (trailing != null) ...[const SizedBox(height: 18), trailing!],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 24),
            trailing!,
          ],
        );
      },
    );
  }
}

/// 管理指标卡（紧凑形态）：标题行 + 大数值 + 单行明细 + 单行 supporting
/// 徽标区与 3px 进度槽，内容整体按最小高度收缩，不再使用 Spacer 撑开。
///
/// 定高卡在超大字号下内容超出时按纯裁剪降级（ClipRect + OverflowBox），
/// 不抛 RenderFlex 溢出异常；卡内不得存在任何 Scrollable 后代，
/// 否则桌面端指针悬停会浮现卡片级滚动条，与页面级滚动条叠加。
/// 卡高与字号缩放由外层指标网格统一钳制；supporting 与进度槽间距
/// 按 132 基准高收紧（7/8），使 supporting+progress 组合天然放得下。
class AdminMetricCard extends StatelessWidget {
  const AdminMetricCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    this.accent,
    this.progress,
    this.supporting = const [],
    this.footer,
    super.key,
  });

  final String title;
  final String value;
  final String detail;
  final IconData icon;
  final Color? accent;
  final double? progress;
  final List<Widget> supporting;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    final resolvedAccent = accent ?? c.primary;
    return WorkbenchPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: 0,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      child: ClipRect(
        // 固定卡高下的兜底：OverflowBox 放开子级高度约束，Column 按固有
        // 高度布局，超出部分由 ClipRect 在内容盒边缘裁剪；不引入
        // Scrollable，悬停不会触发桌面端 ScrollConfiguration 滚动条。
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxHeight: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: AppTypography.labelSmall,
                        height: 14 / 11,
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(icon, size: 16, color: resolvedAccent),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: AppTypography.titleLarge,
                  height: 24 / 20,
                  color: resolvedAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: AppTypography.labelSmall,
                  height: 14 / 11,
                  color: c.onSurfaceVariant,
                ),
              ),
              if (supporting.isNotEmpty) ...[
                const SizedBox(height: 7),
                ConstrainedBox(
                  // supporting 固定单行：折行内容直接裁剪，保持紧凑卡高度稳定。
                  constraints: const BoxConstraints(maxHeight: 28),
                  child: Wrap(spacing: 6, runSpacing: 6, children: supporting),
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: 8),
                _MetricProgress(value: progress!, color: resolvedAccent),
              ],
              if (footer != null) ...[const SizedBox(height: 8), footer!],
            ],
          ),
        ),
      ),
    );
  }
}

class AdminMetricMiniStat extends StatelessWidget {
  const AdminMetricMiniStat({
    required this.label,
    required this.value,
    this.color,
    super.key,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? context.adminColors.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.1),
        border: Border.all(color: resolvedColor.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: AppTypography.labelSmall,
              height: 14 / 11,
              color: context.adminColors.onSurfaceVariant,
            ),
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  color: resolvedColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextSpan(text: ' $label'),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricProgress extends StatelessWidget {
  const _MetricProgress({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(0, 1).toDouble();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: safeValue,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color),
            child: const SizedBox(height: 3),
          ),
        ),
      ),
    );
  }
}

class AdminStatusPill extends StatelessWidget {
  const AdminStatusPill({required this.label, this.color, super.key});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? context.adminColors.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.14),
        border: Border.all(color: resolvedColor.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: resolvedColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: AppTypography.labelSmall,
                height: 14 / 11,
                color: resolvedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminInfoPanel extends StatelessWidget {
  const AdminInfoPanel({
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
    this.expandBody = false,
    this.padding,
    this.headerDivider = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? trailing;

  /// 为 true 时内容区吃满父级有界高度，children 中可使用 Expanded。
  /// 仅用于已用 SizedBox/Expanded 限高的并排面板；页面纵向流式布局须保持 false。
  final bool expandBody;

  /// 面板内边距；null 时沿用工作台面板默认 24。
  /// 样板控制台卡片为 p-5（20），页面按样板传值。
  final EdgeInsetsGeometry? padding;

  /// 为 true 时标题区带 1px 底部分隔线（样板 pb-4 border-b mb-4 形态），
  /// 标题区与内容间距收拢为 16。
  final bool headerDivider;

  @override
  Widget build(BuildContext context) {
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: AppTypography.titleLarge,
                  height: 28 / 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: AppTypography.bodyMedium,
                  height: 20 / 13,
                  color: context.adminColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 16), trailing!],
      ],
    );
    final headerBlock =
        headerDivider
            ? Container(
              padding: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: header,
            )
            : header;
    return WorkbenchPanel(
      borderRadius: 0,
      padding: padding ?? const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          headerBlock,
          SizedBox(height: headerDivider ? 16 : 22),
          if (expandBody)
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            )
          else
            ...children,
        ],
      ),
    );
  }
}

class AdminEmptyFeature extends StatelessWidget {
  const AdminEmptyFeature({
    required this.icon,
    required this.title,
    required this.description,
    this.actions = const [],
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    return WorkbenchPanel(
      borderRadius: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.12),
                  border: Border.all(color: c.outlineVariant),
                ),
                child: Icon(icon, color: c.primary, size: 30),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: AppTypography.titleLarge,
                  height: 28 / 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: AppTypography.bodyLarge,
                  height: 21 / 14,
                  color: c.onSurfaceVariant,
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 22),
                Wrap(spacing: 10, runSpacing: 10, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
