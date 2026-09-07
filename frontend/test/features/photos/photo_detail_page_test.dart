import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/presentation/pages/photo_browse_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_detail_page.dart';
import 'package:omninest/features/photos/presentation/pages/photos_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_slideshow_page.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_exif_sidebar.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_viewer_chrome.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

/// 预置照片列表的照片中心控制器，模拟真实加载完成后的状态。
class _SeededPhotoCenterController extends PhotoCenterController {
  _SeededPhotoCenterController(this.photos);

  final List<PhotoItem> photos;

  @override
  Future<PhotoCenterState> build() async {
    return PhotoCenterState(
      dashboard: PhotoDashboard.empty(),
      photos: photos,
      favorites: const [],
      albums: const [],
      tab: PhotoTab.all,
      photoTotalElements: photos.length,
    );
  }
}

/// 固定浏览范围的桩 Notifier，供详情页上一张/下一张与幻灯片使用。
class _FixedScopeNotifier extends PhotoBrowseScopeNotifier {
  _FixedScopeNotifier(this.photos);

  final List<PhotoItem> photos;

  @override
  PhotoBrowseScope build() =>
      PhotoBrowseScope(photos: photos, source: PhotoBrowseSource.library);
}

/// 伪造的照片中心控制器，返回空状态以避免网络请求。
class _FakePhotoCenterController extends PhotoCenterController {
  @override
  Future<PhotoCenterState> build() async {
    return PhotoCenterState.empty();
  }
}

PhotoItem _photo(String id, String city) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: 'Photo $id',
    format: 'JPEG',
    fileSize: 1024,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2024, 11, 12),
    gpsLocation: <String, dynamic>{'city': city},
  );
}

/// 已提取运动视频的动态照片（仅用于徽标渲染断言，测试内不触发播放）。
PhotoItem _motionPhoto(String id, String city) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: 'Photo $id',
    format: 'JPEG',
    fileSize: 1024,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2024, 11, 12),
    gpsLocation: <String, dynamic>{'city': city},
    motionState: 'READY',
    motionVideoUrl: 'https://example.com/motion/$id.mp4',
  );
}

class _Harness {
  const _Harness({required this.router, required this.child});

  final GoRouter router;
  final Widget child;
}

_Harness _harness({
  List<PhotoItem> scope = const [],
  List<PhotoItem>? centerSeed,
  bool overrideScope = true,
  String localeCode = 'en',
  String initialLocation = '/photos/photo-1',
  bool darkTheme = true,
}) {
  final repository = _MockPhotoRepository();
  when(() => repository.getPhoto(any())).thenAnswer(
    (invocation) async =>
        scope.firstWhere((p) => p.id == invocation.positionalArguments[0]),
  );
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/photos',
        builder:
            (context, state) =>
                const Scaffold(body: Center(child: Text('Photos Home'))),
      ),
      GoRoute(
        path: '/photos/slideshow',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final photos = (extra['photos'] as List<PhotoItem>?) ?? [];
          final source =
              extra['source'] as PhotoBrowseSource? ??
              PhotoBrowseSource.library;
          final sourceKey = extra['sourceKey'] as String?;
          final initialIndex = extra['initialIndex'] as int? ?? 0;
          return PhotoSlideshowPage(
            photos: photos,
            source: source,
            sourceKey: sourceKey,
            initialIndex: initialIndex,
          );
        },
      ),
      GoRoute(
        path: '/photos/:photoId',
        builder:
            (context, state) =>
                PhotoDetailPage(photoId: state.pathParameters['photoId']!),
      ),
    ],
  );
  return _Harness(
    router: router,
    child: ProviderScope(
      overrides: [
        photoRepositoryProvider.overrideWithValue(repository),
        photoCenterControllerProvider.overrideWith(
          () =>
              centerSeed == null
                  ? _FakePhotoCenterController()
                  : _SeededPhotoCenterController(centerSeed),
        ),
        if (overrideScope)
          photoBrowseScopeProvider.overrideWith(
            () => _FixedScopeNotifier(scope),
          ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale(localeCode),
        theme:
            darkTheme
                ? OmniNestTheme.from(AppThemePalette.dark)
                : OmniNestTheme.light(),
      ),
    ),
  );
}

Future<void> _pumpDesktop(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(child);
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  final scope = [
    _photo('photo-1', 'Bern'),
    _photo('photo-2', 'Zurich'),
    _photo('photo-3', 'Geneva'),
  ];

  testWidgets('顶栏使用关闭/下载/删除命令且删除不再是永久删除文案', (tester) async {
    await _pumpDesktop(tester, _harness(scope: scope).child);

    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byTooltip('Download original'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(find.byTooltip('Permanently Delete'), findsNothing);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
  });

  testWidgets('生产链路：网格打开详情后播放按钮启动沉浸页并自动推进', (tester) async {
    final repository = _MockPhotoRepository();
    when(
      () => repository.dashboard(),
    ).thenAnswer((_) async => PhotoDashboard.empty());
    when(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer(
      (_) async => PhotoPage(
        items: scope,
        page: 0,
        size: 50,
        totalElements: scope.length,
        totalPages: 1,
      ),
    );
    when(
      () => repository.listFavorites(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer((_) async => PhotoPage.empty());
    when(
      () => repository.listTrash(),
    ).thenAnswer((_) async => PhotoPage.empty());
    when(
      () => repository.listAlbums(),
    ).thenAnswer((_) async => const <PhotoAlbum>[]);
    when(() => repository.getPhoto(any())).thenAnswer(
      (invocation) async =>
          scope.firstWhere((p) => p.id == invocation.positionalArguments[0]),
    );

    final router = GoRouter(
      initialLocation: '/photos',
      routes: [
        GoRoute(
          path: '/photos',
          builder: (context, state) => const PhotosPage(),
        ),
        GoRoute(
          path: '/photos/browse',
          builder: (context, state) => const PhotoBrowsePage(),
        ),
        GoRoute(
          path: '/photos/slideshow',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return PhotoSlideshowPage(
              photos: (extra['photos'] as List<PhotoItem>?) ?? const [],
              source:
                  extra['source'] as PhotoBrowseSource? ??
                  PhotoBrowseSource.library,
              sourceKey: extra['sourceKey'] as String?,
              initialIndex: extra['initialIndex'] as int? ?? 0,
            );
          },
        ),
        GoRoute(
          path: '/photos/:photoId',
          builder:
              (context, state) =>
                  PhotoDetailPage(photoId: state.pathParameters['photoId']!),
        ),
      ],
    );

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
          photoRepositoryProvider.overrideWithValue(repository),
          photoCenterControllerProvider.overrideWith(
            () => _SeededPhotoCenterController(scope),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 从真实网格点开第一张照片。
    expect(find.byType(PhotoGridTile), findsNWidgets(3));
    await tester.tap(find.byType(PhotoGridTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Bern'), findsOneWidget);

    // 点击播放：沉浸页打开，顶栏计数可见并自动推进。
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('01 / 03'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('02 / 03'), findsOneWidget);

    // 清场：推时钟消化自动播放的后续切换 Timer 与 idle 计时器，
    // 避免测试结束时残留未触发 Timer（新状态机的就绪门控时序）。
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('箭头与滑动手势在单路由内切换照片', (tester) async {
    await _pumpDesktop(tester, _harness(scope: scope).child);

    // 箭头切换：当前照片数据随之更新。
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Zurich'), findsOneWidget);

    // 滑动手势切换到下一张。
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Geneva'), findsOneWidget);

    // 反向滑动回到上一张。
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Zurich'), findsOneWidget);
  });

  testWidgets('动态照片显示 LIVE 徽标且切换到普通照片后隐藏', (tester) async {
    final mixedScope = [
      _motionPhoto('photo-1', 'Bern'),
      _photo('photo-2', 'Zurich'),
    ];
    await _pumpDesktop(tester, _harness(scope: mixedScope).child);

    // 动态照片：徽标可见。
    expect(find.text('LIVE'), findsOneWidget);

    // 切换到普通照片：徽标隐藏。
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('LIVE'), findsNothing);
  });

  testWidgets('桌面端信息面板是全高独立侧栏并压缩照片区', (tester) async {
    await _pumpDesktop(tester, _harness(scope: scope).child);

    // 收起时 AnimatedSize 宽度为 0，不占舞台空间。
    expect(tester.getSize(find.byType(AnimatedSize)).width, 0);
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pumpAndSettle();

    final panelSize = tester.getSize(find.byType(AnimatedSize));
    expect(panelSize.width, 288);
    expect(panelSize.height, 800);
    expect(find.text('Photo Info'), findsOneWidget);
  });

  testWidgets('紧凑端信息面板为右侧抽屉且点击遮罩关闭', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(scope: scope).child);
    await tester.pumpAndSettle();

    // 紧凑端不存在桌面侧栏，信息入口在弹出菜单中。
    expect(find.byType(AnimatedSize), findsNothing);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Info').last);
    await tester.pumpAndSettle();

    expect(find.text('Photo Info'), findsOneWidget);
    expect(find.byType(AnimatedSize), findsNothing);

    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    expect(find.text('Photo Info'), findsNothing);
  });

  testWidgets('亮色主题下查看器保持恒暗（顶栏与信息侧栏）', (tester) async {
    await _pumpDesktop(tester, _harness(scope: scope, darkTheme: false).child);

    // 打开信息侧栏后，亮色应用主题下面板仍为幻灯片同款恒暗底色。
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pumpAndSettle();

    final panel = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(PhotoExifPanel),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((panel.decoration! as BoxDecoration).color, const Color(0xF00A0A0A));

    final bar = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(PhotoViewerTopBar),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (bar.decoration! as BoxDecoration).color,
      Colors.black.withValues(alpha: 0.38),
    );
  });
}
