import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 顶栏搜索框的 Ctrl/Cmd+F 聚焦注册表。
///
/// 全局按键入口（app.dart 硬件层）在 Ctrl/Cmd+F 上调用 [focusActiveTarget]：
/// 命中且条目自检通过则聚焦对应搜索框并消费按键（web 端随 handled 标记
/// 阻断浏览器原生查找）；未命中时返回 false 放行到焦点树，保留 Reader
/// 书内查找等焦树级绑定与浏览器默认查找兜底。与 Ctrl+K 构成互补语义：
/// Ctrl+K 跨模块全局检索，Ctrl+F 聚焦当前页内的顶栏过滤框。
class TopBarSearchFocusRegistry {
  TopBarSearchFocusRegistry._();

  static final TopBarSearchFocusRegistry instance =
      TopBarSearchFocusRegistry._();

  final List<TopBarSearchFocusEntry> _entries = <TopBarSearchFocusEntry>[];

  /// 注册一个可被 Ctrl/Cmd+F 聚焦的搜索框。
  ///
  /// 返回的句柄必须由持有者在 dispose 时释放；条目后注册者优先，
  /// 对话框/展开态搜索条因此天然覆盖顶栏常驻槽。
  TopBarSearchFocusHandle register(TopBarSearchFocusEntry entry) {
    _entries.add(entry);
    return TopBarSearchFocusHandle._(this, entry);
  }

  void _unregister(TopBarSearchFocusEntry entry) {
    _entries.remove(entry);
  }

  /// 聚焦当前活跃的搜索框；没有任何条目自检通过时返回 false。
  bool focusActiveTarget() {
    for (final entry in _entries.reversed) {
      if (entry.isActive()) {
        entry.focus();
        return true;
      }
    }
    return false;
  }
}

/// 单个可聚焦目标。
///
/// [isActive] 自检必须覆盖两个维度：自身当前可见可用（如所在分区支持
/// 搜索、移动端搜索条处于展开态），以及栈顶约束（见 [RouteTopAware]）；
/// 只靠注册顺序无法表达路由压栈期间的下层页面。
class TopBarSearchFocusEntry {
  const TopBarSearchFocusEntry({required this.focus, required this.isActive});

  final VoidCallback focus;
  final bool Function() isActive;
}

/// [TopBarSearchFocusRegistry.register] 返回的注销句柄。
class TopBarSearchFocusHandle {
  TopBarSearchFocusHandle._(this._registry, this._entry);

  final TopBarSearchFocusRegistry _registry;
  final TopBarSearchFocusEntry _entry;
  bool _released = false;

  /// 幂等注销；重复调用与测试清理路径下均安全。
  void dispose() {
    if (_released) {
      return;
    }
    _released = true;
    _registry._unregister(_entry);
  }
}

/// 顶栏搜索快捷键的键帽文案：Apple 平台 ⌘F，其余 Ctrl+F。
String get topBarSearchKeycapLabel => switch (defaultTargetPlatform) {
  TargetPlatform.macOS || TargetPlatform.iOS => '⌘F',
  _ => 'Ctrl+F',
};

/// 为注册条目提供栈顶自检的 State mixin。
///
/// 在 [State.didChangeDependencies] 缓存所在 [ModalRoute]（路由进出栈时
/// 依赖会重新回调，缓存随之刷新），自检只读缓存路由的 isCurrent。
/// 不得在按键回调期现场 `ModalRoute.of(context)`：Element 处于
/// deactivate 到 dispose 的帧内窗口时该查找会命中
/// inactive ancestor 断言。
mixin RouteTopAware<T extends StatefulWidget> on State<T> {
  ModalRoute<Object?>? _routeTopAwareRoute;

  /// 所在路由是否位于栈顶；不在任何路由上下文内时视为栈顶。
  bool get isRouteTop => _routeTopAwareRoute?.isCurrent ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeTopAwareRoute = ModalRoute.of(context);
  }
}
