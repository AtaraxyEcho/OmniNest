import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/notifications/domain/notification_preferences.dart';

const notificationPreferenceScope = 'notification';

final notificationPreferencesProvider = AsyncNotifierProvider<
  NotificationPreferencesController,
  NotificationPreferences
>(NotificationPreferencesController.new);

class NotificationPreferencesController
    extends AsyncNotifier<NotificationPreferences> {
  String? _userId;

  @override
  Future<NotificationPreferences> build() async {
    final session = await ref.watch(authSessionProvider.future);
    _userId = session.user?.id;
    final userId = _userId;
    if (userId == null) {
      return const NotificationPreferences();
    }
    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .load(userId: userId, scope: notificationPreferenceScope);
    return snapshot.preferences.isEmpty
        ? const NotificationPreferences()
        : NotificationPreferences.fromJson(snapshot.preferences);
  }

  Future<void> save(NotificationPreferences preferences) async {
    final previous = state;
    state = AsyncData(preferences);
    final userId = _userId;
    if (userId == null) {
      return;
    }
    try {
      final snapshot = await ref
          .read(preferenceSyncServiceProvider)
          .patch(
            userId: userId,
            scope: notificationPreferenceScope,
            changes: preferences.toJson(),
          );
      state = AsyncData(NotificationPreferences.fromJson(snapshot.preferences));
    } catch (error, stackTrace) {
      state = previous;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// 从远端重新同步通知偏好，并保留本地待提交变更。
  Future<void> refreshFromRemote() async {
    final userId = _userId;
    if (userId == null) return;
    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .synchronize(userId: userId, scope: notificationPreferenceScope);
    if (_userId != userId) return;
    state = AsyncData(
      snapshot.preferences.isEmpty
          ? const NotificationPreferences()
          : NotificationPreferences.fromJson(snapshot.preferences),
    );
  }
}
