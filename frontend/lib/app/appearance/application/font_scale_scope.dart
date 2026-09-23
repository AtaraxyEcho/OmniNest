import 'package:flutter/material.dart';

/// 向子树暴露剔除应用字体档位后的系统 TextScaler（已按
/// ComposedScaler.maxScale 封顶）。
///
/// 根部注入组合缩放后环境值为"系统 × 应用档位"，Reader 正文等自绘排版
/// 区域需要剔除应用档位、仅保留系统无障碍缩放，由此取值。
class FontScaleScope extends InheritedWidget {
  const FontScaleScope({
    required this.systemScaler,
    required super.child,
    super.key,
  });

  final TextScaler systemScaler;

  /// 读取仅含系统缩放的 TextScaler；缺失时回退当前环境值，保证
  /// 未接入根部注入的场景（如局部 Widget 测试）行为不变。
  static TextScaler systemScalerOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FontScaleScope>();
    return scope?.systemScaler ?? MediaQuery.textScalerOf(context);
  }

  /// 用仅含系统缩放的 scaler 覆盖子树，剔除应用字体档位。
  static Widget withSystemScaleOnly({
    required BuildContext context,
    required Widget child,
  }) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: systemScalerOf(context)),
      child: child,
    );
  }

  @override
  bool updateShouldNotify(FontScaleScope oldWidget) {
    return oldWidget.systemScaler != systemScaler;
  }
}
