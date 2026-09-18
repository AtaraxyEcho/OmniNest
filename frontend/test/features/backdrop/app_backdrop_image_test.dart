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
      fallbackAsset: bundledDefaultWallpaperPosterAsset,
    );
    // placeholder 为深色 ColoredBox,不得出现默认壁纸 Image.asset。
    expect(
      find.image(const AssetImage(bundledDefaultWallpaperPosterAsset)),
      findsNothing,
    );
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('fallbackAsset 为空时失败态只显示深色底', (tester) async {
    await pumpBackdrop(tester, url: '', fallbackAsset: null);
    expect(
      find.image(const AssetImage(bundledDefaultWallpaperPosterAsset)),
      findsNothing,
    );
    expect(find.byType(ColoredBox), findsWidgets);
  });

  testWidgets('url 为空时使用 fallbackAsset(内置默认壁纸场景)', (tester) async {
    await pumpBackdrop(
      tester,
      url: '',
      fallbackAsset: bundledDefaultWallpaperPosterAsset,
    );
    expect(
      find.image(const AssetImage(bundledDefaultWallpaperPosterAsset)),
      findsOneWidget,
    );
  });
}
