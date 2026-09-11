import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';

/// 文件模块移动首页（方案一：位置/分区卡）行为测试。
void main() {
  late ProviderContainer container;

  Widget host() {
    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/files',
          builder: (context, state) => const FileBrowserPage(),
        ),
        GoRoute(
          path: '/portal',
          builder:
              (context, state) =>
                  const SizedBox(key: Key('portal-destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        builder:
            (context, child) => MobileShellScope(hosted: true, child: child!),
      ),
    );
  }

  Future<void> pumpHost(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 860);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(seconds: 1));
  }

  setUp(() {
    container = ProviderContainer(
      overrides: [
        fileBrowserControllerProvider.overrideWith(
          () => _FakeFileBrowserController(_stateWithFiles()),
        ),
      ],
    );
    addTearDown(() => container.dispose());
  });

  testWidgets('首页态渲染位置与分区卡，不渲染列表工具区', (tester) async {
    await pumpHost(tester);

    expect(find.text('位置'), findsOneWidget);
    expect(find.text('分区'), findsOneWidget);
    expect(find.text('个人空间'), findsOneWidget);
    expect(find.text('共享空间'), findsOneWidget);
    expect(find.text('全部文件'), findsOneWidget);
    expect(find.text('最近使用'), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('回收站'), findsOneWidget);
    expect(find.text('更多分区'), findsOneWidget);

    // 首页态不出现列表内容与 FAB。
    expect(find.text('Documents'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('点分区卡进入列表态，返回行与系统返回都回首页', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('全部文件'));
    await tester.pumpAndSettle();

    // 列表态：面包屑 + 文件行 + FAB 出现。
    expect(find.text('Documents'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('位置'), findsNothing, reason: '列表态不再显示首页');

    // 返回行回首页。
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.text('位置'), findsOneWidget);
    expect(find.text('Documents'), findsNothing);

    // 再次进入列表态，系统返回手势也回首页而非直接跳门户。
    await tester.tap(find.text('全部文件'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('位置'), findsOneWidget);
    expect(find.byKey(const Key('portal-destination')), findsNothing);
  });
}

FileBrowserState _stateWithFiles() {
  return const FileBrowserState(
    files: <FileNode>[
      FileNode(
        id: 'folder-1',
        parentId: null,
        name: 'Documents',
        isFolder: true,
        nodeType: 'FOLDER',
        normalizedPath: '/Documents',
        sizeBytes: 0,
        updatedAt: null,
      ),
    ],
    recycleBin: <FileNode>[],
  );
}

class _FakeFileBrowserController extends FileBrowserController {
  _FakeFileBrowserController(this.initialState);

  final FileBrowserState initialState;

  @override
  Future<FileBrowserState> build() async => initialState;

  @override
  Future<void> loadSection(FileManagerSection section) async {
    // 测试假体：仅记录分区切换，不发网络请求。
    state = AsyncData(state.asData?.value ?? initialState);
  }
}
