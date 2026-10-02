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

  testWidgets('首页：存储条 + 分类格 + 空间页签 + 内联根列表', (tester) async {
    await pumpHost(tester);

    // 原型 Files 首页结构：存储条、四分类格、我的文件/共享页签、内联列表。
    expect(find.text('存储用量'), findsOneWidget);
    expect(find.text('最近使用'), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('共享给我'), findsOneWidget);
    expect(find.text('离线下载'), findsOneWidget);
    expect(find.text('我的文件'), findsOneWidget);
    expect(find.text('共享空间'), findsOneWidget);

    // 内联根列表直接呈现当前空间根条目；首页态无 FAB。
    expect(find.text('Documents'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    // 「更多分区」经工具栏溢出钮打开，小屏大字号不溢出（滚动兜底）。
    await tester.tap(find.byTooltip('更多分区'));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('托管平板宽度仍走触屏布局：不出现桌面侧栏', (tester) async {
    // 托管态与 Photos/Music/Reader 同规则：宽度只决定触屏内容的网格
    // 密度，桌面侧栏路径仅非托管窗口使用。
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('存储用量'), findsOneWidget, reason: '移动首页可见');
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_FileSidebar',
      ),
      findsNothing,
      reason: '托管平板不复用桌面侧栏',
    );
    // 托管平板内容按壳层 chrome 同宽（720）封顶居中：左缘 = (1280-720)/2 + 16。
    final labelRect = tester.getRect(find.text('存储用量'));
    expect(labelRect.left, closeTo(82, 2));
  });

  testWidgets('点分类卡进入列表态，返回行与系统返回都回首页', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('最近使用'));
    await tester.pumpAndSettle();

    // 列表态：返回行出现，首页卸载。
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.text('存储用量'), findsNothing, reason: '列表态不再显示首页');

    // 返回行回首页。
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('存储用量'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);

    // 再次进入列表态，系统返回手势也回首页而非直接跳门户。
    await tester.tap(find.text('我的收藏'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('存储用量'), findsOneWidget);
    expect(find.byKey(const Key('portal-destination')), findsNothing);

    // 首页态返回：历史栈已清空，直接离站回门户（不出现返回键失灵）。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portal-destination')), findsOneWidget);
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
  Future<void> loadSection(
    FileManagerSection section, {
    bool background = false,
  }) async {
    // 测试假体：仅记录分区切换，不发网络请求。
    state = AsyncData(state.asData?.value ?? initialState);
  }
}
