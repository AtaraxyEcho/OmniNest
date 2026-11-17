import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/realtime/realtime_scope_handler.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';

/// 通知作用域实时失效刷新处理器。
class NotificationSyncHandler implements RealtimeScopeHandler {
  NotificationSyncHandler(this.ref);

  final Ref ref;
  final RealtimeRevisionTracker _countRevisions = RealtimeRevisionTracker();

  @override
  RealtimeScope get scope => RealtimeScope.notifications;

  @override
  bool appliesTo(RealtimeInvalidation invalidation) => true;

  @override
  Future<bool> refresh(List<RealtimeInvalidation> invalidations) async {
    final countPending = _countRevisions.pending(invalidations);
    if (countPending.isNotEmpty && ref.exists(unreadCountProvider)) {
      await ref.read(unreadCountProvider.notifier).refresh();
    }
    _countRevisions.markCompleted(countPending);
    // 通知模块未激活时直接消费失效记录，首次打开自取最新。
    if (!ref.exists(notificationControllerProvider)) return true;
    await ref
        .read(notificationControllerProvider.notifier)
        .refreshForRealtime();
    _countRevisions.clear(invalidations);
    return true;
  }
}
