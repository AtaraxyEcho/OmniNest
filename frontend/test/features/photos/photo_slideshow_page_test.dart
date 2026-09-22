import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/presentation/pages/photo_slideshow_image_cache.dart';
import 'package:omninest/features/photos/presentation/pages/photo_slideshow_page.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_slideshow_chrome.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_slideshow_overlays.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_thumb_image.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';

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
  // 源图宽于 preview 解码目标（≥1280 档），保证两档解码都是降采样（引擎不放大小图）。
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

/// 对任意 GET 请求返回固定图片字节的 HttpClient 桩。
class _MockImageHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _MockImageHttpRequest();

  @override
  Future<void> close({bool force = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 在覆盖区内执行测试体，使 CachedNetworkImageProvider 的下载命中 mock。
Future<void> _mockNetworkImages(Future<void> Function() body) {
  return HttpOverrides.runZoned(
    body,
    createHttpClient: (_) => _MockImageHttpClient(),
  );
}

PhotoItem _photoWithUrl(String id) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: 'Photo $id',
    format: 'JPEG',
    fileSize: 1024,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2024, 11, 12),
    coverUrl: 'https://example.test/cover/$id.webp',
    sourceUrl: 'https://example.test/source/$id.jpg',
  );
}

class _FakePhotoCenterController extends PhotoCenterController {
  @override
  Future<PhotoCenterState> build() async {
    return PhotoCenterState.empty();
  }
}

const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

/// 为 flutter_cache_manager 提供 path_provider 桩，避免测试内触发平台通道。
void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
        final prefix = call.method.replaceAll(RegExp(r'[^A-Za-z]'), '');
        final dir = await Directory.systemTemp.createTemp(
          'omninest-slideshow-$prefix',
        );
        return dir.path;
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });
}

/// 与页面 SlideshowImageCache.obtain 完全一致的 provider 构造。
ImageProvider<Object> _providerFor(
  PhotoItem photo,
  ImageQuality quality,
  int decodeWidth,
) {
  final isThumbnail = quality == ImageQuality.thumbnail;
  final url = isThumbnail ? photo.coverUrl! : photo.sourceUrl!;
  final cacheKey = isThumbnail ? photo.coverCacheKey : photo.sourceCacheKey;
  return ResizeImage.resizeIfNeeded(
    decodeWidth,
    null,
    CachedNetworkImageProvider(url, cacheKey: cacheKey),
  );
}

/// 在真实事件循环内把页面将要 resolve 的 provider 预热进 ImageCache。
///
/// 页面的解码链路从 FakeAsync 帧内发起，真实 IO 完成后的微任务回写会被
/// 测试时钟拦截；预热起点位于 runAsync 的真实 zone，与生产链路一致地
/// 走 mock HTTP + 缓存管理器 + 解码全程，之后页面 obtain 直接命中缓存。
Future<void> _warmImageCache(
  WidgetTester tester,
  Iterable<(PhotoItem, ImageQuality, int)> targets,
) async {
  await tester.runAsync(() async {
    await _ensureServedImageBytes();
    for (final (photo, quality, decodeWidth) in targets) {
      final provider = _providerFor(photo, quality, decodeWidth);
      final completer = Completer<void>();
      late final ImageStreamListener listener;
      final stream = provider.resolve(
        const ImageConfiguration(size: Size(1280, 800)),
      );
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        onError: (Object error, StackTrace? stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
      );
      stream.addListener(listener);
      await completer.future.timeout(const Duration(seconds: 15));
      // 保留监听：维持位图 live 状态，页面 obtain 命中缓存后直接绘制。
    }
  });
}

/// 按照片 id 返回照片的仓储桩：信息面板 watch 详情 provider 时不触真实网络。
class _StubPhotoRepository implements PhotoRepository {
  _StubPhotoRepository(this.photos);

  final List<PhotoItem> photos;

  @override
  Future<PhotoItem> getPhoto(String photoId) async =>
      photos.firstWhere((p) => p.id == photoId, orElse: () => photos.first);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Future<void> _pumpSlideshow(WidgetTester tester, List<PhotoItem> photos) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        photoCenterControllerProvider.overrideWith(
          () => _FakePhotoCenterController(),
        ),
        photoRepositoryProvider.overrideWithValue(_StubPhotoRepository(photos)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: OmniNestTheme.from(AppThemePalette.dark),
        home: PhotoSlideshowPage(
          photos: photos,
          source: PhotoBrowseSource.library,
        ),
      ),
    ),
  );
  // bootstrap：home 路由过渡已完成 → 租约与入场扩缩同帧启动 → 再等一帧
  // 对齐 surface → 才加载首图。与生产路径的帧序保持一致。
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// 探针：把窗口 chrome 状态镜像到 [hidden]，供测试在任意帧断言租约时机。
class _WindowChromeProbe extends ConsumerWidget {
  const _WindowChromeProbe({required this.hidden, required this.child});

  final ValueNotifier<bool> hidden;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    hidden.value = ref.watch(windowChromeControllerProvider).chromeHidden;
    return child;
  }
}

/// 通过真实路由 push 挂载幻灯片页（复现生产入场过渡），并以探针暴露
/// 沉浸租约状态。
Future<void> _pumpSlideshowViaPush(
  WidgetTester tester,
  List<PhotoItem> photos,
  ValueNotifier<bool> chromeHidden,
) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        photoCenterControllerProvider.overrideWith(
          () => _FakePhotoCenterController(),
        ),
        photoRepositoryProvider.overrideWithValue(_StubPhotoRepository(photos)),
      ],
      child: _WindowChromeProbe(
        hidden: chromeHidden,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: Builder(
            builder:
                (context) => Center(
                  child: TextButton(
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            settings: const RouteSettings(
                              name: 'slideshow-push',
                            ),
                            builder:
                                (_) => PhotoSlideshowPage(
                                  photos: photos,
                                  source: PhotoBrowseSource.library,
                                ),
                          ),
                        ),
                    child: const Text('open-slideshow'),
                  ),
                ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 幻灯片图层树中不允许出现 opacity=0 的 RawImage 祖先（黑屏回归断言）。
void _expectNoTransparentLayer(WidgetTester tester) {
  final opacities =
      tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.byType(RawImage),
              matching: find.byType(Opacity),
            ),
          )
          .map((widget) => widget.opacity)
          .toList();
  expect(opacities, isNotEmpty);
  expect(
    opacities.where((value) => value == 0),
    isEmpty,
    reason: '静止帧存在 opacity=0 的图层，页面将渲染为黑屏',
  );
}

/// 与页面一致的 preview 档解码宽(dpr1、窗口宽回退 1280;绑定显示器尺寸)。
int get _previewDecodeWidth =>
    SlideshowImageCache.previewDecodeWidthFor(dpr: 1, fallbackWidth: 1280);

/// preview 档位图是否已渲染:引擎不放大解码,实际宽为 min(目标宽, 源图 1300)。
bool _hasPreviewTierImage(WidgetTester tester) {
  final expectedWidth =
      _previewDecodeWidth >= 1300 ? 1300 : _previewDecodeWidth;
  return tester
      .widgetList<RawImage>(find.byType(RawImage))
      .any((widget) => widget.image?.width == expectedWidth);
}

void main() {
  testWidgets('首图解码完成后静止帧完全不透明且渐进升级为高清档', (tester) async {
    _mockPathProvider();
    final photos = [_photoWithUrl('photo-1'), _photoWithUrl('photo-2')];
    await _mockNetworkImages(() async {
      await _warmImageCache(tester, [
        (photos[0], ImageQuality.thumbnail, 400),
        (photos[0], ImageQuality.preview, _previewDecodeWidth),
        (photos[1], ImageQuality.thumbnail, 400),
        (photos[1], ImageQuality.preview, _previewDecodeWidth),
      ]);
      await _pumpSlideshow(tester, photos);
      await tester.pump();

      expect(find.byType(RawImage), findsWidgets);
      _expectNoTransparentLayer(tester);
      // preview 升级等待入场扩缩动画结束（大图首绘避让原生吸附恢复期）。
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(_hasPreviewTierImage(tester), isTrue);
    });
  });

  testWidgets('自动切换完成后的静止帧保持完全不透明并推进计数', (tester) async {
    _mockPathProvider();
    final photos = [_photoWithUrl('photo-1'), _photoWithUrl('photo-2')];
    await _mockNetworkImages(() async {
      await _warmImageCache(tester, [
        (photos[0], ImageQuality.thumbnail, 400),
        (photos[0], ImageQuality.preview, _previewDecodeWidth),
        (photos[1], ImageQuality.thumbnail, 400),
        (photos[1], ImageQuality.preview, _previewDecodeWidth),
      ]);
      await _pumpSlideshow(tester, photos);
      await tester.pump();
      _expectNoTransparentLayer(tester);

      // 推进 5 秒触发自动切换。切换链路（缓存命中回调、过渡 ticker 启动、
      // completed 状态回调）跨多帧推进：先泵到计数更新，再泵到离场层移除。
      await tester.pump(const Duration(seconds: 5));
      for (var i = 0; i < 40 && find.text('02 / 02').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('02 / 02'), findsOneWidget);
      bool transitionDone() =>
          find.byType(SlideshowSlideLayer).evaluate().length <= 1;
      for (var i = 0; i < 40 && !transitionDone(); i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // 过渡完成回调里的 setState 需要一帧重建，清掉离场层后静止帧必须完全不透明。
      await tester.pump();
      expect(transitionDone(), isTrue);
      _expectNoTransparentLayer(tester);
    });
  });

  testWidgets('桌面顶栏：关闭居左、页码居中、操作组居右', (tester) async {
    _mockPathProvider();
    final photos = [_photoWithUrl('photo-1'), _photoWithUrl('photo-2')];
    await _pumpSlideshow(tester, photos);
    await tester.pump();
    await tester.pump();

    final closeDx = tester.getCenter(find.byIcon(Icons.close_rounded)).dx;
    final counterDx = tester.getCenter(find.text('01 / 02')).dx;
    final fullscreenDx =
        tester.getCenter(find.byIcon(Icons.fullscreen_rounded)).dx;

    expect(closeDx, lessThan(counterDx));
    expect(counterDx, lessThan(fullscreenDx));
    // 页码应大致落在画面水平中心附近（三区布局）。
    expect((counterDx - 640).abs(), lessThan(48));
  });

  testWidgets('点击画面中心切换控件显隐，再次点击恢复显示', (tester) async {
    _mockPathProvider();
    final photos = [_photoWithUrl('photo-1'), _photoWithUrl('photo-2')];
    await _pumpSlideshow(tester, photos);
    await tester.pump();
    await tester.pump();

    bool topBarVisible() {
      final opacity =
          tester
              .widgetList<AnimatedOpacity>(
                find.ancestor(
                  of: find.byIcon(Icons.close_rounded),
                  matching: find.byType(AnimatedOpacity),
                ),
              )
              .firstOrNull;
      return opacity != null && opacity.opacity == 1.0;
    }

    expect(topBarVisible(), isTrue);

    await tester.tapAt(const Offset(640, 400));
    // 播放中进度动画常驻，不可 pumpAndSettle；固定时长推进淡出动画。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(topBarVisible(), isFalse);

    await tester.tapAt(const Offset(640, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(topBarVisible(), isTrue);
  });

  testWidgets('控件已显示时悬停只刷新空闲计时，不打断进度条', (tester) async {
    _mockPathProvider();
    final photos = [_photoWithUrl('photo-1'), _photoWithUrl('photo-2')];
    await _mockNetworkImages(() async {
      await _warmImageCache(tester, [
        (photos[0], ImageQuality.thumbnail, 400),
        (photos[0], ImageQuality.preview, _previewDecodeWidth),
        (photos[1], ImageQuality.thumbnail, 400),
        (photos[1], ImageQuality.preview, _previewDecodeWidth),
      ]);
      await _pumpSlideshow(tester, photos);
      await tester.pump();
      await tester.pump();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: const Offset(640, 200));
      await tester.pump();

      // Repeated hover must not rebuild chrome (was setState on every move).
      final topBarFinder = find.byType(PhotoSlideshowTopBar);
      final topBarBefore = tester.widget<PhotoSlideshowTopBar>(topBarFinder);
      for (var i = 0; i < 20; i++) {
        await gesture.moveTo(Offset(640.0 + i, 200.0));
        await tester.pump(const Duration(milliseconds: 8));
      }
      final topBarAfter = tester.widget<PhotoSlideshowTopBar>(topBarFinder);

      expect(identical(topBarBefore, topBarAfter), isTrue);
      expect(tester.takeException(), isNull);
      expect(find.byType(LinearProgressIndicator), findsWidgets);
    });
  });

  testWidgets('原生沉浸租约等路由入场过渡完成后才申请', (tester) async {
    _mockPathProvider();
    final photos = [_photoWithUrl('photo-1')];
    final chromeHidden = ValueNotifier<bool>(false);
    addTearDown(chromeHidden.dispose);
    await _mockNetworkImages(() async {
      await _warmImageCache(tester, [
        (photos[0], ImageQuality.thumbnail, 400),
        (photos[0], ImageQuality.preview, _previewDecodeWidth),
      ]);
      await _pumpSlideshowViaPush(tester, photos, chromeHidden);
      await tester.tap(find.text('open-slideshow'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(chromeHidden.value, isFalse, reason: '路由过渡未完成不得申请沉浸租约');
      // 过渡时长随平台/主题而异，用状态探测推进到过渡完成，不硬编码时长。
      for (var i = 0; i < 20 && chromeHidden.value == false; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(chromeHidden.value, isTrue, reason: '路由过渡完成后应申请沉浸租约');
    });
  });

  testWidgets('桌面端吸附前先压暗到全黑并在全屏首帧后淡回', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    _mockPathProvider();
    final photos = [_photoWithUrl('photo-1')];
    final chromeHidden = ValueNotifier<bool>(false);
    addTearDown(chromeHidden.dispose);
    try {
      await _mockNetworkImages(() async {
        await _warmImageCache(tester, [
          (photos[0], ImageQuality.thumbnail, 400),
          (photos[0], ImageQuality.preview, _previewDecodeWidth),
        ]);
        await _pumpSlideshowViaPush(tester, photos, chromeHidden);
        await tester.tap(find.text('open-slideshow'));
        await tester.pump();
        await tester.pump();

        final dipFinder = find.byKey(slideshowDipOverlayKey);
        expect(dipFinder, findsOneWidget, reason: '桌面端应挂黑场遮罩');
        double dipOpacity() =>
            tester.widget<FadeTransition>(dipFinder).opacity.value;

        // 路由过渡期内：黑场未启动。
        expect(chromeHidden.value, isFalse);
        expect(dipOpacity(), 0);

        // 推进到吸附发生的那一帧：吸附必须落在黑场底部（压暗已完成），
        // 否则原生交换链重建的黑帧会裸露。
        double? dipAtSnap;
        for (var i = 0; i < 200 && chromeHidden.value == false; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (chromeHidden.value) {
            dipAtSnap = dipOpacity();
          }
        }
        expect(chromeHidden.value, isTrue, reason: '压暗完成后应申请沉浸租约');
        expect(dipAtSnap, isNotNull);
        expect(dipAtSnap!, greaterThan(0.95), reason: '吸附发生在黑场未满时，交换链重建黑帧会裸露');

        // 全屏首帧后黑场反向淡回透明：必须是多帧渐变。曾出现淡入被
        // 表面重建吞掉、黑场"一瞬间直接消失"的观感问题。
        final samples = <double>[];
        for (var i = 0; i < 40 && dipOpacity() > 0; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          samples.add(dipOpacity());
        }
        expect(dipOpacity(), 0, reason: '内容应在全屏上淡回，黑场退回透明');
        expect(
          samples.where((value) => value > 0 && value < 1).length,
          greaterThanOrEqualTo(2),
          reason: '黑场淡回应有多个中间帧，而非一帧内直接消失',
        );
        expect(tester.takeException(), isNull);
      });
    } finally {
      // 框架在测试体结束前校验 foundation 调试变量已复位，不可只用 tearDown。
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('非桌面端不引入黑场遮罩', (tester) async {
    _mockPathProvider();
    final photos = [_photoWithUrl('photo-1')];
    final chromeHidden = ValueNotifier<bool>(false);
    addTearDown(chromeHidden.dispose);
    await _mockNetworkImages(() async {
      await _pumpSlideshowViaPush(tester, photos, chromeHidden);
      await tester.tap(find.text('open-slideshow'));
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(slideshowDipOverlayKey),
        findsNothing,
        reason: '非桌面端无原生窗口几何切换，不应插入黑场',
      );
    });
  });

  testWidgets('路由过渡期内退出不申请沉浸租约', (tester) async {
    _mockPathProvider();
    final photos = [_photoWithUrl('photo-1')];
    final chromeHidden = ValueNotifier<bool>(false);
    addTearDown(chromeHidden.dispose);
    await _mockNetworkImages(() async {
      await _warmImageCache(tester, [
        (photos[0], ImageQuality.thumbnail, 400),
        (photos[0], ImageQuality.preview, _previewDecodeWidth),
      ]);
      await _pumpSlideshowViaPush(tester, photos, chromeHidden);
      await tester.tap(find.text('open-slideshow'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(chromeHidden.value, isFalse, reason: '过渡期退出的页面不得申请沉浸租约');
    });
  });

  testWidgets('加载层以模糊封面打底而非纯黑', (tester) async {
    _mockPathProvider();
    final photos = [_photoWithUrl('photo-1')];
    final chromeHidden = ValueNotifier<bool>(false);
    addTearDown(chromeHidden.dispose);
    await _mockNetworkImages(() async {
      await _pumpSlideshowViaPush(tester, photos, chromeHidden);
      await tester.tap(find.text('open-slideshow'));
      // 指针派发后路由内容在第二帧进树；此刻处于 loading 阶段：
      // 有封面时必须由模糊封面占满画面，不得出现纯黑内容真空。
      await tester.pump();
      await tester.pump();
      expect(find.byType(SlideshowLoadingStage), findsOneWidget);
      expect(find.byType(SlideshowBlurredCover), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('缩略图条瓦片按瓦片尺寸解码而非全分辨率', (tester) async {
    final photos = [for (var i = 1; i <= 6; i++) _photoWithUrl('photo-$i')];
    // 独立挂载缩略图条：只断言解码宽度声明，不经过页面 bootstrap。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlideshowThumbnailStrip(
            photos: photos,
            current: 0,
            onTap: (_) {},
          ),
        ),
      ),
    );

    final tiles = find.descendant(
      of: find.byType(SlideshowThumbnailStrip),
      matching: find.byType(CachedNetworkImage),
    );
    expect(tiles, findsWidgets);
    final expected = thumbnailDecodeWidth(72, tester.view.devicePixelRatio);
    for (final widget in tester.widgetList<CachedNetworkImage>(tiles)) {
      expect(
        widget.memCacheWidth,
        expected,
        reason: '瓦片未按 72px 瓦片宽解码，将按全分辨率解码封面',
      );
    }
  });
}
