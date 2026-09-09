import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/realtime/realtime_scope_handler.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';

/// 阅读作用域实时失效刷新处理器。
class ReaderSyncHandler implements RealtimeScopeHandler {
  ReaderSyncHandler(this.ref);

  final Ref ref;
  final RealtimeRevisionTracker _auxiliaryRevisions = RealtimeRevisionTracker();

  @override
  RealtimeScope get scope => RealtimeScope.reader;

  @override
  bool appliesTo(RealtimeInvalidation invalidation) => true;

  @override
  Future<bool> refresh(List<RealtimeInvalidation> invalidations) async {
    final auxiliary = _auxiliaryRevisions.pending(invalidations);
    final refreshes = <Future<Object?>>[];
    if (auxiliary.isNotEmpty && ref.exists(readerDashboardProvider)) {
      refreshes.add(ref.refresh(readerDashboardProvider.future));
    }
    if (auxiliary.isNotEmpty && ref.exists(readerStatsProvider)) {
      refreshes.add(ref.refresh(readerStatsProvider.future));
    }
    for (final invalidation in auxiliary) {
      final resourceId = invalidation.resourceId;
      if (resourceId == null) continue;
      final detail = readerItemDetailProvider(resourceId);
      if (ref.exists(detail)) {
        refreshes.add(ref.refresh(detail.future));
      }
      final annotations = readerItemAnnotationsProvider(resourceId);
      if (ref.exists(annotations)) {
        refreshes.add(ref.refresh(annotations.future));
      }
      final bookmarks = readerItemBookmarksProvider(resourceId);
      if (ref.exists(bookmarks)) {
        refreshes.add(ref.refresh(bookmarks.future));
      }
    }
    await Future.wait(refreshes);
    _auxiliaryRevisions.markCompleted(auxiliary);
    if (!ref.exists(readerCenterControllerProvider)) return false;
    await ref.read(readerCenterControllerProvider.future);
    await ref
        .read(readerCenterControllerProvider.notifier)
        .refreshForRealtime();
    _auxiliaryRevisions.clear(invalidations);
    return true;
  }
}
