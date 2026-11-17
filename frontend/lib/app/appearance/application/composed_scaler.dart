import 'package:flutter/painting.dart';

/// 组合系统无障碍缩放与应用字体档位的 TextScaler，并按 [maxScale] 封顶。
///
/// 相等性按 [systemScaler] 与 [appScale] 判定：Flutter 框架依赖 TextScaler
/// 相等性决定文本是否重建，MediaQueryData 之间的相等性比较则依赖
/// [textScaleFactor] 的稳定取值，二者缺一不可。
final class ComposedScaler extends TextScaler {
  const ComposedScaler(this.systemScaler, this.appScale);

  /// 组合缩放上限。卡片定高、网格行高与阅读列宽均按该值推算，超过后
  /// 不再放大，避免系统无障碍档位与字体档位叠出不可控字号。
  static const double maxScale = 1.6;

  /// 进入根部覆盖前捕获的原始系统 TextScaler，保留平台非线性缩放策略。
  final TextScaler systemScaler;

  /// 应用字体档位倍率；1.0 时行为与系统缩放一致（仍受 [maxScale] 封顶）。
  final double appScale;

  @override
  double scale(double fontSize) {
    final scaled = systemScaler.scale(fontSize * appScale);
    final maxScaled = fontSize * maxScale;
    return scaled > maxScaled ? maxScaled : scaled;
  }

  @override
  // textScaleFactor 为 TextScaler 抽象成员（已废弃但仍须实现），
  // MediaQueryData 的相等性比较依赖该值，无法规避调用。
  double get textScaleFactor {
    // ignore: deprecated_member_use
    final factor = systemScaler.textScaleFactor * appScale;
    return factor > maxScale ? maxScale : factor;
  }

  @override
  bool operator ==(Object other) {
    return other is ComposedScaler &&
        other.systemScaler == systemScaler &&
        other.appScale == appScale;
  }

  @override
  int get hashCode => Object.hash(systemScaler, appScale);
}
