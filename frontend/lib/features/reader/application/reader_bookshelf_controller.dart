import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';

/// 书架一页的条目数：与服务端默认页尺寸一致。
const int kReaderBookshelfPageSize = 50;

/// 书架分页状态。
///
/// 条目窗口只含已加入书架的条目，`totalElements` 取服务端计数，因此头部数字
/// 不随已加载页数变化。
class ReaderBookshelfState {
  const ReaderBookshelfState({
    this.items = const <ReaderItem>[],
    this.page = 0,
    this.totalElements = 0,
    this.hasMore = false,
    this.loadingMore = false,
    this.errorMessage,
  });

  factory ReaderBookshelfState.fromPage(ReaderItemPage first) {
    return ReaderBookshelfState(
      items: first.items,
      page: first.page,
      totalElements: first.totalElements,
      hasMore: first.hasMore,
    );
  }

  final List<ReaderItem> items;
  final int page;
  final int totalElements;
  final bool hasMore;
  final bool loadingMore;
  final String? errorMessage;

  ReaderBookshelfState copyWith({
    List<ReaderItem>? items,
    int? page,
    int? totalElements,
    bool? hasMore,
    bool? loadingMore,
    String? errorMessage,
  }) {
    return ReaderBookshelfState(
      items: items ?? this.items,
      page: page ?? this.page,
      totalElements: totalElements ?? this.totalElements,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// 书架分页控制器。
///
/// 与书库共用 `/reader/items/page`，但带上 `bookshelfOnly`：过滤发生在服务端分页
/// 之前，所以一页里不会全是未加架条目、总数也不掺进水书库的书。
final readerBookshelfControllerProvider =
    AsyncNotifierProvider<ReaderBookshelfController, ReaderBookshelfState>(
      ReaderBookshelfController.new,
    );

class ReaderBookshelfController extends AsyncNotifier<ReaderBookshelfState> {
  int _generation = 0;

  ReaderApi get _api => ref.read(readerApiProvider);

  @override
  Future<ReaderBookshelfState> build() {
    // 换号时以依赖变化语义重建，避免渲染上一账号的旧书架。
    ref.watch(sessionEpochProvider);
    // 加架/移架后重取第一页：窗口只含已加架条目，本地增删无法维持分页与总数一致。
    ref.watch(readerBookshelfRevisionProvider);
    return _loadFirstPage();
  }

  Future<ReaderBookshelfState> _loadFirstPage() async {
    try {
      final first = await _api.itemsPage(
        bookshelfOnly: true,
        size: kReaderBookshelfPageSize,
      );
      return ReaderBookshelfState.fromPage(first);
    } on Exception catch (e) {
      return ReaderBookshelfState(
        errorMessage: describeUserFacingError(e).message,
      );
    }
  }

  /// 重新取第一页；失败时保留已加载窗口，与阅读器其余列表一致不整页失败。
  Future<void> refresh() async {
    final generation = ++_generation;
    final next = await _loadFirstPage();
    if (generation != _generation) {
      return;
    }
    state = AsyncData(next);
  }

  /// 触底续页：以 id 去重追加，失败回滚门闩等待下次触底。
  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || !current.hasMore || current.loadingMore) {
      return;
    }
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await _api.itemsPage(
        bookshelfOnly: true,
        page: current.page + 1,
        size: kReaderBookshelfPageSize,
      );
      final latest = state.asData?.value;
      if (latest == null || generation != _generation) {
        // 取数在飞期间已另起一轮（刷新或换号）：这一页属于旧窗口，不能追加。
        return;
      }
      final seen = latest.items.map((item) => item.id).toSet();
      state = AsyncData(
        latest.copyWith(
          items: <ReaderItem>[
            ...latest.items,
            ...next.items.where((item) => !seen.contains(item.id)),
          ],
          page: next.page,
          totalElements: next.totalElements,
          hasMore: next.hasMore,
          loadingMore: false,
        ),
      );
    } on Exception {
      final latest = state.asData?.value;
      if (latest != null) {
        state = AsyncData(latest.copyWith(loadingMore: false));
      }
    }
  }

  /// 收起错误横幅：保留已加载窗口，只清掉本次的失败提示。
  void clearError() {
    final current = state.asData?.value;
    if (current?.errorMessage == null) {
      return;
    }
    state = AsyncData(
      ReaderBookshelfState(
        items: current!.items,
        page: current.page,
        totalElements: current.totalElements,
        hasMore: current.hasMore,
        loadingMore: current.loadingMore,
      ),
    );
  }
}
