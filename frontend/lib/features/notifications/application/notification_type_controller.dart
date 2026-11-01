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
