import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/boot_gate.dart';
import 'package:omninest/app/desktop/desktop_shell.dart';
import 'package:omninest/app/desktop/pages/desktop_home_page.dart';
import 'package:omninest/app/desktop/pages/desktop_login_page.dart';
import 'package:omninest/app/desktop/pages/desktop_movie_detail_page.dart';
import 'package:omninest/app/desktop/pages/desktop_series_detail_page.dart';
import 'package:omninest/app/desktop/pages/desktop_movies_page.dart';
import 'package:omninest/app/desktop/pages/desktop_now_playing_page.dart';
import 'package:omninest/app/desktop/pages/desktop_files_page.dart';
import 'package:omninest/app/desktop/pages/desktop_music_page.dart';
import 'package:omninest/app/desktop/pages/desktop_reader_page.dart';
import 'package:omninest/app/desktop/pages/desktop_book_detail_page.dart';
import 'package:omninest/app/desktop/pages/desktop_splash_page.dart';
import 'package:omninest/app/desktop/pages/desktop_settings_page.dart';
import 'package:omninest/app/desktop/pages/desktop_setup_page.dart';
import 'package:omninest/app/desktop/pages/desktop_photo_viewer_page.dart';
import 'package:omninest/app/desktop/pages/desktop_photos_page.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/mobile_shell/mobile_app_shell.dart';
import 'package:omninest/app/phone_form_factor.dart';
import 'package:omninest/app/route/app_route_surface.dart';
import 'package:omninest/app/route/route_surface.dart';
import 'package:omninest/app/route/auth_gate.dart';
import 'package:omninest/app/web_initial_location.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/login_page.dart';
import 'package:omninest/core/server/presentation/server_setup_page.dart';
import 'package:omninest/core/server/server_config_controller.dart';
import 'package:omninest/core/utils/platform_helper.dart';
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
import 'package:omninest/features/video/application/movie_center_state.dart';
import 'package:omninest/features/video/presentation/pages/movie_center_page.dart';
import 'package:omninest/features/video/presentation/pages/movie_detail_page.dart';
import 'package:omninest/features/video/presentation/pages/movie_player_page.dart';
import 'package:omninest/features/video/presentation/pages/series_detail_page.dart';
import 'package:omninest/core/window/desktop_close_action.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
export 'package:omninest/app/route/auth_gate.dart';

/// 根 Navigator 键：复用 `desktopCloseNavigatorKey`，确保窗口关闭确认弹窗与
/// 沉浸式全窗路由均挂载在桌面工作区壳层之上的同一根导航器中。
final GlobalKey<NavigatorState> rootNavigatorKey = desktopCloseNavigatorKey;

/// 桌面工作区内容 Navigator 键：挂载在 `ShellRoute`（`DesktopWorkspaceShell`）内，
/// 与根 Navigator 分层隔离，使沉浸页推入根层时底层工作区零卸载、零重排。
final GlobalKey<NavigatorState> _desktopWorkspaceNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'desktop-workspace');

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRefreshListenable = installBootGate(ref);
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
    navigatorKey: rootNavigatorKey,
    initialLocation: webInitialLocation ?? '/',
    refreshListenable: authRefreshListenable,
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/portal'),
      _animatedRoute('/boot', (state) => const DesktopBootSwitch()),
      _animatedRoute('/setup', (state) => const DesktopSetupSwitch()),
      _animatedRoute(
        '/login',
        (state) => const DesktopFormSwitch(
          desktop: DesktopLoginPage(),
          mobile: LoginPage(),
        ),
      ),
      _animatedRoute('/server-setup', (state) => const ServerSetupPage()),
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
            context,
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
      // 桌面工作区壳层（双层 Navigator 的内层工作区栈）：
      // 桌面端渲染完整工作区 chrome（顶栏 + 侧栏 + _RouteEnter + 详情坞 + 播放条）；
      // 移动端直接透传 child，保持 MobileAppShell 与既有移动导航栈零改动。
      // 沉浸式全窗路由声明 `parentNavigatorKey: rootNavigatorKey` 推入根 Navigator
      // 覆盖在本层之上，进出沉浸页时本层零卸载、零尺寸跳变、零重排。
      ShellRoute(
        navigatorKey: _desktopWorkspaceNavigatorKey,
        pageBuilder: (context, state, child) {
          final content =
              _isDesktopRouteContext(context)
                  ? DesktopWorkspaceShell(
                    path: state.uri.toString(),
                    child: child,
                  )
                  : child;
          return NoTransitionPage<void>(key: state.pageKey, child: content);
        },
        routes: [
          // 通知中心：移动壳层启用时经 MobileHostedRoute 补挂
          // scope，页面分叉移动形态且页内弹窗走底部面板。极性随外观设置。
          _animatedRoute(
            '/notifications',
            (state) => const MobileHostedRoute(child: NotificationPage()),
          ),
          _animatedRoute(
            '/tools',
            (_) => const MobileHostedRoute(child: WorkspaceToolsPage()),
          ),
          _animatedRoute(
            '/profile',
            (state) => DesktopFormSwitch(
              desktop: DesktopSettingsPage(
                initialSection: state.uri.queryParameters['section'],
              ),
              mobile: MobileHostedRoute(
                child: ProfilePage(
                  initialSection: state.uri.queryParameters['section'],
                ),
              ),
            ),
          ),
          StatefulShellRoute(
            pageBuilder: (context, state, navigationShell) {
              final shell = MobileAppShell(navigationShell: navigationShell);
              if (_isDesktopRouteContext(context)) {
                return NoTransitionPage<void>(key: state.pageKey, child: shell);
              }
              return buildAppRoutePage(key: state.pageKey, child: shell);
            },
            navigatorContainerBuilder: _buildSemanticsSafeBranchContainer,
            branches: [
              StatefulShellBranch(
                routes: [
                  _animatedRoute(
                    '/portal',
                    (state) => const DesktopFormSwitch(
                      desktop: DesktopHomePage(),
                      mobile: PortalPage(),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  _animatedRoute(
                    '/library',
                    (state) => const LibrarySpacePage(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  _readerRoute(
                    '/reader',
                    (state) => const DesktopFormSwitch(
                      desktop: DesktopReaderPage(),
                      mobile: ReaderCenterPage(),
                    ),
                  ),
                  _readerRoute(
                    '/reader/bookshelf',
                    (state) => const DesktopFormSwitch(
                      desktop: DesktopReaderPage(initialLibrary: true),
                      mobile: ReaderBookshelfPage(),
                    ),
                  ),
                  _readerRoute(
                    '/reader/stats',
                    (state) => const ReaderStatsPage(),
                  ),
                  _readerRoute(
                    '/reader/admin',
                    (state) => const ReaderAdminPage(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  _animatedRoute(
                    '/files',
                    (state) => DesktopFormSwitch(
                      // 工具总入口按分区直达；非枚举名一律回默认分区。
                      desktop: DesktopFilesPage(
                        initialSection: fileManagerSectionFromRouteName(
                          state.uri.queryParameters['section'],
                        ),
                      ),
                      mobile: FileBrowserPage(
                        initialSection: fileManagerSectionFromRouteName(
                          state.uri.queryParameters['section'],
                        ),
                        initialOAuthStatus: state.uri.queryParameters['oauth'],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 搜索结果直接打开文件预览：命中项只有文件 ID，先回源节点再渲染。
          _desktopDetailRoute(
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
            (state) => const DesktopFormSwitch(
              desktop: DesktopMusicPage(),
              mobile: MobileHostedRoute(child: MusicCenterPage()),
            ),
          ),
          _animatedRoute(
            '/photos',
            (state) => const DesktopFormSwitch(
              desktop: DesktopPhotosPage(),
              mobile: MobileHostedRoute(child: PhotosPage()),
            ),
          ),
          _animatedRoute(
            '/video',
            (state) => DesktopFormSwitch(
              desktop: DesktopMoviesPage(
                initialTab: desktopMoviesTabFromSection(
                  state.uri.queryParameters['section'],
                ),
              ),
              mobile: MobileHostedRoute(
                child: MovieCenterPage(
                  initialSection: movieSectionFromRouteName(
                    state.uri.queryParameters['section'],
                  ),
                ),
              ),
            ),
          ),
          _desktopDetailRoute(
            '/video/:videoId',
            (state) => DesktopFormSwitch(
              desktop: DesktopMovieDetailPage(
                videoItemId: state.pathParameters['videoId'] ?? '',
              ),
              mobile: MobileHostedRoute(
                child: MovieDetailPage(
                  videoItemId: state.pathParameters['videoId'] ?? '',
                ),
              ),
            ),
          ),
          _desktopDetailRoute('/video/series/:seriesId', (state) {
            final seriesId = state.pathParameters['seriesId'] ?? '';
            return DesktopFormSwitch(
              desktop: DesktopSeriesDetailPage(seriesId: seriesId),
              mobile: MobileHostedRoute(
                child: SeriesDetailPage(seriesId: seriesId),
              ),
            );
          }),
          _desktopDetailRoute(
            '/music/history',
            (_) => const MobileHostedRoute(child: MusicHistoryPage()),
          ),
          _desktopDetailRoute(
            '/music/scan',
            (_) => const MobileHostedRoute(child: MusicScanPage()),
          ),
          _desktopDetailRoute(
            '/photos/albums/:albumId',
            (state) =>
                PhotoAlbumDetailPage(albumId: state.pathParameters['albumId']!),
          ),
          _desktopDetailRoute(
            '/photos/albums/:albumId/add',
            (state) => PhotoAlbumPhotoPickerPage(
              albumId: state.pathParameters['albumId']!,
            ),
          ),
          _desktopDetailRoute(
            '/photos/groups',
            (_) => const MobileHostedRoute(child: PhotoGroupsPage()),
          ),
          _desktopDetailRoute(
            '/photos/period/:year/:month',
            (state) => PhotoPeriodPage(
              year: int.tryParse(state.pathParameters['year'] ?? '') ?? 0,
              month: int.tryParse(state.pathParameters['month'] ?? '') ?? 0,
            ),
          ),
          // 书本详情桌面端统一走 `_desktopRoutePage()`，移动端保留既有详情页。
          _desktopDetailRoute('/reader/items/:itemId', buildReaderItemRoute),
          _desktopDetailRoute(
            '/reader/items/:itemId/metadata',
            (state) =>
                ReaderMetadataEditPage(itemId: state.pathParameters['itemId']!),
          ),
          _desktopDetailRoute('/reader/items/:itemId/import-status', (state) {
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
          // Admin 作为 Portal 之上的独立路由节点（push 进入、pop 返回）。
          // 两条路由共用固定 pageKey 保证跨分区跳转原地更新；桌面端统一走
          // `_desktopRoutePage()`，消除移动端 MaterialPage 侧滑过渡。
          GoRoute(
            path: '/admin',
            pageBuilder:
                (context, state) => _desktopRoutePage(
                  context,
                  state,
                  routeSurface('/admin', const AdminDashboardPage()),
                  pageKey: _adminPageKey,
                ),
          ),
          GoRoute(
            path: '/admin/:section',
            pageBuilder:
                (context, state) => _desktopRoutePage(
                  context,
                  state,
                  routeSurface(
                    '/admin/:section',
                    AdminDashboardPage(
                      initialSectionSegment: state.pathParameters['section'],
                    ),
                  ),
                  pageKey: _adminPageKey,
                ),
          ),
        ],
      ),
      // 沉浸式全窗路由：统一挂载在 `rootNavigatorKey`，直接覆盖完整工作区，
      // 置于工作区 `ShellRoute` 之后以确保 `/photos/groups` 等静态路径优先匹配。
      _desktopViewerRoute(
        '/video/:videoId/play',
        (state) => MoviePlayerPage(
          videoItemId: state.pathParameters['videoId'] ?? '',
          fromStart: state.uri.queryParameters['fromStart'] == '1',
        ),
        duration: DesktopMotion.immersiveViewerEnter,
        parentNavigatorKey: rootNavigatorKey,
      ),
      _desktopNowPlayingRoute(
        '/music/now-playing',
        (state) => DesktopFormSwitch(
          desktop: const DesktopNowPlayingPage(),
          mobile: Builder(
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
        parentNavigatorKey: rootNavigatorKey,
      ),
      GoRoute(
        path: '/photos/slideshow',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final photos = (extra['photos'] as List<PhotoItem>?) ?? [];
          final initialIndex = extra['initialIndex'] as int? ?? 0;
          final initialPhotoId = extra['initialPhotoId'] as String?;
          final source =
              extra['source'] as PhotoBrowseSource? ??
              PhotoBrowseSource.library;
          final sourceKey = extra['sourceKey'] as String?;
          return _immersiveTransitionPage(
            context,
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
            duration: DesktopMotion.photoViewerEnter,
          );
        },
      ),
      _desktopViewerRoute(
        '/photos/:photoId',
        (state) {
          final photoId = state.pathParameters['photoId']!;
          // GoRouter 对同模式的 path 参数变化可能复用同一个 StatefulWidget。
          // 没有 id key 时查看器 `_currentId` 仍停在第一次长按/打开的照片，
          // 表现为「取消长按后点另一张，却打开前一张」。
          return DesktopFormSwitch(
            desktop: DesktopPhotoViewerPage(
              key: ValueKey<String>('desktop-photo-viewer-$photoId'),
              photoId: photoId,
            ),
            mobile: PhotoDetailPage(
              key: ValueKey<String>('mobile-photo-detail-$photoId'),
              photoId: photoId,
            ),
          );
        },
        duration: DesktopMotion.photoViewerEnter,
        parentNavigatorKey: rootNavigatorKey,
      ),
      _desktopViewerRoute(
        '/photos/:photoId/edit',
        (state) => PhotoEditorPage(photoId: state.pathParameters['photoId']!),
        duration: DesktopMotion.immersiveViewerEnter,
        parentNavigatorKey: rootNavigatorKey,
      ),
      _desktopViewerRoute(
        '/reader/items/:itemId/chapters/:chapterId',
        (state) => ReaderViewPage(
          itemId: state.pathParameters['itemId']!,
          chapterId: state.pathParameters['chapterId']!,
          entry: state.uri.queryParameters['entry'],
          initialCharOffset: int.tryParse(
            state.uri.queryParameters['offset'] ?? '',
          ),
        ),
        duration: DesktopMotion.immersiveViewerEnter,
        parentNavigatorKey: rootNavigatorKey,
      ),
      _desktopViewerRoute(
        '/reader/comics/:itemId/read',
        (state) => ComicReaderPage(
          itemId: state.pathParameters['itemId']!,
          initialCatalogNodeId: state.uri.queryParameters['catalogNodeId'],
        ),
        duration: DesktopMotion.immersiveViewerEnter,
        parentNavigatorKey: rootNavigatorKey,
      ),
      _desktopViewerRoute(
        '/reader/pdfs/:itemId/read',
        (state) => PdfReaderPage(itemId: state.pathParameters['itemId']!),
        duration: DesktopMotion.immersiveViewerEnter,
        parentNavigatorKey: rootNavigatorKey,
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    authRefreshListenable.dispose();
  });
  // 宿主路由路径驱动背景场景可见性过滤：改为 scheduleMicrotask + lastPath 去重，
  // 避免路由切换同帧内同步写入 Provider 触发冗余重建。
  String? lastPath;
  var syncScheduled = false;
  var disposed = false;

  void flushBackdropScenePath() {
    syncScheduled = false;
    if (disposed) {
      return;
    }
    final nextPath = router.routeInformationProvider.value.uri.path;
    if (nextPath == lastPath) {
      return;
    }
    lastPath = nextPath;
    ref
        .read(appBackdropSceneControllerProvider.notifier)
        .setActivePath(nextPath);
  }

  void updateBackdropScenePath() {
    if (syncScheduled || disposed) {
      return;
    }
    syncScheduled = true;
    scheduleMicrotask(flushBackdropScenePath);
  }

  updateBackdropScenePath();
  router.routeInformationProvider.addListener(updateBackdropScenePath);
  ref.onDispose(() {
    disposed = true;
    router.routeInformationProvider.removeListener(updateBackdropScenePath);
  });
  return router;
});

/// 为 StatefulShellRoute 非活跃分支包裹 `ExcludeSemantics(excluding: index != currentIndex)`
/// 并在根节点声明 `Semantics(explicitChildNodes: true)`，彻底消除 Windows `Offstage`
/// 切换分支引发的 `ui::AXTree` 语义断链。
Widget _buildSemanticsSafeBranchContainer(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  List<Widget> children,
) {
  final currentIndex = navigationShell.currentIndex;
  return Semantics(
    explicitChildNodes: true,
    child: Stack(
      fit: StackFit.expand,
      children: [
        for (var index = 0; index < children.length; index++)
          Offstage(
            offstage: index != currentIndex,
            child: TickerMode(
              enabled: index == currentIndex,
              child: ExcludeSemantics(
                excluding: index != currentIndex,
                child: children[index],
              ),
            ),
          ),
      ],
    ),
  );
}

bool _isDesktopRouteContext(BuildContext context) {
  return !shouldUseResponsiveMobileShell(
    mobilePlatform: isMobilePlatform,
    width: MediaQuery.sizeOf(context).width,
  );
}

/// 桌面端二级详情页与管理后台页面构造。
///
/// 工作区（`DesktopShellMode.chrome`）内的常规与二级路由统一交由外层单一
/// `_RouteEnter` 承载 GPU 合成层过渡，此处直接返回 `NoTransitionPage` 消除
/// 双重入场动画打架；移动端保持平台默认 `MaterialPage`。
Page<void> _desktopRoutePage(
  BuildContext context,
  GoRouterState state,
  Widget child, {
  LocalKey? pageKey,
}) {
  final key = pageKey ?? state.pageKey;
  if (!_isDesktopRouteContext(context)) {
    return buildAppRoutePage(key: key, child: child);
  }
  if (desktopShellModeForPath(state.uri.path) == DesktopShellMode.chrome) {
    return NoTransitionPage<void>(key: key, child: child);
  }
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: DesktopMotion.routeExit,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        return child;
      }
      final curved = CurvedAnimation(
        parent: animation,
        curve: DesktopMotion.ease,
        reverseCurve: DesktopMotion.exitCurve,
      );
      return FadeTransition(
        opacity: curved,
        alwaysIncludeSemantics: true,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.992, end: 1.0).animate(curved),
            alignment: Alignment.topCenter,
            child: child,
          ),
        ),
      );
    },
  );
}

GoRoute _desktopDetailRoute(
  String path,
  Widget Function(GoRouterState state) builder,
) {
  return GoRoute(
    path: path,
    pageBuilder:
        (context, state) => _desktopRoutePage(
          context,
          state,
          routeSurface(path, builder(state)),
        ),
  );
}

/// 分支内无路由级动效的阅读子路由（由外层壳层过渡统一承载）。
GoRoute _readerRoute(
  String path,
  Widget Function(GoRouterState state) builder,
) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) {
      return NoTransitionPage<void>(
        key: state.pageKey,
        child: routeSurface(path, builder(state)),
      );
    },
  );
}

/// 书籍详情的形态分派。桌面端使用当前原型对齐的全屏详情，移动端保留
/// 既有详情页与其 hosted scope，避免深链在桌面误落到旧的移动布局。
@visibleForTesting
Widget buildReaderItemRoute(GoRouterState state) {
  return DesktopFormSwitch(
    desktop: DesktopBookDetailPage(itemId: state.pathParameters['itemId']!),
    mobile: MobileHostedRoute(
      child: ReaderItemDetailPage(itemId: state.pathParameters['itemId']!),
    ),
  );
}

/// 音乐沉浸播放页专属上滑淡入（500ms）与下滑淡出（320ms）。
GoRoute _desktopNowPlayingRoute(
  String path,
  Widget Function(GoRouterState state) builder, {
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    path: path,
    parentNavigatorKey: parentNavigatorKey,
    pageBuilder: (context, state) {
      final child = routeSurface(path, builder(state));
      if (!_isDesktopRouteContext(context)) {
        return NoTransitionPage<void>(key: state.pageKey, child: child);
      }
      return CustomTransitionPage<void>(
        key: state.pageKey,
        transitionDuration: DesktopMotion.nowPlayingIn,
        reverseTransitionDuration: DesktopMotion.nowPlayingOut,
        child: DesktopImmersiveOverlay(
          path: state.uri.toString(),
          child: child,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
            return child;
          }
          final curved = CurvedAnimation(
            parent: animation,
            curve: DesktopMotion.ease,
            reverseCurve: DesktopMotion.exitCurve,
          );
          return FadeTransition(
            opacity: curved,
            alwaysIncludeSemantics: true,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          );
        },
      );
    },
  );
}

Page<void> _immersiveTransitionPage(
  BuildContext context,
  GoRouterState state,
  Widget child, {
  required Duration duration,
}) {
  final wrapped =
      _isDesktopRouteContext(context)
          ? DesktopImmersiveOverlay(path: state.uri.toString(), child: child)
          : child;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    child: wrapped,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        return child;
      }
      final curved = CurvedAnimation(
        parent: animation,
        curve: DesktopMotion.ease,
        reverseCurve: DesktopMotion.exitCurve,
      );
      return FadeTransition(
        opacity: curved,
        alwaysIncludeSemantics: true,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 全局查看器（Video / Reader / Comic / PhotoViewer）的柔和缩放淡入淡出路由。
GoRoute _desktopViewerRoute(
  String path,
  Widget Function(GoRouterState state) builder, {
  required Duration duration,
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    path: path,
    parentNavigatorKey: parentNavigatorKey,
    pageBuilder:
        (context, state) => _immersiveTransitionPage(
          context,
          state,
          routeSurface(path, builder(state)),
          duration: duration,
        ),
  );
}

GoRoute _animatedRoute(
  String path,
  Widget Function(GoRouterState state) builder,
) {
  return GoRoute(
    path: path,
    pageBuilder:
        (context, state) => _materialTransition(
          context,
          state,
          routeSurface(path, builder(state)),
          desktopNoTransition:
              desktopShellModeForPath(state.uri.path) ==
              DesktopShellMode.chrome,
        ),
  );
}

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
Page<void> _materialTransition(
  BuildContext context,
  GoRouterState state,
  Widget child, {
  LocalKey? pageKey,
  bool desktopNoTransition = false,
}) {
  final key = pageKey ?? state.pageKey;
  if (desktopNoTransition && _isDesktopRouteContext(context)) {
    return NoTransitionPage<void>(key: key, child: child);
  }
  return buildAppRoutePage(key: key, child: child);
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
  final waiting = bootGateAllowsWaiting(ref);
  final gate = serverGateRedirectPath(
    isWeb: kIsWeb,
    isConfigLoading: waiting && ref.read(serverConfigProvider).isLoading,
    isConfigured: ref.read(appEnvironmentProvider) != null,
    isAuthenticated: authState.asData?.value.isAuthenticated ?? false,
    location: location,
  );
  if (gate != null) {
    return gate;
  }
  final setupState = ref.read(initialSetupProvider);
  return authRedirectPath(
    isChecking: waiting && authState.isLoading,
    isAuthenticated: authState.asData?.value.isAuthenticated ?? false,
    isSetupChecking: waiting && setupState.isLoading,
    setupRequired: setupState.asData?.value.setupRequired ?? false,
    location: location,
    canAccessAdminConsole: ref.read(canAccessAdminConsoleProvider),
  );
}
