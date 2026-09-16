import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/storage/local_database_provider.dart';
import 'package:omninest/features/reader/application/reader_cache_providers.dart';
import 'package:omninest/features/reader/application/reader_data_manager.dart';
import 'package:omninest/features/reader/application/reader_parsed_book_cache.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/data/reader_image_cache.dart';
import 'package:omninest/features/reader/data/reader_local_storage.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

// ─── Providers ──────────────────────────────────────────────────

/// 阅读器 API 客户端
final readerApiProvider = Provider<ReaderApi>((ref) {
  return ReaderApi(ref.watch(apiClientProvider));
});

/// 阅读器本地存储（共享 LocalDatabase 单例）
final readerLocalStorageProvider = Provider<ReaderLocalStorage>((ref) {
  return ReaderLocalStorage(ref.watch(localDatabaseProvider));
});

/// 阅读器数据管理器（离线优先写入）
final readerDataManagerProvider = Provider<ReaderDataManager>((ref) {
  return ReaderDataManager(
    api: ref.read(readerApiProvider),
    localStorage: ref.read(readerLocalStorageProvider),
  );
});

/// 仪表盘数据
final readerDashboardProvider = FutureProvider<ReaderDashboard>((ref) async {
  return ref.watch(readerApiProvider).dashboard();
});

/// 条目批注（详情页批注页签）
final readerItemAnnotationsProvider = FutureProvider.autoDispose
    .family<List<ReaderAnnotation>, String>((ref, itemId) {
      return ref.watch(readerApiProvider).annotations(itemId);
    });

/// 条目书签（详情页书签页签）
final readerItemBookmarksProvider = FutureProvider.autoDispose
    .family<List<ReaderBookmark>, String>((ref, itemId) {
      return ref.watch(readerApiProvider).bookmarks(itemId);
    });

/// 条目详情（含进度）
final readerItemDetailProvider = FutureProvider.autoDispose
    .family<ReaderItemDetail, String>((ref, itemId) {
      return ref.watch(readerApiProvider).detail(itemId);
    });

/// 阅读统计（读取前先重放离线队列，保证进度上传后再统计）
final readerStatsProvider = FutureProvider<ReaderReadingStats>((ref) async {
  final api = ref.watch(readerApiProvider);
  await ReaderSyncQueue.retryFailed();
  await ReaderSyncQueue.flush(api: api);
  return api.getStats();
});

/// 阅读统计概览（统计页与管理页历史区）：每日分钟数、完成/在读计数与在读列表。
final readerStatsOverviewProvider = FutureProvider<ReaderStatsOverview>((
  ref,
) async {
  return ref.watch(readerApiProvider).getStatsOverview(days: 14);
});

/// 阅读中心控制器
final readerCenterControllerProvider =
    AsyncNotifierProvider<ReaderCenterController, ReaderCenterState>(
      ReaderCenterController.new,
    );

// ─── Bookshelf Toggle Result ────────────────────────────────────

/// 书架切换操作结果
class BookshelfToggleResult {
  const BookshelfToggleResult({required this.addedToBookshelf});

  final bool addedToBookshelf;
}

// ─── State ──────────────────────────────────────────────────────

/// 阅读中心数据状态（书库/书架/统计/管理四个页面共享）
class ReaderCenterState {
  const ReaderCenterState({
    required this.dashboard,
    required this.items,
    required this.searchQuery,
    this.sortBy = ReaderSortBy.recent,
    this.librarySegment = ReaderLibrarySegment.all,
    this.errorMessage,
  });

  /// 空状态工厂
  factory ReaderCenterState.empty() => ReaderCenterState(
    dashboard: ReaderDashboard.empty(),
    items: const [],
    searchQuery: '',
  );

  final ReaderDashboard dashboard;
  final List<ReaderItem> items;
  final String searchQuery;
  final ReaderSortBy sortBy;
  final ReaderLibrarySegment librarySegment;
  final String? errorMessage;

  /// 继续阅读列表（来自仪表盘）
  List<ReaderItem> get continueItems => dashboard.continueReading;

  /// 书架页条目：已加入书架的条目（个人 + 共享）
  List<ReaderItem> get bookshelfItems =>
      items.where((i) => i.addedToBookshelf).toList();

  /// 书库页条目：分段过滤 + 排序 + 搜索后的可见条目
  List<ReaderItem> get visibleItems {
    var source = switch (librarySegment) {
      ReaderLibrarySegment.all => items,
      ReaderLibrarySegment.books => items.where((i) => !i.isComic).toList(),
      ReaderLibrarySegment.comics => items.where((i) => i.isComic).toList(),
    };

    final sorted = switch (sortBy) {
      ReaderSortBy.recent => source,
      ReaderSortBy.title => [...source]
        ..sort((a, b) => a.title.compareTo(b.title)),
    };

    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return sorted;
    return sorted
        .where(
          (i) =>
              i.title.toLowerCase().contains(query) ||
              (i.authorName?.toLowerCase().contains(query) ?? false),
        )
        .toList();
  }

  /// 复制状态
  ReaderCenterState copyWith({
    ReaderDashboard? dashboard,
    List<ReaderItem>? items,
    String? searchQuery,
    ReaderSortBy? sortBy,
    ReaderLibrarySegment? librarySegment,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ReaderCenterState(
      dashboard: dashboard ?? this.dashboard,
      items: items ?? this.items,
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      librarySegment: librarySegment ?? this.librarySegment,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// ─── Controller ─────────────────────────────────────────────────

/// 阅读中心控制器
class ReaderCenterController extends AsyncNotifier<ReaderCenterState> {
  ReaderApi get _api => ref.read(readerApiProvider);

  @override
  Future<ReaderCenterState> build() async {
    return _loadState();
  }

  /// 加载全部数据，部分失败不阻塞整体
  Future<ReaderCenterState> _loadState({
    String searchQuery = '',
    ReaderSortBy sortBy = ReaderSortBy.recent,
  }) async {
    // 错误随本次加载局部收集，实例字段会被并发 refresh 互相污染
    final partialErrors = <String>[];
    final results = await Future.wait([
      _safe(_api.dashboard, ReaderDashboard.empty(), partialErrors),
      _safe(() => _api.items(), <ReaderItem>[], partialErrors),
    ]);
    final dashboard = results[0] as ReaderDashboard;
    final items = results[1] as List<ReaderItem>;

    return ReaderCenterState(
      dashboard: dashboard,
      items: items,
      searchQuery: searchQuery,
      sortBy: sortBy,
      errorMessage: partialErrors.isEmpty ? null : partialErrors.join('；'),
    );
  }

  /// 安全执行异步调用，失败时记录到调用方传入的错误列表并返回 fallback
  Future<T> _safe<T>(
    Future<T> Function() call,
    T fallback,
    List<String> partialErrors,
  ) async {
    try {
      return await call();
    } on Exception catch (e) {
      partialErrors.add(describeUserFacingError(e).message);
      return fallback;
    }
  }

  /// 设置错误消息
  void _setError(String message) {
    final current = state.asData?.value;
    if (current != null) {
      state = AsyncData(current.copyWith(errorMessage: message));
    }
  }

  /// 清除错误消息
  void clearError() {
    final current = state.asData?.value;
    if (current != null) {
      state = AsyncData(current.copyWith(clearError: true));
    }
  }

  /// 刷新全部数据
  Future<void> refresh() async {
    await _refreshState(strict: false);
  }

  /// 严格刷新实时事件涉及的阅读数据并保留当前筛选。
  ///
  /// 由导入监控循环周期调用，避免每轮触发多余请求。
  Future<void> refreshForRealtime() async {
    await _refreshState(strict: true);
  }

  Future<void> _refreshState({required bool strict}) async {
    final current = state.asData?.value;
    final next = await _loadState(
      searchQuery: current?.searchQuery ?? '',
      sortBy: current?.sortBy ?? ReaderSortBy.recent,
    );
    if (strict && next.errorMessage != null) {
      throw StateError(next.errorMessage!);
    }
    // 保留分段状态
    state = AsyncData(
      next.copyWith(
        librarySegment: current?.librarySegment ?? ReaderLibrarySegment.all,
      ),
    );
  }

  /// 切换书库分段（全部/图书/漫画）
  void selectLibrarySegment(ReaderLibrarySegment segment) {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(librarySegment: segment));
  }

  /// 设置搜索关键词
  void setSearchQuery(String query) {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(searchQuery: query));
  }

  /// 设置排序方式
  void setSortBy(ReaderSortBy sortBy) {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(sortBy: sortBy));
  }

  /// 删除阅读条目。
  ///
  /// 默认级联永久删除源文件，与「删除书籍及其源文件」的产品语义一致。
  Future<TaskSubmission> deleteItem(
    String itemId, {
    bool cascade = true,
  }) async {
    try {
      final submission = await _api.deleteItem(itemId, cascade: cascade);
      final current = state.asData?.value;
      if (current != null) {
        state = AsyncData(
          current.copyWith(
            items: current.items.where((i) => i.id != itemId).toList(),
          ),
        );
      }
      ref.invalidate(activeTaskSummaryProvider);
      unawaited(ref.read(taskListProvider.notifier).load());
      unawaited(_cleanupDeletedItemAfterCompletion(itemId, submission.taskId));
      return submission;
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  Future<void> _cleanupDeletedItemAfterCompletion(
    String itemId,
    String taskId,
  ) async {
    try {
      final task = await ref.read(taskApiProvider).waitForTerminal(taskId);
      ref.invalidate(activeTaskSummaryProvider);
      unawaited(ref.read(taskListProvider.notifier).load());
      if (!task.isCompleted) {
        _setError(task.errorMessage ?? '阅读条目删除任务未完成');
        await _restoreItemAfterFailedDelete();
        return;
      }
      await Future.wait([
        ref.read(readerLocalStorageProvider).deleteAllForItem(itemId),
        ref.read(localBookCacheProvider).removeCache(itemId),
        ReaderImageCache.deleteForItem(itemId),
      ]);
      ref.read(readerParsedBookCacheProvider).remove(itemId);
      ref.invalidate(readerItemDetailProvider(itemId));
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      await _restoreItemAfterFailedDelete();
    }
  }

  /// 删除任务失败或等待超时时，恢复被乐观移除的条目。
  /// 后端删除失败则条目仍存在，重新加载列表即可回滚本地移除。
  Future<void> _restoreItemAfterFailedDelete() async {
    try {
      await refresh();
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
    }
  }

  /// 切换书架状态
  ///
  /// 调用 API 切换后全量刷新，以服务端 `addedToBookshelf` 为准同步书架列表。
  Future<BookshelfToggleResult> toggleBookshelf(String itemId) async {
    try {
      await _api.toggleBookshelf(itemId);
      await refresh();
      final item =
          state.asData?.value.items
              .where((item) => item.id == itemId)
              .firstOrNull;
      return BookshelfToggleResult(
        addedToBookshelf: item?.addedToBookshelf ?? false,
      );
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  // ─── 导入与元数据操作 ────────────────────────────────────────

  /// 导入文件到阅读器
  Future<ReaderItem> importFile({
    required String fileNodeId,
    bool force = false,
    String? contentKindOverride,
  }) async {
    try {
      final item = await _api.importFile(
        fileNodeId: fileNodeId,
        force: force,
        contentKindOverride: contentKindOverride,
      );
      await refresh();
      return item;
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).displayMessage);
      rethrow;
    }
  }

  /// 取消解析中的阅读条目并刷新书库状态。
  Future<void> cancelImport(String itemId) async {
    try {
      await _api.cancelImport(itemId);
      await refresh();
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).displayMessage);
      rethrow;
    }
  }

  /// 重新解析阅读条目。
  Future<ReaderItem> reparseItem(String itemId) async {
    try {
      final item = await _api.reparseItem(itemId);
      await refresh();
      return item;
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).displayMessage);
      rethrow;
    }
  }

  /// 更新条目元数据
  Future<void> updateItemMetadata({
    required String itemId,
    required Map<String, dynamic> fields,
  }) async {
    try {
      await _api.updateItemMetadata(itemId: itemId, fields: fields);
      await refresh();
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).displayMessage);
      rethrow;
    }
  }

  /// 获取导入候选文件列表
  Future<List<ReaderImportCandidate>> importCandidates() async {
    try {
      return await _api.importCandidates();
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).displayMessage);
      rethrow;
    }
  }

  /// 使用文件节点设置条目封面。
  Future<void> setCoverFromFile({
    required String itemId,
    required String fileNodeId,
  }) {
    return _api.setCoverFromFile(itemId: itemId, fileNodeId: fileNodeId);
  }

  /// 上传条目封面。
  Future<void> uploadCover({
    required String itemId,
    required Uint8List imageBytes,
    required String fileName,
  }) {
    return _api.uploadCover(
      itemId: itemId,
      imageBytes: imageBytes,
      fileName: fileName,
    );
  }
}
