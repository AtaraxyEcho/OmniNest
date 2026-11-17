import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 把 GoRouter 实例透给壳层 chrome。
///
/// 统一壳挂在 `MaterialApp.builder` 里，也就是 **Router 之上**：标题栏、
/// 侧栏、详情坞、播放条与命令面板都取不到 `GoRouter.of(context)`。
/// 路由内容页在 Router 之内，两种 context 并存，因此壳层一律经本作用域
/// 拿 router，而不是按调用点猜自己在哪一层。
class DesktopRouterScope extends InheritedWidget {
  const DesktopRouterScope({
    required this.router,
    required super.child,
    super.key,
  });

  final GoRouter router;

  static GoRouter of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<DesktopRouterScope>();
    assert(scope != null, '桌面壳层导航必须在 DesktopRouterScope 之内');
    return scope!.router;
  }

  @override
  bool updateShouldNotify(DesktopRouterScope oldWidget) =>
      oldWidget.router != router;
}

/// 同级空间切换：换掉整条栈。
void desktopGo(BuildContext context, String location) =>
    DesktopRouterScope.of(context).go(location);

/// 进内容详情：保留来路。
void desktopPush(BuildContext context, String location) =>
    DesktopRouterScope.of(context).push<void>(location);
