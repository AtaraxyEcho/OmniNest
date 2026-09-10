import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 页内搜索条宿主模块的稳定标识。
///
/// 由核心层持有，壳层与业务模块共用，避免 feature 反向依赖 app 层。
abstract final class MobileModuleSearchHosts {
  static const files = 'files';
  static const photos = 'photos';
}

/// 托管模块页内搜索条的展开状态（按宿主模块隔离）。
///
/// 壳层顶栏搜索钮在 Files/Photos 分支切换对应宿主的状态，由模块页监听并
/// 渲染页内搜索条（保留模块内上下文定位），关闭时模块负责清理查询。
/// family 化后各模块状态天然隔离，壳层无需在分支切换时复位。
final mobileModuleSearchActiveProvider =
    NotifierProvider.family<MobileModuleSearchActive, bool, String>(
      MobileModuleSearchActive.new,
    );

/// 页内搜索条展开状态；宿主标识由 family 构造注入，仅用于区分实例。
class MobileModuleSearchActive extends Notifier<bool> {
  MobileModuleSearchActive(this.host);

  final String host;

  @override
  bool build() => false;

  void set(bool value) => state = value;

  void toggle() => state = !state;
}

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
