import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 桌面图表悬停气泡的水平对齐方式（用于边缘自动避让防裁切）。
enum DesktopChartTipAlign { left, center, right }

/// 根据柱索引与总数自动计算气泡边缘对齐：左右各 3 项自动贴边，中间居中。
DesktopChartTipAlign resolveDesktopChartTipAlign(int index, int count) {
  if (count <= 1) return DesktopChartTipAlign.center;
  if (count <= 6) {
    if (index == 0) return DesktopChartTipAlign.left;
    if (index == count - 1) return DesktopChartTipAlign.right;
    return DesktopChartTipAlign.center;
  }
  if (index < 3) return DesktopChartTipAlign.left;
  if (index >= count - 3) return DesktopChartTipAlign.right;
  return DesktopChartTipAlign.center;
}

/// 统一桌面图表悬停数据气泡：
/// 基于 `OverlayPortal` + `CompositedTransformFollower`，深色胶囊底 `#12161A` +
/// 8×8 菱形尖角 + 左右 3 项自动边缘对齐，不会被父级 `ClipRRect` 或滚动容器裁切。
class DesktopBarTipOverlay extends StatefulWidget {
  const DesktopBarTipOverlay({
    required this.visible,
    required this.child,
    this.title,
    this.value,
    this.subtitle,
    this.dotColor,
    this.align = DesktopChartTipAlign.center,
    super.key,
  });

  final bool visible;
  final Widget child;
  final String? title;
  final String? value;
  final String? subtitle;
  final Color? dotColor;
  final DesktopChartTipAlign align;

  @override
  State<DesktopBarTipOverlay> createState() => _DesktopBarTipOverlayState();
}

class _DesktopBarTipOverlayState extends State<DesktopBarTipOverlay> {
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _portalController = OverlayPortalController();

  bool get _hasContent =>
      (widget.title?.isNotEmpty ?? false) ||
      (widget.value?.isNotEmpty ?? false);

  void _syncPortalVisibility() {
    final shouldShow = widget.visible && _hasContent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nowShow = widget.visible && _hasContent;
      if (nowShow) {
        if (!_portalController.isShowing) {
          _portalController.show();
        }
      } else {
        if (_portalController.isShowing) {
          _portalController.hide();
        }
      }
    });
    if (!shouldShow && _portalController.isShowing) {
      // 尽量在下一帧前及时收回，避免残影。
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.visible && _hasContent) {
      _syncPortalVisibility();
    }
  }

  @override
  void didUpdateWidget(DesktopBarTipOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible ||
        oldWidget.title != widget.title ||
        oldWidget.value != widget.value) {
      _syncPortalVisibility();
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetAnchor = switch (widget.align) {
      DesktopChartTipAlign.left => Alignment.topLeft,
      DesktopChartTipAlign.center => Alignment.topCenter,
      DesktopChartTipAlign.right => Alignment.topRight,
    };
    final followerAnchor = switch (widget.align) {
      DesktopChartTipAlign.left => Alignment.bottomLeft,
      DesktopChartTipAlign.center => Alignment.bottomCenter,
      DesktopChartTipAlign.right => Alignment.bottomRight,
    };
    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: (context) {
        if (!widget.visible || !_hasContent) {
          return const SizedBox.shrink();
        }
        return Positioned(
          top: 0,
          left: 0,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: targetAnchor,
            followerAnchor: followerAnchor,
            offset: const Offset(0, -8),
            child: IgnorePointer(
              child: Material(
                type: MaterialType.transparency,
                child: _DesktopTipCapsule(
                  title: widget.title,
                  value: widget.value,
                  subtitle: widget.subtitle,
                  dotColor: widget.dotColor,
                  align: widget.align,
                ),
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(link: _layerLink, child: widget.child),
    );
  }
}

class _DesktopTipCapsule extends StatelessWidget {
  const _DesktopTipCapsule({
    required this.align,
    this.title,
    this.value,
    this.subtitle,
    this.dotColor,
  });

  final String? title;
  final String? value;
  final String? subtitle;
  final Color? dotColor;
  final DesktopChartTipAlign align;

  static const _capsuleBg = Color(0xFF12161A);

  @override
  Widget build(BuildContext context) {
    final arrowAlignment = switch (align) {
      DesktopChartTipAlign.left => Alignment.bottomLeft,
      DesktopChartTipAlign.center => Alignment.bottomCenter,
      DesktopChartTipAlign.right => Alignment.bottomRight,
    };
    final arrowMargin = switch (align) {
      DesktopChartTipAlign.left => const EdgeInsets.only(left: 12),
      DesktopChartTipAlign.center => EdgeInsets.zero,
      DesktopChartTipAlign.right => const EdgeInsets.only(right: 12),
    };
    return Stack(
      clipBehavior: Clip.none,
      alignment: arrowAlignment,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _capsuleBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.36),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title!.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (dotColor != null) ...[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: dotColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        title!,
                        style: const TextStyle(
                          color: Color(0xFFAAB4BE),
                          fontSize: DesktopType.sizeCaption,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                if (value != null && value!.isNotEmpty) ...[
                  if (title != null && title!.isNotEmpty)
                    const SizedBox(height: 2),
                  Text(
                    value!,
                    style: const TextStyle(
                      color: Color(0xFFF3F6F9),
                      fontSize: DesktopType.sizeSmall,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: Color(0xFF8C97A3),
                      fontSize: DesktopType.sizeMicro,
                      height: 1.2,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: align == DesktopChartTipAlign.left ? 0 : null,
          right: align == DesktopChartTipAlign.right ? 0 : null,
          child: Padding(
            padding: arrowMargin,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _capsuleBg,
                  border: Border(
                    right: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 交互式柱状图的单柱数据项。
@immutable
class DesktopChartBarItem {
  const DesktopChartBarItem({
    required this.fraction,
    required this.color,
    this.secondaryColor,
    this.tipTitle,
    this.tipValue,
    this.tipSubtitle,
  });

  final double fraction;
  final Color color;

  /// 渐变底部色；缺省为 `color.withValues(alpha: 0.35)`。
  final Color? secondaryColor;
  final String? tipTitle;
  final String? tipValue;
  final String? tipSubtitle;
}

/// 交互式柱状图：支持悬停气泡（自动边缘避让）、非悬停柱压暗至 `0.4` 与可选首尾日期轴。
class DesktopInteractiveBarChart extends StatefulWidget {
  const DesktopInteractiveBarChart({
    required this.items,
    this.height = 90,
    this.barSpacing = 6,
    this.minFraction = 0.04,
    this.barBorderRadius = const BorderRadius.vertical(
      top: Radius.circular(6),
      bottom: Radius.circular(3),
    ),
    this.stagger = false,
    this.animateHeight = true,
    this.axisStartLabel,
    this.axisEndLabel,
    this.axisLabelStyle,
    super.key,
  });

  final List<DesktopChartBarItem> items;
  final double height;
  final double barSpacing;
  final double minFraction;
  final BorderRadius barBorderRadius;
  final bool stagger;
  final bool animateHeight;
  final String? axisStartLabel;
  final String? axisEndLabel;
  final TextStyle? axisLabelStyle;

  @override
  State<DesktopInteractiveBarChart> createState() =>
      _DesktopInteractiveBarChartState();
}

class _DesktopInteractiveBarChartState
    extends State<DesktopInteractiveBarChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final hasAxis =
        (widget.axisStartLabel?.isNotEmpty ?? false) ||
        (widget.axisEndLabel?.isNotEmpty ?? false);
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: i == items.length - 1 ? 0 : widget.barSpacing,
                    ),
                    child: _buildBarSlot(
                      context,
                      index: i,
                      item: items[i],
                      total: items.length,
                      animationsDisabled: animationsDisabled,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasAxis) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.axisStartLabel ?? '', style: widget.axisLabelStyle),
              Text(widget.axisEndLabel ?? '', style: widget.axisLabelStyle),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBarSlot(
    BuildContext context, {
    required int index,
    required DesktopChartBarItem item,
    required int total,
    required bool animationsDisabled,
  }) {
    final isHovered = _hoveredIndex == index;
    final dimmed = _hoveredIndex != null && !isHovered;
    final clampedFraction = item.fraction.clamp(widget.minFraction, 1.0);
    final bottomColor =
        item.secondaryColor ?? item.color.withValues(alpha: 0.35);

    Widget buildBarBody(double heightFactor) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          widthFactor: 1.0,
          heightFactor: heightFactor,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: widget.barBorderRadius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [item.color, bottomColor],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }

    Widget bar =
        widget.animateHeight
            ? TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: clampedFraction),
              duration: MotionToken.resolve(context, MotionToken.chart),
              curve: DesktopMotion.spring,
              builder: (context, value, _) => buildBarBody(value),
            )
            : buildBarBody(clampedFraction);

    if (widget.stagger) {
      bar = DesktopStagger(index: index, child: bar);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) {
        if (_hoveredIndex != index) {
          setState(() => _hoveredIndex = index);
        }
      },
      onExit: (_) {
        if (_hoveredIndex == index) {
          setState(() => _hoveredIndex = null);
        }
      },
      child: DesktopBarTipOverlay(
        visible: isHovered,
        title: item.tipTitle,
        value: item.tipValue,
        subtitle: item.tipSubtitle,
        align: resolveDesktopChartTipAlign(index, total),
        child: AnimatedOpacity(
          opacity: dimmed ? 0.4 : 1.0,
          duration:
              animationsDisabled
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
          child: bar,
        ),
      ),
    );
  }
}

/// 分段存储条的单段数据项。
@immutable
class DesktopChartSegment {
  const DesktopChartSegment({
    required this.flex,
    required this.color,
    required this.label,
    required this.valueLabel,
    this.percentLabel,
  });

  final int flex;
  final Color color;
  final String label;
  final String valueLabel;
  final String? percentLabel;
}

/// 交互式分段占比条：支持悬停气泡、非悬停段压暗至 `0.4` 与外部图例双向悬停联动。
class DesktopInteractiveSegmentedBar extends StatefulWidget {
  const DesktopInteractiveSegmentedBar({
    required this.segments,
    required this.trackColor,
    this.remainingFlex = 0,
    this.height = 14,
    this.borderRadius = 8,
    this.hoveredIndex,
    this.onHoverChanged,
    super.key,
  });

  final List<DesktopChartSegment> segments;
  final Color trackColor;
  final int remainingFlex;
  final double height;
  final double borderRadius;

  /// 外部受控悬停段索引（与图例双向联动时传入）；缺省走内部状态。
  final int? hoveredIndex;
  final ValueChanged<int?>? onHoverChanged;

  @override
  State<DesktopInteractiveSegmentedBar> createState() =>
      _DesktopInteractiveSegmentedBarState();
}

class _DesktopInteractiveSegmentedBarState
    extends State<DesktopInteractiveSegmentedBar> {
  int? _internalHoveredIndex;

  int? get _effectiveHoveredIndex =>
      widget.onHoverChanged != null
          ? widget.hoveredIndex
          : _internalHoveredIndex;

  void _setHovered(int? index) {
    if (widget.onHoverChanged != null) {
      widget.onHoverChanged!(index);
    } else if (_internalHoveredIndex != index) {
      setState(() => _internalHoveredIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeIndices = <int>[
      for (var i = 0; i < widget.segments.length; i++)
        if (widget.segments[i].flex > 0) i,
    ];
    final hovered = _effectiveHoveredIndex;
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        height: widget.height,
        child: Row(
          children: [
            for (var pos = 0; pos < activeIndices.length; pos++)
              _buildSegment(
                index: activeIndices[pos],
                pos: pos,
                activeCount: activeIndices.length,
                segment: widget.segments[activeIndices[pos]],
                hovered: hovered,
                animationsDisabled: animationsDisabled,
              ),
            if (widget.remainingFlex > 0 || activeIndices.isEmpty)
              Expanded(
                flex: activeIndices.isEmpty ? 10000 : widget.remainingFlex,
                child: ColoredBox(color: widget.trackColor),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment({
    required int index,
    required int pos,
    required int activeCount,
    required DesktopChartSegment segment,
    required int? hovered,
    required bool animationsDisabled,
  }) {
    final isHovered = hovered == index;
    final dimmed = hovered != null && !isHovered;
    final align =
        activeCount <= 1
            ? DesktopChartTipAlign.center
            : pos == 0
            ? DesktopChartTipAlign.left
            : pos == activeCount - 1
            ? DesktopChartTipAlign.right
            : DesktopChartTipAlign.center;
    final valueText =
        segment.percentLabel != null && segment.percentLabel!.isNotEmpty
            ? '${segment.valueLabel} · ${segment.percentLabel}'
            : segment.valueLabel;
    return Expanded(
      flex: segment.flex,
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        onEnter: (_) => _setHovered(index),
        onExit: (_) {
          if (_effectiveHoveredIndex == index) {
            _setHovered(null);
          }
        },
        child: DesktopBarTipOverlay(
          visible: isHovered,
          title: segment.label,
          value: valueText,
          dotColor: segment.color,
          align: align,
          child: AnimatedOpacity(
            opacity: dimmed ? 0.4 : 1.0,
            duration:
                animationsDisabled
                    ? Duration.zero
                    : const Duration(milliseconds: 140),
            child: ColoredBox(
              color: segment.color,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}
