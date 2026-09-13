import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';

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
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.mobileColors.surface,
          borderRadius: BorderRadius.circular(MobileLayoutTokens.radius),
          border: Border.all(color: context.mobileColors.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              for (final value in values)
                Expanded(
                  child: _MobileSegment(
                    label: labelBuilder(value),
                    icon: iconBuilder?.call(value),
                    selected: value == selected,
                    onTap: () => onSelected(value),
                  ),
                ),
            ],
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
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: AnimatedContainer(
            duration: MobileLayoutTokens.stateDuration,
            curve: MobileLayoutTokens.motionCurve,
            constraints: const BoxConstraints(
              minHeight: MobileLayoutTokens.minimumTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color:
                  selected
                      ? context.mobileColors.surfaceSelected
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 18,
                    color:
                        selected
                            ? context.mobileColors.musicAccent
                            : context.mobileColors.textSecondary,
                  ),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          selected
                              ? context.mobileColors.textPrimary
                              : context.mobileColors.textSecondary,
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
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
