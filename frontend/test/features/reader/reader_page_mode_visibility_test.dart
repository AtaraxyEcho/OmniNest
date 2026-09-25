import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/domain/comic_reader_display_settings.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_reader_settings_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 产品决策 D3：Web 只开放滚动模式，隐藏翻页入口。
void main() {
  ReaderViewSettings settings() =>
      ReaderViewSettings(readingMode: 'scroll', paletteId: 'dark');

  const comicSettings = ComicReaderDisplaySettings(readingMode: 'scroll');

  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(body: child),
    );
  }

  testWidgets('原生提供翻页：显示滚动与翻页', (tester) async {
    await tester.pumpWidget(
      wrap(
        ReaderViewSettingsPanel(
          settings: settings(),
          onSettingsChanged: (_) {},
          embedded: true,
          pageModeEnabled: true,
        ),
      ),
    );
    expect(find.text('滑动'), findsWidgets);
    expect(find.text('左右滑动'), findsWidgets);
  });

  testWidgets('Web 禁止翻页：隐藏阅读模式切换', (tester) async {
    await tester.pumpWidget(
      wrap(
        ReaderViewSettingsPanel(
          settings: settings(),
          onSettingsChanged: (_) {},
          embedded: true,
          pageModeEnabled: false,
        ),
      ),
    );
    expect(find.text('左右滑动'), findsNothing);
    expect(find.text('滑动'), findsNothing);
  });

  testWidgets('漫画设置在 Web 禁止翻页：隐藏翻页分段', (tester) async {
    await tester.pumpWidget(
      wrap(
        ComicReaderSettingsPanel(
          displaySettings: comicSettings,
          themeSettings: settings(),
          onChanged: (_) {},
          volumeKeyPaging: false,
          onVolumeKeyPagingChanged: (_) {},
          pageModeEnabled: false,
        ),
      ),
    );
    expect(find.text('翻页模式'), findsNothing);
  });

  testWidgets('漫画设置在原生显示翻页分段', (tester) async {
    await tester.pumpWidget(
      wrap(
        ComicReaderSettingsPanel(
          displaySettings: comicSettings,
          themeSettings: settings(),
          onChanged: (_) {},
          volumeKeyPaging: false,
          onVolumeKeyPagingChanged: (_) {},
          pageModeEnabled: true,
        ),
      ),
    );
    expect(find.text('翻页模式'), findsOneWidget);
  });
}
