import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';
import 'package:omninest/features/tasks/task_ui.dart';

Future<void> _pumpButton(WidgetTester tester, ActiveTaskSummary summary) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeTaskSummaryProvider.overrideWith((ref) async => summary),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        // 入口读取 globalColors 令牌，必须带应用主题。
        theme: OmniNestTheme.light(),
        home: const Scaffold(body: Center(child: TaskActivityButton())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('无进行中与失败任务时不占顶栏位', (tester) async {
    await _pumpButton(
      tester,
      const ActiveTaskSummary(activeCount: 0, failedCount: 0),
    );

    expect(find.byIcon(Icons.pending_actions_rounded), findsNothing);
  });

  testWidgets('有进行中任务时出现入口并显示计数', (tester) async {
    await _pumpButton(
      tester,
      const ActiveTaskSummary(activeCount: 2, failedCount: 0),
    );

    expect(find.byIcon(Icons.pending_actions_rounded), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('存在失败任务时改显失败数', (tester) async {
    await _pumpButton(
      tester,
      const ActiveTaskSummary(activeCount: 3, failedCount: 1),
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });
}
