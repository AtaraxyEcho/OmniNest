import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/portal/presentation/widgets/reading_progress_widget.dart';
import 'package:omninest/features/reader/application/reader_image_provider.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_image.dart';

void main() {
  testWidgets('继续使用阅读进度卡走 AuthCoverImage，不用接口路径当图片地址', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coverBytesProvider.overrideWith((ref, itemId) async => null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: ReadingProgressWidget(
              item: ReaderItem(
                id: 'reader-1',
                title: '测试书',
                itemType: 'EPUB',
                updatedAt: DateTime(2026, 9, 1),
                // 后端真实形态：接口路径而非可直渲图片 URL。
                coverUrl: '/files/cover-file-1/download-url',
                progressPercent: 42,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试书'), findsWidgets);
    expect(find.byType(AuthCoverImage), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
