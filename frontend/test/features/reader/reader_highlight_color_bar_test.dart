import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_highlight_color_bar.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required String? selected,
    required ValueChanged<String> onSelect,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: Scaffold(
          body: ReaderHighlightColorBar(
            selectedColor: selected,
            onSelect: onSelect,
          ),
        ),
      ),
    );
  }

  testWidgets('五个色点均为 36dp 热区并回传颜色', (tester) async {
    String? picked;
    await pumpBar(
      tester,
      selected: '#FFEB3B',
      onSelect: (color) => picked = color,
    );

    expect(find.byTooltip('黄色高亮'), findsOneWidget);
    expect(find.byTooltip('绿色高亮'), findsOneWidget);
    expect(find.byTooltip('蓝色高亮'), findsOneWidget);
    expect(find.byTooltip('粉色高亮'), findsOneWidget);
    expect(find.byTooltip('灰色高亮'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    final green = find.byTooltip('绿色高亮');
    expect(tester.getSize(green).width, greaterThanOrEqualTo(36));
    await tester.tap(green);
    await tester.pump();
    expect(picked, '#4CAF50');
  });

  testWidgets('已有选中色时显示选中环与对勾', (tester) async {
    await pumpBar(tester, selected: '#2196F3', onSelect: (_) {});

    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
