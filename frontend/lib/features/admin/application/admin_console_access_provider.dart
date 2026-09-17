import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/admin/domain/admin_console_access.dart';

/// 当前会话是否可进入系统管理台。
///
/// domain 层仅保留纯权限判定；Riverpod 绑定放在 application，避免 domain 依赖 Flutter。
final canAccessAdminConsoleProvider = Provider<bool>((ref) {
  final session = ref.watch(authSessionProvider).asData?.value;
  return canAccessAdminConsoleUser(session?.user);
});
