import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/application/admin_user_controller.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/application/file_download_url_provider.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_daily_recommendation_controller.dart';
import 'package:omninest/features/music/application/music_history_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/application/music_platform_qr_session_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/portal/application/portal_paged_cards.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_image_provider.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_image.dart';
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
  musicHistoryControllerProvider,
  musicPlatformLibraryProvider,
  musicDailyRecommendationProvider,
  musicPlaybackSessionProvider,
  platformQrSessionProvider,
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
  adminStorageProvider,
  adminExternalStorageProvider,
  adminConnectorOAuthAppsProvider,
  adminSessionsProvider,
  adminLoginAuditProvider,
  adminConsoleControllerProvider,
  adminUserControllerProvider,
  userSessionsProvider,
  // 门户分页卡片缓存用户内容（照片、书架、队列、影视），换号后必须重置，
  // 避免上一账号的数据在新账号首次进入门户前可见。
  portalContinueWatchingProvider,
  portalRecentPhotosProvider,
  portalPlaybackQueueProvider,
  portalReaderShelfProvider,
  portalVideoPreviewProvider,
];

/// 监听登录会话变更，并在已有登录用户发生变化时重置全部常驻业务 provider。
///
/// 覆盖登出（用户→未认证）、换号（用户 A→B）与 401 强制登出三条路径，
/// 三者都表现为 authSessionProvider 的用户身份变化。此前没有登录用户的
/// 冷启动与同用户 token 刷新不触发，避免无意义的批量失效。
///
/// 过渡帧（AsyncLoading）一律跳过，身份改由 lastUserId 自己记：拿 prev/next 两侧
/// 即时值比较时，一帧过渡态会被当成"登出"触发整站失效，紧接着真正落地的 A→B 又因为
/// prev 是过渡帧取不到前值而被漏掉。
final sessionResetCoordinatorProvider = Provider<void>((ref) {
  String? lastUserId = ref.read(authSessionProvider).value?.user?.id;
  ref.listen<AsyncValue<AuthSessionState>>(authSessionProvider, (_, next) {
    if (next.isLoading) {
      return;
    }
    final nextId = next.value?.user?.id;
    final prevId = lastUserId;
    lastUserId = nextId;
    if (prevId == null || prevId == nextId) {
      return;
    }
    // 静态进程内缓存不随 provider 销毁，换号必须显式清掉。
    ReaderCoverByteCache.clear();
    // 会话级缓存只按文件/条目 ID 索引，不含账号归属：签名下载地址、文本预览、
    // 照片详情（含原图签名地址）与 data URI 解码结果都必须随账号切换失效。
    clearFileDownloadUrlCaches();
    ref.read(photoDetailMemoryCacheProvider).clear();
    clearReaderDataUriDecodeCache();
    // 先递增会话世代：已接入世代的 provider 以依赖变化语义重建，旧账号
    // 数据不会被当作可访问旧值渲染（失效清单中未接入世代的 provider 仍
    // 由下方 invalidate 兜底重建）。
    ref.read(sessionEpochProvider.notifier).bump();
    for (final provider in _resetProviders) {
      ref.invalidate(provider);
    }
  });
});
