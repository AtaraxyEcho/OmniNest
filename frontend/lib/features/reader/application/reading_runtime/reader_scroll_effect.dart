import 'package:flutter/animation.dart' show Curve;

/// 滚动效果执行器（新方案 §25/§43/§62）：Runtime 的唯一物理滚动出口。
/// 页面作为物理适配器实现本接口并注入；Runtime 不持有 Widget/Controller。
abstract interface class ReaderScrollEffect {
  bool get hasClients;

  double get offset;

  double get maxScrollExtent;

  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  });

  void jumpTo(double offset);
}
