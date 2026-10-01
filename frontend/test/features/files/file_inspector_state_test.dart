import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_node.dart';

FileNode _node(String id, {bool folder = false}) {
  return FileNode(
    id: id,
    parentId: null,
    name: id,
    isFolder: folder,
    nodeType: folder ? 'FOLDER' : 'FILE',
    normalizedPath: '/$id',
    sizeBytes: folder ? 0 : 10,
    updatedAt: DateTime(2026, 9, 28),
  );
}

FileBrowserState _state({List<FileNode> files = const []}) {
  return FileBrowserState(files: files, recycleBin: const []);
}

void main() {
  test('dedupeFolderName：重名以数字递增补充', () {
    final siblings = [
      _node('新建文件夹', folder: true),
      _node('新建文件夹 2', folder: true),
      _node('无关文件'),
    ];
    expect(dedupeFolderName('新建文件夹', siblings), '新建文件夹 3');
    expect(dedupeFolderName('资料', siblings), '资料');
  });

  test('draftFolderName 哨兵语义：可显式清空而不回退', () {
    final state = _state().copyWith(draftFolderName: '新建文件夹');
    expect(state.draftFolderName, '新建文件夹');
    final cleared = state.copyWith(draftFolderName: null);
    expect(cleared.draftFolderName, isNull);
    expect(cleared.copyWith(inspectorOpen: true).draftFolderName, isNull);
  });

  test('inspectedFileId 走哨兵语义：null 可显式清空而不回退旧值', () {
    final state = _state().copyWith(inspectedFileId: 'a');
    expect(state.inspectedFileId, 'a');
    final cleared = state.copyWith(inspectedFileId: null);
    expect(cleared.inspectedFileId, isNull);
    final untouched = cleared.copyWith(inspectorOpen: true);
    expect(untouched.inspectedFileId, isNull);
    expect(untouched.inspectorOpen, isTrue);
  });

  test('inspectedNode 在各分区缓存池中解析，未命中返回 null', () {
    final node = _node('file-1');
    final state = _state(files: [node]).copyWith(inspectedFileId: 'file-1');
    expect(state.inspectedNode?.id, 'file-1');

    final fromRecycle = _state().copyWith(
      recycleBin: [_node('gone')],
      inspectedFileId: 'gone',
    );
    expect(fromRecycle.inspectedNode?.id, 'gone');

    final missing = _state(files: [node]).copyWith(inspectedFileId: 'other');
    expect(missing.inspectedNode, isNull);
  });

  test('inspectNode 的 Toggle 语义与开合接线（源码契约）', () {
    final source =
        File(
          'lib/features/files/application/file_browser_selection_actions.dart',
        ).readAsStringSync();
    expect(
      source,
      contains('if (fileId == null || fileId == current.inspectedFileId)'),
    );
    expect(source, contains('inspectorOpen: true'));
  });

  test('导航清理点同步清空检视态（11 处 _clearInspection）', () {
    final source =
        File(
          'lib/features/files/application/file_browser_controller.dart',
        ).readAsStringSync();
    final count = '_clearInspection();'.allMatches(source).length;
    expect(count, 11);
  });

  test('移动端皮肤与贴底批量条（源码接线）', () {
    final batch =
        File(
          'lib/features/files/presentation/pages/file_browser_page_batch.dart',
        ).readAsStringSync();
    expect(batch, contains('_MobileStickyBatchBar'));
    expect(batch, contains('MediaQuery.paddingOf(context).bottom + 12'));
    final mobileHome =
        File(
          'lib/features/files/presentation/pages/file_browser_page_mobile_home.dart',
        ).readAsStringSync();
    expect(mobileHome, isNot(contains('BorderRadius.circular(12)')));
    final fab =
        File(
          'lib/features/files/presentation/pages/file_browser_page_mobile_actions.dart',
        ).readAsStringSync();
    expect(fab, contains('borderRadius: BorderRadius.zero'));
    expect(fab, isNot(contains('mobileColors')));
  });

  test('宽屏 Row 挂 dock、窄屏 listen 弹贴底抽屉（源码接线）', () {
    final page =
        File(
          'lib/features/files/presentation/pages/file_browser_page.dart',
        ).readAsStringSync();
    expect(page, contains('_InspectorDock(state: state)'));
    expect(page, contains('_showInspectorSheet(controller)'));
    final inspector =
        File(
          'lib/features/files/presentation/pages/file_browser_page_inspector.dart',
        ).readAsStringSync();
    expect(inspector, contains('width: state.inspectorOpen ? 320 : 0'));
    expect(inspector, contains('MotionToken.pageSwitch'));
  });
}
