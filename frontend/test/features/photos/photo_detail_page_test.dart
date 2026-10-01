import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/presentation/pages/photo_detail_page.dart';
import 'package:omninest/features/photos/presentation/pages/photos_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_slideshow_page.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_info_panel.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_viewer_chrome.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

// ─── 图片网络 mock（与 photo_slideshow_page_test 同款模式） ───

/// mock HTTP 返回的图片字节：由测试引擎现场生成并编码的合法 PNG。
Uint8List? _servedImageBytes;

Future<void> _ensureServedImageBytes() async {
  if (_servedImageBytes != null) return;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1300, 800),
    Paint()..color = const Color(0xFFC07840),
  );
  final picture = recorder.endRecording();
  // 源图宽于查看器解码目标（≥1280 档），保证解码为降采样。
  final image = await picture.toImage(1300, 800);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  _servedImageBytes = data!.buffer.asUint8List();
}

class _MockImageHttpHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void forEach(void Function(String name, List<String> values) action) {}

  @override
  String? value(String name) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockImageHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  String get reasonPhrase => 'OK';

  @override
  int get contentLength => _servedImageBytes!.length;

  @override
  HttpHeaders get headers => _MockImageHttpHeaders();

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> element)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[
      _servedImageBytes!,
    ]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockImageHttpRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockImageHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockImageHttpResponse();

  // http 包 IOClient 发送前会无条件调用 flush；这些 Future 型成员若走
  // noSuchMethod 返回 null 会抛类型错误并被缓存层吞掉，导致图片加载挂起。
  @override
  Future<void> flush() async {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<HttpClientResponse> get done => Future<void>.value() as dynamic;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockImageHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _MockImageHttpRequest();

  @override
  Future<void> close({bool force = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 在覆盖区内执行测试体，使 CachedNetworkImage 的下载命中 mock 并立即成功。
Future<void> _mockNetworkImages(Future<void> Function() body) {
  return HttpOverrides.runZoned(
    body,
    createHttpClient: (_) => _MockImageHttpClient(),
  );
}

// ─── path_provider 桩（与 photo_slideshow_page_test 同款） ───

const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

/// 为 flutter_cache_manager 提供 path_provider 桩，避免测试内触发平台通道。
void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
        final prefix = call.method.replaceAll(RegExp(r'[^A-Za-z]'), '');
        final dir = await Directory.systemTemp.createTemp(
          'omninest-photo-detail-$prefix',
        );
        return dir.path;
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });
}

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

/// 携带签名原图与封面 URL 的照片（相邻页预取路径）。
PhotoItem _urlPhoto(String id) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: 'Photo $id',
    format: 'JPEG',
    fileSize: 1024,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2024, 11, 12),
    coverUrl: 'https://example.test/cover/$id.jpg',
    sourceUrl: 'https://example.test/source/$id.jpg',
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
  const _Harness({
    required this.router,
    required this.child,
    required this.repository,
  });

  final GoRouter router;
  final Widget child;
  final _MockPhotoRepository repository;
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
    repository: repository,
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

/// 带图片 URL 的用例改用固定帧推进：mock 下载/解码在 fake async 下不会
/// 完成到可 settle 的程度，而断言只依赖组件构建与预取注册，无需 settle。
Future<void> _pumpDesktopFrames(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(child);
  // 首帧 → 详情 provider 就绪出舞台 → post-frame 预取注册。
  for (final step in [
    const Duration(milliseconds: 16),
    const Duration(milliseconds: 16),
    const Duration(milliseconds: 50),
    const Duration(milliseconds: 50),
  ]) {
    await tester.pump(step);
  }
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
      () => repository.listAlbumsPage(
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) async => PhotoAlbumPage.empty());
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
    expect(
      find.descendant(
        of: find.byType(PhotoViewerTopBar),
        matching: find.text('Bern'),
      ),
      findsOneWidget,
    );

    // 点击播放：沉浸页打开，顶栏计数可见并自动推进。
    // Bootstrap 依次等三次 endOfFrame（封面绘制 → 租约全屏 → surface 对齐）
    // 后加载首图；进度条 ticker 从下一帧的帧时间戳才开始计时。
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('01 / 03'), findsOneWidget);
    // 先推一帧让进度 ticker 记下起点，再推满 5s 间隔触发完成回调，
    // 最后消化 450ms 切换动画；否则完成点会落在测试时钟之外（差一帧）。
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 800));
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
    expect(
      find.descendant(
        of: find.byType(PhotoViewerTopBar),
        matching: find.text('Zurich'),
      ),
      findsOneWidget,
    );

    // 滑动手势切换到下一张。
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(PhotoViewerTopBar),
        matching: find.text('Geneva'),
      ),
      findsOneWidget,
    );

    // 反向滑动回到上一张。
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(PhotoViewerTopBar),
        matching: find.text('Zurich'),
      ),
      findsOneWidget,
    );
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

  testWidgets('桌面端信息侧栏为右滑入覆盖层（320px），点击遮罩关闭', (tester) async {
    await _pumpDesktop(tester, _harness(scope: scope).child);

    // 打开 Info：覆盖层滑入，宽度与幻灯片信息面板一致。
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Photo Info'), findsOneWidget);
    final positioned = tester.widget<Positioned>(
      find
          .ancestor(
            of: find.byType(PhotoInfoPanel),
            matching: find.byType(Positioned),
          )
          .first,
    );
    expect(positioned.width, photoInfoPanelWidth);

    // 点击遮罩：面板滑出（offset 回到 (1, 0)）。
    await tester.tapAt(const Offset(100, 400));
    await tester.pumpAndSettle();
    final slide = tester.widget<AnimatedSlide>(
      find
          .ancestor(
            of: find.byType(PhotoInfoPanel),
            matching: find.byType(AnimatedSlide),
          )
          .first,
    );
    expect(slide.offset, const Offset(1, 0));
  });

  testWidgets('紧凑端信息面板为底部滑入形态且点击遮罩关闭', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(scope: scope).child);
    await tester.pumpAndSettle();

    // 信息入口在弹出菜单中；紧凑宽度为底部滑入面板。
    expect(find.byType(AnimatedSize), findsNothing);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Info').last);
    await tester.pumpAndSettle();

    expect(find.text('Photo Info'), findsOneWidget);
    expect(find.byType(AnimatedSize), findsNothing);

    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    final slide = tester.widget<AnimatedSlide>(
      find
          .ancestor(
            of: find.byType(PhotoInfoPanel),
            matching: find.byType(AnimatedSlide),
          )
          .first,
    );
    expect(slide.offset, const Offset(0, 1));
  });

  testWidgets('亮色主题下查看器保持恒暗（顶栏与信息侧栏）', (tester) async {
    await _pumpDesktop(tester, _harness(scope: scope, darkTheme: false).child);

    // 打开信息侧栏后，亮色应用主题下面板仍为幻灯片同款恒暗底色。
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pumpAndSettle();

    final panel = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(PhotoInfoPanel),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((panel.decoration! as BoxDecoration).color, const Color(0xFF0A0A0A));

    final bar = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(PhotoViewerTopBar),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (bar.decoration as BoxDecoration).color,
      Colors.black.withValues(alpha: 0.38),
    );
  });

  testWidgets('相邻页预取使用与渲染一致的解码键（ResizeImage 包装）', (tester) async {
    _mockPathProvider();
    await _mockNetworkImages(() async {
      // toImage 需真实 raster 线程，须在 runAsync 内生成字节。
      await tester.runAsync(_ensureServedImageBytes);
      final urlScope = [
        _urlPhoto('photo-1'),
        _urlPhoto('photo-2'),
        _urlPhoto('photo-3'),
      ];
      await _pumpDesktopFrames(
        tester,
        _harness(scope: urlScope, initialLocation: '/photos/photo-2').child,
      );

      final context = tester.element(find.byType(PhotoDetailPage));
      final widths = viewerDecodeWidths(context);
      final imageCache = tester.binding.imageCache;
      // 原图按渲染同键（sourceCacheKey + 原图档宽度）预解码；
      // 若退回裸 provider 预取，此处键不命中，滑入时仍会现场解码。
      for (final neighbor in [urlScope.first, urlScope.last]) {
        final provider = ResizeImage(
          CachedNetworkImageProvider(
            neighbor.sourceUrl!,
            cacheKey: neighbor.sourceCacheKey,
          ),
          width: widths.source,
        );
        final key = await provider.obtainKey(ImageConfiguration.empty);
        expect(
          imageCache.containsKey(key),
          isTrue,
          reason: '相邻页 ${neighbor.id} 原图应按渲染同键预解码',
        );
      }
      // 封面按封面档宽度预取。
      final coverProvider = ResizeImage(
        CachedNetworkImageProvider(
          urlScope.first.coverUrl!,
          cacheKey: urlScope.first.coverCacheKey,
        ),
        width: widths.cover,
      );
      final coverKey = await coverProvider.obtainKey(ImageConfiguration.empty);
      expect(imageCache.containsKey(coverKey), isTrue);
    });
  });

  testWidgets('原图层就绪后短淡入，封面层异步就绪短淡入柔化直出', (tester) async {
    _mockPathProvider();
    await _mockNetworkImages(() async {
      await tester.runAsync(_ensureServedImageBytes);
      final urlScope = [_urlPhoto('photo-1')];
      await _pumpDesktopFrames(tester, _harness(scope: urlScope).child);

      final images =
          tester
              .widgetList<CachedNetworkImage>(
                find.descendant(
                  of: find.byType(InteractiveViewer),
                  matching: find.byType(CachedNetworkImage),
                ),
              )
              .toList();
      expect(images, hasLength(2), reason: '舞台应渲染封面与原图两层');
      // 封面层异步就绪后 120ms 短淡入：柔化 Hero 落位后解码才完成的直出跳变；
      // 同步缓存命中（含与飞行层共享解码）不播淡入，保证无缝接管。
      expect(
        images.first.fadeInDuration,
        const Duration(milliseconds: 120),
        reason: '封面层异步就绪短淡入柔化直出跳变',
      );
      expect(
        images.last.fadeInDuration,
        const Duration(milliseconds: 220),
        reason: '原图层异步就绪后短淡入柔化清晰度跳变',
      );
    });
  });

  testWidgets('缺少签名原图的相邻页触发详情预取并写入内存缓存', (tester) async {
    // scope 夹具不带 sourceUrl/coverUrl，模拟首页最近/收藏条带路径。
    final harness = _harness(scope: scope, initialLocation: '/photos/photo-2');
    await _pumpDesktop(tester, harness.child);

    verify(
      () => harness.repository.getPhoto('photo-1'),
    ).called(greaterThanOrEqualTo(1));
    verify(
      () => harness.repository.getPhoto('photo-3'),
    ).called(greaterThanOrEqualTo(1));

    final element = tester.element(find.byType(PhotoDetailPage));
    final container = ProviderScope.containerOf(element);
    expect(
      container.read(photoDetailMemoryCacheProvider).get('photo-1'),
      isNotNull,
      reason: '相邻页详情预取结果应写入内存缓存供滑入时作种子',
    );
    expect(
      container.read(photoDetailMemoryCacheProvider).get('photo-3'),
      isNotNull,
    );
  });

  testWidgets('宽屏档位下查看器入场抬高图片缓存字节预算下限', (tester) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final before = tester.binding.imageCache.maximumSizeBytes;
    await tester.pumpWidget(_harness(scope: scope).child);
    await tester.pump();
    await tester.pump();

    // 物理宽 2560@dpr2 → 逻辑宽 1280 → 原图档 2560、封面档 1024：
    // (2560²+1024²)×4B×3 张×1.3 余量 ≈ 119MB，应抬过默认 100MB 下限。
    final context = tester.element(find.byType(PhotoDetailPage));
    final widths = viewerDecodeWidths(context);
    final expected =
        ((widths.source * widths.source + widths.cover * widths.cover) *
                4 *
                3 *
                1.3)
            .round();
    expect(tester.binding.imageCache.maximumSizeBytes, expected);
    expect(expected, greaterThan(before), reason: '宽屏档位的解码工作集应超过默认预算并触发抬高');
  });
}
