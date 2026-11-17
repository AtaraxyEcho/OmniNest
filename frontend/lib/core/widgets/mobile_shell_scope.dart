import 'package:flutter/widgets.dart';

/// 标记当前页面由应用级移动端壳层承载。
///
/// Feature 页面通过该作用域隐藏自身重复的顶部栏和底部导航，作用域不包含
/// 任何业务状态，避免核心层反向依赖业务模块。
class MobileShellScope extends InheritedWidget {
  const MobileShellScope({
    required this.hosted,
    required super.child,
    super.key,
  });

  final bool hosted;

  /// 返回当前页面是否由应用级移动端壳层承载。
  static bool isHosted(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<MobileShellScope>()
            ?.hosted ??
        false;
  }

  @override
  bool updateShouldNotify(MobileShellScope oldWidget) {
    return hosted != oldWidget.hosted;
  }
}
