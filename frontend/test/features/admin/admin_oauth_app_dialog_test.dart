import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/app/widgets/app_dropdown.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/data/admin_operations_api.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_redesign_components.dart';

class _MockAdminOperationsApi extends Mock implements AdminOperationsApi {}

const _savedApp = AdminConnectorOAuthApp(
  id: 'app-1',
  connectorCode: 'DROPBOX',
  clientId: 'client-id',
  redirectUri: 'https://cb.example/oauth',
  enabled: true,
  updatedAt: '2026-09-19T00:00:00Z',
);

Future<void> _pumpExternalStoragePage(
  WidgetTester tester,
  _MockAdminOperationsApi api,
) async {
  when(() => api.listConnectorOAuthApps()).thenAnswer((_) async => const []);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminOperationsApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: AdminExternalStoragePage(
              view: AdminExternalStorageView(items: []),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const AdminConnectorOAuthApp(
        id: '',
        connectorCode: '',
        clientId: '',
        redirectUri: '',
        enabled: false,
        updatedAt: '',
      ),
    );
  });

  testWidgets('OAuth 类型为下拉框：默认 OneDrive，可选 Dropbox 并按所选编码保存', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _MockAdminOperationsApi();
    when(
      () => api.saveConnectorOAuthApp(
        connectorCode: any(named: 'connectorCode'),
        clientId: any(named: 'clientId'),
        clientSecret: any(named: 'clientSecret'),
        redirectUri: any(named: 'redirectUri'),
        enabled: any(named: 'enabled'),
      ),
    ).thenAnswer((_) async => _savedApp);
    await _pumpExternalStoragePage(tester, api);
    await _openDialog(tester);

    // 类型字段是下拉框而非自由文本，旧版 ONEDRIVE 预填文本不再出现。
    final dropdownFinder = find.byWidgetPredicate(
      (widget) => widget is AppDropdown<String>,
    );
    expect(dropdownFinder, findsOneWidget);
    expect(find.text('OneDrive'), findsOneWidget);
    expect(find.text('ONEDRIVE'), findsNothing);

    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dropbox'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '客户端 ID'),
      'client-id',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '重定向 URI'),
      'https://cb.example/oauth',
    );
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('保存')),
    );
    await tester.pumpAndSettle();

    final codes =
        verify(
          () => api.saveConnectorOAuthApp(
            connectorCode: captureAny(named: 'connectorCode'),
            clientId: any(named: 'clientId'),
            clientSecret: any(named: 'clientSecret'),
            redirectUri: any(named: 'redirectUri'),
            enabled: any(named: 'enabled'),
          ),
        ).captured;
    expect(codes.single, 'DROPBOX');
    // 保存后对话框关闭，退场动画结束后不触发控制器 disposed 断言或布局异常。
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OAuth 对话框取消关闭不残留异常', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _MockAdminOperationsApi();
    await _pumpExternalStoragePage(tester, api);
    await _openDialog(tester);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    verifyNever(
      () => api.saveConnectorOAuthApp(
        connectorCode: any(named: 'connectorCode'),
        clientId: any(named: 'clientId'),
        clientSecret: any(named: 'clientSecret'),
        redirectUri: any(named: 'redirectUri'),
        enabled: any(named: 'enabled'),
      ),
    );
  });

  testWidgets('系统正常（UP）时监控页头部胶囊为绿色，WARN 组件为琥珀而非红色', (tester) async {
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
        home: const Scaffold(
          body: SingleChildScrollView(
            child: AdminMonitoringPage(
              view: AdminMonitoringView(
                overview: AdminMonitoringOverview(
                  status: 'UP',
                  uptime: '1d 0h 0m',
                  cpuUsage: 5,
                  memoryUsage: 40,
                  diskUsage: 30,
                  jvmHeapUsage: 50,
                  activeTasks: 0,
                  queueDepth: 0,
                  todayRequests: 10,
                ),
                components: [
                  AdminMonitoringComponent(
                    name: 'PostgreSQL',
                    status: 'UP',
                    detail: <String, dynamic>{'状态': 'UP'},
                  ),
                  AdminMonitoringComponent(
                    name: 'ClamAV',
                    status: 'WARN',
                    detail: <String, dynamic>{'状态': 'WARN'},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final adminColors = AdminColors.of(tester.element(find.text('运行正常')));
    Color? pillColor(String label) {
      final boxes = tester.widgetList<DecoratedBox>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(DecoratedBox),
        ),
      );
      for (final box in boxes) {
        final decoration = box.decoration;
        if (decoration is BoxDecoration && decoration.color != null) {
          return decoration.color;
        }
      }
      return null;
    }

    // 系统正常但存在 WARN 组件（如 ClamAV 未启用）时，头部胶囊必须保持绿色。
    expect(pillColor('运行正常'), adminColors.success.withValues(alpha: 0.14));
    // WARN 是警告语义，用琥珀色而非红色。
    expect(pillColor('WARN'), adminColors.warning.withValues(alpha: 0.14));
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务健康瓦片：UP 为绿色，WARN 为琥珀色', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: Column(
            children: [
              AdminServiceTile(name: '数据库', status: 'UP', detail: 'UP'),
              AdminServiceTile(name: '病毒防护', status: 'WARN', detail: 'WARN'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final adminColors = AdminColors.of(tester.element(find.text('数据库')));
    final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
    final upIcon = icons.firstWhere(
      (icon) => icon.icon == Icons.check_circle_rounded,
    );
    final warnIcon = icons.firstWhere(
      (icon) => icon.icon == Icons.warning_rounded,
    );
    expect(upIcon.color, adminColors.success);
    expect(warnIcon.color, adminColors.warning);
  });
}
