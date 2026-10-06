import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/core/widgets/omni_icons.dart';

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
    // 托管模块页固定环境深底（样例 module-overlay rgba(10,15,14,.94)）：
    // pageMask 取自主题，浅色主题下为浅色会导致浅字内容不可见。
    if (MobileShellScope.isHosted(context)) {
      final double alpha = (backdropOpacity ?? 0.94).clamp(0.0, 1.0).toDouble();
      return ColoredBox(
        color: MobileEnvColors.stage.withValues(alpha: alpha),
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

/// 移动端区块标题及可选尾部操作。
class MobileSectionHeader extends StatelessWidget {
  const MobileSectionHeader({
    required this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.mobileColors.textPrimary,
                  fontSize: AppTypography.titleLarge,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.mobileColors.textSecondary,
                    fontSize: AppTypography.bodySmall,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    );
  }
}

/// 移动端模块子页面使用的统一返回控件。
class MobileSubpageBackButton extends StatelessWidget {
  const MobileSubpageBackButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: MobileLayoutTokens.minimumTarget,
      child: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: onPressed,
        icon: Icon(Icons.arrow_back_rounded, size: 22),
        style: IconButton.styleFrom(
          foregroundColor: context.mobileColors.textPrimary,
          minimumSize: const Size.square(MobileLayoutTokens.minimumTarget),
        ),
      ),
    );
  }
}

/// 移动端模块内的一级分段导航。
class MobileSegmentedControl<T> extends StatelessWidget {
  const MobileSegmentedControl({
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
    this.iconBuilder,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelBuilder;
  final IconData? Function(T value)? iconBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    // 样例 .segmented：紧凑胶囊容器（r16·内衬 4·白 9% 描边），
    // 选中段酸绿实心 + 墨绿深字 + 投影。段数超出可用宽度时整体
    // 等比缩放兜底（样例最多四档，不会触达该路径）。
    return Semantics(
      container: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MobileEnvColors.segmentBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MobileEnvColors.line09),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final value in values) ...[
                  _MobileSegment(
                    label: labelBuilder(value),
                    icon: iconBuilder?.call(value),
                    selected: value == selected,
                    onTap: () => onSelected(value),
                  ),
                  if (value != values.last) const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileSegment extends StatelessWidget {
  const _MobileSegment({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: MobileLayoutTokens.stateDuration,
            curve: MobileLayoutTokens.motionCurve,
            constraints: const BoxConstraints(minWidth: 66, minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? MobileEnvColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow:
                  selected
                      ? const [
                        BoxShadow(
                          color: Color(0x2E000000),
                          offset: Offset(0, 3),
                          blurRadius: 10,
                        ),
                      ]
                      : null,
            ),
            // 紧凑分段下宽度由文字自定（minWidth 66 兜底），不得使用
            // 弹性子级，避免 shrink-wrap 链路的无界宽度断言。
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 18,
                    color:
                        selected
                            ? MobileEnvColors.onAccentDeep
                            : MobileEnvColors.inkMuted,
                  ),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        selected
                            ? MobileEnvColors.onAccentDeep
                            : MobileEnvColors.inkMuted,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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

/// 移动端加载占位：保留请求尺寸的空盒 + 居中指示器。
///
/// 主流方案用指示器替代骨架块，避免占位与最终内容形状错位。
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
    return SizedBox(
      width: width,
      height: height,
      child: const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// 移动端列表内的空状态或错误状态。
class MobileInlineState extends StatelessWidget {
  const MobileInlineState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.error = false,
    super.key,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final accent =
        error ? context.mobileColors.danger : context.mobileColors.musicAccent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 28),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.mobileColors.textSecondary,
              fontSize: AppTypography.bodyLarge,
              height: 1.45,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
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
              color: context.mobileColors.textSecondary,
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
    final foreground =
        destructive
            ? context.mobileColors.danger
            : context.mobileColors.textPrimary;
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
                              color: context.mobileColors.textSecondary,
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
                            color: context.mobileColors.textSecondary,
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

/// 模块全屏页的玻璃圆动作钮（样例 .icon-button：48px 圆、深绿玻璃底、
/// 白 10% 细描边）。
class MobileGlassIconButton extends StatelessWidget {
  const MobileGlassIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 20, color: MobileEnvColors.ink),
          style: IconButton.styleFrom(
            backgroundColor: MobileEnvColors.iconButtonGlass,
            foregroundColor: MobileEnvColors.ink,
            side: const BorderSide(color: MobileEnvColors.line10),
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
          child: Icon(icon, size: iconSize, color: MobileEnvColors.inkMuted),
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
                icon: Icons.arrow_back_rounded,
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
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: MobileEnvColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9,
                        color: MobileEnvColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              for (final action in actions) ...[
                const SizedBox(width: 8),
                action,
              ],
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
    backgroundColor: MobileEnvColors.sheetSolid,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      return SafeArea(
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
                          : const Color(0x14D5F17D),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: OmniIcon(
                  icon: destructive ? OmniIcons.close : OmniIcons.check,
                  size: 22,
                  color:
                      destructive
                          ? const Color(0xFFE69696)
                          : MobileEnvColors.accent,
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
                  color: MobileEnvColors.ink,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 9, // ignore: font_size_whitelist
                  height: 1.55,
                  color: MobileEnvColors.inkMuted,
                ),
              ),
              const SizedBox(height: 17),
              Row(
                children: [
                  Expanded(
                    child: _MobileConfirmButton(
                      label: cancelLabel ?? l10n.cancelButtonLabel,
                      background: const Color(0x12FFFFFF),
                      foreground: MobileEnvColors.ink,
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
                              : MobileEnvColors.accent,
                      foreground:
                          destructive ? Colors.white : MobileEnvColors.onAccent,
                      onTap: () => Navigator.of(sheetContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
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

/// 样例 .env-switch：34×20 胶囊轨道（关=白 14%，开=酸绿）+ 14px 圆点
/// （关=墨白，开=深墨右移 14px），200ms ease。
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
            color: value ? MobileEnvColors.accent : const Color(0x24FFFFFF),
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
                  color:
                      value
                          ? MobileEnvColors.onAccentDeep
                          : MobileEnvColors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
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
            style: TextStyle(
              color: MobileEnvColors.inkFaint,
              fontSize: AppTypography.labelSmall,
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
                  color: MobileEnvColors.ink,
                  fontSize: AppTypography.headlineSmall,
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
/// 与可选箭头，发丝线分隔；用于挂载账户、导入/离线任务、共享条目等
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
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MobileEnvColors.line07)),
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
                      ? const Color(0x0DFFFFFF)
                      : MobileEnvColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(13),
            ),
            child: OmniIcon(
              icon: icon,
              size: 18,
              color:
                  neutralIcon
                      ? MobileEnvColors.inkMuted
                      : MobileEnvColors.accent,
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
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: MobileEnvColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9, // ignore: font_size_whitelist
                    color: MobileEnvColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          if (showChevron) ...[
            const SizedBox(width: 8),
            const OmniIcon(
              icon: OmniIcons.chevron,
              size: 16,
              color: MobileEnvColors.ink40,
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
