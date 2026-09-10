import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_admin_page.dart';
import 'package:omninest/features/reader/presentation/pages/reader_stats_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';

class _FakeReaderCenterController extends ReaderCenterController {
  @override
  Future<ReaderCenterState> build() async {
    return ReaderCenterState(
      dashboard: ReaderDashboard.empty(),
      items: const [],
      searchQuery: '',
    );
  }
}

Widget _wrap(Widget child, {bool hosted = false}) {
  return ProviderScope(
    overrides: [
      authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: OmniNestTheme.dark(),
      home: MobileShellScope(hosted: hosted, child: child),
    ),
  );
}

void main() {
  group('ReaderPageScaffold', () {
    testWidgets('桌面布局渲染顶栏、页签与内容', (tester) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const ReaderPageScaffold(
            target: ReaderPageTarget.library,
            child: Text('library content'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // 桌面样例布局：面包屑含模块名，侧栏含三个页签
      expect(find.text('OmniNest'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Bookshelf'), findsOneWidget);
      expect(find.text('Stats'), findsOneWidget);
      expect(find.text('library content'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('桌面窄窗口使用样例底导航', (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const ReaderPageScaffold(
            target: ReaderPageTarget.library,
            child: Text('narrow content'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('narrow content'), findsOneWidget);
      expect(find.text('Bookshelf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('窄屏使用样例底导航渲染内容', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const ReaderPageScaffold(
            target: ReaderPageTarget.library,
            child: Text('mobile library content'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('mobile library content'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Bookshelf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('托管态隐藏模块顶栏与底导航，分区改为顶部页签行', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const ReaderPageScaffold(
            target: ReaderPageTarget.library,
            child: Text('hosted library content'),
          ),
          hosted: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('hosted library content'), findsOneWidget);
      // 页签行渲染三个非管理员分区
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Bookshelf'), findsOneWidget);
      expect(find.text('Stats'), findsOneWidget);
      // 模块顶栏面包屑与底导航/侧栏图标不再渲染
      expect(find.text('OmniNest'), findsNothing);
      expect(find.byIcon(Icons.admin_panel_settings_outlined), findsNothing);
      expect(find.byIcon(Icons.auto_stories_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('ReaderStatsPage', () {
    testWidgets('统计页渲染阅读报告卡片', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionStoreProvider.overrideWithValue(
              MemoryAuthSessionStore(),
            ),
            readerStatsProvider.overrideWith((ref) async {
              return const ReaderReadingStats(
                totalMinutesToday: 25,
                totalMinutesThisWeek: 180,
                currentStreak: 3,
                totalBooksRead: 12,
              );
            }),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            theme: OmniNestTheme.dark(),
            home: const ReaderStatsPage(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ReaderStatsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ReaderAdminPage', () {
    testWidgets('非管理员渲染无权访问兜底视图', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionStoreProvider.overrideWithValue(
              MemoryAuthSessionStore(),
            ),
            readerCenterControllerProvider.overrideWith(
              _FakeReaderCenterController.new,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            theme: OmniNestTheme.dark(),
            home: const ReaderAdminPage(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Management tools visible to super admins only'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
