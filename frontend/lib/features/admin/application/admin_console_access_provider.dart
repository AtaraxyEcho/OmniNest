import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/phone_form_factor.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/admin/domain/admin_console_access.dart';

/// 当前会话在当前设备上是否可进入系统管理台。
///
/// domain 层仅保留纯权限判定；Riverpod 绑定放在 application，避免 domain 依赖 Flutter。
/// 手机形态按决策 D2 不暴露管理台（平板、桌面与 Web 端不受影响）；入口可见性
/// 与路由守卫统一消费本 provider，摘要请求经 [adminConsoleSummaryProvider]
/// 的短路保证手机形态不产生管理端请求。
final canAccessAdminConsoleProvider = Provider<bool>((ref) {
  final session = ref.watch(authSessionProvider).asData?.value;
  return canAccessAdminConsoleUser(session?.user) &&
      !ref.watch(phoneFormFactorProvider);
});
