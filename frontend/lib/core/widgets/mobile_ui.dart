import 'dart:ui' show ImageFilter;

import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_sliding_segment_row.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/core/widgets/mobile_sheet_semantics.dart';

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
const Color _dangerForeground = Color(0xFFFFFFFF);

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

/// 玻璃面的高斯模糊层。
///
/// 两态都需要：样例的 `.bottom-nav`、`.mini-player` 在浅态仍是半透明白
/// 加 `backdrop-filter`，模糊是这一档表面的一部分，不是暗态专属。
class MobileEnvBlur extends StatelessWidget {
  const MobileEnvBlur({required this.sigma, required this.child, super.key});

  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}

/// 模块全屏页的玻璃圆动作钮（样例 .icon-button：48px 圆、深绿玻璃底、
/// 白 10% 细描边）。图标可给 Material [IconData] 或样例同源矢量
/// [OmniIconsData]，二者取其一。
class MobileGlassIconButton extends StatelessWidget {
  const MobileGlassIconButton({
    required this.tooltip,
    this.icon,
    this.vector,
    required this.onPressed,
    super.key,
  }) : assert(icon != null || vector != null, '图标二选一');

  final String tooltip;
  final IconData? icon;
  final OmniIconsData? vector;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final glyph =
        vector != null
            ? OmniIcon(icon: vector!, size: 20, color: context.env.ink)
            : Icon(icon, size: 20, color: context.env.ink);
    return SizedBox.square(
      dimension: 48,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          icon: glyph,
          style: IconButton.styleFrom(
            backgroundColor: context.env.iconButtonGlass,
            foregroundColor: context.env.ink,
            side: BorderSide(color: context.env.line10),
            minimumSize: const Size.square(48),
          ),
        ),
      ),
    );
  }
}

/// 原型 `.recycle-actions button` / 眉标动作位的行内图标钮：38 见方、
/// 透明底、弱化前景；用于删除、新建这类挂在行内或眉标右侧的轻动作。
class MobileEnvInlineIconButton extends StatelessWidget {
  const MobileEnvInlineIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.iconSize = 18,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox.square(
          dimension: 38,
          child: Icon(icon, size: iconSize, color: context.env.inkMuted),
        ),
      ),
    );
  }
}

/// 模块全屏页玻璃横幅（样例 module-overlay > header）：返回圆钮 +
/// 居中标题/副题 + 右侧动作钮位；hosted 模块页（音乐/照片/影视/通知）
/// 由根级路由承载时统一使用。
class MobileModuleHeader extends StatelessWidget {
  const MobileModuleHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.backTooltip,
    this.actions = const <Widget>[],
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final String? backTooltip;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 90,
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 7),
        child: Center(
          child: Row(
            children: [
              MobileGlassIconButton(
                tooltip:
                    backTooltip ??
                    MaterialLocalizations.of(context).backButtonTooltip,
                vector: OmniIcons.chevronLeft,
                onPressed: onBack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.env.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: context.env.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              for (final action in actions) ...[
                const SizedBox(width: 8),
                action,
              ],
              // 样例页头是 [48 返回][中列][48 动作] 三列网格；无动作的页面
              // 缺右列会把中列整体右移 28px，补等宽占位保持标题居中。
              if (actions.isEmpty) const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }
}

/// 样例形态确认面板（底部玻璃 sheet）：对齐原型 `.danger-confirm`——
/// 52 图块 + 衬线 23 标题 + 9px 说明 + 两个等宽按钮，危险动作为 #b95f5f
/// 实底白字，常规动作为酸绿实底深字。
///
/// 托管态所有二次确认统一走本入口，替代工位直角确认窗。
Future<bool> showMobileConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final l10n = MaterialLocalizations.of(context);
  final result = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    backgroundColor: context.env.sheetSolid,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      return MobileSheetSemantics(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color:
                        destructive
                            ? const Color(0x1FDA5050)
                            : context.env.accentInk.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: OmniIcon(
                    icon: destructive ? OmniIcons.close : OmniIcons.check,
                    size: 22,
                    color:
                        destructive
                            ? context.env.statusDanger
                            : context.env.accentInk,
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTypography.serifFamily,
                    fontFamilyFallback: AppTypography.serifFamilyFallback,
                    // ignore: font_size_whitelist
                    fontSize: 23,
                    height: 1.0,
                    fontWeight: FontWeight.w400,
                    color: context.env.ink,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9, // ignore: font_size_whitelist
                    height: 1.55,
                    color: context.env.inkMuted,
                  ),
                ),
                const SizedBox(height: 17),
                Row(
                  children: [
                    Expanded(
                      child: _MobileConfirmButton(
                        label: cancelLabel ?? l10n.cancelButtonLabel,
                        background: context.env.line07,
                        foreground: context.env.ink,
                        onTap: () => Navigator.of(sheetContext).pop(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MobileConfirmButton(
                        label: confirmLabel ?? l10n.okButtonLabel,
                        background:
                            destructive
                                ? const Color(0xFFB95F5F)
                                : context.env.actionFill,
                        foreground:
                            destructive
                                ? _dangerForeground
                                : context.env.actionFillInk,
                        onTap: () => Navigator.of(sheetContext).pop(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

/// 确认面板底部按钮：45 高、r13、10px 标签（原型 `.danger-confirm button`）。
class _MobileConfirmButton extends StatelessWidget {
  const _MobileConfirmButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MobilePressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 45),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(13),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10, // ignore: font_size_whitelist
            color: foreground,
          ),
        ),
      ),
    );
  }
}

/// 样例 .env-switch 的几何与动效：34×20 胶囊轨道 + 14px 圆点，右移 14px，
/// 200ms ease。颜色由调用方给出：环境面板取极性表，阅读调色板用自己的实底。
class MobilePillSwitch extends StatelessWidget {
  const MobilePillSwitch({
    required this.value,
    required this.onChanged,
    required this.trackOn,
    required this.trackOff,
    required this.knobOn,
    required this.knobOff,
    this.knobShadow,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color trackOn;
  final Color trackOff;
  final Color knobOn;
  final Color knobOff;
  final List<BoxShadow>? knobShadow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.ease,
          width: 34,
          height: 20,
          decoration: BoxDecoration(
            color: value ? trackOn : trackOff,
            borderRadius: BorderRadius.circular(10),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.ease,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? knobOn : knobOff,
                  boxShadow: knobShadow,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 环境面板用的样例 .env-switch：关=白 14% 轨道 + 墨白旋钮，
/// 开=酸绿轨道 + 深墨旋钮；浅态旋钮是白的，靠投影与浅灰轨道分离。
class MobileEnvSwitch extends StatelessWidget {
  const MobileEnvSwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MobilePillSwitch(
      value: value,
      onChanged: onChanged,
      trackOn: context.env.switchOn,
      trackOff: context.env.switchOff,
      knobOn: context.env.switchKnobOn,
      knobOff: context.env.switchKnobOff,
      // 浅态旋钮是白的，落在 16% 的浅灰轨道上必须靠投影分离；
      // 暗态旋钮本来就是浅色实底配深色轨道，不加这层。
      knobShadow:
          context.env.brightness == Brightness.light
              ? const [
                BoxShadow(
                  color: Color(0x401A1D1B),
                  offset: Offset(0, 1),
                  blurRadius: 3,
                ),
              ]
              : null,
    );
  }
}

/// 样例 section-title 段头：眉标（9px 语义档·字距 1.5·w700 弱化）+
/// Instrument Serif 标题 + 右侧动作钮位；模块页 hosted 内容统一使用。
class MobileEnvSectionHeader extends StatelessWidget {
  const MobileEnvSectionHeader({
    required this.title,
    this.eyebrow,
    this.action,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null && eyebrow!.isNotEmpty)
          Text(
            eyebrow!.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // 样例 .section-title > small 眉标：9px + 字距 1.5，浅态第 4 层把它
            // 与 .notif-group 一起换成 rgba(26,29,27,.58)，暗态是主墨 43%——同一档
            // groupLabelInk。行高 1.45 只在浅层声明，暗态无人声明，两态按 1.45 走。
            style: TextStyle(
              color: context.env.groupLabelInk,
              fontSize: AppTypography.labelNano,
              height: 1.45,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTypography.serifFamily,
                  fontFamilyFallback: AppTypography.serifFamilyFallback,
                  color: context.env.ink,
                  // 样例 .section-title 的 h2 是 21，不是卡片区头档（24）。
                  fontSize: AppTypography.headlineSection,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
            ),
            if (action != null) ...[const SizedBox(width: 12), action!],
          ],
        ),
      ],
    );
  }
}

/// rootNavigator 模态层的宿主环境快照。
///
/// `showModalBottomSheet` 默认经根导航器呈现，面板子树不在移动壳层的
/// Theme 与 `MobileShellScope` 内：壳层暗皮肤、模块调色板重绑与托管标记
/// 全部丢失，表现为白底输入框与浅色面板。打开面板前在宿主页面上下文
/// 捕获环境，面板 builder 用 [wrap] 重放；非托管态原样返回子级。
class MobileSheetAmbience {
  MobileSheetAmbience.capture(BuildContext context)
    : _theme = Theme.of(context),
      _hosted = MobileShellScope.isHosted(context);

  final ThemeData _theme;
  final bool _hosted;

  /// 面板是否由移动壳层承载（决定圆角与实底面板色等形态）。
  bool get hosted => _hosted;

  /// 在面板子树重放宿主主题与托管标记。
  Widget wrap(Widget child) {
    if (!_hosted) {
      return child;
    }
    return Theme(
      data: _theme,
      child: MobileShellScope(hosted: true, child: child),
    );
  }
}

/// 原型 `.feature-list > button` 行：42 图标舱 + 名称/明细 + 尾部状态位
/// 与可选箭头，发丝线分隔；用于挂载账户、导入任务、共享条目等
/// 无进度条的条目列表。
///
/// 与 `.transfer-row` 的差别是不带 3px 进度条，行高 69 由内容自撑。
class MobileFeatureListRow extends StatelessWidget {
  const MobileFeatureListRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.neutralIcon = false,
    super.key,
  });

  final OmniIconsData icon;
  final String title;
  final String detail;

  /// 尾部状态丸等控件；无内容时不占位。
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 可进入下一层的行显示 16px 弱化箭头（原型行尾 chevron）。
  final bool showChevron;

  /// 原型 `.notif-icon.neutral`：弱化前景 + 白 5% 底，用于无状态条目。
  final bool neutralIcon;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 69),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.env.line07)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  neutralIcon
                      ? context.env.surfaceTint
                      : context.env.accentInk.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(13),
            ),
            child: OmniIcon(
              icon: icon,
              size: 18,
              color: neutralIcon ? context.env.inkMuted : context.env.accentInk,
            ),
          ),
          const SizedBox(width: 10),
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
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.env.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9, // ignore: font_size_whitelist
                    color: context.env.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          if (showChevron) ...[
            const SizedBox(width: 8),
            OmniIcon(
              icon: OmniIcons.chevron,
              size: 16,
              color: context.env.ink40,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) {
      return row;
    }
    return MobilePressable(semanticLabel: title, onTap: onTap, child: row);
  }
}
