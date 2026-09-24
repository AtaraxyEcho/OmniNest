import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/data/music_cover_cache.dart';
import 'package:omninest/features/portal/application/portal_dashboard_providers.dart';
import 'package:omninest/features/portal/domain/portal_focus_models.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_media_thumbnail.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_visual_widgets.dart';

/// Portal 封面自愈接线回归：
/// hero 大卡与预览网格此前与胶片条不同构——既无稳定 cacheKey，也无
/// 失效回调，签名 URL 一次性失败后永久降级（黑块/占位格）。
void main() {
  group('PortalDashboardActions.sectionFor', () {
    test('封面分区模块映射到对应可重签分区', () {
      expect(
        PortalDashboardActions.sectionFor(PortalFocusModule.video),
        PortalDashboardSection.video,
      );
      expect(
        PortalDashboardActions.sectionFor(PortalFocusModule.photos),
        PortalDashboardSection.photos,
      );
      expect(
        PortalDashboardActions.sectionFor(PortalFocusModule.music),
        PortalDashboardSection.music,
      );
      expect(
        PortalDashboardActions.sectionFor(PortalFocusModule.reader),
        PortalDashboardSection.reader,
      );
    });

    test('无封面语义的模块返回 null', () {
      expect(
        PortalDashboardActions.sectionFor(PortalFocusModule.files),
        isNull,
      );
      expect(
        PortalDashboardActions.sectionFor(PortalFocusModule.weather),
        isNull,
      );
      expect(
        PortalDashboardActions.sectionFor(PortalFocusModule.tasks),
        isNull,
      );
      expect(
        PortalDashboardActions.sectionFor(PortalFocusModule.admin),
        isNull,
      );
    });
  });

  group('PortalGradientCover hero 路径', () {
    testWidgets('非直连分支传递稳定 cacheKey 并约束解码宽度', (tester) async {
      late PortalVisualPalette palette;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  palette = PortalVisualPalette.of(context);
                  return SizedBox(
                    width: 400,
                    height: 540,
                    child: PortalGradientCover(
                      palette: palette,
                      title: 't',
                      subtitle: 's',
                      imageUrl: 'http://localhost:1/cover.jpg',
                      coverCacheKey: 'portal-cover:photos:p1',
                      directImage: false,
                      showTextOverlay: false,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      final images =
          tester
              .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
              .toList();
      expect(images, isNotEmpty);
      for (final image in images) {
        expect(image.cacheKey, 'portal-cover:photos:p1');
      }
      // 前景层有量化解码上限，不再整图分辨率解码。
      expect(images.any((image) => image.memCacheWidth != null), isTrue);
    });
  });

  group('PortalMediaThumbnail', () {
    Widget wrap(Widget child) =>
        ProviderScope(child: MaterialApp(home: Scaffold(body: child)));

    testWidgets('空 URL 直接降级且不构建网络图', (tester) async {
      await tester.pumpWidget(
        wrap(
          const PortalMediaThumbnail(
            imageUrl: null,
            fallback: SizedBox(key: Key('fallback')),
          ),
        ),
      );
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byKey(const Key('fallback')), findsOneWidget);
    });

    testWidgets('cacheKey 透传给 CachedNetworkImage', (tester) async {
      await tester.pumpWidget(
        wrap(
          const PortalMediaThumbnail(
            imageUrl: 'http://localhost:1/cover.jpg',
            cacheKey: 'portal-preview:photos:p1',
            fallback: SizedBox.shrink(),
          ),
        ),
      );
      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.cacheKey, 'portal-preview:photos:p1');
      // 签名直链不接管缓存：沿用默认缓存路径，行为与历史一致。
      expect(image.cacheManager, isNull);
    });

    testWidgets('本地音乐封面 API 路径接鉴权缓存管理器', (tester) async {
      // 注入下载客户端后，音乐专域管理器才会存在；这里走生产映射，
      // 断言门户确实把它交给了 CachedNetworkImage（否则相对路径与 401 会让 hero 永久降级）。
      MusicCoverCache.configure(Dio());
      await tester.pumpWidget(
        wrap(
          const PortalMediaThumbnail(
            imageUrl: '/api/v1/music/covers/track-cover-1/thumbnail',
            cacheKey: 'portal-preview:music:t1',
            fallback: SizedBox.shrink(),
          ),
        ),
      );
      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.cacheManager, isNotNull);
    });
  });
}
