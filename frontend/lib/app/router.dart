import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/mobile_shell/mobile_activity_center_page.dart';
import 'package:omninest/app/mobile_shell/mobile_app_shell.dart';
import 'package:omninest/app/route/app_route_surface.dart';
import 'package:omninest/app/route/boot_page.dart';
import 'package:omninest/app/web_initial_location.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/login_page.dart';
import 'package:omninest/core/server/presentation/server_setup_page.dart';
import 'package:omninest/core/server/server_config_controller.dart';
import 'package:omninest/features/admin/domain/admin_console_access.dart';
import 'package:omninest/features/admin/presentation/pages/admin_dashboard_page.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';
import 'package:omninest/features/files/presentation/pages/file_share_preview_page.dart';
import 'package:omninest/features/music/presentation/pages/music_center_page.dart';
import 'package:omninest/features/music/presentation/pages/music_history_page.dart';
import 'package:omninest/features/music/presentation/pages/music_metadata_edit_page.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_overlay.dart';
import 'package:omninest/features/notifications/presentation/pages/notification_page.dart';
import 'package:omninest/features/notifications/presentation/pages/notification_settings_page.dart';
import 'package:omninest/features/profile/presentation/pages/profile_page.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/pages/photo_album_detail_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_album_photo_picker_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_detail_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_editor_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_shared_album_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_shared_item_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_period_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_slideshow_page.dart';
import 'package:omninest/features/photos/presentation/pages/photos_page.dart';
import 'package:omninest/features/portal/presentation/pages/portal_page.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_center_page.dart';
import 'package:omninest/features/reader/presentation/pages/reader_bookshelf_page.dart';
import 'package:omninest/features/reader/presentation/pages/reader_stats_page.dart';
import 'package:omninest/features/reader/presentation/pages/reader_admin_page.dart';
import 'package:omninest/features/reader/presentation/pages/reader_item_detail_page.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
import 'package:omninest/features/reader/presentation/pages/reader_metadata_edit_page.dart';
import 'package:omninest/features/reader/presentation/pages/comic_reader_page.dart';
import 'package:omninest/features/reader/presentation/pages/pdf_reader_page.dart';
import 'package:omninest/features/reader/presentation/pages/comic_import_confirm_page.dart';
import 'package:omninest/features/search/presentation/pages/search_page.dart';
import 'package:omninest/features/setup/application/initial_setup_controller.dart';
import 'package:omninest/features/setup/presentation/pages/initial_setup_page.dart';
import 'package:omninest/features/tasks/presentation/pages/tasks_page.dart';
import 'package:omninest/features/video/presentation/pages/movie_center_page.dart';
import 'package:omninest/features/video/presentation/pages/movie_detail_page.dart';
import 'package:omninest/features/video/presentation/pages/movie_player_page.dart';
import 'package:omninest/features/video/presentation/pages/series_detail_page.dart';
import 'package:omninest/core/window/desktop_close_action.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRefreshListenable = ValueNotifier<int>(0);
  ref.listen(authSessionProvider, (previous, next) {
    authRefreshListenable.value++;
  });
  ref.listen(initialSetupProvider, (previous, next) {
    authRefreshListenable.value++;
  });
  ref.listen(serverConfigProvider, (previous, next) {
    authRefreshListenable.value++;
  });
  // Web 引擎的 defaultRouteName 恒为 '/'，且 Dart 侧 Uri.base 在 isolate
  // 启动时已拿不到地址 hash；go_router 以它们作初始位置会丢失浏览器深链
  // （整页加载/F5/书签/分享链接全部弹回门户）。index.html 在引擎归一化
  // history 之前把原始地址存入 __omninestInitialHref，经条件导入在 Web 端
  // 读取恢复初始路由；原生端无地址栏，固定从门户进入。
  final webInitialLocation = kIsWeb ? readWebInitialLocation() : null;
  final router = GoRouter(
    navigatorKey: desktopCloseNavigatorKey,
    initialLocation: webInitialLocation ?? '/',
    refreshListenable: authRefreshListenable,
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/portal'),
      _animatedRoute('/boot', (state) => const BootPage()),
      _animatedRoute('/setup', (state) => const InitialSetupPage()),
      _animatedRoute('/login', (state) => const LoginPage()),
      _animatedRoute('/server-setup', (state) => const ServerSetupPage()),
      _animatedRoute('/notifications', (state) => const NotificationPage()),
      _animatedRoute(
        '/profile/notifications',
        (state) => const NotificationSettingsPage(),
      ),
      _animatedRoute('/tasks', (state) => const TasksPage()),
      _animatedRoute(
        '/activity',
        (state) => MobileActivityCenterPage(
          initialIndex: state.uri.queryParameters['tab'] == 'tasks' ? 1 : 0,
        ),
      ),
      _animatedRoute(
        '/search',
        (state) => SearchPage(
          initialScope: state.uri.queryParameters['scope'] ?? 'all',
        ),
      ),
      GoRoute(
        path: '/settings',
        redirect: (context, state) => '/profile?section=appearance',
      ),
      _animatedRoute(
        '/profile',
        (state) =>
            ProfilePage(initialSection: state.uri.queryParameters['section']),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MobileAppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [_animatedRoute('/portal', (state) => const PortalPage())],
          ),
          StatefulShellBranch(
            routes: [
              _animatedRoute('/music', (state) => const MusicCenterPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [_animatedRoute('/photos', (state) => const PhotosPage())],
          ),
          StatefulShellBranch(
            routes: [
              _animatedRoute('/video', (state) => const MovieCenterPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _readerRoute('/reader', (state) => const ReaderCenterPage()),
              _readerRoute(
                '/reader/bookshelf',
                (state) => const ReaderBookshelfPage(),
              ),
              _readerRoute('/reader/stats', (state) => const ReaderStatsPage()),
              _readerRoute('/reader/admin', (state) => const ReaderAdminPage()),
              _readerRoute(
                '/reader/items/:itemId',
                (state) => ReaderItemDetailPage(
                  itemId: state.pathParameters['itemId']!,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _animatedRoute('/files', (state) => const FileBrowserPage()),
            ],
          ),
        ],
      ),
      _animatedRoute(
        '/video/:videoId',
        (state) =>
            MovieDetailPage(videoItemId: state.pathParameters['videoId'] ?? ''),
      ),
      _animatedRoute(
        '/video/series/:seriesId',
        (state) =>
            SeriesDetailPage(seriesId: state.pathParameters['seriesId'] ?? ''),
      ),
      _animatedRoute(
        '/video/:videoId/play',
        (state) =>
            MoviePlayerPage(videoItemId: state.pathParameters['videoId'] ?? ''),
      ),
      _animatedRoute(
        '/music/now-playing',
        (state) => Builder(
          builder:
              (context) => MusicImmersiveOverlay(
                onClose: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/music');
                  }
                },
              ),
        ),
      ),
      _animatedRoute(
        '/music/tracks/:trackId/metadata',
        (state) => MusicMetadataEditPage(
          trackId: state.pathParameters['trackId'] ?? '',
        ),
      ),
      _animatedRoute('/music/history', (_) => const MusicHistoryPage()),
      _animatedRoute(
        '/photos/albums/:albumId',
        (state) =>
            PhotoAlbumDetailPage(albumId: state.pathParameters['albumId']!),
      ),
      _animatedRoute(
        '/photos/albums/:albumId/add',
        (state) => PhotoAlbumPhotoPickerPage(
          albumId: state.pathParameters['albumId']!,
        ),
      ),
      GoRoute(
        path: '/photos/slideshow',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final photos = (extra['photos'] as List<PhotoItem>?) ?? [];
          final initialIndex = extra['initialIndex'] as int? ?? 0;
          final source =
              extra['source'] as PhotoBrowseSource? ??
              PhotoBrowseSource.library;
          final sourceKey = extra['sourceKey'] as String?;
          return _materialTransition(
            state,
            AppRouteSurface(
              owner: 'route:photos-slideshow',
              policy: AppBackdropPolicy.staticContent,
              routePath: '/photos/slideshow',
              child: PhotoSlideshowPage(
                photos: photos,
                source: source,
                sourceKey: sourceKey,
                initialIndex: initialIndex,
              ),
            ),
          );
        },
      ),
      _animatedRoute(
        '/photos/period/:year/:month',
        (state) => PhotoPeriodPage(
          year: int.tryParse(state.pathParameters['year'] ?? '') ?? 0,
          month: int.tryParse(state.pathParameters['month'] ?? '') ?? 0,
        ),
      ),
      _animatedRoute(
        '/photos/:photoId',
        (state) => PhotoDetailPage(photoId: state.pathParameters['photoId']!),
      ),
      _animatedRoute(
        '/photos/:photoId/edit',
        (state) => PhotoEditorPage(photoId: state.pathParameters['photoId']!),
      ),
      _animatedRoute(
        '/shared/photos/:token',
        (state) => PhotoSharedAlbumPage(token: state.pathParameters['token']!),
      ),
      _animatedRoute(
        '/shared/photos/item/:token',
        (state) => PhotoSharedItemPage(token: state.pathParameters['token']!),
      ),
      GoRoute(
        path: '/s/:token',
        pageBuilder: (context, state) {
          final token = state.pathParameters['token']!;
          return _materialTransition(
            state,
            AppRouteSurface(
              owner: 'route:file-share',
              policy: AppBackdropPolicy.work,
              routePath: '/s',
              child: FileSharePreviewPage(token: token),
            ),
          );
        },
      ),
      _animatedRoute(
        '/reader/items/:itemId/chapters/:chapterId',
        (state) => ReaderViewPage(
          itemId: state.pathParameters['itemId']!,
          chapterId: state.pathParameters['chapterId']!,
          entry: state.uri.queryParameters['entry'],
        ),
      ),
      _animatedRoute(
        '/reader/items/:itemId/metadata',
        (state) =>
            ReaderMetadataEditPage(itemId: state.pathParameters['itemId']!),
      ),
      _animatedRoute('/reader/items/:itemId/import-status', (state) {
        final args = state.extra as ComicImportConfirmArgs?;
        final itemId = state.pathParameters['itemId']!;
        return ComicImportConfirmPage(
          itemId: itemId,
          manifest:
              args?.manifest ??
              ComicManifest(
                itemId: itemId,
                sources: const [],
                catalog: const [],
                pages: const [],
                importStatus: 'PARSING',
              ),
          fileName: args?.fileName ?? '',
        );
      }),
      _animatedRoute(
        '/reader/comics/:itemId/read',
        (state) => ComicReaderPage(
          itemId: state.pathParameters['itemId']!,
          initialCatalogNodeId: state.uri.queryParameters['catalogNodeId'],
        ),
      ),
      _animatedRoute(
        '/reader/pdfs/:itemId/read',
        (state) => PdfReaderPage(itemId: state.pathParameters['itemId']!),
      ),
      // Admin 作为 Portal 之上的独立路由节点（push 进入、pop 返回）。
      // 分区深链使用 /admin/:section（与 AdminSection.location 对齐）；
      // 路径段非法时 AdminSection.fromPathSegment 回落到 overview。
      // 两条路由共用固定 pageKey：首次点击侧边栏（/admin → /admin/:section）
      // 属跨路由跳转，若各自使用 location 派生的 pageKey，Navigator 会整页
      // 替换并重跑 initState（表现为重新加载页面）；共用 key 后原地更新，
      // 仅触发 didUpdateWidget 分区切换，与常驻分支模块行为一致。
      GoRoute(
        path: '/admin',
        pageBuilder:
            (context, state) => _materialTransition(
              state,
              _routeSurface('/admin', const AdminDashboardPage()),
              pageKey: _adminPageKey,
            ),
      ),
      GoRoute(
        path: '/admin/:section',
        pageBuilder:
            (context, state) => _materialTransition(
              state,
              _routeSurface(
                '/admin/:section',
                AdminDashboardPage(
                  initialSectionSegment: state.pathParameters['section'],
                ),
              ),
              pageKey: _adminPageKey,
            ),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    authRefreshListenable.dispose();
  });
  // 宿主路由路径驱动背景场景可见性过滤：IndexedStack 常驻分支声明的
  // pathPrefix 不匹配当前路径时不参与生效，portal 等可见分支得以恢复。
  void updateBackdropScenePath() {
    ref
        .read(appBackdropSceneControllerProvider.notifier)
        .setActivePath(router.routeInformationProvider.value.uri.path);
  }

  updateBackdropScenePath();
  router.routeInformationProvider.addListener(updateBackdropScenePath);
  ref.onDispose(() {
    router.routeInformationProvider.removeListener(updateBackdropScenePath);
  });
  return router;
});

/// 构建带淡入+微滑过渡的 GoRoute。
/// 阅读模块内部页面路由：无过渡动画（样例切视图即时切换）。
GoRoute _readerRoute(
  String path,
  Widget Function(GoRouterState state) builder,
) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) {
      return NoTransitionPage<void>(key: state.pageKey, child: builder(state));
    },
  );
}

GoRoute _animatedRoute(
  String path,
  Widget Function(GoRouterState state) builder,
) {
  return GoRoute(
    path: path,
    pageBuilder:
        (context, state) =>
            _materialTransition(state, _routeSurface(path, builder(state))),
  );
}

Widget _routeSurface(String path, Widget child) {
  if (_shellOwnedPaths.contains(path) || path == '/music/now-playing') {
    return child;
  }

  // 影视重设计页使用不透明主题底；继续叠加静态壁纸会在 Impeller
  // 合成时出现对角线亮缝。照片/阅读仍保留静态背景快照。
  final AppBackdropPolicy policy;
  if (path.startsWith('/video')) {
    policy = AppBackdropPolicy.work;
  } else if (path.startsWith('/photos') ||
      path.startsWith('/shared/photos') ||
      path.startsWith('/reader')) {
    policy = AppBackdropPolicy.staticContent;
  } else {
    policy = AppBackdropPolicy.work;
  }
  return AppRouteSurface(
    owner: 'route:$path',
    policy: policy,
    routePath: path,
    child: child,
  );
}

const Set<String> _shellOwnedPaths = <String>{
  '/portal',
  '/files',
  '/music',
  '/photos',
  '/video',
  '/reader',
  '/reader/bookshelf',
  '/reader/stats',
  '/reader/admin',
};

/// Admin 仪表盘两条路由共用的页面键，保证跨路由跳转原地更新。
const LocalKey _adminPageKey = ValueKey<String>('admin-dashboard');

/// 使用 Navigator 托管的页面过渡，避免动画监听器持有已失活的路由子树。
MaterialPage<void> _materialTransition(
  GoRouterState state,
  Widget child, {
  LocalKey? pageKey,
}) {
  return buildAppRoutePage(key: pageKey ?? state.pageKey, child: child);
}

/// 构建由 Navigator 管理生命周期和平台过渡的应用页面。
@visibleForTesting
MaterialPage<void> buildAppRoutePage({
  required LocalKey key,
  required Widget child,
}) {
  return MaterialPage<void>(key: key, child: child);
}

/// 全局重定向：服务器配置门控优先于安装与登录门控。
String? _redirect(Ref ref, GoRouterState state) {
  final location = state.uri.toString();
  final authState = ref.read(authSessionProvider);
  final gate = serverGateRedirectPath(
    isWeb: kIsWeb,
    isConfigLoading: ref.read(serverConfigProvider).isLoading,
    isConfigured: ref.read(appEnvironmentProvider) != null,
    isAuthenticated: authState.asData?.value.isAuthenticated ?? false,
    location: location,
  );
  if (gate != null) {
    return gate;
  }
  final setupState = ref.read(initialSetupProvider);
  return authRedirectPath(
    isChecking: authState.isLoading,
    isAuthenticated: authState.asData?.value.isAuthenticated ?? false,
    isSetupChecking: setupState.isLoading,
    setupRequired: setupState.asData?.value.setupRequired ?? false,
    location: location,
    userRole: authState.asData?.value.user?.role,
    userPermissions: authState.asData?.value.user?.permissions,
  );
}

/// 服务器配置门控决策；返回 null 表示放行进入后续安装/登录门控链。
///
/// 非 Web 端在服务器配置加载期间停泊在引导页，避免空环境下业务页面
/// 瞬时构建；未配置进入 /server-setup 并保留 redirect 目标（配置完成后
/// 经登录页续跳）；已配置后访问引导页则按认证状态回到登录或目标页；
/// 携带 switch=1 的显式切换请求放行（设置页更换服务器入口使用，覆盖
/// 预置存在时 clear 后回落预置导致引导页不可达的死角）。
/// Web 恒有同源推导，不经过服务器门控。
@visibleForTesting
String? serverGateRedirectPath({
  required bool isWeb,
  required bool isConfigLoading,
  required bool isConfigured,
  required bool isAuthenticated,
  required String location,
}) {
  final uri = Uri.parse(location);
  final path = uri.path;
  if (!isWeb && (isConfigLoading || !isConfigured)) {
    return path == '/server-setup' ? null : _serverSetupLocation(uri);
  }
  if (path == '/server-setup') {
    if (uri.queryParameters['switch'] == '1') {
      return null;
    }
    final target = _safeRedirectTarget(uri.queryParameters['redirect']);
    if (isAuthenticated) {
      return target ?? '/portal';
    }
    return target == null
        ? '/login'
        : Uri(path: '/login', queryParameters: {'redirect': target}).toString();
  }
  return null;
}

String _serverSetupLocation(Uri uri) {
  final target = uri.toString();
  if (target == '/' || uri.path == '/server-setup' || uri.path == '/login') {
    return '/server-setup';
  }
  return Uri(
    path: '/server-setup',
    queryParameters: {'redirect': target},
  ).toString();
}

String? authRedirectPath({
  required bool isChecking,
  required bool isAuthenticated,
  required String location,
  bool isSetupChecking = false,
  bool setupRequired = false,
  String? userRole,
  Set<String>? userPermissions,
}) {
  if (isChecking || isSetupChecking) {
    // 认证/安装检查在途：仅放行公开路径，受保护路径停泊到引导页。
    // 避免页面在无凭据状态下构建并发起必然 401 的首批请求——这是
    // Web 刷新后被强制登出的直接诱因。
    final uri = Uri.parse(location);
    final path = uri.path;
    if (path == '/boot' || _isPublicPath(path) || path == '/server-setup') {
      return null;
    }
    final target = location == '/' ? '/portal' : location;
    return Uri(path: '/boot', queryParameters: {'redirect': target}).toString();
  }

  final uri = Uri.parse(location);
  final path = uri.path;
  final isLogin = path == '/login';

  if (setupRequired) {
    return path == '/setup' ? null : '/setup';
  }
  if (path == '/boot') {
    // 检查已结束：按认证结果落位到原目标或登录页。
    final target = _safeRedirectTarget(uri.queryParameters['redirect']);
    if (!isAuthenticated) {
      return Uri(
        path: '/login',
        queryParameters: {'redirect': target ?? '/portal'},
      ).toString();
    }
    return target ?? '/portal';
  }
  if (path == '/setup') {
    return isAuthenticated ? '/portal' : '/login';
  }

  if (isAuthenticated && isLogin) {
    return _safeRedirectTarget(uri.queryParameters['redirect']) ?? '/portal';
  }

  // 公开路径不做任何重定向
  if (_isPublicPath(path)) {
    return null;
  }

  if (!isAuthenticated && !_isPublicPath(path)) {
    final target = location == '/' ? '/portal' : location;
    return Uri(
      path: '/login',
      queryParameters: {'redirect': target},
    ).toString();
  }

  // 管理页面：具备任一管理端入口权限即可进入；分区细粒度由页面权限校验
  if (isAuthenticated && path.startsWith('/admin')) {
    if (!canAccessAdminConsole(
      userRole: userRole,
      userPermissions: userPermissions,
    )) {
      return '/portal';
    }
  }

  return null;
}

bool _isPublicPath(String path) {
  return path == '/login' ||
      path == '/setup' ||
      path.startsWith('/shared/photos/') ||
      path.startsWith('/s/');
}

String? _safeRedirectTarget(String? redirect) {
  if (redirect == null || redirect.isEmpty) {
    return null;
  }
  if (!redirect.startsWith('/') ||
      redirect.startsWith('//') ||
      redirect.startsWith('/login')) {
    return null;
  }
  return redirect;
}
