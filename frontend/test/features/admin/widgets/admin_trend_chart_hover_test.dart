import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_trend_charts.dart';

List<DailyTaskMetric> _barData() {
  return <DailyTaskMetric>[
    for (var i = 0; i < 7; i++)
      DailyTaskMetric(
        date: '2026-09-${(23 + i).toString().padLeft(2, '0')}',
        completed: 40 + i * 6,
        failed: i % 3,
        running: 2,
      ),
  ];
}

List<AdminChartPoint> _linePoints() {
  return <AdminChartPoint>[
    for (var i = 0; i < 7; i++)
      AdminChartPoint(
        date: '2026-09-${(23 + i).toString().padLeft(2, '0')}',
        value: (8 + i).toDouble(),
      ),
  ];
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: OmniNestTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(body: SizedBox(width: 600, height: 220, child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<TestGesture> _mouseAt(WidgetTester tester, Offset position) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: position);
  await tester.pump();
  await gesture.moveTo(position);
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets('吞吐柱状图悬停出现直角浮牌与数值，移出清除', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    await _pump(
      tester,
      AdminThroughputBarChart(data: _barData(), semanticsLabel: '任务吞吐趋势'),
    );

    // 悬停前无浮牌。
    expect(find.text('2026-09-26'), findsNothing);

    // 指针移到图表中部：600 宽 7 柱，x=300 命中第 4 柱（2026-09-26）。
    final gesture = await _mouseAt(tester, const Offset(300, 100));
    expect(find.text('2026-09-26'), findsOneWidget);
    expect(find.text('完成 58'), findsOneWidget);
    expect(find.text('失败 0'), findsOneWidget);
    expect(find.text('运行 2'), findsOneWidget);
    // Semantics 标签随悬停同步当前柱数值。
    expect(
      find.bySemanticsLabel('任务吞吐趋势, 2026-09-26, 完成 58, 失败 0, 运行 2'),
      findsOneWidget,
    );

    // 移出绘图区后浮牌清除，语义标签回落到基础描述。
    await gesture.moveTo(const Offset(300, 500));
    await tester.pump();
    expect(find.text('2026-09-26'), findsNothing);
    expect(find.text('完成 58'), findsNothing);
    expect(find.bySemanticsLabel('任务吞吐趋势'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semanticsHandle.dispose();
  });

  testWidgets('细线折线图悬停显示日期与数值，移出清除', (tester) async {
    await _pump(
      tester,
      AdminHairlineLineChart(
        points: _linePoints(),
        valueFormatter: (value) => value.round().toString(),
      ),
    );

    expect(find.text('2026-09-26'), findsNothing);

    // x=300 → 最近点索引 round(300/600*6)=3，即 2026-09-26、数值 11。
    final gesture = await _mouseAt(tester, const Offset(300, 100));
    expect(find.text('2026-09-26'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);

    await gesture.moveTo(const Offset(300, 500));
    await tester.pump();
    expect(find.text('2026-09-26'), findsNothing);
    expect(find.text('11'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
