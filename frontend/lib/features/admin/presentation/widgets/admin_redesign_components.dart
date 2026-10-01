import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 入场动画：统一交错淡入+滑入
// ─────────────────────────────────────────────────────────────────────────────

/// 页面级入场动画容器：子项按序交错淡入。
class AdminSectionEntrance extends StatefulWidget {
  const AdminSectionEntrance({required this.children, super.key});

  final List<Widget> children;

  @override
  State<AdminSectionEntrance> createState() => _AdminSectionEntranceState();
}

class _AdminSectionEntranceState extends State<AdminSectionEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: MotionToken.stagger, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) && !_ctrl.isCompleted) {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < widget.children.length; i++)
          _animated(i, widget.children[i]),
      ],
    );
  }

  Widget _animated(int index, Widget child) {
    final total = widget.children.length;
    final start = (index / total).clamp(0.0, 0.8);
    final end = (start + 0.5).clamp(0.0, 1.0);
    final curve = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(start, end, curve: MotionToken.curve),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: MotionToken.slideContent,
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 响应式指标卡网格
// ─────────────────────────────────────────────────────────────────────────────

/// 响应式指标卡网格：按容器宽度自适应列数，固定卡片高度保证同行对齐。
class AdminResponsiveMetricGrid extends StatelessWidget {
  const AdminResponsiveMetricGrid({
    required this.children,
    this.cardHeight = 132,
    super.key,
  });

  final List<Widget> children;

  /// 统一卡片高度（紧凑形态：标题行 + 数值 + 明细 + 单行徽标/进度槽）。
  ///
  /// 基准 132：内边距 24 + 标题/数值/明细约 60 + 单行徽标 26 与间距余量；
  /// 卡片内容超出时由卡片自身裁剪降级，网格高度随字号缩放钳制同步放大。
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // 四列阈值放宽，避免宽屏下卡片过窄导致数值/徽标换行错位。
        final columns =
            w >= 1280
                ? 4
                : w >= 820
                ? 2
                : 1;
        // 字体放大时卡片高度同步放大；1.3 以上钳制，避免卡片重新占满半屏。
        final textScale =
            MediaQuery.textScalerOf(
              context,
            ).scale(1).clamp(1.0, 1.3).toDouble();
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent: cardHeight * textScale,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 趋势指标徽标（↑↓ + 百分比）
// ─────────────────────────────────────────────────────────────────────────────

/// 趋势方向徽标：与上一周期对比的涨跌指示。
class AdminTrendBadge extends StatelessWidget {
  const AdminTrendBadge({
    required this.current,
    required this.previous,
    this.invertGood = false,
    super.key,
  });

  final double current;
  final double previous;

  /// 为 true 时下降视为好趋势（如错误率、延迟）。
  final bool invertGood;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    final delta = previous == 0 ? 0.0 : ((current - previous) / previous * 100);
    final isUp = delta >= 0;
    final isGood = invertGood ? !isUp : isUp;
    final color =
        delta == 0
            ? c.onSurfaceVariant
            : isGood
            ? c.success
            : c.error;
    final icon =
        delta == 0
            ? Icons.trending_flat_rounded
            : isUp
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          delta == 0 ? '—' : '${delta.abs().toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: AppTypography.labelSmall,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 服务状态瓦片
// ─────────────────────────────────────────────────────────────────────────────

/// 服务健康状态瓦片：状态点 + 名称 + 说明，直角细边框。
class AdminServiceTile extends StatelessWidget {
  const AdminServiceTile({
    required this.name,
    required this.status,
    required this.detail,
    super.key,
  });

  final String name;
  final String status;
  final String detail;

  Color _statusColor(AdminColors c) {
    return switch (status) {
      'UP' => c.success,
      'WARN' => c.warning,
      _ => c.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    final color = _statusColor(c);
    return WorkbenchPanel(
      padding: const EdgeInsets.all(14),
      borderRadius: 0,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w700,
                    color: c.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypography.labelSmall,
                    color: c.onSurfaceVariant.withValues(alpha: 0.70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
