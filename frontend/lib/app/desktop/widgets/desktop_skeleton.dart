import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 骨架占位文案字号（对齐样例 13px 的 `sk-line` 标签）。
const _skeletonLabelSize = 13.0;

/// 全局单时钟骨架扫光作用域。
///
/// 挂在桌面壳层根部，全应用仅维护 1 个 [AnimationController]：有活跃骨架时
/// 自动启动循环扫光，无活跃骨架时立即停表零功耗，彻底消除一屏 30–50 个独立
/// Ticker 造成的切页掉帧。
class DesktopSkeletonShimmerScope extends StatefulWidget {
  const DesktopSkeletonShimmerScope({required this.child, super.key});

  final Widget child;

  @override
  State<DesktopSkeletonShimmerScope> createState() =>
      _DesktopSkeletonShimmerScopeState();
}

class _DesktopSkeletonShimmerScopeState
    extends State<DesktopSkeletonShimmerScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DesktopMotion.skeletonSweep,
  );
  int _activeCount = 0;
  bool _disableAnimations = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disabled != _disableAnimations) {
      _disableAnimations = disabled;
      _syncTicker();
    }
  }

  void _attach() {
    _activeCount++;
    _syncTicker();
  }

  void _detach() {
    if (_activeCount > 0) {
      _activeCount--;
    }
    _syncTicker();
  }

  void _syncTicker() {
    if (!mounted) {
      return;
    }
    if (_disableAnimations || _activeCount <= 0) {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      if (_disableAnimations && _controller.value != 0) {
        _controller.value = 0;
      }
      return;
    }
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DesktopSkeletonShimmerInherited(
      animation: _controller,
      attach: _attach,
      detach: _detach,
      child: widget.child,
    );
  }
}

class _DesktopSkeletonShimmerInherited extends InheritedWidget {
  const _DesktopSkeletonShimmerInherited({
    required this.animation,
    required this.attach,
    required this.detach,
    required super.child,
  });

  final Animation<double> animation;
  final VoidCallback attach;
  final VoidCallback detach;

  static _DesktopSkeletonShimmerInherited? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<_DesktopSkeletonShimmerInherited>();
  }

  @override
  bool updateShouldNotify(_DesktopSkeletonShimmerInherited oldWidget) =>
      animation != oldWidget.animation;
}

/// 条目级骨架（样例新版 polish.css）：105deg 微斜向扫光，共享根部单时钟。
class DesktopSkeletonBox extends StatefulWidget {
  const DesktopSkeletonBox({
    this.width,
    this.height = 14,
    this.radius = 8,
    this.index = 0,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;

  /// 条目序号：`:nth-child(2n)` 与 `(3n)` 的 .18/.36s 延迟换算成循环
  /// 动画的相位差，不再为每一格创建 Timer 或独立 Controller。
  final int index;

  @override
  State<DesktopSkeletonBox> createState() => _DesktopSkeletonBoxState();
}

class _DesktopSkeletonBoxState extends State<DesktopSkeletonBox> {
  _DesktopSkeletonShimmerInherited? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _DesktopSkeletonShimmerInherited.maybeOf(context);
    if (!identical(next, _scope)) {
      _scope?.detach();
      _scope = next;
      _scope?.attach();
    }
  }

  @override
  void dispose() {
    _scope?.detach();
    _scope = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final base = Color.lerp(skin.bg2, skin.text, skin.isDark ? 0.09 : 0.08)!;
    final highlight =
        Color.lerp(base, Colors.white, skin.isDark ? 0.10 : 0.85)!;
    final childIndex = widget.index + 1;
    final phase =
        childIndex % 3 == 0 ? 0.225 : (childIndex % 2 == 0 ? 0.1125 : 0.0);
    final animation = _scope?.animation;
    if (animation == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          color: base,
        ),
      );
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final sweep = DesktopMotion.skeletonCurve.transform(
          (animation.value - phase + 1) % 1,
        );
        final dx = -1.6 + sweep * 3.2;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              // 105deg 微斜向扫光（与水平方向夹角 15°，tan 15° ≈ 0.268）。
              begin: Alignment(dx, -0.268),
              end: Alignment(dx + 1.0, 0.268),
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// 骨架 → 真实内容平滑切换器（对齐样例 `.sk-done` 350ms 淡入 + `skelSeen` 会话记忆）。
///
/// 当提供 [regionId] 时，首次加载完成即记入本次会话已见集合；切回该区域若已有
/// 缓存数据（[hasData] 为 true），不再重复闪出骨架屏。
class DesktopSkeletonSwitcher extends StatefulWidget {
  const DesktopSkeletonSwitcher({
    required this.loading,
    required this.skeleton,
    required this.child,
    this.regionId,
    this.hasData = false,
    super.key,
  });

  final bool loading;
  final Widget skeleton;
  final Widget child;
  final String? regionId;
  final bool hasData;

  static final Set<String> _seenRegions = <String>{};

  @visibleForTesting
  static void resetSeenRegions() => _seenRegions.clear();

  @override
  State<DesktopSkeletonSwitcher> createState() =>
      _DesktopSkeletonSwitcherState();
}

class _DesktopSkeletonSwitcherState extends State<DesktopSkeletonSwitcher> {
  void _markSeenIfReady() {
    final id = widget.regionId;
    if (!widget.loading && id != null && id.isNotEmpty) {
      DesktopSkeletonSwitcher._seenRegions.add(id);
    }
  }

  @override
  void initState() {
    super.initState();
    _markSeenIfReady();
  }

  @override
  void didUpdateWidget(covariant DesktopSkeletonSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    _markSeenIfReady();
  }

  @override
  Widget build(BuildContext context) {
    final seen =
        widget.regionId != null &&
        DesktopSkeletonSwitcher._seenRegions.contains(widget.regionId);
    final showSkeleton = widget.loading && !(seen && widget.hasData);
    return AnimatedSwitcher(
      duration: DesktopMotion.of(context, DesktopMotion.skeletonReveal),
      switchInCurve: DesktopMotion.ease,
      switchOutCurve: DesktopMotion.exitCurve,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topLeft,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child:
          showSkeleton
              ? KeyedSubtree(
                key: const ValueKey<String>('desktop-skeleton-loading'),
                child: widget.skeleton,
              )
              : KeyedSubtree(
                key: const ValueKey<String>('desktop-skeleton-content'),
                child: widget.child,
              ),
    );
  }
}

/// 等形卡片网格骨架：支持 `2/3` 海报与书封、`1/1` 专辑封面及双行圆头文本条。
class DesktopSkeletonCardGrid extends StatelessWidget {
  const DesktopSkeletonCardGrid({
    this.count = 8,
    this.aspectRatio = 2 / 3,
    this.minTileWidth = 172,
    this.spacing = 16,
    this.runSpacing = 22,
    this.radius = 12,
    this.showTextLines = true,
    super.key,
  });

  final int count;
  final double aspectRatio;
  final double minTileWidth;
  final double spacing;
  final double runSpacing;
  final double radius;
  final bool showTextLines;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 960.0;
        final columns = ((maxWidth + spacing) / (minTileWidth + spacing))
            .floor()
            .clamp(2, 8);
        final rows = (count / columns).ceil();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var row = 0; row < rows; row++) ...[
              if (row > 0) SizedBox(height: runSpacing),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var col = 0; col < columns; col++) ...[
                    if (col > 0) SizedBox(width: spacing),
                    Expanded(
                      child:
                          row * columns + col < count
                              ? _SkeletonCardTile(
                                index: row * columns + col,
                                aspectRatio: aspectRatio,
                                radius: radius,
                                showTextLines: showTextLines,
                              )
                              : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SkeletonCardTile extends StatelessWidget {
  const _SkeletonCardTile({
    required this.index,
    required this.aspectRatio,
    required this.radius,
    required this.showTextLines,
  });

  final int index;
  final double aspectRatio;
  final double radius;
  final bool showTextLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: aspectRatio,
          child: DesktopSkeletonBox(
            height: double.infinity,
            radius: radius,
            index: index * 3,
          ),
        ),
        if (showTextLines) ...[
          const SizedBox(height: 10),
          FractionallySizedBox(
            widthFactor: 0.66,
            child: DesktopSkeletonBox(
              height: 11,
              radius: 5.5,
              index: index * 3 + 1,
            ),
          ),
          const SizedBox(height: 6),
          FractionallySizedBox(
            widthFactor: 0.40,
            child: DesktopSkeletonBox(
              height: 9,
              radius: 4.5,
              index: index * 3 + 2,
            ),
          ),
        ],
      ],
    );
  }
}

/// 桌面细环加载指示器（对齐样例 `.spinner`，替代裸露的 Material 转圈）。
class DesktopSpinner extends StatefulWidget {
  const DesktopSpinner({
    this.size = 16,
    this.strokeWidth = 2,
    this.color,
    super.key,
  });

  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  State<DesktopSpinner> createState() => _DesktopSpinnerState();
}

class _DesktopSpinnerState extends State<DesktopSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionToken.spinner,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
      _controller.value = 0.25;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final arcColor = widget.color ?? skin.accent;
    final trackColor = skin.line2;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _DesktopSpinnerPainter(
              progress: _controller.value,
              color: arcColor,
              trackColor: trackColor,
              strokeWidth: widget.strokeWidth,
            ),
          );
        },
      ),
    );
  }
}

class _DesktopSpinnerPainter extends CustomPainter {
  const _DesktopSpinnerPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.max(0.0, (size.shortestSide - strokeWidth) / 2);
    final trackPaint =
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final arcPaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;
    final startAngle = progress * math.pi * 2 - math.pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      math.pi * 1.45,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_DesktopSpinnerPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      trackColor != oldDelegate.trackColor ||
      strokeWidth != oldDelegate.strokeWidth;
}

/// 磨砂遮罩全区加载器（对齐样例 `.overlay-load`）。
class DesktopOverlayLoader extends StatelessWidget {
  const DesktopOverlayLoader({this.label, this.blur = 10, super.key});

  final String? label;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: ColoredBox(
          color: skin.bg.withValues(alpha: 0.56),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DesktopSpinner(size: 28, strokeWidth: 2.5),
                if (label != null && label!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    label!,
                    style: TextStyle(
                      fontSize: _skeletonLabelSize,
                      color: skin.text2,
                      fontWeight: FontWeight.w500,
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

/// 照片网格骨架：日期分组头 + 2 组 4 行错落 Justified 行流 + 严格 6px 间距与 10px 圆角。
class DesktopSkeletonPhotoGrid extends StatelessWidget {
  const DesktopSkeletonPhotoGrid({
    this.targetHeight = 200,
    this.rows = 2,
    this.groups = 2,
    this.showGroupHeaders = true,
    super.key,
  });

  final double targetHeight;
  final int rows;
  final int groups;
  final bool showGroupHeaders;

  static const List<List<int>> _staggeredRowFlexes = <List<int>>[
    <int>[15, 10, 18, 12],
    <int>[11, 17, 13, 14],
    <int>[16, 12, 10, 17],
    <int>[13, 15, 18, 10],
  ];

  @override
  Widget build(BuildContext context) {
    final groupCount = math.max(1, groups);
    final rowsPerGroup = math.max(1, rows);
    var tileIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var group = 0; group < groupCount; group++) ...[
          if (group > 0) const SizedBox(height: 34),
          if (showGroupHeaders) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DesktopSkeletonBox(
                  width: group.isEven ? 156 : 132,
                  height: 18,
                  radius: 6,
                  index: tileIndex++,
                ),
                const SizedBox(width: 12),
                DesktopSkeletonBox(
                  width: 56,
                  height: 11,
                  radius: 5.5,
                  index: tileIndex++,
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          for (var row = 0; row < rowsPerGroup; row++) ...[
            if (row > 0) const SizedBox(height: 6),
            SizedBox(
              height: targetHeight,
              child: Row(
                children: [
                  for (
                    var col = 0;
                    col <
                        _staggeredRowFlexes[(group * rowsPerGroup + row) %
                                _staggeredRowFlexes.length]
                            .length;
                    col++
                  ) ...[
                    if (col > 0) const SizedBox(width: 6),
                    Expanded(
                      flex:
                          _staggeredRowFlexes[(group * rowsPerGroup + row) %
                              _staggeredRowFlexes.length][col],
                      child: DesktopSkeletonBox(
                        height: targetHeight,
                        radius: 10,
                        index: tileIndex++,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// 列表骨架：圆形/方形缩略 + 两条文本条，按行错峰。
class DesktopSkeletonRows extends StatelessWidget {
  const DesktopSkeletonRows({this.count = 6, this.avatar = true, super.key});

  final int count;
  final bool avatar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                DesktopSkeletonBox(
                  width: avatar ? 36 : 46,
                  height: avatar ? 36 : 32,
                  radius: avatar ? 18 : 9,
                  index: i * 4,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 样例 `polish.css:225-228`：文本条是 66% × 11 与
                      // 40% × 9 的圆头条，宽度按百分比而不是固定 px。
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 0.66,
                          child: DesktopSkeletonBox(
                            height: 11,
                            radius: 5.5,
                            index: i * 4 + 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 0.40,
                          child: DesktopSkeletonBox(
                            height: 9,
                            radius: 4.5,
                            index: i * 4 + 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                DesktopSkeletonBox(width: 64, height: 12, index: i * 4 + 3),
              ],
            ),
          ),
      ],
    );
  }
}
