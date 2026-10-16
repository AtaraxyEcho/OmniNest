// 托管阅读管理页回归：`/reader/admin` 此前只有深链进得来——`ReaderPageScaffold`
// 在托管态隐藏模块 chrome，页面顶端既没有模块头也没有返回位。
// 现在按壳层同一条约定挂 MobileModuleHeader（90 带 + 48 圆返回钮 + 状态栏避让）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_dashboard.dart';
import 'package:omninest/features/reader/domain/reader_item.dart';
import 'package:omninest/features/reader/presentation/pages/reader_admin_page.dart';

const double _statusBarInset = 44;

final _adminUser = UserProfile(
  id: 'u1',
  username: 'tester',
  role: 'ADMIN',
  permissions: const {'media:write'},
);

class _FakeAuthSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async => AuthSessionState(user: _adminUser);
}

class _FakeReaderCenterController extends ReaderCenterController {
  @override
  Future<ReaderCenterState> build() async {
    return ReaderCenterState(
      dashboard: ReaderDashboard.empty(),
      items: [
        ReaderItem(
          id: 'book-1',
          title: 'The Art of Stillness',
          itemType: 'EPUB',
          progressPercent: 0.4,
          updatedAt: DateTime(2026, 10, 1),
        ),
      ],
      searchQuery: '',
    );
  }
}

Future<void> _pumpHostedAdmin(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: _statusBarInset, bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);

  final router = GoRouter(
    initialLocation: '/reader/admin',
    routes: [
      GoRoute(
        path: '/reader/admin',
        builder:
            (context, state) =>
                const MobileHostedRoute(child: ReaderAdminPage()),
      ),
      GoRoute(
        path: '/reader',
        builder: (context, state) => const Scaffold(body: Text('阅读空间桩')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(_FakeAuthSessionNotifier.new),
        readerCenterControllerProvider.overrideWith(
          _FakeReaderCenterController.new,
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: OmniNestTheme.dark(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('托管管理页有模块头，返回钮让开状态栏', (tester) async {
    await _pumpHostedAdmin(tester);

    expect(find.byType(MobileModuleHeader), findsOneWidget);
    expect(find.text('阅读管理'), findsOneWidget);
    expect(find.text('导入、待导入文件与元数据管理'), findsOneWidget);

    final back = find.byType(MobileGlassIconButton);
    expect(back, findsOneWidget);
    expect(
      tester.getRect(back).top,
      greaterThanOrEqualTo(_statusBarInset),
      reason: '返回钮顶缘必须在状态栏之下',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('头部返回钮退出托管管理页', (tester) async {
    await _pumpHostedAdmin(tester);

    await tester.tap(find.byType(MobileGlassIconButton));
    await tester.pumpAndSettle();

    expect(find.text('阅读空间桩'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
