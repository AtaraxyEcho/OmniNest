import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/realtime_providers.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/widgets/top_bar_search_focus.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';

/// 顶栏搜索槽 Ctrl/Cmd+F：支持搜索的分区聚焦，不支持的分区分区级放行。
class _FixedSectionController extends FileBrowserController {
  _FixedSectionController(this.initialState);

  final FileBrowserState initialState;

  @override
  Future<FileBrowserState> build() async => initialState;

  @override
  Future<void> loadSection(
    FileManagerSection section, {
    bool background = false,
  }) async {}

  @override
  Future<void> refreshForRealtime() async {}
}

Future<void> _pumpFiles(WidgetTester tester, FileManagerSection section) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      fileBrowserControllerProvider.overrideWith(
        () => _FixedSectionController(
          FileBrowserState(
            section: section,
            files: const [],
            recycleBin: const [],
          ),
        ),
      ),
      // 侧栏实时状态点依赖协调器（会拉起 drift/网络），测试态置空。
      realtimeCoordinatorProvider.overrideWith((ref) => null),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/files',
    routes: [
      GoRoute(
        path: '/files',
        builder: (context, state) => FileBrowserPage(initialSection: section),
      ),
      GoRoute(
        path: '/portal',
        builder:
            (context, state) => const SizedBox(key: Key('portal-destination')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('全部文件分区：Ctrl+F 聚焦顶栏搜索槽且键帽不再显示 ⌘K', (tester) async {
    await _pumpFiles(tester, FileManagerSection.allFiles);

    expect(find.text(topBarSearchKeycapLabel), findsOneWidget);
    expect(find.text('⌘K'), findsNothing);
    final field = tester.widget<TextField>(
      find.ancestor(
        of: find.text(topBarSearchKeycapLabel),
        matching: find.byType(TextField),
      ),
    );

    expect(TopBarSearchFocusRegistry.instance.focusActiveTarget(), isTrue);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(field.focusNode));
    expect(tester.takeException(), isNull);
  });

  testWidgets('上传队列分区：无搜索目标时放行按键', (tester) async {
    await _pumpFiles(tester, FileManagerSection.uploadQueue);

    expect(find.text(topBarSearchKeycapLabel), findsNothing);
    expect(TopBarSearchFocusRegistry.instance.focusActiveTarget(), isFalse);
    expect(tester.takeException(), isNull);
  });
}
