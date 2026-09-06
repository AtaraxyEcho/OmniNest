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
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';

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
  List<PhotoItem> build() => photos;
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
        theme: OmniNestTheme.from(AppThemePalette.dark),
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
  await tester.pumpAndSettle();
}

void main() {
  final scope = [
    _photo('photo-1', 'Bern'),
    _photo('photo-2', 'Zurich'),
    _photo('photo-3', 'Geneva'),
  ];

  testWidgets('生产链路：网格打开详情后幻灯片点击播放并自动推进', (tester) async {
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

    // 点击播放：徽章出现并开始自动推进。
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.text('幻灯片 · 1 / 3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('幻灯片 · 2 / 3'), findsOneWidget);
  });

  testWidgets('箭头与滑动手势在单路由内切换照片', (tester) async {
    await _pumpDesktop(tester, _harness(scope: scope).child);

    // 箭头切换：当前照片数据与徽章随之更新。
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Zurich'), findsOneWidget);

    // 滑动手势切换到下一张。
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('Geneva'), findsOneWidget);

    // 反向滑动回到上一张。
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('Zurich'), findsOneWidget);
  });

  testWidgets('浏览页式进入（范围未写、中心列表含照片）可播放', (tester) async {
    await _pumpDesktop(
      tester,
      _harness(
        scope: scope,
        centerSeed: scope,
        overrideScope: false,
        localeCode: 'zh',
      ).child,
    );

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.text('幻灯片 · 1 / 3'), findsOneWidget);
  });

  testWidgets('无可播放序列时点击给出可见反馈且不进入播放态', (tester) async {
    await _pumpDesktop(
      tester,
      _harness(
        scope: scope,
        centerSeed: const [],
        overrideScope: false,
        localeCode: 'zh',
      ).child,
    );

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.text('当前没有可连续播放的照片'), findsOneWidget);
    expect(find.textContaining('幻灯片 ·'), findsNothing);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
  });

  testWidgets('浏览范围晚到时点击反馈后可正常播放', (tester) async {
    final harness = _harness(
      scope: scope,
      centerSeed: const [],
      overrideScope: false,
      localeCode: 'zh',
    );
    await _pumpDesktop(tester, harness.child);

    // 数据未就绪时点击只提示，不进入播放态。
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.text('当前没有可连续播放的照片'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);

    // 浏览范围晚到写入后无需重建页面即可播放。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PhotoDetailPage)),
    );
    container.read(photoBrowseScopeProvider.notifier).set(scope);
    // 清除第一次点击的提示条，避免干扰第二次点击的断言。
    ScaffoldMessenger.of(
      tester.element(find.byType(PhotoDetailPage)),
    ).clearSnackBars();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.text('幻灯片 · 1 / 3'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.text('当前没有可连续播放的照片'), findsNothing);
  });

  testWidgets('顶栏使用关闭/下载/删除命令且删除不再是永久删除文案', (tester) async {
    await _pumpDesktop(tester, _harness(scope: scope).child);

    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byTooltip('Download original'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(find.byTooltip('Permanently Delete'), findsNothing);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
  });

  testWidgets('幻灯片在查看器内自动推进并循环回第一张', (tester) async {
    await _pumpDesktop(tester, _harness(scope: scope).child);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.text('Slideshow · 1 / 3'), findsOneWidget);

    // 第一次推进：photo-1 → photo-2，播放状态跨路由替换保持。
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Slideshow · 2 / 3'), findsOneWidget);

    // 第二次推进：photo-2 → photo-3。
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Slideshow · 3 / 3'), findsOneWidget);

    // 末尾循环回第一张。
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Slideshow · 1 / 3'), findsOneWidget);
  });

  testWidgets('暂停后不再自动推进', (tester) async {
    await _pumpDesktop(tester, _harness(scope: scope).child);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Slideshow · 2 / 3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(find.text('Slideshow · 2 / 3'), findsNothing);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Zurich'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('离开详情后播放状态自动复位，再次进入不恢复播放', (tester) async {
    final harness = _harness(scope: scope, initialLocation: '/photos');
    await _pumpDesktop(tester, harness.child);
    expect(find.text('Photos Home'), findsOneWidget);

    // 从列表 push 进入详情，与生产导航路径一致，关闭时走 pop。
    harness.router.push('/photos/photo-1');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Slideshow · 2 / 3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Photos Home'), findsOneWidget);

    harness.router.push('/photos/photo-3');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    expect(find.textContaining('Slideshow ·'), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('页面销毁时幻灯片定时器随之取消', (tester) async {
    await _pumpDesktop(tester, _harness(scope: scope).child);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    // 若定时器未取消，测试结束时会被标记为 pending timer。
    await tester.pump(const Duration(seconds: 10));
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
}
