import 'dart:async';
import 'package:omninest/app/session/session_epoch.dart';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/storage/local_database_provider.dart';
import 'package:omninest/features/files/file_dashboard.dart'
    show FileNode, listHostedFileNodes;
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/application/reader_data_manager.dart';
import 'package:omninest/features/reader/application/reader_image_provider.dart';
import 'package:omninest/features/reader/application/reader_progress_backup_port.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/data/reader_local_storage.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

// ─── Providers ──────────────────────────────────────────────────

/// 阅读器 API 客户端
final readerApiProvider = Provider<ReaderApi>((ref) {
  return ReaderApi(ref.watch(apiClientProvider));
});

/// 阅读器本地存储（共享 LocalDatabase 单例；章节正文/笔记等敏感列按当前用户加密）
final readerLocalStorageProvider = Provider<ReaderLocalStorage>((ref) {
  final userId = ref.watch(
    authSessionProvider.select((session) => session.value?.user?.id),
  );
  return ReaderLocalStorage(
    ref.watch(localDatabaseProvider),
    textCipher: ref.watch(offlineColumnCipherProvider),
    userId: userId,
  );
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
  ref.watch(sessionEpochProvider);
  return ref.watch(readerApiProvider).dashboard();
});

/// 条目批注（详情页批注页签）
///
/// 必须走离线优先的 ReaderDataManager：阅读页里的增删改先落 SQLite 并排进同步队列，
/// 直接打服务端会看不到未上传的改动，离线时整页报错。
final readerItemAnnotationsProvider = FutureProvider.autoDispose
    .family<List<ReaderAnnotation>, String>(
      (ref, itemId) =>
          ref.watch(readerDataManagerProvider).loadAnnotations(itemId),
    );

/// Reader 空间「最近笔记」：跨书最近标注（本地缓存按创建时间倒序）。
final readerRecentAnnotationsProvider =
    FutureProvider.autoDispose<List<ReaderAnnotation>>((ref) {
      final storage = ref.watch(readerLocalStorageProvider);
      return storage.loadRecentAnnotations(limit: 6);
    });

/// 条目书签（详情页书签页签）
///
/// 与批注同源：书签在阅读页是本地先写、退出时才 flush 队列，直连接口会漏掉未同步的那份。
final readerItemBookmarksProvider = FutureProvider.autoDispose.family<
  List<ReaderBookmark>,
  String
>((ref, itemId) => ref.watch(readerDataManagerProvider).loadBookmarks(itemId));

/// 条目详情（含进度）
final readerItemDetailProvider = FutureProvider.autoDispose
    .family<ReaderItemDetail, String>((ref, itemId) {
      return ref.watch(readerApiProvider).detail(itemId);
    });

/// 阅读统计（读取前先重放离线队列，保证进度上传后再统计）
final readerStatsProvider = FutureProvider<ReaderReadingStats>((ref) async {
  ref.watch(sessionEpochProvider);
  final api = ref.watch(readerApiProvider);
  await ReaderSyncQueue.retryFailed();
  await ReaderSyncQueue.flush(api: api);
  return api.getStats();
});

/// 阅读统计概览（统计页与管理页历史区）：每日分钟数、完成/在读计数与在读列表。
final readerStatsOverviewProvider = FutureProvider<ReaderStatsOverview>((
  ref,
) async {
  ref.watch(sessionEpochProvider);
  // 读取前先重放离线队列：刚退出阅读页就查看统计时，本机会话
  // 仍躺在队列里未上传，会呈现滞后一拍的旧数据。
  final api = ref.watch(readerApiProvider);
  await ReaderSyncQueue.retryFailed();
  await ReaderSyncQueue.flush(api: api);
  return api.getStatsOverview(days: 14);
});

/// 阅读中心控制器
final readerCenterControllerProvider =
    AsyncNotifierProvider<ReaderCenterController, ReaderCenterState>(
      ReaderCenterController.new,
    );

/// 书架成员变更计数：加入或移出书架时递增，书架分页据此重建。
///
/// 书架窗口是独立分页，不能靠书库列表的派生过滤维持；用递增令牌驱动重建，
/// 避免阅读中心反向依赖书架控制器形成同特性内的循环引用。
final readerBookshelfRevisionProvider =
    NotifierProvider<ReaderBookshelfRevision, int>(ReaderBookshelfRevision.new);

class ReaderBookshelfRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state = state + 1;
  }
}

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
    this.itemsPage = -1,
    this.itemsHasMore = false,
    this.itemsLoadingMore = false,
  });

  /// 空状态工厂
  factory ReaderCenterState.empty() => ReaderCenterState(
    dashboard: ReaderDashboard.empty(),
    items: const [],
    searchQuery: '',
  );

  final ReaderDashboard dashboard;
  final List<ReaderItem> items;

  /// 条目滚动加载分页：itemsPage 为已加载末页（-1 未加载）。
  final int itemsPage;
  final bool itemsHasMore;
  final bool itemsLoadingMore;
  final String searchQuery;
  final ReaderSortBy sortBy;
  final ReaderLibrarySegment librarySegment;
  final String? errorMessage;

  /// 继续阅读列表（来自仪表盘）
  List<ReaderItem> get continueItems => dashboard.continueReading;

  /// 书库页条目：服务端已按分段与关键词过滤，这里只做客户端排序。
  List<ReaderItem> get visibleItems {
    if (sortBy == ReaderSortBy.title) {
      return [...items]..sort((a, b) => a.title.compareTo(b.title));
    }
    return items;
  }

  /// 复制状态
  ReaderCenterState copyWith({
    ReaderDashboard? dashboard,
    List<ReaderItem>? items,
    int? itemsPage,
    bool? itemsHasMore,
    bool? itemsLoadingMore,
    String? searchQuery,
    ReaderSortBy? sortBy,
    ReaderLibrarySegment? librarySegment,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ReaderCenterState(
      dashboard: dashboard ?? this.dashboard,
      items: items ?? this.items,
      itemsPage: itemsPage ?? this.itemsPage,
      itemsHasMore: itemsHasMore ?? this.itemsHasMore,
      itemsLoadingMore: itemsLoadingMore ?? this.itemsLoadingMore,
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

  /// 取数完成后的回写基准。
  ///
  /// 完成回调不得拿 `await` 之前抓的快照整份发布：那段窗口里发生的写入（书库分段、
  /// 搜索词、排序、续载窗口）会被旧快照无声覆盖，表现为刚切完分段又被弹回旧分段。
  /// 优先取发布时刻的实况；仅在状态尚未就绪（首帧取数、错误态、刷新中的 loading 态）
  /// 时退回快照，与改动前的空值口径一致。
  ReaderCenterState _liveOr(ReaderCenterState? captured) =>
      state.asData?.value ?? captured ?? ReaderCenterState.empty();

  /// 条目取数的筛选代际：分段与关键词已下沉服务端查询参数，一次筛选变更即换代。
  /// 在途响应代际不符时直接丢弃，否则旧筛选的那页会覆盖用户刚切到的新结果。
  int _itemsGeneration = 0;

  /// 搜索去抖定时器：控制器持有的异步资源必须随 Provider 一起释放。
  Timer? _searchDebounce;

  /// 搜索去抖时长：比一次输入停顿短，比逐字符请求长。
  static const _searchDebounceDelay = Duration(milliseconds: 300);

  /// 分段与关键词对应的服务端查询参数。
  static ({String? contentKind, String? query}) _serverFilters(
    ReaderCenterState from,
  ) {
    return (
      contentKind: switch (from.librarySegment) {
        ReaderLibrarySegment.all => null,
        ReaderLibrarySegment.books => 'TEXT',
        ReaderLibrarySegment.comics => 'COMIC',
      },
      query: from.searchQuery.trim().isEmpty ? null : from.searchQuery.trim(),
    );
  }

  @override
  Future<ReaderCenterState> build() async {
    // 换号时以依赖变化语义重建，避免渲染上一账号的旧值。
    ref.watch(sessionEpochProvider);
    ref.onDispose(() => _searchDebounce?.cancel());
    return _loadState(ReaderCenterState.empty());
  }

  /// 加载仪表盘与条目首页，部分失败不阻塞整体。
  ///
  /// 调用方负责在发布前核对代际：本方法只取数，不知道返回的结果是否已经过期。
  Future<ReaderCenterState> _loadState(ReaderCenterState from) async {
    // 错误随本次加载局部收集，实例字段会被并发 refresh 互相污染
    final partialErrors = <String>[];
    final filters = _serverFilters(from);
    final results = await Future.wait([
      _safe(_api.dashboard, ReaderDashboard.empty(), partialErrors),
      _safe(
        () => _api.itemsPage(
          contentKind: filters.contentKind,
          query: filters.query,
        ),
        _emptyItemsPage,
        partialErrors,
      ),
    ]);
    final dashboard = results[0] as ReaderDashboard;
    final itemPage = results[1] as ReaderItemPage;

    return ReaderCenterState(
      dashboard: dashboard,
      items: itemPage.items,
      itemsPage: itemPage.page,
      itemsHasMore: itemPage.hasMore,
      searchQuery: from.searchQuery,
      sortBy: from.sortBy,
      librarySegment: from.librarySegment,
      errorMessage: partialErrors.isEmpty ? null : partialErrors.join('；'),
    );
  }

  /// 条目滚动加载续页：以 id 去重追加，失败回滚门闩等待下次触底。
  Future<void> loadMoreItems() async {
    final current = state.asData?.value;
    if (current == null || !current.itemsHasMore || current.itemsLoadingMore) {
      return;
    }
    final generation = _itemsGeneration;
    final filters = _serverFilters(current);
    state = AsyncData(current.copyWith(itemsLoadingMore: true));
    try {
      final next = await _api.itemsPage(
        contentKind: filters.contentKind,
        query: filters.query,
        page: current.itemsPage + 1,
      );
      final latest = state.asData?.value;
      if (latest == null || generation != _itemsGeneration) {
        // 换代说明用户已经切了分段或改了关键词：这一页属于旧窗口，不能追加。
        return;
      }
      final seen = latest.items.map((item) => item.id).toSet();
      state = AsyncData(
        latest.copyWith(
          items: <ReaderItem>[
            ...latest.items,
            ...next.items.where((item) => !seen.contains(item.id)),
          ],
          itemsPage: next.page,
          itemsHasMore: next.hasMore,
          itemsLoadingMore: false,
        ),
      );
    } on Exception {
      final latest = state.asData?.value;
      if (latest != null) {
        state = AsyncData(latest.copyWith(itemsLoadingMore: false));
      }
    }
  }

  /// 空条目分页兜底：首页加载失败时保持空窗口而非整页失败。
  static const _emptyItemsPage = ReaderItemPage(
    items: <ReaderItem>[],
    page: 0,
    size: 50,
    totalElements: 0,
    totalPages: 0,
  );

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
    final generation = ++_itemsGeneration;
    final next = await _loadState(current ?? ReaderCenterState.empty());
    if (strict && next.errorMessage != null) {
      throw StateError(next.errorMessage!);
    }
    if (generation != _itemsGeneration) {
      // 取数在飞期间用户已经换了筛选并另起一轮：这一份属于旧条件，丢弃。
      return;
    }
    // 排序仍是客户端位，取数期间用户可能改过；发布基准必须取发布时刻的实况。
    final live = _liveOr(current);
    state = AsyncData(
      next.copyWith(
        librarySegment: live.librarySegment,
        searchQuery: live.searchQuery,
        sortBy: live.sortBy,
      ),
    );
  }

  /// 切换书库分段（全部/图书/漫画）：按新条件重取服务端第一页。
  void selectLibrarySegment(ReaderLibrarySegment segment) {
    final current = state.asData?.value;
    if (current == null || current.librarySegment == segment) {
      return;
    }
    _applyItemFilters(current.copyWith(librarySegment: segment));
  }

  /// 设置搜索关键词：先去抖，再按新关键词重取服务端第一页。
  ///
  /// 关键词已经是查询参数：逐字符发请求等于每敲一键打一次后端。
  void setSearchQuery(String query) {
    final current = state.asData?.value;
    if (current == null || current.searchQuery == query) {
      return;
    }
    state = AsyncData(current.copyWith(searchQuery: query));
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDelay, _reloadItemsWithLiveFilters);
  }

  /// 以当前实况筛选条件重取首页（去抖到点后的搜索入口）。
  void _reloadItemsWithLiveFilters() {
    final live = state.asData?.value;
    if (live == null) {
      return;
    }
    _applyItemFilters(live);
  }

  /// 发布新筛选并按服务端条件重取首页。
  ///
  /// 分段与关键词是查询参数而不是内存过滤位：不重取就只能看见已加载窗口里的那几本，
  /// 排在第 51 本之后的漫画和搜到的书永远出不来。
  void _applyItemFilters(ReaderCenterState next) {
    _searchDebounce?.cancel();
    final generation = ++_itemsGeneration;
    // 换代后旧续页的在飞回包会被丢弃，续载门闩必须跟着新窗口一起复位，
    // 否则一次筛选切换就把触底加载永久锁死。
    state = AsyncData(next.copyWith(itemsLoadingMore: false));
    unawaited(
      _loadState(next).then((loaded) {
        if (generation != _itemsGeneration) {
          return;
        }
        final live = _liveOr(next);
        state = AsyncData(
          loaded.copyWith(
            librarySegment: live.librarySegment,
            searchQuery: live.searchQuery,
            sortBy: live.sortBy,
          ),
        );
      }),
    );
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
      await ref.read(readerLocalStorageProvider).deleteAllForItem(itemId);
      // 进程内解析缓存、书级样式表池、章节正文备忘和归档句柄都挂在 itemId 上；
      // 只清 SQLite 会让同一进程里重新导入同名的书读到旧正文。
      await invalidateBookCache(ref, itemId);
      ReaderCoverByteCache.remove(itemId);
      ReaderProgressBackupWeb.clear(itemId);
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

  /// 设定书架状态
  ///
  /// 目标状态由调用方按当前事实取反后显式传入，避免请求重放把收藏翻回去；
  /// 写入后全量刷新，以服务端 `addedToBookshelf` 为准同步书架列表。
  Future<BookshelfToggleResult> setBookshelf(
    String itemId, {
    required bool onBookshelf,
  }) async {
    try {
      await _api.setBookshelf(itemId, onBookshelf: onBookshelf);
      await refresh();
      ref.read(readerBookshelfRevisionProvider.notifier).bump();
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
  ///
  /// 解析缓存必须一起作废：缓存里是旧的书籍结构与逐章正文，只刷新条目列表的话，
  /// 读者看到的还是重解析前的内容，看起来"点了没反应"。详情页那条入口以前就是
  /// 这样漏的，所以作废动作放在这里，而不是等每个调用点自己记得清。
  Future<ReaderItem> reparseItem(String itemId) async {
    try {
      final item = await _api.reparseItem(itemId);
      await invalidateBookCache(ref, itemId);
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

  /// 获取导入候选文件列表；truncated 表示服务端按上限截断。
  Future<ReaderImportCandidates> importCandidates() async {
    try {
      return await _api.importCandidates();
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).displayMessage);
      rethrow;
    }
  }

  /// 列出可用于封面的托管图片节点。
  ///
  /// 后端导入候选接口按 `isReaderFile` 过滤，只返回书籍类型，永远不含图片；
  /// 封面候选必须走文件模块的分类查询（数据库侧已限定 FILE 且排除派生与本地只读）。
  Future<List<ReaderCoverCandidate>> coverCandidates() async {
    try {
      final nodes = await listHostedFileNodes(ref, category: 'image');
      return [
        for (final FileNode node in nodes)
          if (node.id.isNotEmpty)
            ReaderCoverCandidate(fileNodeId: node.id, fileName: node.name),
      ];
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
