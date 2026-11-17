import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/realtime_providers.dart';
import 'package:omninest/app/sync/preference_sync_handler.dart';
import 'package:omninest/core/realtime/realtime_invalidation_dispatcher.dart';
import 'package:omninest/features/admin/application/admin_sync_handler.dart';
import 'package:omninest/features/files/application/file_sync_handler.dart';
import 'package:omninest/features/music/application/music_sync_handler.dart';
import 'package:omninest/features/notifications/application/notification_sync_handler.dart';
import 'package:omninest/features/photos/application/photo_sync_handler.dart';
import 'package:omninest/features/reader/application/reader_sync_handler.dart';
import 'package:omninest/features/tasks/application/task_sync_handler.dart';
import 'package:omninest/features/video/application/video_sync_handler.dart';

/// 组合当前用户实时协调器和各业务作用域刷新处理器。
final appSyncCoordinatorProvider = Provider<RealtimeInvalidationDispatcher?>((
  ref,
) {
  final coordinator = ref.watch(realtimeCoordinatorProvider);
  if (coordinator == null) return null;
  final dispatcher = RealtimeInvalidationDispatcher(
    dirtyScopes: coordinator.dirtyScopes,
    pendingInvalidations: coordinator.pendingInvalidations,
    acknowledge: coordinator.acknowledge,
    handlers: [
      TaskSyncHandler(ref),
      FileTaskSyncHandler(ref),
      VideoTaskSyncHandler(ref),
      FileSyncHandler(ref),
      PhotoSyncHandler(ref),
      VideoSyncHandler(ref),
      MusicSyncHandler(ref),
      ReaderSyncHandler(ref),
      PreferenceSyncHandler(ref),
      NotificationSyncHandler(ref),
      AdminSyncHandler(ref),
    ],
  );
  unawaited(dispatcher.start());
  ref.onDispose(() => unawaited(dispatcher.dispose()));
  return dispatcher;
});
