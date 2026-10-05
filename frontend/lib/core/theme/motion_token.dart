import 'package:flutter/material.dart';

/// 全局动画时长与曲线常量，所有动画引用此文件，不硬编码。
/// 参考标准：Material Design 3、Apple HIG、Linear/Stripe/Vercel。
class MotionToken {
  const MotionToken._();

  // ── 时长 ─────────────────────────────────────────────────────────

  /// hover、toggle、颜色切换
  static const fast = Duration(milliseconds: 150);

  /// 页面切换、面板展开
  static const normal = Duration(milliseconds: 300);

  /// 阅读器和工作台页面切换
  static const pageSwitch = Duration(milliseconds: 220);

  /// 单元素入场
  static const slow = Duration(milliseconds: 400);

  /// stagger 总时长
  static const stagger = Duration(milliseconds: 900);

  /// 图表数据动画
  static const chart = Duration(milliseconds: 800);

  /// 根据当前无障碍设置解析动画时长。
  static Duration resolve(BuildContext context, Duration duration) {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false
        ? Duration.zero
        : duration;
  }

  /// 在尚未建立组件上下文时根据平台无障碍设置解析动画时长。
  static Duration resolveForPlatform(Duration duration) {
    return WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations
        ? Duration.zero
        : duration;
  }

  /// 统一的减弱动效判定：当前上下文是否要求关闭动画。
  ///
  /// 壳层与状态族的动画必须经此判定决定时长与过渡，调用点不得再散落
  /// 各自的 Duration.zero 分支。
  static bool prefersReduced(BuildContext context) {
    return MediaQuery.disableAnimationsOf(context);
  }

  /// 减弱动效下的时长出口：要求关闭动画时返回零时长，否则返回标准时长。
  ///
  /// 零时长只取消过渡过程，不改变动画结束后的最终视觉状态。
  static Duration reduced(BuildContext context, Duration duration) {
    return prefersReduced(context) ? Duration.zero : duration;
  }

  // ── 曲线 ─────────────────────────────────────────────────────────

  /// 主曲线 — 出场/入场通用（Material 3 standard easing）
  static const curve = Curves.easeOutCubic;

  /// 阅读器页面切换曲线，较短位移下保持干净收束
  static const pageCurve = Curves.easeOutQuart;

  /// 页面切换出场曲线（稍快）
  static const curveIn = Curves.easeInCubic;

  // ── 位移 ─────────────────────────────────────────────────────────

  /// 桌面端页面切换上滑距离
  static const slideDesktop = Offset(0, 0.03);

  /// 移动端页面切换上滑距离
  static const slideMobile = Offset(0, 0.05);

  /// 内容入场上滑距离
  static const slideContent = Offset(0, 0.08);

  // ── Stagger 参数 ─────────────────────────────────────────────────

  /// 每个元素的动画时长占比（占 controller 时长）
  static const double elementExtent = 0.35;

  /// 元素间的交错延迟占比
  static const double elementStagger = 0.08;

  /// 计算第 [index] 个元素的 stagger 延迟。
  static Duration staggerDelay(int index, {required int total}) {
    return Duration(milliseconds: (stagger.inMilliseconds * index) ~/ total);
  }
}
