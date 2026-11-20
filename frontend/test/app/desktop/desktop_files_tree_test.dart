import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/pages/desktop_files_page.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_repository.dart';

import 'desktop_test_harness.dart';

/// 结构树的取子层与落点移动都走仓储扩展方法，测试在仓储层记账；
/// 其余接口一律抛错，避免把未种子的能力伪装成成功。
class _TreeRepository implements FileRepository {
  _TreeRepository(
    Map<String?, List<FileNode>> children, {
    required List<FileNode> root,
  }) : children = <String?, List<FileNode>>{
         for (final entry in children.entries)
           entry.key: List<FileNode>.of(entry.value),
       },
       root = List<FileNode>.of(root);

  final Map<String?, List<FileNode>> children;
  final List<FileNode> root;
  final List<(List<String>, String)> moves = <(List<String>, String)>[];
  final List<String?> listedParents = <String?>[];

  @override
  Future<List<FileNode>> listFiles({String? parentId, String? category}) async {
    listedParents.add(parentId);
    return parentId == null ? root : children[parentId] ?? const <FileNode>[];
  }

  @override
  Future<FileNodePage> listFilesPage({
    String? parentId,
    String? category,
    int page = 0,
    int size = 10,
  }) async {
    final items =
        parentId == null ? root : children[parentId] ?? const <FileNode>[];
    return FileNodePage(
      items: items,
      page: page,
      size: size,
      totalElements: items.length,
      totalPages: 1,
    );
  }

  @override
  Future<List<FileNode>> batchMoveFiles(
    List<String> fileIds,
    String parentId,
  ) async {
    moves.add((fileIds, parentId));
    for (final id in fileIds) {
      FileNode? moving;
      void removeFrom(List<FileNode> nodes) {
        final index = nodes.indexWhere((node) => node.id == id);
        if (index >= 0) moving = nodes.removeAt(index);
      }

      removeFrom(root);
      for (final nodes in children.values) {
        removeFrom(nodes);
      }
      if (moving != null) {
        if (parentId.isEmpty) {
          root.add(moving!);
        } else {
          (children[parentId] ??= <FileNode>[]).add(moving!);
        }
      }
    }
    return const <FileNode>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 只负责首屏状态；其余动作走真实控制器 + 假仓储。
class _TreeBrowser extends FileBrowserController {
  _TreeBrowser(this.seed);

  final FileBrowserState seed;

  @override
  Future<FileBrowserState> build() async => seed;

  @override
  Future<void> loadSection(
    FileManagerSection section, {
    bool background = false,
  }) async {}
}

FileNode _folder(
  String id,
  String name, {
  String? parentId,
  int childCount = 0,
}) {
  return FileNode(
    id: id,
    parentId: parentId,
    name: name,
    isFolder: true,
    nodeType: 'FOLDER',
    normalizedPath: '/OmniCloud/$name',
    sizeBytes: 0,
    childCount: childCount,
    updatedAt: DateTime(2026, 11, 2),
    spaceType: SpaceType.personal,
  );
}

FileNode _file(String id, String name, {String? parentId}) {
  return FileNode(
    id: id,
    parentId: parentId,
    name: name,
    isFolder: false,
    nodeType: 'DOCUMENT',
    normalizedPath: '/OmniCloud/$name',
    sizeBytes: 1024,
    mimeType: 'application/pdf',
    updatedAt: DateTime(2026, 10, 28),
    spaceType: SpaceType.personal,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final studio = _folder('d-1', 'Studio archive', childCount: 2);
  final travel = _folder('d-2', 'Travel selects');
  final child = _folder('d-1-1', 'Spring trip', parentId: 'd-1');
  final pdf = _file('f-1', 'Budget review.pdf');

  Future<_TreeRepository> pumpTree(
    WidgetTester tester, {
    Map<String?, List<FileNode>> children = const <String?, List<FileNode>>{},
  }) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _TreeRepository(
      children,
      root: <FileNode>[studio, travel],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          fileRepositoryProvider.overrideWithValue(repository),
          fileBrowserControllerProvider.overrideWith(
            () => _TreeBrowser(
              FileBrowserState(
                files: <FileNode>[studio, travel, pdf],
                recycleBin: const <FileNode>[],
              ),
            ),
          ),
        ],
        child: wrapDesktop(const DesktopFilesPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));
    return repository;
  }

  /// 树在左轨（x < 300），主列表同名文本在右侧；按渲染位置区分。
  Finder treeLabel(String name) => find.byElementPredicate((element) {
    final widget = element.widget;
    if (widget is! Text || widget.data != name) {
      return false;
    }
    final box = element.renderObject as RenderBox?;
    return box != null && box.localToGlobal(Offset.zero).dx < 300;
  });

  Finder nodeChevron(String folderName) {
    final id = switch (folderName) {
      'Studio archive' => 'd-1',
      'Travel selects' => 'd-2',
      'Spring trip' => 'd-1-1',
      _ => throw ArgumentError.value(folderName, 'folderName'),
    };
    return find.descendant(
      of: find.byKey(ValueKey<String>('desktop-files-tree-chevron-$id')),
      matching: find.byIcon(DesktopIcons.chevron),
    );
  }

  testWidgets('结构树展开按钮拉取子层并按深度缩进', (tester) async {
    final repository = await pumpTree(
      tester,
      children: <String?, List<FileNode>>{
        'd-1': <FileNode>[child, _file('f-2', 'Notes.pdf', parentId: 'd-1')],
      },
    );

    expect(find.text('Studio archive'), findsWidgets);
    expect(find.text('Travel selects'), findsWidgets);
    expect(find.text('Spring trip'), findsNothing);

    await tester.tap(nodeChevron('Studio archive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(repository.listedParents, contains('d-1'));
    expect(find.text('Spring trip'), findsWidgets);

    // 再点收起，子层从树上移除。
    await tester.tap(nodeChevron('Studio archive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('Spring trip'), findsNothing);
  });

  testWidgets('聚焦树节点后 → 展开、← 收起', (tester) async {
    final repository = await pumpTree(
      tester,
      children: <String?, List<FileNode>>{
        'd-1': <FileNode>[child],
      },
    );

    // 点行会把列表切进该目录（同时把焦点交给树节点），这里只关心键盘。
    await tester.tap(treeLabel('Studio archive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    final collapsed = find.text('Spring trip').evaluate().length;

    repository.listedParents.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(repository.listedParents, contains('d-1'), reason: '→ 必须触发树节点取子层');
    expect(find.text('Spring trip').evaluate().length, collapsed + 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('Spring trip').evaluate().length, collapsed);
  });

  testWidgets('拖动停在目录上 650ms 自动展开该层', (tester) async {
    final travelChild = _folder('d-2-1', 'Oslo trip', parentId: 'd-2');
    final repository = await pumpTree(
      tester,
      children: <String?, List<FileNode>>{
        'd-2': <FileNode>[travelChild],
      },
    );

    final start = tester.getCenter(treeLabel('Studio archive'));
    final target = tester.getCenter(treeLabel('Travel selects'));
    final pointer = TestPointer(2, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(start));
    await tester.pump();
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();

    expect(find.text('Oslo trip'), findsNothing);
    // 样例 `Files.tsx` 的 expandOnHover：停满 650ms 才展开，按住即走不展开。
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 320));
    expect(repository.listedParents, contains('d-2'));
    expect(find.text('Oslo trip'), findsWidgets);

    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 320));
  });

  testWidgets('把一个目录拖到另一个目录上按目标 id 触发移动', (tester) async {
    final repository = await pumpTree(
      tester,
      children: const <String?, List<FileNode>>{},
    );

    final start = tester.getCenter(find.text('Studio archive').last);
    final target = tester.getCenter(find.text('Travel selects').last);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(start));
    await tester.pump();
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 320));

    expect(repository.moves, isNotEmpty);
    expect(repository.moves.first.$1, contains('d-1'));
    expect(repository.moves.first.$2, 'd-2');
  });

  testWidgets('把嵌套目录拖到 My files 根行时使用空父目录', (tester) async {
    final repository = await pumpTree(
      tester,
      children: <String?, List<FileNode>>{
        'd-1': <FileNode>[child],
      },
    );

    Finder rootNav() => find.byElementPredicate((element) {
      final widget = element.widget;
      if (widget is! Text || widget.data != 'My files') {
        return false;
      }
      final box = element.renderObject as RenderBox?;
      return box != null && box.localToGlobal(Offset.zero).dx < 300;
    });

    await tester.tap(nodeChevron('Studio archive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    final start = tester.getCenter(treeLabel('Spring trip'));
    final target = tester.getCenter(rootNav());
    final pointer = TestPointer(4, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(start));
    await tester.pump();
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(repository.moves, isNotEmpty);
    expect(repository.moves.last.$1, <String>['d-1-1']);
    expect(repository.moves.last.$2, '');
  });

  testWidgets('树内跨分支移动后刷新已展开的来源和目标目录', (tester) async {
    final repository = await pumpTree(
      tester,
      children: <String?, List<FileNode>>{
        'd-1': <FileNode>[child],
        'd-2': <FileNode>[],
      },
    );

    await tester.tap(nodeChevron('Studio archive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(repository.listedParents, contains('d-1'));
    final start = tester.getCenter(treeLabel('Spring trip'));
    final target = tester.getCenter(treeLabel('Travel selects'));
    final pointer = TestPointer(3, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(start));
    await tester.pump();
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(repository.listedParents, contains('d-2'));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(repository.moves, isNotEmpty);
    expect(repository.moves.last.$1, <String>['d-1-1']);
    expect(repository.moves.last.$2, 'd-2');
    expect(treeLabel('Spring trip'), findsOneWidget);
    expect(repository.listedParents.where((id) => id == 'd-1').length, 2);
    expect(repository.listedParents.where((id) => id == 'd-2').length, 2);
    expect(
      tester.getTopLeft(treeLabel('Spring trip')).dy,
      greaterThan(tester.getTopLeft(treeLabel('Travel selects')).dy),
    );
  });
}
