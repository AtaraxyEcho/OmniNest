import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

/// 当前设备是否为手机形态（移动平台且最短边低于平板阈值）。
///
/// 判定取 `shortestSide`：旋转不变，横屏手机仍是手机形态，竖屏平板仍是
/// 平板形态。Web 与桌面恒为 false（Web 端管理台不做设备限制；桌面最小
/// 窗口宽度已高于阈值）。消费方为管理台入口可见性与路由守卫的统一
/// 收敛（docs/2026-09-23/002 决策 D2）。
final phoneFormFactorProvider = NotifierProvider<PhoneFormFactorNotifier, bool>(
  PhoneFormFactorNotifier.new,
);

/// [phoneFormFactorProvider] 的纯函数形态，便于按宿主场景测试。
@visibleForTesting
bool resolvePhoneFormFactor({
  required bool mobilePlatform,
  required double shortestSide,
}) {
  return mobilePlatform && shortestSide < ResponsiveBreakpoints.mobile;
}

/// 手机形态判定状态。
///
/// 初始值从 dispatcher 视口推得；根节点 [DeviceFormFactorListener] 在挂载
/// 与 metrics 变化（旋转不触发、分屏与折叠屏开合会触发）时刷新。
class PhoneFormFactorNotifier extends Notifier<bool> {
  @override
  bool build() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      return false;
    }
    final view = views.first;
    return resolvePhoneFormFactor(
      mobilePlatform: isMobilePlatform,
      shortestSide: view.physicalSize.shortestSide / view.devicePixelRatio,
    );
  }

  /// 按最新视口最短边刷新判定；结论不变时不重复写状态。
  void updateShortestSide(double shortestSide) {
    final next = resolvePhoneFormFactor(
      mobilePlatform: isMobilePlatform,
      shortestSide: shortestSide,
    );
    if (next != state) {
      state = next;
    }
  }
}

/// 把系统 metrics 变化发布到 [phoneFormFactorProvider] 的根监听。
///
/// 挂载于 App 根部，自身不渲染内容。
class DeviceFormFactorListener extends ConsumerStatefulWidget {
  const DeviceFormFactorListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DeviceFormFactorListener> createState() =>
      _DeviceFormFactorListenerState();
}

class _DeviceFormFactorListenerState
    extends ConsumerState<DeviceFormFactorListener>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _publish();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _publish();
  }

  void _publish() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      return;
    }
    final view = views.first;
    ref
        .read(phoneFormFactorProvider.notifier)
        .updateShortestSide(
          view.physicalSize.shortestSide / view.devicePixelRatio,
        );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
