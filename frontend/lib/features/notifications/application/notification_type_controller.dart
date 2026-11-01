import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/features/notifications/domain/notification_type.dart';

final notificationTypesProvider = FutureProvider<List<NotificationTypeConfig>>((
  ref,
) async {
  final api = ref.watch(notificationTypeApiProvider);
  List<NotificationTypeConfig> types;
  try {
    types = await api.list();
  } on Exception {
    types = NotificationTypeConfig.fallbackTypes;
  }
  // 配置页与移动端资料页共用展示顺序；在状态派生层排一次，构建期不再重排。
  return [...types]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
});

/// 管理员视图：包含已禁用类型的完整列表。
final allNotificationTypesProvider =
    FutureProvider<List<NotificationTypeConfig>>((ref) async {
      final api = ref.watch(notificationTypeApiProvider);
      final types = await api.listAll();
      return [...types]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    });

/// 通知管理写操作：类型开关与 SMTP 测试邮件。
final notificationAdminActionsProvider = Provider<NotificationAdminActions>((
  ref,
) {
  return NotificationAdminActions(ref);
});

class NotificationAdminActions {
  NotificationAdminActions(this.ref);

  final Ref ref;

  Future<void> setTypeEnabled(String id, {required bool enabled}) async {
    await ref
        .read(notificationTypeApiProvider)
        .updateType(id, enabled: enabled);
    ref.invalidate(allNotificationTypesProvider);
    ref.invalidate(notificationTypesProvider);
  }

  Future<void> sendTestEmail({String? to}) {
    return ref.read(notificationEmailAdminApiProvider).sendTest(to: to);
  }
}
