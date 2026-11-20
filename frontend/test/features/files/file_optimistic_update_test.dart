// 收藏 / 删除 / 重命名的乐观更新：先改内存态，网络失败再刷新回滚。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_repository.dart';

class _FakeFileRepository extends Mock implements FileRepository {}

class _SeededController extends FileBrowserController {
  _SeededController(this.initial);

  final FileBrowserState initial;

  @override
  Future<FileBrowserState> build() async => initial;
}

FileNode _node(String id, {bool favorited = false, String? parentId}) =>
    FileNode(
      id: id,
      parentId: parentId,
      name: '$id.txt',
      isFolder: false,
      nodeType: 'DOCUMENT',
      normalizedPath: '/$id.txt',
      sizeBytes: 1024,
      updatedAt: DateTime(2026, 11, 10),
      favorited: favorited,
    );

FileBrowserState _state() => FileBrowserState(
  files: [_node('a'), _node('b')],
  recycleBin: const <FileNode>[],
  recentFiles: [_node('a'), _node('b')],
  favoriteFiles: const <FileNode>[],
  selectedFileIds: const <String>{'a'},
  fileTotalElements: 2,
  fileTotalPages: 1,
);

typedef _Harness =
    ({ProviderContainer container, _FakeFileRepository repository});

Future<_Harness> _pump(
  List<FileNode> Function() page, {
  FileBrowserState? initial,
}) async {
  final repository = _FakeFileRepository();
  when(
    () => repository.listFilesPage(
      parentId: any(named: 'parentId'),
      category: any(named: 'category'),
      page: any(named: 'page'),
      size: any(named: 'size'),
    ),
  ).thenAnswer(
    (_) async => FileNodePage(
      items: page(),
      page: 0,
      size: 10,
      totalElements: page().length,
      totalPages: 1,
    ),
  );
  when(
    () => repository.listFavoriteFiles(),
  ).thenAnswer((_) async => <FileNode>[]);
  final container = ProviderContainer.test(
    overrides: [
      fileRepositoryProvider.overrideWithValue(repository),
      fileBrowserControllerProvider.overrideWith(
        () => _SeededController(initial ?? _state()),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(fileBrowserControllerProvider.future);
  return (container: container, repository: repository);
}

void main() {
  test('删除先移行再等网络', () async {
    // 服务端返回随删除推进：成功后刷新拿到的只有剩下那一行。
    var rows = [_node('a'), _node('b')];
    final harness = await _pump(() => rows);
    final gate = Completer<List<FileNode>>();
    when(
      () => harness.repository.batchDeleteFiles(any()),
    ).thenAnswer((_) => gate.future);
    final notifier = harness.container.read(
      fileBrowserControllerProvider.notifier,
    );

    final future = notifier.batchDeleteFiles();
    // 还没等到接口返回，行已经从列表与选中集里消失。
    final optimistic =
        harness.container.read(fileBrowserControllerProvider).value!;
    expect(optimistic.files.map((node) => node.id), <String>['b']);
    expect(optimistic.selectedFileIds, isEmpty);

    rows = [_node('b')];
    gate.complete(const <FileNode>[]);
    await future;
    expect(
      harness.container
          .read(fileBrowserControllerProvider)
          .value!
          .files
          .map((node) => node.id),
      <String>['b'],
    );
  });

  test('删除失败时刷新回滚并把错误抛给调用方', () async {
    final harness = await _pump(() => [_node('a'), _node('b')]);
    when(
      () => harness.repository.batchDeleteFiles(any()),
    ).thenThrow(StateError('boom'));
    final notifier = harness.container.read(
      fileBrowserControllerProvider.notifier,
    );

    await expectLater(notifier.batchDeleteFiles(), throwsStateError);
    // 回滚走刷新：服务端仍有两行，界面上被移掉的行回来了。
    final state = harness.container.read(fileBrowserControllerProvider).value!;
    expect(state.files.map((node) => node.id), <String>['a', 'b']);
  });

  test('拖到文件夹：先让行离开当前目录，再按 id 集发移动请求', () async {
    var rows = [_node('a'), _node('b')];
    final harness = await _pump(() => rows);
    final gate = Completer<List<FileNode>>();
    when(
      () => harness.repository.batchMoveFiles(any(), any()),
    ).thenAnswer((_) => gate.future);
    final notifier = harness.container.read(
      fileBrowserControllerProvider.notifier,
    );

    final future = notifier.moveFilesTo(<String>['a'], 'folder-1');
    final optimistic =
        harness.container.read(fileBrowserControllerProvider).value!;
    expect(optimistic.files.map((node) => node.id), <String>['b']);

    rows = [_node('b')];
    gate.complete(const <FileNode>[]);
    await future;
    verify(
      () => harness.repository.batchMoveFiles(<String>['a'], 'folder-1'),
    ).called(1);
  });

  test('拖到自身是空操作，不发请求也不动列表', () async {
    final harness = await _pump(() => [_node('a'), _node('b')]);
    final notifier = harness.container.read(
      fileBrowserControllerProvider.notifier,
    );

    // 把文件夹拖到它自己身上没有任何意义，不该发请求。
    await notifier.moveFilesTo(<String>['a'], 'a');
    expect(
      harness.container.read(fileBrowserControllerProvider).value!.files.length,
      2,
    );
    verifyNever(() => harness.repository.batchMoveFiles(any(), any()));
  });

  test('从嵌套目录拖到根目录，即使当前列表在根层也会发移动请求', () async {
    final nested = _node('a', parentId: 'folder-1');
    final harness = await _pump(
      () => [nested, _node('b')],
      initial: _state().copyWith(files: [nested, _node('b')]),
    );
    when(
      () => harness.repository.batchMoveFiles(any(), any()),
    ).thenAnswer((_) async => const <FileNode>[]);
    final notifier = harness.container.read(
      fileBrowserControllerProvider.notifier,
    );

    await notifier.moveFilesTo(<String>['a'], '');

    verify(
      () => harness.repository.batchMoveFiles(<String>['a'], ''),
    ).called(1);
  });

  test('收藏先点亮星标再等网络', () async {
    final harness = await _pump(() => [_node('a'), _node('b')]);
    final gate = Completer<List<FileNode>>();
    when(
      () => harness.repository.batchAddFavorites(any()),
    ).thenAnswer((_) => gate.future);
    final notifier = harness.container.read(
      fileBrowserControllerProvider.notifier,
    );

    final future = notifier.batchAddFavorites();
    final optimistic =
        harness.container.read(fileBrowserControllerProvider).value!;
    expect(optimistic.files.firstWhere((n) => n.id == 'a').favorited, isTrue);
    expect(optimistic.favoriteIdSet, contains('a'));
    expect(optimistic.favoriteFiles.map((n) => n.id), contains('a'));

    gate.complete(const <FileNode>[]);
    await future;
  });

  test('重命名先换名字再等网络', () async {
    final harness = await _pump(() => [_node('a')]);
    final gate = Completer<FileNode>();
    when(
      () => harness.repository.renameFile(
        fileId: any(named: 'fileId'),
        name: any(named: 'name'),
      ),
    ).thenAnswer((_) => gate.future);
    final notifier = harness.container.read(
      fileBrowserControllerProvider.notifier,
    );
    final target =
        harness.container
            .read(fileBrowserControllerProvider)
            .value!
            .files
            .first;

    final future = notifier.renameFile(target, 'renamed.txt');
    final optimistic =
        harness.container.read(fileBrowserControllerProvider).value!;
    expect(optimistic.files.first.name, 'renamed.txt');
    // 最近列表同一节点也要跟着改名，否则两处显示不一致。
    expect(optimistic.recentFiles.first.name, 'renamed.txt');

    gate.complete(_node('a'));
    await future;
  });
}
