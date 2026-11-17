import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/router.dart';
import 'package:omninest/core/notifications/system_notifier.dart';

/// 系统通知点击落位绑定：把通知 tap 转成对通知中心的压栈跳转。
///
/// 在应用根 watch 一次即可持续生效；用 push 而非 go，保留用户当前页面，
/// 返回即可回到原处。未登录时由路由器认证守卫自行重定向。
final systemNotificationTapBindingProvider = Provider<void>((ref) {
  notificationTapRouteHandler = (route) {
    ref.read(appRouterProvider).push(route);
  };
  ref.onDispose(() {
    notificationTapRouteHandler = null;
  });
});
