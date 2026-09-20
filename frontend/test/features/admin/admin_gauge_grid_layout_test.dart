import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_redesign_components.dart';

void main() {
  testWidgets('系统监控仪表环使用统一网格布局且不抛异常', (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: AdminMonitoringPage(
              view: AdminMonitoringView(
                overview: AdminMonitoringOverview(
                  status: 'UP',
                  uptime: '1d',
                  cpuUsage: 12,
                  memoryUsage: 34,
                  diskUsage: 56,
                  jvmHeapUsage: 22,
                  activeTasks: 0,
                  queueDepth: 0,
                  todayRequests: 10,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdminGaugeGrid), findsOneWidget);
    expect(find.byType(AdminGaugeRing), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
