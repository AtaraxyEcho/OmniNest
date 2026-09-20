import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/connectivity_listener.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/preferences/user_preferences_api.dart';
import 'package:omninest/core/preferences/preference_sync_service.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/core/storage/local_database_provider.dart';
import 'package:omninest/features/tasks/data/task_api.dart';
import 'package:omninest/core/storage/sync_queue.dart';
import 'package:omninest/features/files/application/media_import_service.dart';
import 'package:omninest/features/files/data/file_providers.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_progress_repository.dart';
import 'package:omninest/features/notifications/data/notification_type_api.dart';
import 'package:omninest/features/profile/data/me_api.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/data/reader_image_cache.dart';
import 'package:omninest/features/reader/data/reader_image_repository.dart';
import 'package:omninest/features/reader/data/reader_image_repository_base.dart';
import 'package:omninest/features/reader/data/reader_local_progress.dart';
import 'package:omninest/features/reader/data/reader_local_storage.dart';
import 'package:omninest/core/log/dev_log.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  if (environment == null) {
    throw StateError('服务器地址未配置');
  }
  final sessionStore = ref.watch(authSessionStoreProvider);
  return ApiClient(
    environment,
    sessionStore: sessionStore,
    refreshSession:
        () => ref.read(authSessionProvider.notifier).refreshSession(),
    clearSession: () => ref.read(authSessionProvider.notifier).clearSession(),
  );
});

final userPreferencesApiProvider = Provider<UserPreferencesApi>((ref) {
  return UserPreferencesApi(ref.watch(apiClientProvider));
});

final preferenceSyncServiceProvider = Provider<PreferenceSyncService>((ref) {
  return PreferenceSyncService(api: ref.watch(userPreferencesApiProvider));
});

final notificationTypeApiProvider = Provider<NotificationTypeApi>((ref) {
  return NotificationTypeApi(ref.watch(apiClientProvider));
});

final meApiProvider = Provider<MeApi>((ref) {
  return MeApi(ref.watch(apiClientProvider));
});

final mediaImportServiceProvider = Provider<MediaImportService>((ref) {
  return MediaImportService(
    ref.watch(fileApiProvider),
    TaskApi(ref.watch(apiClientProvider)),
  );
});

final globalMusicApiProvider = Provider<MusicApi>((ref) {
  return MusicApi(ref.watch(apiClientProvider));
});

final globalMusicProgressRepositoryProvider = Provider<MusicProgressRepository>(
  (ref) {
    final database = ref.watch(localDatabaseProvider);
    return MusicProgressRepository(
      database: database,
      syncQueue: SyncQueue(database),
      api: ref.watch(globalMusicApiProvider),
    );
  },
);

final globalReaderApiProvider = Provider<ReaderApi>((ref) {
  return ReaderApi(ref.watch(apiClientProvider));
});

/// 初始化依赖 LocalDatabase 的静态工具类。
/// 必须在应用启动时读取一次，确保 ReaderLocalProgress / ReaderSyncQueue / ReaderImageCache 可用。
final localDatabaseInitProvider = Provider<LocalDatabase>((ref) {
  final db = ref.watch(localDatabaseProvider);
  final userId = ref.watch(
    authSessionProvider.select((session) => session.asData?.value.user?.id),
  );
  final localStorage = ReaderLocalStorage(db);
  final imageRepository = createReaderImageRepository(
    database: db,
    userId: userId,
  );
  ReaderLocalProgress.init(DatabaseReaderLocalProgressStore(db));
  ReaderSyncQueue.init(db);
  ReaderImageCache.init(imageRepository);

  // 启动时自动清理过期缓存（不阻塞启动）
  _autoCleanExpiredCache(localStorage, imageRepository);

  return db;
});

/// 全局网络恢复监听器，用于重放离线同步队列。
final connectivityListenerProvider = Provider<ConnectivityListener>((ref) {
  final listener = ConnectivityListener(
    syncQueue: SyncQueue(ref.watch(localDatabaseProvider)),
    fileApi: ref.watch(fileApiProvider),
    musicApi: ref.watch(globalMusicApiProvider),
    musicProgressRepository: ref.watch(globalMusicProgressRepositoryProvider),
    readerApi: ref.watch(globalReaderApiProvider),
  );
  listener.start();
  ref.onDispose(listener.stop);
  return listener;
});

/// 应用级在线状态，供全局壳层显示离线反馈。
final appOnlineStatusProvider = StreamProvider<bool>((ref) async* {
  final listener = ref.watch(connectivityListenerProvider);
  final current = listener.isOnline;
  if (current != null) {
    yield current;
  }
  yield* listener.onlineStream;
});

/// 启动时自动清理超过 30 天未访问的章节和图片缓存。
Future<void> _autoCleanExpiredCache(
  ReaderLocalStorage localStorage,
  ReaderImageRepository imageRepository,
) async {
  try {
    await localStorage.cleanOldChapters(maxAgeDays: 30);
    await imageRepository.cleanOld(maxAgeDays: 30);
    if (kDebugMode) {
      devLog('CacheCleanup: expired cache cleaned');
    }
  } on Exception catch (e) {
    if (kDebugMode) {
      devLog('CacheCleanup: auto-clean failed: $e');
    }
  }
}
