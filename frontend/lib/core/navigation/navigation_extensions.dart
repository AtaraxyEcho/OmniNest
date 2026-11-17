import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 页面级导航辅助方法。
extension SafeNavigationContext on BuildContext {
  /// 优先返回上一页；当前为路由栈根节点时进入指定兜底页面。
  void popOrGo(String fallbackLocation) {
    if (canPop()) {
      pop();
      return;
    }
    go(fallbackLocation);
  }
}
