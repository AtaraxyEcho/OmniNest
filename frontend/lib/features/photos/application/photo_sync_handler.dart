import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/realtime/realtime_scope_handler.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';

/// 照片作用域实时失效刷新处理器。
class PhotoSyncHandler implements RealtimeScopeHandler {
  PhotoSyncHandler(this.ref);

  final Ref ref;
  final RealtimeRevisionTracker _auxiliaryRevisions = RealtimeRevisionTracker();
  Future<bool>? _inFlight;

  @override
  RealtimeScope get scope => RealtimeScope.photos;

  @override
  bool appliesTo(RealtimeInvalidation invalidation) => true;

  @override
  Future<bool> refresh(List<RealtimeInvalidation> invalidations) {
    if (!ref.mounted) {
      return Future<bool>.value(false);
    }
    final active = _inFlight;
    if (active != null) return active;
    late final Future<bool> future;
    future = _refreshInternal(invalidations);
    _inFlight = future;
    unawaited(
      future.then(
        (_) {
          if (identical(_inFlight, future)) _inFlight = null;
        },
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_inFlight, future)) _inFlight = null;
        },
      ),
    );
    return future;
  }

  Future<bool> _refreshInternal(
    List<RealtimeInvalidation> invalidations,
  ) async {
    if (!ref.mounted) {
      return false;
    }
    final auxiliary = _auxiliaryRevisions.pending(invalidations);
    final refreshes = <Future<Object?>>[];
    if (auxiliary.isNotEmpty && ref.exists(photoDashboardProvider)) {
      refreshes.add(ref.read(photoDashboardProvider.notifier).reload());
    }
    if (auxiliary.isNotEmpty && ref.exists(photoListProvider)) {
      refreshes.add(ref.refresh(photoListProvider.future));
    }
    if (auxiliary.isNotEmpty && ref.exists(photoFavoritesProvider)) {
      refreshes.add(ref.refresh(photoFavoritesProvider.future));
    }
    if (auxiliary.isNotEmpty && ref.exists(photoAlbumsProvider)) {
      refreshes.add(ref.refresh(photoAlbumsProvider.future));
    }
    if (auxiliary.isNotEmpty && ref.exists(photoTagsProvider)) {
      refreshes.add(ref.refresh(photoTagsProvider.future));
    }
    for (final invalidation in auxiliary) {
      final resourceId = invalidation.resourceId;
      if (resourceId == null) continue;
      final detail = photoDetailProvider(resourceId);
      if (ref.exists(detail)) {
        refreshes.add(ref.refresh(detail.future));
      }
      final album = photoAlbumDetailProvider(resourceId);
      if (ref.exists(album)) {
        refreshes.add(ref.refresh(album.future));
      }
    }
    await Future.wait(refreshes);
    if (!ref.mounted) {
      return false;
    }
    if (!ref.exists(photoCenterControllerProvider)) {
      return false;
    }
    _auxiliaryRevisions.markCompleted(auxiliary);
    await ref.read(photoCenterControllerProvider.future);
    if (!ref.mounted || !ref.exists(photoCenterControllerProvider)) {
      return false;
    }
    await ref.read(photoCenterControllerProvider.notifier).refreshForRealtime();
    if (!ref.mounted) {
      return false;
    }
    _auxiliaryRevisions.clear(invalidations);
    return true;
  }
}
