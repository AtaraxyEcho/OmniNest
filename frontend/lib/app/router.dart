import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/mobile_shell/mobile_app_shell.dart';
import 'package:omninest/app/phone_form_factor.dart';
import 'package:omninest/app/route/app_route_surface.dart';
import 'package:omninest/app/route/boot_page.dart';
import 'package:omninest/app/web_initial_location.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/login_page.dart';
import 'package:omninest/core/server/presentation/server_setup_page.dart';
import 'package:omninest/core/server/server_config_controller.dart';
import 'package:omninest/features/admin/application/admin_console_access_provider.dart';
import 'package:omninest/features/admin/presentation/pages/admin_dashboard_page.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/app/mobile_shell/workspace_tools_page.dart';
import 'package:omninest/features/files/application/file_browser_models.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';
import 'package:omninest/features/files/presentation/pages/file_preview_route_page.dart';
import 'package:omninest/features/files/presentation/pages/file_share_preview_page.dart';
import 'package:omninest/features/library/presentation/pages/library_space_page.dart';
import 'package:omninest/features/music/presentation/pages/music_center_page.dart';
import 'package:omninest/features/music/presentation/pages/music_history_page.dart';
import 'package:omninest/features/music/presentation/pages/music_scan_page.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_overlay.dart';
import 'package:omninest/features/notifications/presentation/pages/notification_page.dart';
import 'package:omninest/features/profile/presentation/pages/profile_page.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/pages/photo_album_detail_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_album_photo_picker_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_detail_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_editor_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_groups_page.dart';
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
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/search/presentation/pages/mobile_search_page.dart';
import 'package:omninest/features/setup/application/initial_setup_controller.dart';
import 'package:omninest/features/setup/presentation/pages/initial_setup_page.dart';
import 'package:omninest/features/video/application/movie_center_state.dart';
import 'package:omninest/features/video/presentation/pages/movie_center_page.dart';
import 'package:omninest/features/video/presentation/pages/movie_detail_page.dart';
import 'package:omninest/features/video/presentation/pages/movie_player_page.dart';
import 'package:omninest/features/video/presentation/pages/series_detail_page.dart';
import 'package:omninest/core/window/desktop_close_action.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';

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
  // 手机形态变化（分屏、折叠屏开合）影响管理台可达性：触发守卫对当前
  // 路由重估，避免已在 /admin 时形态切换后停留在不可达页面。
  ref.listen(phoneFormFactorProvider, (previous, next) {
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
      // 通知中心为根级路由：移动壳层启用时经 MobileHostedRoute 补挂
      // scope，页面分叉移动形态且页内弹窗走底部面板。极性随外观设置。
      _animatedRoute(
        '/notifications',
        (state) => const MobileHostedRoute(child: NotificationPage()),
      ),
      GoRoute(
        path: '/profile/notifications',
        // 通知偏好并入新个人中心的移动形态二级视图；桌面壳层经
        // ProfileDesktopShell 导航进入原页面，保留桌面可达性。
        redirect: (context, state) => '/profile?section=notifications',
      ),
      // 任务队列不再是普通用户可见概念（由管理端按归属人查阅处理），
      // 旧入口保留重定向：/notifications-tasks 是合并中心时期、/activity 是改名前。
      GoRoute(
        path: '/notifications-tasks',
        redirect: (context, state) => '/notifications',
      ),
      GoRoute(path: '/tasks', redirect: (context, state) => '/notifications'),
      GoRoute(
        path: '/activity',
        redirect: (context, state) => '/notifications',
      ),
      GoRoute(
        path: '/settings',
        redirect: (context, state) => '/profile?section=appearance',
      ),
      _animatedRoute(
        '/tools',
        (_) => const MobileHostedRoute(child: WorkspaceToolsPage()),
      ),
      _animatedRoute(
        '/profile',
        (state) => MobileHostedRoute(
          child: ProfilePage(
            initialSection: state.uri.queryParameters['section'],
          ),
        ),
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
              _animatedRoute('/library', (state) => const LibrarySpacePage()),
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
            ],
          ),
          StatefulShellBranch(
            routes: [
              _animatedRoute(
                '/files',
                (state) => FileBrowserPage(
                  // 工具总入口按分区直达；非枚举名一律回默认分区。
                  initialSection: fileManagerSectionFromRouteName(
                    state.uri.queryParameters['section'],
                  ),
                  initialOAuthStatus: state.uri.queryParameters['oauth'],
                ),
              ),
            ],
          ),
        ],
      ),
      // 搜索结果直接打开文件预览：命中项只有文件 ID，先回源节点再渲染。
      _animatedRoute(
        '/files/preview/:fileId',
        (state) => MobileHostedRoute(
          child: FilePreviewRoutePage(
            fileId: state.pathParameters['fileId']!,
          ),
        ),
      ),
      // 全局搜索：跨内容类型的统一查找覆盖层，不属于一级导航。
      // 覆盖层自带近乎实底的深色底，因此包 hosted 作用域并列入壳层自有路径，
      // 不接路由级环境档；`scope` 查询参数决定预选的内容档。
      _animatedRoute(
        '/search',
        (state) => MobileHostedRoute(
          child: MobileSearchPage(
            initialScope: _searchScopeFromQuery(
              state.uri.queryParameters['scope'],
            ),
          ),
        ),
      ),
      // 音乐/照片/影视不再占据一级导航，作为全屏模块页从 Library 或
      // 深链进入；移动壳层启用时经 MobileHostedRoute 补挂 scope，模块
      // 页分叉移动形态（样例 module-overlay）且页内弹窗走底部面板。
      _animatedRoute(
        '/music',
        (state) => const MobileHostedRoute(child: MusicCenterPage()),
      ),
      _animatedRoute(
        '/photos',
        (state) => const MobileHostedRoute(child: PhotosPage()),
      ),
      _animatedRoute(
        '/video',
        (state) => MobileHostedRoute(
          child: MovieCenterPage(
            initialSection: movieSectionFromRouteName(
              state.uri.queryParameters['section'],
            ),
          ),
        ),
      ),
      _animatedRoute(
        '/video/:videoId',
        (state) => MobileHostedRoute(
          child: MovieDetailPage(
            videoItemId: state.pathParameters['videoId'] ?? '',
          ),
        ),
      ),
      _animatedRoute(
        '/video/series/:seriesId',
        (state) => MobileHostedRoute(
          child: SeriesDetailPage(
            seriesId: state.pathParameters['seriesId'] ?? '',
          ),
        ),
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
        '/music/history',
        (_) => const MobileHostedRoute(child: MusicHistoryPage()),
      ),
      _animatedRoute(
        '/music/scan',
        (_) => const MobileHostedRoute(child: MusicScanPage()),
      ),
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
          final initialPhotoId = extra['initialPhotoId'] as String?;
          final source =
              extra['source'] as PhotoBrowseSource? ??
              PhotoBrowseSource.library;
          final sourceKey = extra['sourceKey'] as String?;
          return _materialTransition(
            state,
            AppRouteSurface.environmental(
              owner: 'route:photos-slideshow',
              routePath: '/photos/slideshow',
              child: PhotoSlideshowPage(
                photos: photos,
                source: source,
                sourceKey: sourceKey,
                initialIndex: initialIndex,
                initialPhotoId: initialPhotoId,
              ),
            ),
          );
        },
      ),
      _animatedRoute(
        '/photos/groups',
        (_) => const MobileHostedRoute(child: PhotoGroupsPage()),
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
        (state) => MobileHostedRoute(
          child: PhotoSharedAlbumPage(token: state.pathParameters['token']!),
        ),
      ),
      _animatedRoute(
        '/shared/photos/item/:token',
        (state) => MobileHostedRoute(
          child: PhotoSharedItemPage(token: state.pathParameters['token']!),
        ),
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
      // 书本详情是全屏覆盖层（样例 `.module-overlay`/`.book-detail` 都是
      // position: fixed; inset: 0），所以和章节阅读页一样挂在壳层之外：挂在
      // /reader 分支里时它只能盖住内容区，壳层顶栏与底栏那两条环境带会留在
      // 纸面之上，从阅读页返回就露出接缝。MobileHostedRoute 补托管 scope。
      _readerRoute(
        '/reader/items/:itemId',
        (state) => MobileHostedRoute(
          child: ReaderItemDetailPage(itemId: state.pathParameters['itemId']!),
        ),
      ),
      _animatedRoute(
        '/reader/items/:itemId/chapters/:chapterId',
        (state) => ReaderViewPage(
          itemId: state.pathParameters['itemId']!,
          chapterId: state.pathParameters['chapterId']!,
          entry: state.uri.queryParameters['entry'],
          initialCharOffset: int.tryParse(
            state.uri.queryParameters['offset'] ?? '',
          ),
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
      // 表面与场景档必须在这里挂上：书本详情是从首页 push 进来的分支路由，
      // 壳层仍停在来源空间，没有这一层就没人把阅读档（focus）注册进背景场景，
      // 页面底就还是首页的环境档。壳层自有路径由 _routeSurface 自行跳过。
      return NoTransitionPage<void>(
        key: state.pageKey,
        child: _routeSurface(path, builder(state)),
      );
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

  // 移动壳层按全局环境模式继承（媒体 ambient/阅读 focus/其余 utility）；
  // 桌面端保持原有语义：照片/阅读静态快照、影视与系统页实底
  // （影视不透明底同时规避 Impeller 合成对角亮缝）。
  return AppRouteSurface.environmental(
    owner: 'route:$path',
    routePath: path,
    child: child,
  );
}

const Set<String> _shellOwnedPaths = <String>{
  '/portal',
  '/library',
  '/files',
  '/music',
  '/reader',
  '/reader/bookshelf',
  '/reader/stats',
  '/reader/admin',
  '/search',
};

/// 解析 `/search?scope=` 的内容档；未知取值回落「全部」而不是报错。
ScopedSearchId? _searchScopeFromQuery(String? raw) {
  for (final scope in ScopedSearchId.values) {
    if (scope.name == raw) {
      return scope;
    }
  }
  return null;
}

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
    canAccessAdminConsole: ref.read(canAccessAdminConsoleProvider),
  );
}

/// 服务器配置门控决策；返回 null 表示放行进入后续安装/登录门控链。
///
/// 非 Web 端在服务器配置加载期间停泊在引导页（避免空环境下业务页面
/// 瞬时构建，也避免安装向导在已配置实例上闪现数秒）；加载完成且未
/// 配置才进入 /server-setup 并保留 redirect 目标（配置完成后经登录页
/// 续跳）；已配置后访问引导页则按认证状态回到登录或目标页；携带
/// switch=1 的显式切换请求放行（设置页更换服务器入口使用，覆盖预置
/// 存在时 clear 后回落预置导致引导页不可达的死角）。
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
  if (!isWeb) {
    // 配置在途：停泊引导页（带 redirect 目标），已配置实例不再闪现
    // 安装向导；判定完成且未配置才落 /server-setup。
    if (isConfigLoading) {
      if (path == '/boot' || path == '/server-setup') {
        return null;
      }
      final target = location == '/' ? '/portal' : location;
      return Uri(
        path: '/boot',
        queryParameters: {'redirect': target},
      ).toString();
    }
    if (!isConfigured) {
      return path == '/server-setup' ? null : _serverSetupLocation(uri);
    }
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
  // 配置加载期间深链先停在 /boot?redirect=...；配置完成后必须解包内层目标，
  // 否则会把 /boot 自身再次编码进 redirect，最终被 _safeRedirectTarget 拒绝。
  if (uri.path == '/boot') {
    final inner = _safeRedirectTarget(uri.queryParameters['redirect']);
    if (inner == null || inner == '/' || inner == '/portal') {
      return '/server-setup';
    }
    return Uri(
      path: '/server-setup',
      queryParameters: {'redirect': inner},
    ).toString();
  }
  final target = uri.toString();
  if (target == '/' || uri.path == '/server-setup' || uri.path == '/login') {
    return '/server-setup';
  }
  return Uri(
    path: '/server-setup',
    queryParameters: {'redirect': target},
  ).toString();
}

/// 认证与安装门控决策；返回 null 表示放行。
///
/// [canAccessAdminConsole] 由调用方经 `canAccessAdminConsoleProvider` 求得
/// （权限与手机形态的统一事实源），本函数只做路由侧决策。
String? authRedirectPath({
  required bool isChecking,
  required bool isAuthenticated,
  required String location,
  required bool canAccessAdminConsole,
  bool isSetupChecking = false,
  bool setupRequired = false,
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

  // 管理页面：入口判定统一走 canAccessAdminConsoleProvider（权限 +
  // 手机形态）；分区细粒度由页面权限校验
  if (isAuthenticated && path.startsWith('/admin')) {
    if (!canAccessAdminConsole) {
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
  // 反斜杠与协议相对地址都可能被浏览器解释成外部跳转；控制路由不能作为登录回跳目标。
  if (!redirect.startsWith('/') ||
      redirect.startsWith('//') ||
      redirect.contains('\\') ||
      redirect.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    return null;
  }
  final uri = Uri.tryParse(redirect);
  if (uri == null) {
    return null;
  }
  final path = uri.path;
  if (path == '/login' ||
      path.startsWith('/login/') ||
      path == '/boot' ||
      path == '/setup' ||
      path == '/server-setup') {
    return null;
  }
  return redirect;
}
