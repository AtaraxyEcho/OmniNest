import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_redesign_components.dart';

void main() {
  testWidgets('监控页组件健康与告警使用限高滚动，不再展示操作审计', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auditItems = List<AdminAuditLog>.generate(
      20,
      (index) => AdminAuditLog(
        id: 'audit-$index',
        action: 'UPDATE_$index',
        resourceType: 'FILE',
        resourceId: 'resource-$index',
        ipAddress: '127.0.0.1',
        createdAt: '2026-08-03T12:00:00',
      ),
    );
    final components = List<AdminMonitoringComponent>.generate(
      12,
      (index) => AdminMonitoringComponent(
        name: 'component-$index',
        status: 'UP',
        detail: const <String, dynamic>{'status': 'ready'},
      ),
    );
    final alerts = List<AdminMonitoringAlert>.generate(
      10,
      (index) => AdminMonitoringAlert(
        severity: 'WARNING',
        message: 'alert-$index',
        timestamp: '2026-08-03T12:00:00',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminMonitoringPage(
              view: AdminMonitoringView(
                components: components,
                alerts: alerts,
                auditRecent: auditItems,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 操作审计已从监控页移除（日志中心已有），仅保留组件健康 + 告警两个滚动区。
    expect(find.text('最近操作记录'), findsNothing);
    expect(find.byType(Scrollbar), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  for (final scale in <double>[1.15, 1.3]) {
    testWidgets('监控页仪表环在字体档位 $scale 下不溢出', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const Scaffold(
            body: SingleChildScrollView(
              child: AdminMonitoringPage(view: AdminMonitoringView()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 重设计后：4 个仪表环（CPU/内存/磁盘/JVM）替代 3 张指标卡。
      expect(find.byType(AdminGaugeRing), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  }
}
