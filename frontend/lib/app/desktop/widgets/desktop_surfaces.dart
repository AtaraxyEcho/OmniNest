import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';
part 'desktop_image_loading.dart';

/// 样例 `.eyebrow`：大写小字眉标。
class DesktopEyebrow extends StatelessWidget {
  const DesktopEyebrow(this.text, {this.color, this.padding, super.key});

  final String text;
  final Color? color;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Text(
        text.toUpperCase(),
        style: DesktopType.eyebrow(color ?? skin.text3),
      ),
    );
  }
}

/// 计算桌面页面内容区左右留白，使 [DesktopSliverPage] 与 [DesktopPage] 对齐。
double _desktopContentSideInset(
  double viewportWidth, {
  double maxWidth = DesktopMetrics.pageMaxWidth,
}) {
  final horizontal = (viewportWidth * 0.03).clamp(
    DesktopMetrics.pageHorizontalMin,
    DesktopMetrics.pageHorizontalMax,
  );
  if (!maxWidth.isFinite || viewportWidth <= maxWidth) {
    return horizontal;
  }
  return (viewportWidth - maxWidth) / 2 + horizontal;
}

/// 样例 `.page`：限宽 1560、左右 24-52 自适应、底部为播放条留白。
class DesktopPage extends StatelessWidget {
  const DesktopPage({
    required this.children,
    this.maxWidth = DesktopMetrics.pageMaxWidth,
    this.topPadding,
    this.staggerChildren = false,
    super.key,
  });

  final List<Widget> children;
  final double maxWidth;
  final double? topPadding;

  /// 首页按样例给每个顶层区块挂 55ms 交错入场；其他页面保持即显。
  final bool staggerChildren;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = (width * 0.03).clamp(
      DesktopMetrics.pageHorizontalMin,
      DesktopMetrics.pageHorizontalMax,
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            topPadding ?? DesktopMetrics.pageTopPadding,
            horizontal,
            DesktopMetrics.playerBarClearance,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++)
                staggerChildren
                    ? DesktopStagger(index: i, child: children[i])
                    : children[i],
            ],
          ),
        ),
      ),
    );
  }
}

/// 通用吸顶页面骨架：基于 [CustomScrollView]，保持与 [DesktopPage] 一致的最大
/// 内容宽度与水平内边距，同时让 [DesktopStickySliver] 在吸顶态实现全出血磨砂背板。
class DesktopSliverPage extends StatefulWidget {
  const DesktopSliverPage({
    this.controller,
    this.topPadding = DesktopMetrics.pageTopPadding,
    this.bottomPadding = 130.0,
    required this.slivers,
    super.key,
  });

  final ScrollController? controller;
  final double topPadding;
  final double bottomPadding;
  final List<Widget> slivers;

  @override
  State<DesktopSliverPage> createState() => _DesktopSliverPageState();
}

class _DesktopSliverPageState extends State<DesktopSliverPage> {
  ScrollController? _fallbackController;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _fallbackController = ScrollController();
    }
  }

  @override
  void didUpdateWidget(DesktopSliverPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == null && widget.controller != null) {
      _fallbackController?.dispose();
      _fallbackController = null;
    } else if (oldWidget.controller != null && widget.controller == null) {
      _fallbackController ??= ScrollController();
    }
  }

  @override
  void dispose() {
    _fallbackController?.dispose();
    _fallbackController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveController = widget.controller ?? _fallbackController!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth =
            constraints.hasBoundedWidth
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
        final sideInset = _desktopContentSideInset(viewportWidth);
        return Scrollbar(
          controller: effectiveController,
          child: CustomScrollView(
            controller: effectiveController,
            primary: false,
            slivers: [
              if (widget.topPadding > 0)
                SliverToBoxAdapter(child: SizedBox(height: widget.topPadding)),
              for (final sliver in widget.slivers)
                sliver is DesktopStickySliver
                    ? sliver
                    : SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: sideInset),
                      sliver: sliver,
                    ),
              if (widget.bottomPadding > 0)
                SliverToBoxAdapter(
                  child: SizedBox(height: widget.bottomPadding),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 通用 Sticky 分类栏 Sliver（样例 `.page-head.sticky` / `.cat-sticky`）。
///
/// 吸顶时铺满全宽（忽略内容区左右 padding，实现 `inset: 0 -100vw` 全出血磨砂），
/// 外层严格包裹 [ClipRect] 再套独立 [BackdropFilter]（blur: 26, sat: 1.4），
/// 并自测量真实高度驱动 [SliverPersistentHeader]，防止窄窗口换行时触发 RenderFlex 溢出。
class DesktopStickySliver extends StatefulWidget {
  const DesktopStickySliver({
    required this.child,
    this.minHeight,
    this.maxHeight,
    super.key,
  });

  final Widget child;
  final double? minHeight;
  final double? maxHeight;

  @override
  State<DesktopStickySliver> createState() => _DesktopStickySliverState();
}

class _DesktopStickySliverState extends State<DesktopStickySliver> {
  static const int _maxMeasurePasses = 3;

  double? _measuredHeight;
  int _measurePasses = 0;

  @override
  void didUpdateWidget(DesktopStickySliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minHeight != widget.minHeight ||
        oldWidget.maxHeight != widget.maxHeight) {
      _measurePasses = 0;
    }
  }

  void _onChildSizeChanged(Size size) {
    final next = size.height;
    if (next <= 0 || !next.isFinite) {
      return;
    }
    if (_measurePasses >= _maxMeasurePasses) {
      return;
    }
    if (_measuredHeight != null && (_measuredHeight! - next).abs() <= 1.0) {
      return;
    }
    _measurePasses += 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _measuredHeight = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final resolvedMin = widget.minHeight ?? _measuredHeight ?? 68.0;
    final resolvedMax = math.max(
      resolvedMin,
      widget.maxHeight ?? _measuredHeight ?? resolvedMin,
    );
    return SliverPersistentHeader(
      pinned: true,
      delegate: _DesktopStickySliverDelegate(
        minExtent: resolvedMin,
        maxExtent: resolvedMax,
        child: widget.child,
        onMeasured:
            widget.minHeight != null && widget.maxHeight != null
                ? null
                : _onChildSizeChanged,
      ),
    );
  }
}

class _DesktopStickySliverDelegate extends SliverPersistentHeaderDelegate {
  _DesktopStickySliverDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.child,
    this.onMeasured,
  });

  @override
  final double minExtent;

  @override
  final double maxExtent;

  final Widget child;
  final ValueChanged<Size>? onMeasured;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final skin = DesktopSkin.of(context);
    final stuck = shrinkOffset > 0.5 || overlapsContent;
    final duration = MotionToken.reduced(
      context,
      const Duration(milliseconds: 250),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth =
            constraints.hasBoundedWidth
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
        final sideInset = _desktopContentSideInset(viewportWidth);
        Widget content = Padding(
          padding: EdgeInsets.symmetric(horizontal: sideInset),
          child: child,
        );
        if (onMeasured != null) {
          content = _StickyMeasureSize(onChange: onMeasured!, child: content);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: stuck ? 1.0 : 0.0),
                    duration: duration,
                    curve: DesktopMotion.ease,
                    builder: (context, opacity, _) {
                      if (opacity <= 0.01) {
                        return const SizedBox.shrink();
                      }
                      return Opacity(
                        opacity: opacity.clamp(0.0, 1.0),
                        alwaysIncludeSemantics: true,
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: desktopGlassFilter(
                              blur: 26,
                              saturation: 1.4,
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: skin.bg.withValues(alpha: 0.38),
                                border: Border(
                                  bottom: BorderSide(color: skin.line),
                                ),
                                boxShadow:
                                    skin.isDark
                                        ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.08,
                                            ),
                                            blurRadius: 24,
                                            offset: const Offset(0, 6),
                                          ),
                                        ]
                                        : null,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            // 用不可滚的单子滚动容器包裹内容，确保首帧测量尚未完成或窄窗
            // 换行时绝不触发 RenderFlex overflow。
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: content,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  bool shouldRebuild(covariant _DesktopStickySliverDelegate oldDelegate) {
    return oldDelegate.minExtent != minExtent ||
        oldDelegate.maxExtent != maxExtent ||
        oldDelegate.child != child;
  }
}

class _StickyMeasureSize extends SingleChildRenderObjectWidget {
  const _StickyMeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderStickyMeasureSize(onChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderStickyMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderStickyMeasureSize extends RenderProxyBox {
  _RenderStickyMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();
    final current = child?.size;
    if (current != null && current != _lastSize) {
      _lastSize = current;
      onChange(current);
    }
  }
}

/// 样例 `.page-head`：眉标 + 衬线大标题 + 副标题 + 右侧动作区。
class DesktopPageHead extends StatelessWidget {
  const DesktopPageHead({
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions = const <Widget>[],
    this.actionsRightAlignedWhenWrapped = false,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;
  final bool actionsRightAlignedWhenWrapped;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (eyebrow != null) DesktopEyebrow(eyebrow!),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(title, style: DesktopType.display(skin.text)),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(subtitle!, style: DesktopType.body(skin.text2)),
          ),
      ],
    );
    // 样例 `.head-actions` 是不换行 flex；窄窗口只让整组动作换到标题下方。
    final actionContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          actions[index],
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 26),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (actions.isEmpty || !actionsRightAlignedWhenWrapped) {
            return Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 20,
              runSpacing: 14,
              children: [
                heading,
                if (actions.isNotEmpty)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
              ],
            );
          }

          if (constraints.maxWidth < DesktopMetrics.pageHeadSplitBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerRight, child: actionContent),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 20),
              actionContent,
            ],
          );
        },
      ),
    );
  }
}

/// 样例 `.sect` + `.sect-head`：区块标题与「查看全部」链接。
class DesktopSection extends StatelessWidget {
  const DesktopSection({
    required this.title,
    required this.child,
    this.eyebrow,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    super.key,
  });

  final String title;
  final Widget child;
  final String? eyebrow;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom:
            compact
                ? DesktopMetrics.sectionGapCompact
                : DesktopMetrics.sectionGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null) DesktopEyebrow(eyebrow!),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          title,
                          style: DesktopType.sectionTitle(skin.text),
                        ),
                      ),
                    ],
                  ),
                ),
                if (actionLabel != null)
                  DesktopLink(label: actionLabel!, onPressed: onAction),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// 样例 `.link`：强调色文字 + 右尖括号。
class DesktopLink extends StatelessWidget {
  const DesktopLink({
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailing = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      enabled: onPressed != null,
      builder:
          (context, hovered) => GestureDetector(
            onTap: onPressed,
            behavior: HitTestBehavior.opaque,
            child: Opacity(
              opacity: hovered ? 0.75 : 1,
              alwaysIncludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 13, color: skin.accent),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.link(skin.accent),
                      ),
                    ),
                    if (trailing)
                      Icon(DesktopIcons.chevron, size: 14, color: skin.accent),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

/// 样例 `.card`：半透明面板 + 发丝描边 + 18 圆角。
class DesktopCard extends StatelessWidget {
  const DesktopCard({
    required this.child,
    this.title,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(24, 22, 24, 22),
    super.key,
  });

  final Widget child;
  final String? title;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final radius = BorderRadius.circular(DesktopMetrics.radiusCard);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter.grouped(
          filterConfig: ImageFilterConfig(
            desktopGlassFilter(blur: 24, saturation: 1.3),
          ),
          child: RepaintBoundary(
            child: Container(
              decoration: BoxDecoration(
                color: skin.panel,
                borderRadius: radius,
                border: Border.all(color: skin.line),
              ),
              child: Material(
                type: MaterialType.transparency,
                borderRadius: radius,
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title!,
                                  style: DesktopType.cardTitle(skin.text),
                                ),
                              ),
                              if (action != null) action!,
                            ],
                          ),
                        ),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 样例 `.mini-prog`：4px 进度条，右侧百分比小字。
class DesktopProgress extends StatelessWidget {
  const DesktopProgress({
    required this.fraction,
    this.label,
    this.large = false,
    this.color,
    super.key,
  });

  final double fraction;
  final String? label;
  final bool large;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final clamped = fraction.clamp(0.0, 1.0);
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: large ? 6 : 4,
        child: Stack(
          children: [
            ColoredBox(color: skin.raise3),
            FractionallySizedBox(
              widthFactor: clamped,
              child: ColoredBox(color: color ?? skin.accent),
            ),
          ],
        ),
      ),
    );
    if (label == null) {
      return bar;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        bar,
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(label!, style: DesktopType.micro(skin.text3)),
        ),
      ],
    );
  }
}

/// 样例 `.kv`：左标签右值的两列定义表。
class DesktopKeyValues extends StatelessWidget {
  const DesktopKeyValues({
    required this.entries,
    this.alignValuesRight = true,
    super.key,
  });

  final List<MapEntry<String, String>> entries;
  final bool alignValuesRight;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 132),
                    child: Text(
                      entry.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.dense(skin.text3),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      entry.value,
                      textAlign:
                          alignValuesRight ? TextAlign.right : TextAlign.left,
                      style: DesktopType.dense(skin.text),
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

/// 样例 `.empty`：圆形光晕章 + 标题/说明分层 + soft 按钮动作。
class DesktopEmpty extends StatelessWidget {
  const DesktopEmpty({
    required this.message,
    this.icon = DesktopIcons.info,
    this.description,
    this.actionLabel,
    this.onAction,
    this.large = false,
    this.small = false,
    super.key,
  });

  final String message;
  final IconData icon;

  /// 可选第二行说明；不传时保持单段空态，兼容既有 23 处调用点。
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 整页级空态（样例 `.empty.big`：`padding 90px 20px`）。
  final bool large;

  /// 面板内嵌空态（样例 `.empty-sm`：`padding 24px 16px`，图标 18 + 11）。
  /// 与 [large] 同时为真时按整页级渲染。
  final bool small;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final accent = skin.accent;
    final compact = small && !large;
    final padding =
        large
            ? const EdgeInsets.symmetric(vertical: 90, horizontal: 20)
            : compact
            ? const EdgeInsets.symmetric(vertical: 24, horizontal: 16)
            : const EdgeInsets.symmetric(vertical: 44, horizontal: 24);
    final iconSize = compact ? 18.0 : 24.0;
    final iconPadding = compact ? 11.0 : 16.0;
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: compact ? 6 : 10),
              child: Container(
                padding: EdgeInsets.all(iconPadding),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.4, -0.5),
                    radius: 1.03,
                    colors: [
                      accent.withValues(alpha: 0.22),
                      accent.withValues(alpha: 0.08),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.06),
                      blurRadius: 0,
                      spreadRadius: 7,
                    ),
                  ],
                ),
                foregroundDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                ),
                child: Icon(icon, size: iconSize, color: accent),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: DesktopType.medium(
                  skin.text,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (description != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    description!,
                    textAlign: TextAlign.center,
                    style: DesktopType.dense(skin.text3).copyWith(height: 1.55),
                  ),
                ),
              ),
            if (actionLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: DesktopButton(
                  label: actionLabel!,
                  variant: DesktopButtonVariant.soft,
                  onPressed: onAction,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 样例 `.img`：加载期为微光底，解码后 600ms 淡入；失败保留底面不露破图。
class DesktopImage extends StatelessWidget {
  const DesktopImage({
    required this.url,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.cacheWidth,
    this.fallbackIcon,
    super.key,
  });

  final String? url;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// 缩略图场景按显示尺寸限制解码宽度；null 保持原图解码（全屏查看器用）。
  final int? cacheWidth;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final placeholder = _ImageShimmer(borderRadius: borderRadius);
    final skin = DesktopSkin.of(context);
    final fallback = ColoredBox(
      color: skin.raise2,
      child:
          fallbackIcon == null
              ? null
              : Center(child: Icon(fallbackIcon, size: 28, color: skin.text3)),
    );
    Widget content = fallback;
    final source = url;
    if (source != null && source.isNotEmpty) {
      content = Image.network(
        source,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        cacheWidth: cacheWidth,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return _ImageFadeIn(child: child);
          }
          return placeholder;
        },
        loadingBuilder:
            (context, child, progress) =>
                progress == null ? child : placeholder,
        errorBuilder: (context, error, stack) => fallback,
      );
    }
    if (borderRadius != null) {
      content = ClipRRect(borderRadius: borderRadius!, child: content);
    }
    return content;
  }
}

/// 图片加载期的微光底（样例 `.img:not(.ok){animation:shimmer 1.8s}`）。
class DesktopHoverLift extends StatelessWidget {
  const DesktopHoverLift({
    required this.child,
    this.onTap,
    this.onSecondaryTap,
    this.lift = 4,
    this.tooltip,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final double lift;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget content = DesktopHover(
      enabled: onTap != null,
      builder:
          (context, hovered) => TweenAnimationBuilder<double>(
            tween: Tween<double>(end: hovered ? -lift : 0),
            duration: MotionToken.reduced(context, DesktopMotion.lift),
            curve: DesktopMotion.spring,
            builder:
                (context, dy, child) =>
                    Transform.translate(offset: Offset(0, dy), child: child),
            child: child,
          ),
    );
    content = GestureDetector(
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
    if (tooltip != null) {
      content = Tooltip(message: tooltip!, child: content);
    }
    return content;
  }
}
