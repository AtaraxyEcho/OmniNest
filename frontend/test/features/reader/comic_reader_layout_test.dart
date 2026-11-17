import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/application/reader_comic_image_provider.dart';
import 'package:omninest/features/reader/data/comic_image_provider.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';
import 'package:omninest/features/reader/domain/comic_reader_display_settings.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_page_image.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_reader_layout.dart';

class _StubComicImageLoader extends Mock implements ComicImageLoader {}

void main() {
  group('ComicReaderLayout', () {
    test('移动端连续阅读使用全部可用宽度', () {
      final layout = ComicReaderLayout.resolve(
        viewport: const Size(390, 844),
        preferredContentWidth: 960,
        fullWidth: false,
      );

      expect(layout.horizontalPadding, 0);
      expect(layout.contentWidth, 390);
      expect(layout.pagedPadding, const EdgeInsets.all(8));
    });

    test('桌面端默认限制页面宽度', () {
      final layout = ComicReaderLayout.resolve(
        viewport: const Size(3840, 2160),
        preferredContentWidth: 960,
        fullWidth: false,
      );

      expect(layout.horizontalPadding, 40);
      expect(layout.contentWidth, 960);
      expect(layout.pagedPadding, const EdgeInsets.all(32));
    });

    test('桌面端全宽模式使用扣除边距后的宽度', () {
      final layout = ComicReaderLayout.resolve(
        viewport: const Size(1920, 1080),
        preferredContentWidth: 960,
        fullWidth: true,
      );

      expect(layout.contentWidth, 1840);
    });
  });

  test('漫画偏好会校验持久化数值范围', () {
    final settings = ComicReaderDisplaySettings.fromPreferences(const {
      'comicReadingMode': 'invalid',
      'comicContentWidth': 5000,
      'comicPageGap': -5,
    }, defaultReadingMode: 'scroll');

    expect(settings.readingMode, 'scroll');
    expect(settings.contentWidth, 1440);
    expect(settings.pageGap, 0);
  });

  test('音量键开关合并整张偏好后落盘', () {
    // 只传单键的 save 会把偏好字典覆盖成只剩这一项：字号、行高与漫画显示设置一起丢。
    final saved = mergeComicReaderPreferences(
      current: const {
        'fontSize': 19.0,
        'lineHeight': 1.85,
        'comicReadingMode': 'scroll',
        'comicContentWidth': 720.0,
        'volumeKeyPaging': true,
      },
      appliedDisplaySettings: const ComicReaderDisplaySettings(
        readingMode: 'scroll',
        contentWidth: 720,
      ),
      patch: const {'volumeKeyPaging': false},
    );

    expect(saved['volumeKeyPaging'], isFalse);
    expect(saved['fontSize'], 19.0, reason: '字号与主题被单键覆盖丢过一次');
    expect(saved['lineHeight'], 1.85);
    expect(saved['comicContentWidth'], 720.0);
  });

  test('防抖里未落盘的显示设置随下一次保存一起写出', () {
    // 显示设置走 320ms 防抖：音量键这次保存若不带上了它那份，防抖到点后又把
    // 用户刚调过的宽度盖回旧值。
    final saved = mergeComicReaderPreferences(
      current: const {'comicContentWidth': 960.0},
      pendingDisplaySettings: const ComicReaderDisplaySettings(
        readingMode: 'page',
        contentWidth: 640,
      ),
      appliedDisplaySettings: const ComicReaderDisplaySettings(
        readingMode: 'page',
      ),
      patch: const {'volumeKeyPaging': false},
    );

    expect(saved['comicContentWidth'], 640.0);
    expect(saved['comicReadingMode'], 'page');
    expect(saved['volumeKeyPaging'], isFalse);
  });
  group('尺寸未知页面的撑高（R5）', () {
    final loader = _StubComicImageLoader();
    // 解码与否不影响本判据：只看字节到手后外层还锁不锁 3:4。
    final bytes = Uint8List.fromList(List<int>.generate(64, (index) => index));
    setUp(() {
      registerFallbackValue('');
      when(
        () => loader.getImage(any(), any(), pageId: any(named: 'pageId')),
      ).thenAnswer((_) async => bytes);
    });

    Widget host(ComicPage page) => ProviderScope(
      overrides: [comicImageLoaderProvider.overrideWithValue(loader)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 1200,
            child: ListView(
              children: [
                SizedBox(
                  height: 1200,
                  child: ComicPageImage(
                    page: page,
                    itemId: 'item-1',
                    surfaceColor: const Color(0xFF101010),
                    layout: ComicPageImageLayout.continuous,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    testWidgets('清单没给宽高时不再套 3:4 比例盒', (tester) async {
      await tester.pumpWidget(
        host(
          const ComicPage(
            id: 'p1',
            sourceId: 's1',
            sourcePath: 'pages/1.png',
            pageIndex: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(AspectRatio),
        findsNothing,
        reason: '锁死 3:4 时长条漫画被压成盒子中央一条细线，上报的高度也是错的',
      );
    });

    testWidgets('清单给了宽高时仍按声明比例占位', (tester) async {
      await tester.pumpWidget(
        host(
          const ComicPage(
            id: 'p1',
            sourceId: 's1',
            sourcePath: 'pages/1.png',
            pageIndex: 0,
            width: 1200,
            height: 1800,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AspectRatio), findsOneWidget);
    });
  });
}
