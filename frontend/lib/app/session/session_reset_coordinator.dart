import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/application/admin_user_controller.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_daily_recommendation_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/video/application/movie_controller.dart';

/// 登录用户变更时需要重置的常驻业务 provider 清单。
///
/// 只收持有用户内容的 provider；全局字典（通知类型、天气配置）与无状态
/// 服务 provider 不在其中。派生 provider（Portal 门面、profile 派生值、
/// 未读计数）分别依赖本清单中的源 provider 或 authSessionProvider，无需
/// 重复列出。
final List<ProviderOrFamily> _resetProviders = <ProviderOrFamily>[
  taskListProvider,
  activeTaskSummaryProvider,
  notificationControllerProvider,
  fileBrowserControllerProvider,
  fileStorageStatsProvider,
  movieDashboardProvider,
  movieCenterControllerProvider,
  movieCenterSectionProvider,
  musicDashboardProvider,
  musicCenterControllerProvider,
  musicPlatformLibraryProvider,
  musicDailyRecommendationProvider,
  musicPlaybackSessionProvider,
  photoDashboardProvider,
  photoCenterControllerProvider,
  photoListProvider,
  photoFavoritesProvider,
  photoAlbumsProvider,
  readerDashboardProvider,
  readerStatsProvider,
  readerStatsOverviewProvider,
  readerCenterControllerProvider,
  adminConsoleSummaryProvider,
  adminRolesProvider,
  adminConfigsProvider,
  adminTasksProvider,
  adminDlqProvider,
  adminLogsProvider,
  adminMonitoringProvider,
  adminStorageProvider,
  adminExternalStorageProvider,
  adminSessionsProvider,
  adminLoginAuditProvider,
  adminConsoleControllerProvider,
  adminUserControllerProvider,
  userSessionsProvider,
];

/// 监听登录会话变更，并在已有登录用户发生变化时重置全部常驻业务 provider。
///
/// 覆盖登出（用户→未认证）、换号（用户 A→B）与 401 强制登出三条路径，
/// 三者都表现为 authSessionProvider 的用户身份变化。此前没有登录用户的
/// 冷启动与同用户 token 刷新不触发，避免无意义的批量失效。
final sessionResetCoordinatorProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<AuthSessionState>>(authSessionProvider, (prev, next) {
    final prevId = prev?.asData?.value.user?.id;
    final nextId = next.asData?.value.user?.id;
    if (prevId == null || prevId == nextId) {
      return;
    }
    for (final provider in _resetProviders) {
      ref.invalidate(provider);
    }
  });
});
