import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/application/reader_image_provider.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_cover.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_image.dart';

/// 封面卡渲染契约：真实封面整卡纯净渲染（不叠加书脊/字标/标题），
/// 无封面与拉取失败退化为生成式封面（书脊 + 字标 + 标题作者）。
void main() {
  // 1x1 透明 PNG。
  final pngBytes = Uint8List.fromList(const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  ReaderItem item({String? coverUrl}) => ReaderItem(
    id: 'reader-1',
    title: '测试书',
    authorName: '测试作者',
    itemType: 'EPUB',
    contentKind: 'TEXT',
    coverUrl: coverUrl,
    updatedAt: null,
  );

  Future<void> pumpCover(
    WidgetTester tester, {
    required ReaderItem item,
    required ReaderCoverSize size,
    required Uint8List? Function(dynamic ref, String itemId) coverOverride,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coverBytesProvider.overrideWith(
            (ref, itemId) async => coverOverride(ref, itemId),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 170,
                child: ReaderBookCover(item: item, size: size),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('真实封面整卡纯净渲染：不叠加标题文字', (tester) async {
    await pumpCover(
      tester,
      item: item(coverUrl: '/files/cover-file-1/download-url'),
      size: ReaderCoverSize.grid,
      coverOverride: (ref, itemId) => pngBytes,
    );

    expect(find.byType(AuthCoverImage), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('测试书'), findsNothing);
    expect(find.text('测试作者'), findsNothing);
  });

  testWidgets('无封面走生成式封面：书脊字标与标题作者齐备', (tester) async {
    await pumpCover(
      tester,
      item: item(coverUrl: null),
      size: ReaderCoverSize.grid,
      coverOverride: (ref, itemId) => null,
    );

    expect(find.byType(AuthCoverImage), findsNothing);
    expect(find.text('测试书'), findsOneWidget);
    expect(find.text('测试作者'), findsOneWidget);
  });

  testWidgets('封面拉取失败退化为生成式封面观感', (tester) async {
    await pumpCover(
      tester,
      item: item(coverUrl: '/files/cover-file-1/download-url'),
      size: ReaderCoverSize.grid,
      coverOverride: (ref, itemId) => null,
    );

    expect(find.byType(AuthCoverImage), findsOneWidget);
    expect(find.text('测试书'), findsOneWidget);
  });

  testWidgets('row 尺寸生成封面不显示标题（回归守卫）', (tester) async {
    await pumpCover(
      tester,
      item: item(coverUrl: null),
      size: ReaderCoverSize.row,
      coverOverride: (ref, itemId) => null,
    );

    expect(find.text('测试书'), findsNothing);
  });
}
