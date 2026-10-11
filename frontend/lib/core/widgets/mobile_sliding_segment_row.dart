import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 滑块层的可寻址键：用例与像素测量都靠它定位，不参与视觉表现。
const Key segmentPillKey = ValueKey<String>('omninest.mobile.segment-pill');

/// 分段导航的滑动胶囊行：单层胶囊在段间滑过，位置与宽度同时插值。
///
/// 段宽由标签内容自定（样例 `.segmented` 是 width:max-content），滑块因此必须
/// 先拿到各段真实宽度才能插值，按等分推算会在长标签上错位。宽度按**粗体**标签
/// 度量：段内文字选中时加粗，若按当前字重度量，切换瞬间段宽会跳、滑块跟着抖。
///
/// [page] 是连续档：页签与原生 PageView 同轴时传入页码，滑块跟手移动并在松手后
/// 吸附；为 null 时用隐式动画在段间补间。减弱动效下两者都直接落终态。
///
/// 本行只画"选中滑块 + 段本体"，容器底色与描边由调用点包在外面，这样限宽、
/// 吸顶与横向滚动的取舍仍归各模块页自己管。
class MobileSlidingSegmentRow extends StatelessWidget {
  const MobileSlidingSegmentRow({
    required this.labels,
    required this.selectedIndex,
    required this.onTap,
    required this.pill,
    required this.activeInk,
    required this.idleInk,
    this.page,
    this.gap = 4,
    this.containerPadding = 4,
    this.segmentHeight = 40,
    this.minimumSegmentWidth = 66,
    this.labelPadding = 14,
    this.labelSize = 12,
    this.cornerRadius = 12,
    super.key,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  /// 滑块画法：底色、圆角、投影由调用点给（模块分段与媒体库分段的配方不同）。
  final BoxDecoration pill;
  final Color activeInk;
  final Color idleInk;

  /// 连续档的页码（可含小数），如 PageView 的当前偏移。
  final double? page;

  /// 段间隙：样例 `.segmented` 为 4。
  final double gap;

  /// 容器内衬：样例 `.segmented` 为 4。
  final double containerPadding;

  /// 段高：样例 `.segmented button` 为 40，媒体库分段按触控裁决取 48。
  final double segmentHeight;

  /// 段最小宽度：样例 `.segmented button` 为 66；媒体库分段按标签自定。
  final double minimumSegmentWidth;

  /// 标签左右内衬：样例 14，媒体库分段 16。
  final double labelPadding;
  final double labelSize;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final widths = <double>[
      for (final label in labels)
        math.max(
          minimumSegmentWidth,
          _labelExtent(context, label, textScaler).ceilToDouble() +
              labelPadding * 2,
        ),
    ];

    final lefts = <double>[];
    var cursor = containerPadding;
    for (final width in widths) {
      lefts.add(cursor);
      cursor += width + gap;
    }

    final last = labels.length - 1;
    final target = selectedIndex.clamp(0, last);
    final Rect pillRect;
    final continuous = page;
    if (continuous != null) {
      final offset = continuous.clamp(0.0, last.toDouble()).toDouble();
      final from = offset.floor().clamp(0, last);
      final to = math.min(from + 1, last);
      pillRect =
          Rect.lerp(
            _segmentRect(from, lefts, widths),
            _segmentRect(to, lefts, widths),
            offset - from,
          ) ??
          _segmentRect(target, lefts, widths);
    } else {
      pillRect = _segmentRect(target, lefts, widths);
    }

    return Stack(
      children: [
        // 滑块在段之下：横向位置由页码或选中段决定，竖向固定在段带上。
        if (continuous != null)
          Positioned(
            key: segmentPillKey,
            left: pillRect.left,
            top: pillRect.top,
            width: pillRect.width,
            height: pillRect.height,
            child: _buildPill(),
          )
        else
          AnimatedPositioned(
            key: segmentPillKey,
            duration: MotionToken.reduced(
              context,
              MobileLayoutTokens.stateDuration,
            ),
            curve: MobileLayoutTokens.motionCurve,
            left: pillRect.left,
            top: pillRect.top,
            width: pillRect.width,
            height: pillRect.height,
            child: _buildPill(),
          ),
        // 段本体决定整行尺寸：父级可能是纵向列表（无界高度），因此不使用
        // stretch 交叉对齐，也不把行钉死在 Positioned.fill 上。
        Padding(
          padding: EdgeInsets.all(containerPadding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < labels.length; index++) ...[
                _MobileSegment(
                  label: labels[index],
                  width: widths[index],
                  height: segmentHeight,
                  selected: index == target,
                  activeInk: activeInk,
                  idleInk: idleInk,
                  labelSize: labelSize,
                  cornerRadius: cornerRadius,
                  onTap: () => onTap(index),
                ),
                if (index != last) SizedBox(width: gap),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Rect _segmentRect(int index, List<double> lefts, List<double> widths) {
    return Rect.fromLTWH(
      lefts[index],
      containerPadding,
      widths[index],
      segmentHeight,
    );
  }

  Widget _buildPill() {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: DecoratedBox(decoration: pill, child: const SizedBox.shrink()),
      ),
    );
  }

  /// 用 TextPainter 量标签占位，与段内 Text 用同一套字号与字重（粗体），
  /// 量出来的宽度即段宽，滑块边界因此与真实排布一致。
  double _labelExtent(
    BuildContext context,
    String label,
    TextScaler textScaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(fontSize: labelSize, fontWeight: FontWeight.w700),
      ),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final extent = painter.width;
    painter.dispose();
    return extent;
  }
}

/// 分段本体：只保留命中区与文字配色，选中底色归滑块层。
///
/// 否则滑块滑过来时会出现两层胶囊叠加，边界处露出一圈深色边。
class _MobileSegment extends StatelessWidget {
  const _MobileSegment({
    required this.label,
    required this.width,
    required this.height,
    required this.selected,
    required this.activeInk,
    required this.idleInk,
    required this.labelSize,
    required this.cornerRadius,
    required this.onTap,
  });

  final String label;
  final double width;
  final double height;
  final bool selected;
  final Color activeInk;
  final Color idleInk;
  final double labelSize;
  final double cornerRadius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // 样例 `.segmented` 是 role="tablist"，选中态用 aria-selected 而非 aria-checked。
      selected: selected,
      // 不另写 label：子级 Text 已提供名称，重复写会让合并节点的 label 变成 "y\ny"，
      // 读屏把段名播两遍。
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(cornerRadius),
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? activeInk : idleInk,
                  fontSize: labelSize,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
