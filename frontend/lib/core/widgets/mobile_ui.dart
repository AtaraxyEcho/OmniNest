import 'dart:ui' show ImageFilter;

import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_sliding_segment_row.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/app/theme/status_tint_colors.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/core/widgets/mobile_sheet_semantics.dart';
part 'mobile_env_widgets.dart';

/// 移动端页面的半透明内容表面。
class MobilePageSurface extends StatelessWidget {
  const MobilePageSurface({
    required this.child,
    this.exposeBackdrop = true,
    this.backdropOpacity,
    super.key,
  });

  final Widget child;
  final bool exposeBackdrop;
  final double? backdropOpacity;

  @override
  Widget build(BuildContext context) {
    // 托管页可以整页不带 Scaffold：那样子树里没有 Material 装 DefaultTextStyle，
    // 每个 Text 都会去继承 MaterialApp 的兜底样式（monospace / 48px /
    // 黄色双下划线），字重与字号被各自的 style 盖掉之后，只剩那条双下划线
    // 画在每一行字下面。这里补一层正常正文；子树里的 Material 仍会覆盖它。
    return DefaultTextStyle(
      style:
          Theme.of(context).textTheme.bodyMedium ??
          const TextStyle(inherit: false),
      child: _surfaceBody(context),
    );
  }

  Widget _surfaceBody(BuildContext context) {
    // 托管模块页固定环境深底（样例 module-overlay rgba(10,15,14,.94)）：
    // pageMask 取自主题，浅色主题下为浅色会导致浅字内容不可见。
    if (MobileShellScope.isHosted(context)) {
      final double alpha = (backdropOpacity ?? 0.94).clamp(0.0, 1.0).toDouble();
      return ColoredBox(
        color: context.env.stage.withValues(alpha: alpha),
        child: child,
      );
    }
    return ColoredBox(
      color:
          exposeBackdrop
              ? context.mobileColors.pageMask.withValues(
                alpha: (backdropOpacity ?? 0.56).clamp(0, 1),
              )
              : context.mobileColors.pageMask,
      child: child,
    );
  }
}

/// polarity-stable：危险红底上的白字两极性同值（红底白字 4.35:1），不随极性翻转。
const Color _dangerForeground = Colors.white;

/// 浅态开关旋钮投影：落在浅灰轨道上靠这层阴影分离。
const Color _knobShadow = Color(0x401A1D1B);

/// 移动端模块内的一级分段导航。
class MobileSegmentedControl<T> extends StatelessWidget {
  const MobileSegmentedControl({
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
    this.shrinkToFit = false,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onSelected;

  /// 放不下时转等分档：段数多到样例的 `max-content + min-width:66` 超出内容带，
  /// 就让六段等分吃掉整条内容带，全部可见而不靠横向滚动。
  ///
  /// 这是对样例 `.segmented` 的记账式偏离（照片页裁定口径）：等分档下段宽
  /// (390 - 2×20 - 2×4 - 5×4) / 6 ≈ 53.7dp，低于样例的 66；只在按标签实测
  /// 装不下的时候才生效，段数少时仍是样例的自适应宽度。
  final bool shrinkToFit;

  @override
  Widget build(BuildContext context) {
    // 样例 .segmented：紧凑胶囊容器（r16·内衬 4·白 9% 描边），选中段是
    // 酸绿实心 + 墨绿深字 + 投影的单层滑块，切换时滑过去而不是就地换色。
    // 段数超出可用宽度时默认横向滚动（样例同口径）；照片页六段实测要 431dp，
    // 而内容带只有 350dp，于是按 shrinkToFit 转等分档。
    final selectedIndex = values.indexOf(selected);
    final labels = [for (final value in values) labelBuilder(value)];

    Widget capsule(double? equalSegmentWidth) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: context.env.segmentBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.env.segmentBorder),
        ),
        child: MobileSlidingSegmentRow(
          labels: labels,
          selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
          onTap: (index) => onSelected(values[index]),
          activeInk: context.env.segmentActiveInk,
          idleInk: context.env.inkMuted,
          equalSegmentWidth: equalSegmentWidth,
          // 样例 `.segmented button.active`：暗态黑 18%、浅态
          // rgba(26,29,27,.06) 的投影都取自 pillGlow，随极性换档。
          pill: BoxDecoration(
            color: context.env.segmentActiveBg,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: context.env.pillGlow,
                offset: const Offset(0, 3),
                blurRadius: 10,
              ),
            ],
          ),
        ),
      );
    }

    Widget scrollable(double? equalSegmentWidth) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: capsule(equalSegmentWidth),
      );
    }

    return Semantics(
      container: true,
      child:
          shrinkToFit
              ? LayoutBuilder(
                builder: (context, constraints) {
                  if (!constraints.hasBoundedWidth) {
                    return scrollable(null);
                  }
                  final natural = MobileSlidingSegmentRow.naturalExtent(
                    context: context,
                    labels: labels,
                  );
                  if (natural <= constraints.maxWidth) {
                    return scrollable(null);
                  }
                  final chrome = 4 * 2 + 4 * (labels.length - 1);
                  return scrollable(
                    (constraints.maxWidth - chrome) / labels.length,
                  );
                },
              )
              : scrollable(null),
    );
  }
}

/// 提供统一按压缩放反馈的移动端交互容器。
class MobilePressable extends StatefulWidget {
  const MobilePressable({
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.onLongPress,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  @override
  State<MobilePressable> createState() => _MobilePressableState();
}

class _MobilePressableState extends State<MobilePressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown:
            widget.onTap == null
                ? null
                : (_) => setState(() => _pressed = true),
        onTapCancel:
            widget.onTap == null
                ? null
                : () => setState(() => _pressed = false),
        onTapUp:
            widget.onTap == null
                ? null
                : (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: reduceMotion || !_pressed ? 1 : 0.985,
          duration: MobileLayoutTokens.pressDuration,
          curve: MobileLayoutTokens.motionCurve,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 移动端加载占位规则（本文件两个件共同构成）：
///
/// - 一屏之内的**动画指示至多一处**：整页/整区首屏用 [AppLoading] 或
///   [MobileLoadingLine]，页面内某个子块在已有内容旁边等数据时用
///   [MobileSkeletonBlock]（静态，不产生第二个动画）。
/// - [MobileSkeletonBlock] 早期版本在盒内塞一个 24px 转圈：同屏放两块就是
///   两个转圈，放进 16px 高的槽位还会溢出，故改为静态占位。
///
/// 静态占位块：等一块内容就绪时保持版面稳定，不模拟最终形状（只是一条
/// 圆角弱底），因此不会与真实内容形状错位。
class MobileSkeletonBlock extends StatelessWidget {
  const MobileSkeletonBlock({
    required this.height,
    this.width = double.infinity,
    super.key,
  });

  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: onSurface.withValues(alpha: 0.05)),
        ),
      ),
    );
  }
}

/// 区级不定量细进度线：一屏只放一处，用于"整区正在取数、但已有内容要保留"
/// 的场景（首屏整页加载仍用 [AppLoading] 的居中环）。
class MobileLoadingLine extends StatelessWidget {
  const MobileLoadingLine({this.top = false, super.key});

  /// true 时贴区域顶部（不带上下留白），否则自带 12 上下间距。
  final bool top;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: top ? 0 : 12, horizontal: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: scheme.onSurface.withValues(alpha: 0.07),
            valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
          ),
        ),
      ),
    );
  }
}

/// 移动端设置页使用的无卡片分组。
class MobileSettingsGroup extends StatelessWidget {
  const MobileSettingsGroup({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: context.env.inkMuted,
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.mobileColors.surface,
            borderRadius: BorderRadius.circular(MobileLayoutTokens.radius),
          ),
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1)
                  Divider(
                    height: 1,
                    indent: 60,
                    color: context.mobileColors.outline.withValues(alpha: 0.5),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 移动端设置或个人中心使用的稳定列表行。
class MobileSettingsTile extends StatelessWidget {
  const MobileSettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final foreground = destructive ? context.env.statusDanger : context.env.ink;
    return Semantics(
      button: onTap != null,
      label: title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MobileLayoutTokens.radius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: MobileLayoutTokens.listRowHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 36,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: (iconColor ?? foreground).withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: iconColor ?? foreground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontSize: AppTypography.titleMedium,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.env.inkMuted,
                              fontSize: AppTypography.bodySmall,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing ??
                      (onTap == null
                          ? const SizedBox.shrink()
                          : Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: context.env.inkMuted,
                          )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
