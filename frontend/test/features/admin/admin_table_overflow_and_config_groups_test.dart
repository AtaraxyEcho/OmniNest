import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/data/admin_operations_api.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_list_components.dart';

class _MockAdminOperationsApi extends Mock implements AdminOperationsApi {}

const _longDescription =
    '管理员在文件模块执行了批量重命名操作，涉及多个目录与大量文件，'
    '该描述用于验证操作内容列在宽度受限时省略并支持悬停查看完整文案'
    '为了避免测试对具体像素宽度的敏感，这里刻意填充足够长的中文内容';

AdminAuditLog _auditLog() => AdminAuditLog(
  id: 'audit-1',
  action: 'LOGIN',
  description: _longDescription,
  resourceType: 'auth',
  // 测试字体（Ahem）每字符等宽：短 IP 才能在 130px 列内完整显示。
  ipAddress: '1.1.1.1',
  createdAt: '2026-09-19T10:00:00',
);

AdminLoginAuditItem _loginAudit() => AdminLoginAuditItem(
  id: 'login-1',
  username: 'administrator-with-very-long-name@example-domain.test',
  loginResult: 'SUCCESS',
  clientPlatform: 'WEB',
  ipAddress: '127.0.0.1',
  createdAt: '2026-09-19T10:00:00',
);

Future<void> _pumpLogsPage(
  WidgetTester tester,
  _MockAdminOperationsApi api,
) async {
  when(
    () => api.logPage(
      page: any(named: 'page'),
      size: any(named: 'size'),
      action: any(named: 'action'),
      query: any(named: 'query'),
      sort: any(named: 'sort'),
      dir: any(named: 'dir'),
    ),
  ).thenAnswer(
    (_) async => AdminPage<AdminAuditLog>(
      items: [_auditLog()],
      page: 0,
      size: 10,
      totalElements: 1,
      totalPages: 1,
    ),
  );
  when(
    () => api.loginAuditPage(
      page: any(named: 'page'),
      size: any(named: 'size'),
      result: any(named: 'result'),
      platform: any(named: 'platform'),
      query: any(named: 'query'),
      sort: any(named: 'sort'),
      dir: any(named: 'dir'),
    ),
  ).thenAnswer(
    (_) async => AdminPage<AdminLoginAuditItem>(
      items: [_loginAudit()],
      page: 0,
      size: 10,
      totalElements: 1,
      totalPages: 1,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminOperationsApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(body: AdminLogsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('操作审计：超宽操作内容悬停可看全文，短值不挂 Tooltip', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpLogsPage(tester, _MockAdminOperationsApi());

    expect(find.byType(AdminCellText), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(AdminCellText),
        matching: find.textContaining('批量重命名'),
      ),
      findsOneWidget,
    );
    // 内容被截断：单元格挂 Tooltip 承载全文。
    expect(
      find.ancestor(
        of: find.textContaining('批量重命名'),
        matching: find.byType(Tooltip),
      ),
      findsOneWidget,
    );
    // 短值未截断：不挂 Tooltip。
    expect(
      find.ancestor(of: find.text('LOGIN'), matching: find.byType(Tooltip)),
      findsNothing,
    );
    expect(
      find.ancestor(of: find.text('1.1.1.1'), matching: find.byType(Tooltip)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('登录日志：超长用户名悬停可看全文', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpLogsPage(tester, _MockAdminOperationsApi());

    await tester.tap(find.text('登录日志'));
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.textContaining('administrator-with-very-long-name'),
        matching: find.byType(Tooltip),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: find.text('WEB'), matching: find.byType(Tooltip)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('配置中心：新增目录键归入正确分组且不再显示未知配置项', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const view = AdminConfigManagementView(
      items: [
        AdminConfigEntry(
          key: 'backdrop.max-image-bytes',
          value: '20971520',
          valueType: 'NUMBER',
          category: 'backdrop',
          refreshScope: 'HOT',
          updatedAt: '2026-09-19T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.backdrop.maxImageBytes',
        ),
        AdminConfigEntry(
          key: 'auth.two-factor.required-roles',
          value: 'SUPER_ADMIN',
          valueType: 'STRING',
          category: 'auth',
          refreshScope: 'HOT',
          updatedAt: '2026-09-19T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.auth.twoFactorRequiredRoles',
        ),
        AdminConfigEntry(
          key: 'app.version.latest',
          value: '0.1.1',
          valueType: 'STRING',
          category: 'general',
          refreshScope: 'HOT',
          updatedAt: '2026-09-19T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.appVersion.latest',
        ),
        AdminConfigEntry(
          key: 'photo.geo.offline',
          value: 'true',
          valueType: 'BOOLEAN',
          category: 'photo',
          refreshScope: 'HOT',
          updatedAt: '2026-09-19T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.photo.geo.offline',
        ),
        AdminConfigEntry(
          key: 'clamav.timeout-millis',
          value: '2000000',
          valueType: 'NUMBER',
          category: 'security',
          refreshScope: 'HOT',
          updatedAt: '2026-09-19T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.security.clamav.timeout',
        ),
        AdminConfigEntry(
          key: 'security.quarantine.retention-days',
          value: '7',
          valueType: 'NUMBER',
          category: 'security',
          refreshScope: 'HOT',
          updatedAt: '2026-09-19T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.security.quarantine.retentionDays',
        ),
        AdminConfigEntry(
          key: 'log-retention.enabled',
          value: 'true',
          valueType: 'BOOLEAN',
          category: 'general',
          refreshScope: 'HOT',
          updatedAt: '2026-09-19T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.logRetention.enabled',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: SingleChildScrollView(child: AdminConfigPage(view: view)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 分组正确：背景库 / 认证 / 系统；安全与照片维持原分组。
    expect(find.text('背景库'), findsOneWidget);
    expect(find.text('认证'), findsOneWidget);
    expect(find.text('系统'), findsNWidgets(2));
    // 标题与描述来自新映射。
    expect(find.text('背景图片大小上限'), findsOneWidget);
    expect(find.text('强制两步验证角色'), findsOneWidget);
    expect(find.text('客户端最新版本号'), findsOneWidget);
    expect(find.text('离线逆地理编码'), findsOneWidget);
    expect(find.text('扫描超时'), findsOneWidget);
    expect(find.text('隔离区保留天数'), findsOneWidget);
    expect(find.text('日志保留清理'), findsOneWidget);
    // 不再出现未知配置项与其他设置分组。
    expect(find.text('未知配置项'), findsNothing);
    expect(find.text('其他设置'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('配置中心：未映射键描述回退后端目录描述而非集成开关文案', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const view = AdminConfigManagementView(
      items: [
        AdminConfigEntry(
          key: 'future.unknown.key',
          value: 'abc',
          valueType: 'STRING',
          category: 'media',
          refreshScope: 'HOT',
          updatedAt: '2026-09-19T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.future.unknown',
          description: '来自后端目录的权威描述',
        ),
        AdminConfigEntry(
          key: 'future.unknown-toggle',
          value: 'true',
          valueType: 'BOOLEAN',
          category: 'media',
          refreshScope: 'HOT',
          updatedAt: '2026-09-19T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.future.toggle',
          description: '',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: SingleChildScrollView(child: AdminConfigPage(view: view)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('来自后端目录的权威描述'), findsOneWidget);
    expect(find.text('控制是否允许使用此集成服务。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AdminCellText：普通文本仅截断时挂 Tooltip，富文案常驻挂载', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: Column(
            children: [
              // 测试字体等宽：10 字符 × 12px = 120px，恰好完整显示。
              SizedBox(
                width: 120,
                child: AdminCellText(
                  'short-text',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              SizedBox(
                width: 60,
                child: AdminCellText(
                  'a-very-long-cell-text-that-will-overflow',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              SizedBox(
                width: 120,
                child: AdminCellText(
                  'rich-text',
                  style: TextStyle(fontSize: 12),
                  tooltipMessage: 'rich-text\n\nstack-trace-lines',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 未截断且无富文案：不挂 Tooltip。
    expect(
      find.ancestor(
        of: find.text('short-text'),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );
    // 截断：挂 Tooltip 承载全文。
    final overflowTooltip = find.ancestor(
      of: find.textContaining('a-very-long-cell-text'),
      matching: find.byType(Tooltip),
    );
    expect(overflowTooltip, findsOneWidget);
    expect(
      tester.widget<Tooltip>(overflowTooltip).message,
      'a-very-long-cell-text-that-will-overflow',
    );
    // 富文案：即使未截断也常驻挂载，消息为富文案（含堆栈）。
    final richTooltip = find.ancestor(
      of: find.text('rich-text'),
      matching: find.byType(Tooltip),
    );
    expect(richTooltip, findsOneWidget);
    expect(
      tester.widget<Tooltip>(richTooltip).message,
      'rich-text\n\nstack-trace-lines',
    );
  });
}
