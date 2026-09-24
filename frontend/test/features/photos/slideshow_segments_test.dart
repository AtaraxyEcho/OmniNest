import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_slideshow_overlays.dart';

Future<void> _pumpSegments(
  WidgetTester tester, {
  required int count,
  required double width,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SlideshowSegments(
              count: count,
              current: 2,
              isPlaying: false,
              progress: ValueNotifier<double>(0.5),
              onTap: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('可逐格上限按每格 36dp 推导并夹在 4..12', () {
    // 250/1300 只是示例宽度，用于钉住推导与上下限。
    expect(SlideshowSegments.maxTickCount(250), 7);
    expect(SlideshowSegments.maxTickCount(1300), 12);
    expect(SlideshowSegments.maxTickCount(double.infinity), 12);
    expect(SlideshowSegments.maxTickCount(100), 4);
  });

  testWidgets('上限内仍逐张一格且无序号文本', (tester) async {
    await _pumpSegments(tester, count: 6, width: 250);

    expect(find.byType(GestureDetector), findsNWidgets(6));
    expect(find.byType(LinearProgressIndicator), findsNWidgets(6));
    expect(find.text('第 3 / 共 6 张'), findsNothing);
  });

  testWidgets('超过上限退化为单条进度并显示序号', (tester) async {
    await _pumpSegments(tester, count: 40, width: 250);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('第 3 / 共 40 张'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('千张规模下构建成本与照片数无关', (tester) async {
    await _pumpSegments(tester, count: 1000, width: 250);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.text('第 3 / 共 1000 张'), findsOneWidget);
  });
}
