import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/widgets/top_bar_search_focus.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/presentation/pages/admin_dashboard_page.dart';

/// 顶栏搜索框 Ctrl/Cmd+F 聚焦：注册表路由、栈顶放行与窄屏对话框优先。
AdminConsoleSummary _fakeSummary() {
  return AdminConsoleSummary(
    users: AdminUserStats(
      total: 12,
      active: 10,
      disabled: 2,
      roleCounts: const {},
    ),
    roles: const [],
    configs: AdminConfigStats(
      total: 0,
      hot: 0,
      nextTask: 0,
      restartRequired: 0,
    ),
    tasks: AdminTaskStats(
      total: 0,
      queued: 0,
      running: 0,
      completed: 0,
      failed: 0,
      cancelled: 0,
      dlq: 0,
    ),
    storage: AdminStorageStats(
      fileCount: 4280,
      folderCount: 0,
      objectCount: 0,
      usedBytes: 842500000000,
      externalAccountCount: 0,
    ),
    health: const [],
  );
}

class _FakeAdminConsoleController extends AdminConsoleController {
  @override
  Future<AdminConsoleSummary> build() => Future.value(_fakeSummary());
}

class _AdminSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    return AuthSessionState(
      user: UserProfile(
        id: 'admin-1',
        username: 'admin-it',
        role: 'ADMIN',
        permissions: const {
          'system:config:read',
          'system:user:read',
          'task:admin',
        },
      ),
    );
  }
}

Future<void> _pumpAdmin(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminConsoleControllerProvider.overrideWith(
          _FakeAdminConsoleController.new,
        ),
        authSessionProvider.overrideWith(_AdminSessionNotifier.new),
      ],
      child: MaterialApp(
        theme: OmniNestTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const AdminDashboardPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _searchFieldWithKeycap() {
  return find.ancestor(
    of: find.text(topBarSearchKeycapLabel),
    matching: find.byType(TextField),
  );
}

void main() {
  testWidgets('宽屏顶栏搜索槽被注册表聚焦且键帽按平台显示', (tester) async {
    await _pumpAdmin(tester);

    expect(find.text(topBarSearchKeycapLabel), findsOneWidget);
    final field = tester.widget<TextField>(_searchFieldWithKeycap());

    expect(TopBarSearchFocusRegistry.instance.focusActiveTarget(), isTrue);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(field.focusNode));
    expect(tester.takeException(), isNull);
  });

  testWidgets('上层路由压栈期间放行，返回后恢复命中', (tester) async {
    await _pumpAdmin(tester);

    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: SizedBox())),
    );
    await tester.pumpAndSettle();

    expect(
      TopBarSearchFocusRegistry.instance.focusActiveTarget(),
      isFalse,
      reason: '压在栈下的页面不得劫持 Ctrl+F，应放行给栈顶路由的绑定',
    );

    navigator.pop();
    await tester.pumpAndSettle();

    expect(TopBarSearchFocusRegistry.instance.focusActiveTarget(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏搜索对话框成为唯一 Ctrl+F 目标', (tester) async {
    await _pumpAdmin(tester, size: const Size(700, 900));

    // 窄屏顶栏不渲染常驻搜索槽，无目标时必须放行。
    expect(find.text(topBarSearchKeycapLabel), findsNothing);
    expect(TopBarSearchFocusRegistry.instance.focusActiveTarget(), isFalse);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.tap(find.byTooltip(l10n.adminSearchHint));
    await tester.pumpAndSettle();

    expect(TopBarSearchFocusRegistry.instance.focusActiveTarget(), isTrue);
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(FocusManager.instance.primaryFocus, same(field.focusNode));

    await tester.tap(find.text(l10n.coreCancel));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(TopBarSearchFocusRegistry.instance.focusActiveTarget(), isFalse);
    expect(tester.takeException(), isNull);
  });
}
