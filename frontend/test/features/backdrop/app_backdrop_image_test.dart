import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpBackdrop(
    WidgetTester tester, {
    required String url,
    String? fallbackAsset,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: AppBackdropImage(
              url: url,
              cacheKey: 'backdrop:test',
              fit: BoxFit.cover,
              fallbackAsset: fallbackAsset,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('自定义壁纸加载占位不显示默认壁纸海报', (tester) async {
    await pumpBackdrop(
      tester,
      url: 'https://example.com/custom.jpg',
      fallbackAsset: bundledDesktopWallpaperAssetPath,
    );
    // placeholder 为深色 ColoredBox,不得出现默认壁纸 Image.asset。
    expect(
      find.image(const AssetImage(bundledDesktopWallpaperAssetPath)),
      findsNothing,
    );
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('fallbackAsset 为空时失败态只显示深色底', (tester) async {
    await pumpBackdrop(tester, url: '', fallbackAsset: null);
    expect(
      find.image(const AssetImage(bundledDesktopWallpaperAssetPath)),
      findsNothing,
    );
    expect(find.byType(ColoredBox), findsWidgets);
  });

  testWidgets('url 为空时使用 fallbackAsset(内置默认壁纸场景)', (tester) async {
    await pumpBackdrop(
      tester,
      url: '',
      fallbackAsset: bundledDesktopWallpaperAssetPath,
    );
    expect(
      find.image(const AssetImage(bundledDesktopWallpaperAssetPath)),
      findsOneWidget,
    );
  });

  testWidgets('提供预览地址时低清先行层与主图同栈渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: AppBackdropImage(
              url: 'https://example.com/full.jpg',
              cacheKey: 'backdrop:preview-test',
              fit: BoxFit.cover,
              previewUrl: 'https://example.com/thumb.jpg',
              previewCacheKey: 'backdrop-preview:preview-test',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final images = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .toList(growable: false);
    // 先行层 + 主图两层,先行层使用预览缓存键与 cover 铺满。
    expect(images, hasLength(2));
    expect(
      images.any((image) => image.cacheKey == 'backdrop-preview:preview-test'),
      isTrue,
    );
    expect(
      images.any((image) => image.cacheKey == 'backdrop:preview-test'),
      isTrue,
    );
  });

  testWidgets('无预览地址时保持单层主图', (tester) async {
    await pumpBackdrop(tester, url: 'https://example.com/single.jpg');
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });
}
