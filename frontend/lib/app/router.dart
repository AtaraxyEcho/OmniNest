import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/mobile_shell/mobile_activity_center_page.dart';
import 'package:omninest/app/mobile_shell/mobile_app_shell.dart';
import 'package:omninest/app/route/app_route_surface.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/login_page.dart';
import 'package:omninest/features/admin/domain/admin_section.dart';
import 'package:omninest/features/admin/presentation/pages/admin_dashboard_page.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';
import 'package:omninest/features/files/presentation/pages/file_share_preview_page.dart';
import 'package:omninest/features/music/presentation/pages/music_center_page.dart';
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
import 'package:omninest/features/photos/presentation/pages/photo_browse_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_period_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_albums_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_insights_page.dart';
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
import 'package:omninest/features/reader/presentation/pages/comic_import_confirm_page.dart';
import 'package:omninest/features/search/presentation/pages/search_page.dart';
import 'package:omninest/features/setup/application/initial_setup_controller.dart';
import 'package:omninest/features/setup/presentation/pages/initial_setup_page.dart';
import 'package:omninest/features/tasks/presentation/pages/tasks_page.dart';
import 'package:omninest/features/video/presentation/pages/movie_center_page.dart';
import 'package:omninest/features/video/presentation/pages/movie_detail_page.dart';
import 'package:omninest/features/video/presentation/pages/movie_player_page.dart';
import 'package:omninest/features/video/presentation/pages/series_detail_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRefreshListenable = ValueNotifier<int>(0);
  ref.listen(authSessionProvider, (previous, next) {
    authRefreshListenable.value++;
  });
  ref.listen(initialSetupProvider, (previous, next) {
    authRefreshListenable.value++;
  });
  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: authRefreshListenable,
    redirect: (context, state) {
      final authState = ref.read(authSessionProvider);
      final setupState = ref.read(initialSetupProvider);
      return authRedirectPath(
        isChecking: authState.isLoading,
        isAuthenticated: authState.asData?.value.isAuthenticated ?? false,
        isSetupChecking: setupState.isLoading,
        setupRequired: setupState.asData?.value.setupRequired ?? false,
        location: state.uri.toString(),
        userRole: authState.asData?.value.user?.role,
      );
    },
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/portal'),
      _animatedRoute('/setup', (state) => const InitialSetupPage()),
      _animatedRoute('/login', (state) => const LoginPage()),
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
              _animatedRoute('/files', (state) => const FileBrowserPage()),
            ],
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
      _animatedRoute('/photos/browse', (state) => const PhotoBrowsePage()),
      _animatedRoute('/photos/albums', (state) => const PhotoAlbumsPage()),
      _animatedRoute('/photos/insights', (state) => const PhotoInsightsPage()),
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
              child: FileSharePreviewPage(token: token),
            ),
          );
        },
      ),
      _animatedRoute(
        '/reader/items/:itemId',
        (state) =>
            ReaderItemDetailPage(itemId: state.pathParameters['itemId']!),
      ),
      _animatedRoute(
        '/reader/items/:itemId/chapters/:chapterId',
        (state) => ReaderViewPage(
          itemId: state.pathParameters['itemId']!,
          chapterId: state.pathParameters['chapterId']!,
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
      GoRoute(
        path: '/admin',
        redirect: (context, state) => AdminSection.overview.location,
      ),
      _animatedRoute(
        '/admin/:section',
        (state) => AdminDashboardPage(
          section: AdminSection.fromPathSegment(
            state.pathParameters['section'],
          ),
        ),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    authRefreshListenable.dispose();
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
      final child = _routeSurface(path, builder(state));
      return NoTransitionPage<void>(key: state.pageKey, child: child);
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

  final policy =
      path.startsWith('/photos') ||
              path.startsWith('/shared/photos') ||
              path.startsWith('/video') ||
              path.startsWith('/reader')
          ? AppBackdropPolicy.staticContent
          : AppBackdropPolicy.work;
  return AppRouteSurface(owner: 'route:$path', policy: policy, child: child);
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

/// 使用 Navigator 托管的页面过渡，避免动画监听器持有已失活的路由子树。
MaterialPage<void> _materialTransition(GoRouterState state, Widget child) {
  return buildAppRoutePage(key: state.pageKey, child: child);
}

/// 构建由 Navigator 管理生命周期和平台过渡的应用页面。
@visibleForTesting
MaterialPage<void> buildAppRoutePage({
  required LocalKey key,
  required Widget child,
}) {
  return MaterialPage<void>(key: key, child: child);
}

String? authRedirectPath({
  required bool isChecking,
  required bool isAuthenticated,
  required String location,
  bool isSetupChecking = false,
  bool setupRequired = false,
  String? userRole,
}) {
  if (isChecking || isSetupChecking) {
    return null;
  }

  final uri = Uri.parse(location);
  final path = uri.path;
  final isLogin = path == '/login';

  if (setupRequired) {
    return path == '/setup' ? null : '/setup';
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

  // 管理页面仅对 ADMIN / SUPER_ADMIN 开放
  if (isAuthenticated && path.startsWith('/admin')) {
    final isAdmin = userRole == 'ADMIN' || userRole == 'SUPER_ADMIN';
    if (!isAdmin) {
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
