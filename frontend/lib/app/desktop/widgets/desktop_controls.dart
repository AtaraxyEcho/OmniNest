import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;

import 'package:omninest/app/desktop/widgets/desktop_focus_outline.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_press.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';

export 'package:omninest/app/desktop/widgets/desktop_chart_tooltip.dart';

// 滑块自带键盘与 ARIA，体量够单开一份；public API 仍从本文件导出。
part 'desktop_controls_slider.dart';

/// 悬停态包装：样例几乎所有控件都靠 `:hover` 换底色/抬升，
/// Flutter 侧统一经此拿 hovered，避免每个控件各写一份 MouseRegion。
class DesktopHover extends StatefulWidget {
  const DesktopHover({
    required this.builder,
    this.enabled = true,
    this.cursor = SystemMouseCursors.click,
    super.key,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final bool enabled;
  final MouseCursor cursor;

  @override
  State<DesktopHover> createState() => _DesktopHoverState();
}

class _DesktopHoverState extends State<DesktopHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.enabled ? widget.cursor : SystemMouseCursors.basic,
      onEnter: (_) {
        if (widget.enabled) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, widget.enabled && _hovered),
    );
  }
}

enum DesktopButtonVariant { primary, soft, ghost, glass, danger }

/// 样例 `.btn`：34/42 两档高度，10/12 圆角，按下轻微缩放。
class DesktopButton extends StatelessWidget {
  const DesktopButton({
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = DesktopButtonVariant.ghost,
    this.large = false,
    this.fullWidth = false,
    this.active = false,
    this.foregroundOverride,
    this.busy = false,
    this.tooltip,
    super.key,
  });

  const DesktopButton.iconOnly({
    required IconData this.icon,
    required this.onPressed,
    this.variant = DesktopButtonVariant.soft,
    this.large = false,
    this.active = false,
    this.foregroundOverride,
    this.tooltip,
    super.key,
  }) : label = null,
       fullWidth = false,
       busy = false;

  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final DesktopButtonVariant variant;
  final bool large;
  final bool fullWidth;
  final bool active;
  final Color? foregroundOverride;
  final bool busy;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final enabled = onPressed != null && !busy;
    final height =
        large ? DesktopMetrics.buttonLargeHeight : DesktopMetrics.buttonHeight;
    final radius =
        large ? DesktopMetrics.radiusButtonLarge : DesktopMetrics.radiusButton;
    final (background, hoverBackground, foreground, border) = switch (variant) {
      DesktopButtonVariant.primary => (
        skin.accent,
        skin.accent,
        skin.accentInk,
        null,
      ),
      DesktopButtonVariant.soft => (
        active ? skin.raise3 : skin.raise2,
        skin.raise3,
        skin.text,
        null,
      ),
      DesktopButtonVariant.ghost => (
        active ? skin.raise3 : Colors.transparent,
        skin.raise2,
        skin.text,
        null,
      ),
      DesktopButtonVariant.glass => (
        skin.onStageWash(0.14),
        skin.onStageWash(0.24),
        skin.onStage,
        skin.onStageWash(0.22),
      ),
      DesktopButtonVariant.danger => (
        DesktopPalette.danger,
        Color.lerp(DesktopPalette.danger, Colors.white, 0.12)!,
        Colors.white,
        null,
      ),
    };
    final effectiveForeground = foregroundOverride ?? foreground;

    Widget content = DesktopHover(
      enabled: enabled,
      builder: (context, hovered) {
        final resolved = hovered ? hoverBackground : background;
        final box = AnimatedContainer(
          duration: MotionToken.reduced(context, MotionToken.fast),
          curve: MotionToken.curve,
          height: height,
          // 样例 `desktop.css:70-74`：primary hover 抬 1px，按下整体缩到 0.96。
          transform: Matrix4.translationValues(
            0,
            hovered && variant == DesktopButtonVariant.primary ? -1 : 0,
            0,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: label == null ? 0 : (large ? 20 : 14),
          ),
          // 图标按钮保持与当前高度一致的正方形（34×34 / 42×42），与同排大按钮对齐。
          width: label == null ? height : null,
          decoration: BoxDecoration(
            color: resolved,
            borderRadius: BorderRadius.circular(radius),
            border: border == null ? null : Border.all(color: border),
            boxShadow:
                variant == DesktopButtonVariant.primary
                    ? [
                      BoxShadow(
                        color: skin.accentWash(hovered ? 0.42 : 0.28),
                        blurRadius: hovered ? 28 : 20,
                        offset: Offset(0, hovered ? 10 : 8),
                        spreadRadius: -8,
                      ),
                    ]
                    : null,
          ),
          child: Row(
            // Wrap/Row 给的是松约束：mainAxisSize.max 会让按钮撑满整行，
            // 只有 fullWidth 才该铺满，其余按内容收宽。
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(
                  width: DesktopMetrics.iconSmall,
                  height: DesktopMetrics.iconSmall,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: effectiveForeground,
                  ),
                )
              else if (icon != null)
                Icon(
                  icon,
                  size: DesktopMetrics.iconSmall,
                  color: effectiveForeground,
                ),
              if (label != null) ...[
                if (icon != null || busy) const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        large
                            ? DesktopType.buttonLarge(effectiveForeground)
                            : DesktopType.button(effectiveForeground),
                  ),
                ),
              ],
            ],
          ),
        );
        if (variant == DesktopButtonVariant.glass) {
          return DesktopGlassSurface(
            borderRadius: BorderRadius.circular(radius),
            blur: 16,
            saturation: 1.4,
            child: box,
          );
        }
        return box;
      },
    );

    content = Opacity(opacity: enabled ? 1 : 0.4, child: content);
    content = GestureDetector(
      onTap: enabled ? onPressed : null,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
    // 按下反馈：`.btn:active{transform:scale(.96)}`。
    content = DesktopPressScale(enabled: enabled, scale: 0.96, child: content);
    if (fullWidth) {
      content = SizedBox(width: double.infinity, child: content);
    }
    if (tooltip != null) {
      content = Tooltip(message: tooltip!, child: content);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: label ?? tooltip,
      child: DesktopFocusOutline(
        radius: radius,
        onActivate: enabled ? onPressed : null,
        child: content,
      ),
    );
  }
}

/// 样例 `.tb-btn`：32 方形、9 圆角、激活态染强调色，可挂角标。
class DesktopIconButton extends StatelessWidget {
  const DesktopIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.active = false,
    this.size,
    this.iconSize,
    this.badge,
    this.badgeColor,
    this.color,
    this.glyph,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;
  final double? size;
  final double? iconSize;
  final int? badge;
  final Color? badgeColor;
  final Color? color;

  /// 自定义图形：需要自带过渡的图标（如主题切换的日/月交接）走这里，
  /// 传了就不再用 [icon]。
  final Widget? glyph;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final side = size ?? DesktopMetrics.iconButtonSize;
    final enabled = onPressed != null;
    final foreground = color ?? (active ? skin.accent : skin.text2);
    Widget button = DesktopHover(
      enabled: enabled,
      builder:
          (context, hovered) => AnimatedContainer(
            duration: MotionToken.reduced(context, MotionToken.fast),
            curve: MotionToken.curve,
            width: side,
            height: side,
            decoration: BoxDecoration(
              color:
                  active
                      ? skin.accentWash(0.14)
                      : hovered
                      ? skin.raise2
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(
                DesktopMetrics.radiusIconButton,
              ),
            ),
            child:
                glyph ??
                Icon(
                  icon,
                  size: iconSize ?? DesktopMetrics.iconSmall + 1,
                  color: hovered && !active ? skin.text : foreground,
                ),
          ),
    );
    if (badge != null && badge! > 0) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            top: 2,
            right: 1,
            child: DesktopBadgePop(
              value: badge!,
              child: Container(
                constraints: const BoxConstraints(minWidth: 15),
                height: 15,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: badgeColor ?? skin.accent,
                  borderRadius: BorderRadius.circular(
                    DesktopMetrics.radiusPill,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  badge! > 99 ? '99+' : '$badge',
                  style: DesktopType.nano(
                    badgeColor == null ? skin.accentInk : skin.onStage,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      );
    }
    button = Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: button,
      ),
    );
    // `.tb-btn:active { transform: scale(.88) }`：按下瞬间缩一下，松手回弹。
    button = DesktopPressScale(enabled: enabled, child: button);
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: DesktopFocusOutline(
        radius: DesktopMetrics.radiusIconButton,
        onActivate: enabled ? onPressed : null,
        child: button,
      ),
    );
  }
}

/// 样例 `.chip`：静态标签；`solid` 为强调色实底。
class DesktopChip extends StatelessWidget {
  const DesktopChip(
    this.label, {
    this.icon,
    this.solid = false,
    this.tone,
    super.key,
  });

  final String label;
  final IconData? icon;
  final bool solid;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final seed = tone ?? skin.text2;
    final background =
        solid
            ? (tone ?? skin.accent)
            : tone == null
            ? skin.raise2
            : seed.withValues(alpha: 0.16);
    final foreground =
        solid
            ? (tone == null ? skin.accentInk : skin.onStage)
            : tone == null
            ? skin.text2
            : seed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusPill),
        border:
            solid
                ? null
                : Border.all(
                  color:
                      tone == null ? skin.line : seed.withValues(alpha: 0.30),
                ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(label, style: DesktopType.chip(foreground)),
        ],
      ),
    );
  }
}

/// 样例 `.chip-btn`：可点筛选胶囊，选中为强调色实底。
class DesktopChipButton extends StatelessWidget {
  const DesktopChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.dashed = false,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: MotionToken.reduced(context, MotionToken.fast),
              curve: MotionToken.curve,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                // 样例 `more.css:21`：选中是 `accent 18%` 淡底 + `accent 45%`
                // 描边 + 600 字重，不是实底反白；实底留给主按钮。
                color:
                    selected
                        ? skin.accentWash(dashed ? 0.14 : 0.18)
                        : hovered
                        ? skin.raise2
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(DesktopMetrics.radiusPill),
                border: Border.all(
                  color: selected ? skin.accentWash(0.45) : skin.line,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: DesktopType.chipButton(
                      selected || hovered ? skin.text : skin.text2,
                    ).copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Text('$count', style: DesktopType.micro(skin.text3)),
                  ],
                ],
              ),
            ),
          ),
    );
  }
}

/// 样例 `.seg`：分段控件，指示块按选中项实测宽度滑动。
class DesktopSeg<T> extends StatefulWidget {
  const DesktopSeg({
    required this.options,
    required this.value,
    required this.onChanged,
    required this.labelOf,
    this.small = false,
    super.key,
  });

  final List<T> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T) labelOf;
  final bool small;

  @override
  State<DesktopSeg<T>> createState() => _DesktopSegState<T>();
}

class _DesktopSegState<T> extends State<DesktopSeg<T>> {
  final Map<T, GlobalKey> _keys = <T, GlobalKey>{};
  final GlobalKey _stackKey = GlobalKey();
  Rect _indicator = Rect.zero;

  GlobalKey _keyFor(T option) => _keys.putIfAbsent(option, GlobalKey.new);

  void _measure() {
    final box =
        _keys[widget.value]?.currentContext?.findRenderObject() as RenderBox?;
    final host = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || host == null || !box.attached || !host.attached) {
      return;
    }
    final origin = box.localToGlobal(Offset.zero, ancestor: host);
    final next = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      box.size.width,
      box.size.height,
    );
    if (next != _indicator) {
      setState(() => _indicator = next);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _measure();
      }
    });
  }

  @override
  void didUpdateWidget(DesktopSeg<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _measure();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final vertical = widget.small ? 4.0 : 6.0;
    final horizontal = widget.small ? 11.0 : 14.0;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: skin.line),
      ),
      child: Stack(
        key: _stackKey,
        children: [
          if (_indicator != Rect.zero)
            AnimatedPositioned(
              // 样例 `.seg i { transition: transform .45s var(--spring),
              // width .45s var(--spring) }`。
              duration: MotionToken.reduced(context, DesktopMotion.modal),
              curve: DesktopMotion.spring,
              left: _indicator.left,
              top: _indicator.top,
              width: _indicator.width,
              height: _indicator.height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: skin.raise3,
                  borderRadius: BorderRadius.circular(
                    DesktopMetrics.radiusSmall,
                  ),
                  // 样例 `desktop.css:90`：指示块带一层 1px/6px 的投影。
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in widget.options)
                // 样例 `ui.tsx:28-30`：分段控件是 tablist，每段是带
                // aria-selected 的 tab。
                Semantics(
                  button: true,
                  selected: option == widget.value,
                  inMutuallyExclusiveGroup: true,
                  child: DesktopHover(
                    builder:
                        (context, hovered) => GestureDetector(
                          key: _keyFor(option),
                          onTap: () => widget.onChanged(option),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontal,
                              vertical: vertical,
                            ),
                            child: Text(
                              widget.labelOf(option),
                              style: DesktopType.dense(
                                option == widget.value
                                    ? skin.text
                                    : hovered
                                    ? skin.text2
                                    : skin.text2,
                              ).copyWith(
                                fontWeight:
                                    option == widget.value
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 样例 `.toggle`：38×22 轨道 + 16 圆点。
class DesktopToggle extends StatelessWidget {
  const DesktopToggle({
    required this.value,
    required this.onChanged,
    this.label,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Semantics(
      // 样例 `ui.tsx:36`：开关是 `role=switch aria-checked`，不是按钮。
      toggled: value,
      label: label,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          // 样例 `.toggle { transition: background .25s }`。
          duration: MotionToken.reduced(context, DesktopMotion.springHover),
          curve: MotionToken.curve,
          width: 38,
          height: 22,
          decoration: BoxDecoration(
            color: value ? skin.accent : skin.raise3,
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusPill),
          ),
          child: AnimatedAlign(
            // 样例 `.toggle i { transition: transform .35s var(--spring) }`；
            // 位移 16px 由 38 - 16 - 3×2 自然推出。
            duration: MotionToken.reduced(context, DesktopMotion.lift),
            curve: DesktopMotion.spring,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: DesktopSkin.of(context).onStage,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: skin.shadow.last.color,
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
