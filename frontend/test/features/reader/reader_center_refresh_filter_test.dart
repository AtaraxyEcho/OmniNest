// 书库筛选的服务端分页契约。
//
// 分段与关键词是服务端查询参数：只在已加载窗口里做内存过滤，会让排在第 51 本之后
// 的漫画与命中的书名永远出不来。同时 `_refreshState` 的取数窗口里用户可能已经切过
// 分段、改过搜索词与排序，回包若按 `await` 之前抓的快照发布，就会把刚做的筛选无声
// 写回旧值（导入完成与实时事件高频触发这条路径）。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';

class _Request {
  const _Request({this.contentKind, this.query, required this.page});

  final String? contentKind;
  final String? query;
  final int page;
}

class _GatedReaderApi implements ReaderApi {
  _GatedReaderApi();

  final ReaderDashboard dashboardValue = ReaderDashboard.empty();

  /// 回哪一页内容由用例决定：默认给一页空窗口。
  ReaderItemPage Function(_Request request) pageFor =
      (_) => const ReaderItemPage(
        items: <ReaderItem>[],
        page: 0,
        size: 50,
        totalElements: 0,
        totalPages: 0,
      );

  final List<_Request> requests = <_Request>[];

  /// 门控：未 complete 前取数不返回，用来制造「取数在飞、用户改筛选」的窗口。
  Completer<void> gate = Completer<void>()..complete();

  @override
  Future<ReaderDashboard> dashboard() async {
    await gate.future;
    return dashboardValue;
  }

  @override
  Future<ReaderItemPage> itemsPage({
    String? itemType,
    String? contentKind,
    String? query,
    int page = 0,
    int size = 50,
  }) async {
    final request = _Request(
      contentKind: contentKind,
      query: query,
      page: page,
    );
    requests.add(request);
    await gate.future;
    return pageFor(request);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

ReaderItem _item(String id, {bool comic = false}) => ReaderItem(
  id: id,
  title: id,
  itemType: comic ? 'CBZ' : 'EPUB',
  contentKind: comic ? 'COMIC' : 'TEXT',
  updatedAt: null,
);

/// 多页书库：翻页号写进条目 id，便于断言窗口里混进了哪一页。
void _serveNumberedPages(_GatedReaderApi api) {
  api.pageFor =
      (request) => ReaderItemPage(
        items: [_item('book-${request.page}')],
        page: request.page,
        size: 50,
        totalElements: 200,
        totalPages: 4,
      );
}

ProviderContainer _container(_GatedReaderApi api) {
  final container = ProviderContainer.test(
    overrides: [readerApiProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  return container;
}

/// 越过控制器里的搜索去抖窗口，让排队的服务端请求真正发出。
Future<void> _waitForSearchDebounce() =>
    Future<void>.delayed(const Duration(milliseconds: 400));

void main() {
  test('刷新期间的分段、搜索词与排序不被取数前的快照写回', () async {
    final api = _GatedReaderApi();
    final container = _container(api);
    await container.read(readerCenterControllerProvider.future);

    final notifier = container.read(readerCenterControllerProvider.notifier);
    api.gate = Completer<void>();
    final pending = notifier.refresh();
    // 让 refresh 真正进到取数挂起状态，再改筛选位。
    await Future<void>.delayed(Duration.zero);
    notifier.selectLibrarySegment(ReaderLibrarySegment.books);
    notifier.setSearchQuery('三体');
    notifier.setSortBy(ReaderSortBy.title);

    api.gate.complete();
    await pending;
    await Future<void>.delayed(Duration.zero);

    final state = container.read(readerCenterControllerProvider).value!;
    expect(state.librarySegment, ReaderLibrarySegment.books);
    expect(state.searchQuery, '三体');
    expect(state.sortBy, ReaderSortBy.title);
  });

  test('分段与关键词下沉服务端查询参数，而不是客户端过滤已加载窗口', () async {
    final api = _GatedReaderApi();
    final container = _container(api);
    await container.read(readerCenterControllerProvider.future);
    // 首屏不带任何筛选。
    expect(api.requests.single.contentKind, isNull);
    expect(api.requests.single.query, isNull);

    api.pageFor =
        (request) => ReaderItemPage(
          items: [_item('manga-1', comic: true)],
          page: request.page,
          size: 50,
          totalElements: 60,
          totalPages: 2,
        );
    final notifier = container.read(readerCenterControllerProvider.notifier);
    notifier.selectLibrarySegment(ReaderLibrarySegment.comics);
    await Future<void>.delayed(Duration.zero);
    expect(api.requests.last.contentKind, 'COMIC');

    notifier.setSearchQuery('  一拳  ');
    await _waitForSearchDebounce();
    expect(api.requests.last.contentKind, 'COMIC');
    // 关键词两侧空白不进查询串。
    expect(api.requests.last.query, '一拳');

    final state = container.read(readerCenterControllerProvider).value!;
    expect(state.visibleItems.map((item) => item.id), ['manga-1']);
  });

  test('连续输入只发一次服务端请求', () async {
    final api = _GatedReaderApi();
    final container = _container(api);
    await container.read(readerCenterControllerProvider.future);
    final notifier = container.read(readerCenterControllerProvider.notifier);

    notifier.setSearchQuery('三');
    notifier.setSearchQuery('三体');
    notifier.setSearchQuery('三体x');
    // 去抖窗口内不打下游请求。
    expect(api.requests, hasLength(1));

    await _waitForSearchDebounce();
    expect(api.requests, hasLength(2));
    expect(api.requests.last.query, '三体x');
  });

  test('清空关键词回到不带筛选的服务端查询', () async {
    final api = _GatedReaderApi();
    final container = _container(api);
    await container.read(readerCenterControllerProvider.future);
    final notifier = container.read(readerCenterControllerProvider.notifier);

    notifier.setSearchQuery('三体');
    await _waitForSearchDebounce();
    expect(api.requests.last.query, '三体');

    notifier.setSearchQuery('');
    await _waitForSearchDebounce();
    expect(api.requests.last.query, isNull);
  });

  test('续页沿用当前筛选', () async {
    final api = _GatedReaderApi();
    _serveNumberedPages(api);
    final container = _container(api);
    await container.read(readerCenterControllerProvider.future);

    final notifier = container.read(readerCenterControllerProvider.notifier);
    notifier.selectLibrarySegment(ReaderLibrarySegment.books);
    notifier.setSearchQuery('三体');
    await _waitForSearchDebounce();

    await notifier.loadMoreItems();
    expect(api.requests.last.page, 1);
    expect(api.requests.last.contentKind, 'TEXT');
    expect(api.requests.last.query, '三体');
  });

  test('旧筛选在飞的续页回包不得追加进新窗口', () async {
    final api = _GatedReaderApi();
    _serveNumberedPages(api);
    final container = _container(api);
    await container.read(readerCenterControllerProvider.future);

    final notifier = container.read(readerCenterControllerProvider.notifier);
    // 第 1 页在飞：门控未开。
    api.gate = Completer<void>();
    final pendingMore = notifier.loadMoreItems();
    await Future<void>.delayed(Duration.zero);
    expect(api.requests.last.page, 1);

    // 期间用户切到漫画分段：新一代筛选自己重取首页。
    notifier.selectLibrarySegment(ReaderLibrarySegment.comics);
    api.gate.complete();
    await pendingMore;
    await Future<void>.delayed(Duration.zero);

    final state = container.read(readerCenterControllerProvider).value!;
    // 旧分段的第 1 页不能混进漫画窗口，窗口里只有新首页。
    expect(state.items.map((item) => item.id), ['book-0']);
    expect(api.requests.last.contentKind, 'COMIC');
  });
}
