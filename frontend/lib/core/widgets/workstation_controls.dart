/// 建筑极简主义工位控件集：仅依赖 ColorScheme，可被任何
/// 工位皮肤 Scope（Files / Admin）覆盖的子树直接使用。
///
/// 度量铁律：桌面顶栏/工具栏控件高度锁定 32px，移动端触控
/// 热区外扩到 44px；全部 0px 直角、1px 细线、零阴影。
library;

import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';

/// 工位输入装饰：1px 细线直角、凹入槽体底色。
///
/// 默认边框为 hairline（outlineVariant），聚焦仅 1px 精准升为
/// onSurface，杜绝未聚焦时呈现强边框的“伪选中态”。
InputDecoration workstationInputDecoration(
  BuildContext context, {
  String? hintText,
  IconData prefixIcon = Icons.search_rounded,
  double height = 32,
}) {
  final scheme = Theme.of(context).colorScheme;
  final enabledBorder = OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: scheme.outlineVariant, width: 1),
  );
  final focusedBorder = OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: scheme.onSurface, width: 1),
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: scheme.surfaceContainerLow,
    hintText: hintText,
    hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    prefixIcon: Icon(prefixIcon, size: 16, color: scheme.onSurfaceVariant),
    // 前缀图标盒与字段同高，图标才能垂直居中（minHeight:0 会让图标贴顶）。
    prefixIconConstraints: BoxConstraints(minWidth: 30, minHeight: height),
    border: enabledBorder,
    enabledBorder: enabledBorder,
    focusedBorder: focusedBorder,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    constraints: BoxConstraints(minHeight: height, maxHeight: height),
  );
}

/// 顶栏/页面工具栏统一 32px 直角描边图标按钮。
///
/// 三态：未激活（hairline 边 + 次级前景）、悬停（1px 细线精准变色）、
/// 激活（surface-2 底 + 边框 + 主前景）。高度严格锁定 32px。
class WorkstationIconButton extends StatefulWidget {
  const WorkstationIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.size = 32,
    this.iconSize = 16,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  /// 是否处于激活态（如详情栏开关展开时）。
  final bool active;

  final double size;

  final double iconSize;

  @override
  State<WorkstationIconButton> createState() => _WorkstationIconButtonState();
}

class _WorkstationIconButtonState extends State<WorkstationIconButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    final active = widget.active;
    final border =
        active
            ? scheme.outlineVariant
            : _hovering && enabled
            ? scheme.onSurface
            : scheme.outline;
    final foreground =
        !enabled
            ? scheme.onSurfaceVariant.withValues(alpha: 0.45)
            : active || _hovering
            ? scheme.onSurface
            : scheme.onSurfaceVariant;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  active ? scheme.surfaceContainerHighest : Colors.transparent,
              border: Border.all(color: border, width: 1),
            ),
            child: Icon(widget.icon, size: widget.iconSize, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// 直角分段切换器（如 表格视图 | 卡片视图）。
///
/// 各分段等宽共享 1px 外框，选中项 surface-2 底色高对比，未选中纯靠
/// 变色驱动，杜绝边框切换引起的尺寸跳变。
class WorkstationSegmented<T> extends StatelessWidget {
  const WorkstationSegmented({
    required this.segments,
    required this.selected,
    required this.onSelected,
    this.height = 32,
    super.key,
  });

  final List<WorkstationSegment<T>> segments;

  final T selected;

  final ValueChanged<T> onSelected;

  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < segments.length; index++) ...[
            if (index > 0)
              VerticalDivider(width: 1, thickness: 1, color: scheme.outline),
            _SegmentButton(
              segment: segments[index],
              selected: segments[index].value == selected,
              height: height,
              onTap: () => onSelected(segments[index].value),
            ),
          ],
        ],
      ),
    );
  }
}

class WorkstationSegment<T> {
  const WorkstationSegment({
    required this.value,
    required this.tooltip,
    required this.icon,
    this.label,
  });

  final T value;
  final String tooltip;
  final IconData icon;
  final String? label;
}

class _SegmentButton extends StatefulWidget {
  const _SegmentButton({
    required this.segment,
    required this.selected,
    required this.height,
    required this.onTap,
  });

  final WorkstationSegment<Object?> segment;
  final bool selected;
  final double height;
  final VoidCallback onTap;

  @override
  State<_SegmentButton> createState() => _SegmentButtonState();
}

class _SegmentButtonState extends State<_SegmentButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final foreground =
        selected
            ? scheme.onSurface
            : _hovering
            ? scheme.onSurface
            : scheme.onSurfaceVariant;
    final background =
        selected
            ? scheme.surfaceContainerHighest
            : _hovering
            ? scheme.surfaceContainer
            : Colors.transparent;
    return Tooltip(
      message: widget.segment.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: widget.height - 2,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            color: background,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.segment.icon, size: 16, color: foreground),
                if (widget.segment.label != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    widget.segment.label!,
                    style: TextStyle(
                      fontSize: AppTypography.labelMedium,
                      height: 16 / AppTypography.labelMedium,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 模板规格动作按钮：桌面 28px / 移动 44px，直角三变体。
///
/// primary = 反色高强调（上传等主操作）；secondary = 细线描边次操作；
/// danger = 绯红描边破坏性操作。悬停只换底色，不改变边框几何。
class WorkstationActionButton extends StatefulWidget {
  const WorkstationActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = WorkstationActionButtonVariant.secondary,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final WorkstationActionButtonVariant variant;

  @override
  State<WorkstationActionButton> createState() =>
      _WorkstationActionButtonState();
}

enum WorkstationActionButtonVariant { primary, secondary, danger }

class _WorkstationActionButtonState extends State<WorkstationActionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    final height = AppControlTokens.isDesktopDensity ? 28.0 : 44.0;
    final Color background;
    final Color foreground;
    final Color border;
    final Color hoverBackground;
    switch (widget.variant) {
      case WorkstationActionButtonVariant.primary:
        background = scheme.onSurface;
        foreground = scheme.surface;
        border = scheme.onSurface;
        // 反色主按钮悬停必须保持反色对比：换 surfaceContainerHighest 会
        // 变成“深灰底 + 深色前景”，两套主题下都不可读；改为降不透明度。
        hoverBackground = scheme.onSurface.withValues(alpha: 0.82);
      case WorkstationActionButtonVariant.secondary:
        background = scheme.surfaceContainerLow;
        foreground = scheme.onSurface;
        border = scheme.outlineVariant;
        hoverBackground = scheme.surfaceContainerHigh;
      case WorkstationActionButtonVariant.danger:
        background = scheme.surfaceContainerLow;
        foreground = scheme.error;
        border = scheme.error.withValues(alpha: 0.55);
        hoverBackground = scheme.error.withValues(alpha: 0.10);
    }
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color:
                !enabled
                    ? scheme.surfaceContainerLow
                    : _hovering
                    ? hoverBackground
                    : background,
            border: Border.all(
              color: !enabled ? scheme.outlineVariant : border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 14,
                  color: !enabled ? scheme.onSurfaceVariant : foreground,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: AppTypography.labelMedium,
                  fontWeight:
                      widget.variant == WorkstationActionButtonVariant.primary
                          ? FontWeight.w600
                          : FontWeight.w500,
                  color: !enabled ? scheme.onSurfaceVariant : foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 建筑极简主义 `✔` 文本复选框。
///
/// 勾选标志为加粗纯文本 ✔ 字符（非 clip-path），弹出过渡 120ms；
/// 移动端触控热区外扩到 44px。默认值必须为未勾选。
/// [indeterminate] 为半选态（组内部分选中）：不显示 ✔，改渲染
/// 1px 短横线；点按仍走 [onChanged]（由调用方决定整组语义）。
class WorkstationCheckMark extends StatefulWidget {
  const WorkstationCheckMark({
    required this.value,
    this.onChanged,
    this.enabled = true,
    this.size = 16,
    this.indeterminate = false,
    super.key,
  });

  final bool value;

  final ValueChanged<bool>? onChanged;

  final bool enabled;

  /// 视觉方框边长。
  final double size;

  /// 半选态：仅在与 [value] 为 false 组合时生效。
  final bool indeterminate;

  @override
  State<WorkstationCheckMark> createState() => _WorkstationCheckMarkState();
}

class _WorkstationCheckMarkState extends State<WorkstationCheckMark> {
  bool _hovering = false;

  void _handleTap() {
    final onChanged = widget.onChanged;
    if (!widget.enabled || onChanged == null) {
      return;
    }
    onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final interactive = widget.enabled && widget.onChanged != null;
    final value = widget.value;
    // 输入边界用交互强边框，未选中时悬停仅 1px 细线精准变色。
    final borderColor =
        value
            ? scheme.onSurface
            : _hovering && interactive
            ? scheme.onSurface
            : scheme.outline;
    final target = AppControlTokens.isDesktopDensity ? widget.size + 10 : 44.0;
    return Semantics(
      checked: value,
      enabled: interactive,
      button: true,
      child: MouseRegion(
        cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: interactive ? _handleTap : null,
          child: SizedBox.square(
            dimension: target,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: widget.size,
                height: widget.size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // 勾选=实底反白 ✔；未勾选悬停=底色微升提示可点。
                  color:
                      value
                          ? scheme.onSurface
                          : _hovering && interactive
                          ? scheme.surfaceContainerHighest
                          : Colors.transparent,
                  border: Border.all(color: borderColor, width: 1),
                ),
                child:
                    value
                        ? TweenAnimationBuilder<double>(
                          key: const ValueKey('files-check-pop'),
                          tween: Tween(begin: 0.4, end: 1),
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOutCubic,
                          builder: (context, scale, child) {
                            return Opacity(
                              opacity: scale.clamp(0.0, 1.0),
                              child: Transform.scale(
                                scale: scale,
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            '✔',
                            style: TextStyle(
                              fontSize: widget.size * 0.72,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              color: scheme.surface,
                            ),
                          ),
                        )
                        : widget.indeterminate
                        ? Container(
                          width: widget.size * 0.55,
                          height: 1,
                          color: scheme.onSurface,
                        )
                        : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 建筑极简主义工位开关：32×16 矩形轨道 + 10px 方形滑块，120ms 过渡。
///
/// 选中态轨道以 onSurface 反色填充（滑块转 surface），未选中为
/// surfaceContainerHighest 底 + outline 描边。提供 [label] 时渲染为
/// 整行可点的开关行（label 左、开关右，可选 [subtitle] 次级说明），
/// 禁用态整行 45% 透明；不提供 [label] 时为独立开关，触控密度下
/// 热区外扩到 44px。
class WorkstationToggle extends StatelessWidget {
  const WorkstationToggle({
    required this.value,
    this.onChanged,
    this.enabled = true,
    this.label,
    this.subtitle,
    super.key,
  });

  final bool value;

  final ValueChanged<bool>? onChanged;

  final bool enabled;

  /// 开关行主文案；为空时仅渲染独立开关。
  final String? label;

  /// 开关行次级说明，位于主文案下方。
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final interactive = enabled && onChanged != null;
    final selected = value;
    final borderColor =
        selected
            ? scheme.onSurface
            : interactive
            ? scheme.outline
            : scheme.outlineVariant;

    final Widget track = AnimatedContainer(
      // 轨道键：测试与调用方定位轨道几何（32×16）用。
      key: const ValueKey('workstation-toggle-track'),
      duration: const Duration(milliseconds: 120),
      width: 32,
      height: 16,
      // 轨道内宽 30：滑块 10 + 两侧各 2px 余量，选中态右移 16px。
      padding: EdgeInsets.only(
        top: 2,
        bottom: 2,
        left: selected ? 18 : 2,
        right: selected ? 2 : 18,
      ),
      decoration: BoxDecoration(
        color: selected ? scheme.onSurface : scheme.surfaceContainerHighest,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 10,
        height: 10,
        color: selected ? scheme.surface : scheme.outline,
      ),
    );

    void handleTap() {
      final onChanged = this.onChanged;
      if (!interactive || onChanged == null) {
        return;
      }
      onChanged(!value);
    }

    final Widget content;
    if (label == null) {
      final target = AppControlTokens.isDesktopDensity ? 42.0 : 44.0;
      content = SizedBox.square(dimension: target, child: Center(child: track));
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            track,
          ],
        ),
      );
    }

    return Semantics(
      toggled: selected,
      enabled: interactive,
      button: true,
      child: MouseRegion(
        cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: interactive ? handleTap : null,
          child: Opacity(opacity: interactive ? 1 : 0.45, child: content),
        ),
      ),
    );
  }
}

/// 建筑极简主义方形开关：0px 轨道 + 方形滑块，140ms 平滑过渡。
///
/// 语义与 workstation 主题 Switch 色一致（选中 = 主前景轨道），
/// 但几何为纯直角，替代 M3 胶囊形态。
class WorkstationSwitch extends StatelessWidget {
  const WorkstationSwitch({
    required this.value,
    this.onChanged,
    this.enabled = true,
    super.key,
  });

  final bool value;

  final ValueChanged<bool>? onChanged;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final interactive = enabled && onChanged != null;
    final selected = value;
    final trackColor =
        selected ? scheme.onSurface : scheme.surfaceContainerHighest;
    final thumbColor = selected ? scheme.surface : scheme.outline;
    final borderColor =
        selected
            ? scheme.onSurface
            : interactive
            ? scheme.outline
            : scheme.outlineVariant;
    return Semantics(
      toggled: selected,
      enabled: interactive,
      button: true,
      child: MouseRegion(
        cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: interactive ? () => onChanged!(!value) : null,
          child: SizedBox(
            width: 44,
            height: 28,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 36,
                height: 20,
                padding: EdgeInsets.only(
                  left: selected ? 20 : 2,
                  top: 3,
                  bottom: 3,
                  right: selected ? 2 : 20,
                ),
                decoration: BoxDecoration(
                  color: trackColor,
                  border: Border.all(color: borderColor),
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 14,
                  height: 14,
                  color: thumbColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
