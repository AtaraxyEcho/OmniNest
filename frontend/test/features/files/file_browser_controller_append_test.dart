// 子分区滚动续载（loadMore*）的追加语义：下一页并入已载入集合、按 id 去重、
// 末页守卫不再发请求；页翻转仍由 show* 供桌面分页条跳页。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_repository.dart';

class _FakeFileRepository extends Mock implements FileRepository {}

class _AppendController extends FileBrowserController {
  _AppendController(this.initial);

  final FileBrowserState initial;

  @override
  Future<FileBrowserState> build() async => initial;
}

FileNode _node(String id) => FileNode(
  id: id,
  parentId: null,
  name: '$id.txt',
  isFolder: false,
  nodeType: 'FILE',
  normalizedPath: '/$id.txt',
  sizeBytes: 1024,
  updatedAt: null,
);

SharedFileItem _shared(String id) => SharedFileItem(
  shareId: id,
  file: _node('file-$id'),
  ownerUserId: 'u-1',
  sharedAt: DateTime.utc(2026, 10, 1),
);

const _metaPage0Of2 = FilesSubPageMeta(
  page: 0,
  size: 2,
  totalElements: 3,
  totalPages: 2,
);

FileBrowserState _sharedState() => FileBrowserState(
  files: const <FileNode>[],
  recycleBin: const <FileNode>[],
  section: FileManagerSection.sharedWithMe,
  sharedWithMe: <SharedFileItem>[_shared('a'), _shared('b')],
  sharedWithMeMeta: _metaPage0Of2,
);

FileBrowserState _recentState() => FileBrowserState(
  files: const <FileNode>[],
  recycleBin: const <FileNode>[],
  section: FileManagerSection.recent,
  recentFiles: <FileNode>[_node('r0'), _node('r1')],
  recentMeta: _metaPage0Of2,
);

void main() {
  test('与我共享续载把下一页并入已列条目并推进 meta.page', () async {
    final repository = _FakeFileRepository();
    when(() => repository.listSharedWithMePage(page: 1, size: 2)).thenAnswer(
      (_) async => FilesSubPage<SharedFileItem>(
        items: <SharedFileItem>[_shared('b'), _shared('c')],
        page: 1,
        size: 2,
        totalElements: 3,
        totalPages: 2,
      ),
    );
    final container = ProviderContainer.test(
      overrides: [
        fileRepositoryProvider.overrideWithValue(repository),
        fileBrowserControllerProvider.overrideWith(
          () => _AppendController(_sharedState()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await notifier.loadMoreSharedWithMe();

    final state = container.read(fileBrowserControllerProvider).value!;
    // shareId 'b' 两页都有：按 id 去重后只剩一条。
    expect(state.sharedWithMe.map((item) => item.shareId).toList(), <String>[
      'a',
      'b',
      'c',
    ]);
    expect(state.sharedWithMeMeta.page, 1);

    // 末页守卫：再点一次不再发请求。
    await notifier.loadMoreSharedWithMe();
    expect(
      container.read(fileBrowserControllerProvider).value!.sharedWithMe.length,
      3,
    );
    verify(() => repository.listSharedWithMePage(page: 1, size: 2)).called(1);
  });

  test('最近使用续载按节点 id 去重追加', () async {
    final repository = _FakeFileRepository();
    when(() => repository.listRecentFilesPage(page: 1, size: 2)).thenAnswer(
      (_) async => FileNodePage(
        items: <FileNode>[_node('r1'), _node('r2')],
        page: 1,
        size: 2,
        totalElements: 3,
        totalPages: 2,
      ),
    );
    final container = ProviderContainer.test(
      overrides: [
        fileRepositoryProvider.overrideWithValue(repository),
        fileBrowserControllerProvider.overrideWith(
          () => _AppendController(_recentState()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await notifier.loadMoreRecentFiles();

    final state = container.read(fileBrowserControllerProvider).value!;
    expect(state.recentFiles.map((node) => node.id).toList(), <String>[
      'r0',
      'r1',
      'r2',
    ]);
    expect(state.recentMeta.page, 1);
  });

  test('分区不符时不跨分区续页', () async {
    final repository = _FakeFileRepository();
    final container = ProviderContainer.test(
      overrides: [
        fileRepositoryProvider.overrideWithValue(repository),
        fileBrowserControllerProvider.overrideWith(
          () => _AppendController(_recentState()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await notifier.loadMoreFavoriteFiles();

    verifyNever(() => repository.listFavoriteFilesPage(page: 1, size: 2));
    expect(
      container.read(fileBrowserControllerProvider).value!.favoriteFiles,
      isEmpty,
    );
  });

  // 后端最近/收藏列表整表返回（Top50 不分页），却按请求 size 折算
  // totalPages：条目已取全时 hasMore 仍为真。守卫必须按已载入条数判定。
  test('条目已取全时不再发续页请求，即使 totalPages 谎报还有下一页', () async {
    final repository = _FakeFileRepository();
    final container = ProviderContainer.test(
      overrides: [
        fileRepositoryProvider.overrideWithValue(repository),
        fileBrowserControllerProvider.overrideWith(
          () => _AppendController(
            FileBrowserState(
              files: const <FileNode>[],
              recycleBin: const <FileNode>[],
              section: FileManagerSection.recent,
              recentFiles: <FileNode>[_node('r0'), _node('r1')],
              recentMeta: const FilesSubPageMeta(
                page: 0,
                size: 1,
                totalElements: 2,
                totalPages: 2,
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await notifier.loadMoreRecentFiles();

    verifyNever(
      () => repository.listRecentFilesPage(
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    );
  });

  // 续载过的分区被实时刷新顶回单页，会把手上的前几页挤掉。
  test('续载过的分区刷新按已载入条数整窗重取', () async {
    final repository = _FakeFileRepository();
    when(() => repository.listRecentFilesPage(page: 0, size: 4)).thenAnswer(
      (_) async => FileNodePage(
        items: <FileNode>[_node('r0'), _node('r1'), _node('r2'), _node('r3')],
        page: 0,
        size: 4,
        totalElements: 6,
        totalPages: 2,
      ),
    );
    final container = ProviderContainer.test(
      overrides: [
        fileRepositoryProvider.overrideWithValue(repository),
        fileBrowserControllerProvider.overrideWith(
          () => _AppendController(
            FileBrowserState(
              files: const <FileNode>[],
              recycleBin: const <FileNode>[],
              section: FileManagerSection.recent,
              recentFiles: <FileNode>[
                _node('r0'),
                _node('r1'),
                _node('r2'),
                _node('r3'),
              ],
              recentMeta: const FilesSubPageMeta(
                page: 1,
                size: 2,
                totalElements: 6,
                totalPages: 3,
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await notifier.refreshFileNodesForCurrentSection();

    verify(() => repository.listRecentFilesPage(page: 0, size: 4)).called(1);
    final state = container.read(fileBrowserControllerProvider).value!;
    expect(state.recentFiles.length, 4);
    expect(state.recentMeta.page, 0);
    expect(state.recentMeta.size, 4);
  });

  test('未续载时刷新仍只拉当前页窗', () async {
    final repository = _FakeFileRepository();
    when(() => repository.listRecentFilesPage(page: 2, size: 2)).thenAnswer(
      (_) async => FileNodePage(
        items: <FileNode>[_node('r4'), _node('r5')],
        page: 2,
        size: 2,
        totalElements: 6,
        totalPages: 3,
      ),
    );
    final container = ProviderContainer.test(
      overrides: [
        fileRepositoryProvider.overrideWithValue(repository),
        fileBrowserControllerProvider.overrideWith(
          () => _AppendController(
            FileBrowserState(
              files: const <FileNode>[],
              recycleBin: const <FileNode>[],
              section: FileManagerSection.recent,
              recentFiles: <FileNode>[_node('r4'), _node('r5')],
              recentMeta: const FilesSubPageMeta(
                page: 2,
                size: 2,
                totalElements: 6,
                totalPages: 3,
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await notifier.refreshFileNodesForCurrentSection();

    // 单页窗口（桌面跳页态）按目标页重取，不扩成整窗。
    verify(() => repository.listRecentFilesPage(page: 2, size: 2)).called(1);
  });
}
