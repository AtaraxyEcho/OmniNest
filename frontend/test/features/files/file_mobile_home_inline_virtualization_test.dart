import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/application/file_browser_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';
import 'package:omninest/features/files/presentation/widgets/file_env_glyph.dart';

/// 目录原地展开态的列表虚拟化闸门。
///
/// 判据不是"用了哪个 widget"，而是最坏真实尺寸下**实际被构建的行数**：
/// 360×860 视口展开 300 项时，一次性构建会把 300 行全部实例化，
/// 懒建后同屏只应构建视口内加缓存高度那几十行。
void main() {
  testWidgets('原地展开 300 项时只构建视口附近的行', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 860);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        fileBrowserControllerProvider.overrideWith(
          () => _InlineFolderController(_stateWith300Files()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container));
    await tester.pump(const Duration(seconds: 1));

    final builtRows = tester.widgetList(find.byType(FileEnvRow)).length;
    // ignore: avoid_print
    print('built_rows=$builtRows');
    expect(builtRows, lessThan(60), reason: '300 项全部实例化说明没有懒加载');

    // 滚到底仍要能拿到最后一项，防止"变懒"变成"少渲染"。
    await tester.scrollUntilVisible(find.text('文件299'), 500);
    await tester.pumpAndSettle();
    expect(find.text('文件299'), findsOneWidget);
  });
}

Widget _host(ProviderContainer container) {
  final router = GoRouter(
    initialLocation: '/files',
    routes: [
      GoRoute(
        path: '/files',
        builder: (context, state) => const FileBrowserPage(),
      ),
    ],
  );
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

FileBrowserState _stateWith300Files() {
  final files = List<FileNode>.generate(
    300,
    (index) => FileNode(
      id: 'file-$index',
      parentId: 'root-1',
      name: '文件$index',
      isFolder: false,
      nodeType: 'FILE',
      normalizedPath: '/Library/文件$index',
      sizeBytes: 1024,
      updatedAt: null,
    ),
    growable: false,
  );
  return FileBrowserState(
    section: FileManagerSection.allFiles,
    files: files,
    recycleBin: const [],
    breadcrumbs: const [
      FileNode(
        id: 'root-1',
        parentId: null,
        name: 'Library',
        isFolder: true,
        nodeType: 'FOLDER',
        normalizedPath: '/Library',
        sizeBytes: 0,
        updatedAt: null,
      ),
    ],
    fileTotalPages: 30,
  );
}

class _InlineFolderController extends FileBrowserController {
  _InlineFolderController(this.initialState);

  final FileBrowserState initialState;

  @override
  Future<FileBrowserState> build() async => initialState;

  @override
  Future<void> loadMoreFiles() async {
    // 续载由真实 controller 负责；本用例只测构建数量。
  }
}
