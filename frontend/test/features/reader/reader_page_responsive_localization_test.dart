import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/comic_detail_page.dart';

void main() {
  const comic = ReaderItem(
    id: 'comic-1',
    title: 'Sample Comic',
    itemType: 'CBZ',
    contentKind: 'COMIC',
    authorName: 'Sample Author',
    progressPercent: 0.42,
    rating: 8.5,
    updatedAt: null,
  );

  for (final entry in const [
    (width: 390.0, brightness: Brightness.dark),
    (width: 1280.0, brightness: Brightness.light),
  ]) {
    testWidgets('漫画详情在 ${entry.width.toInt()} 宽度和 2.0 文字缩放下无裁切', (
      tester,
    ) async {
      await _setViewport(tester, width: entry.width, height: 1100);
      await tester.pumpWidget(
        _TestApp(
          brightness: entry.brightness,
          textScaler: const TextScaler.linear(2),
          child: const ComicDetailPage(item: comic, canRead: false),
        ),
      );
      await tester.pump();

      // Hero 标题与封面叠字各渲染一次标题。
      expect(find.text('Sample Comic'), findsNWidgets(2));
      expect(find.text('Continue Reading'), findsOneWidget);
      expect(_visibleText(tester), isNot(matches(RegExp(r'[\u4e00-\u9fff]'))));
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _setViewport(
  WidgetTester tester, {
  required double width,
  required double height,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

String _visibleText(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
      .join('\n');
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.child,
    this.brightness = Brightness.light,
    this.textScaler = TextScaler.noScaling,
  });

  final Widget child;
  final Brightness brightness;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme:
            brightness == Brightness.dark
                ? OmniNestTheme.dark()
                : OmniNestTheme.light(),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          );
        },
        home: Scaffold(body: child),
      ),
    );
  }
}
