import 'dart:async';
import 'package:omninest/app/session/session_epoch.dart';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_codes.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/files/application/file_browser_models.dart';
import 'package:omninest/features/files/data/file_providers.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_operation.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_repository.dart';
import 'package:omninest/features/files/domain/file_upload_session.dart';
import 'package:omninest/features/files/domain/upload_part_size.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';

export 'package:omninest/features/files/data/file_providers.dart';
export 'package:omninest/features/files/application/file_browser_models.dart';

part 'file_browser_selection_actions.dart';
part 'file_browser_upload_actions.dart';
part 'file_browser_integration_actions.dart';
part 'file_browser_page_mappers.dart';

final fileBrowserControllerProvider =
    AsyncNotifierProvider<FileBrowserController, FileBrowserState>(
      FileBrowserController.new,
    );

/// 提供文件模块的存储摘要只读视图。
final fileStorageStatsProvider = FutureProvider<FileStorageStats>((ref) {
  ref.watch(sessionEpochProvider);
  return ref.watch(fileApiProvider).storageStats();
});

class FileBrowserController extends AsyncNotifier<FileBrowserState> {
  FileRepository get _repository => ref.read(fileRepositoryProvider);

  /// 上传动作扩展访问任务轮询接口的出口；扩展不是 Notifier 子类，不能直接用 ref。
  Ref get uploadRef => ref;

  /// 文件仓储（展示层版本历史对话框直接读取）。
  FileBrowserState? get _currentState => state.asData?.value;

  void _emitState(FileBrowserState nextState) {
    state = AsyncData(nextState);
  }

  /// 取数或远端动作完成后的回写基准。
  ///
  /// 完成回调不得拿 `await` 之前抓的快照整份发布：那段窗口里发生的写入（移动端子页态、
  /// 多选、视图模式、分页窗口）会被旧快照无声覆盖，真机表现为点分区卡后闪一下又弹回
  /// 模块首页。优先取发布时刻的实况；仅在状态尚未就绪（首帧取数、错误态）时退回快照。
  /// 新增同类回写点由 `test/architecture/async_state_publish_ratchet_test.dart` 拦住。
  FileBrowserState _liveOr(FileBrowserState? captured) =>
      state.asData?.value ??
      captured ??
      const FileBrowserState(files: [], recycleBin: []);

  /// 导航世代号：分区切换、进入/回退目录与空间切换共用一条序号。发起方在取数前领取
  /// 自己的世代号，回包时若已被后来的导航超过就直接丢弃，否则晚到的旧回包会把用户
  /// 已经离开的层级重新压回页面（连点两张分区卡时表现为停在先点的那一页）。
  int _beginNavigation() => ++_navigationGeneration;

  bool _isStaleNavigation(int navigation) =>
      navigation != _navigationGeneration;

  /// 分区乐观写：切换分区时先落 `section` 并清搜索词，取数回包不再碰这两项，
  /// 于是「子页 chrome 已收起、正文仍是上一分区」的中间帧与旧回包拖回上一页的
  /// 竞态都只由这一处发起。同分区重复取数（实时刷新、下拉刷新）不产出新状态。
  void _applySectionOptimistically(FileManagerSection section) {
    final live = state.asData?.value;
    if (live == null || live.section == section) {
      return;
    }
    _beginNavigation();
    // 分区切换等于换上下文：搜索词与分类筛选一起归零，否则会带着上个分区的
    // 分类条件进入新分区，列表莫名只剩一类文件。
    state = AsyncData(
      live.copyWith(
        section: section,
        searchQuery: '',
        fileCategory: FileBrowserFileCategory.all,
      ),
    );
  }

  /// 导航世代计数，见 `_beginNavigation`。
  int _navigationGeneration = 0;

  final Map<String, _UploadRuntime> _uploadRuntimes = {};
  final Map<
    String,
    ({
      SoftDeleteConflict conflict,
      XFile file,
      String fileName,
      int sizeBytes,
      String mimeType,
    })
  >
  _pendingConflicts = {};
  Timer? _uploadQueuePollTimer;
  Timer? _importTaskPollTimer;
  int _externalBrowseRequestGeneration = 0;

  @override
  Future<FileBrowserState> build() async {
    // 换号时以依赖变化语义重建，避免渲染上一账号的旧值。
    ref.watch(sessionEpochProvider);
    ref.onDispose(() {
      _uploadQueuePollTimer?.cancel();
      _uploadQueuePollTimer = null;
      _importTaskPollTimer?.cancel();
      _importTaskPollTimer = null;
    });
    final filesPage = await _repository.listFilesPage();
    final stats = await _repository.storageStats();
    List<FileUploadQueueItem> uploadQueue = const [];
    try {
      uploadQueue = await _repository.listUploadQueue();
    } on Exception {
      // 上传队列获取失败不影响主初始化
    }
    List<FileNode> favoriteFiles = const [];
    try {
      // 预载收藏列表：任意分区的行内星标都需要已收藏状态。
      favoriteFiles = await _repository.listFavoriteFiles();
    } on Object {
      // 收藏列表获取失败（含测试假体 UnimplementedError 属 Error 非
      // Exception）不影响主初始化。
    }
    return FileBrowserState(
      files: filesPage.items,
      recycleBin: const [],
      storageStats: stats,
      uploadQueue: uploadQueue,
      favoriteFiles: favoriteFiles,
      filePage: filesPage.page,
      filePageSize: filesPage.size,
      fileTotalElements: filesPage.totalElements,
      fileTotalPages: filesPage.totalPages,
    );
  }

  void clearActionError() {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    state = AsyncData(current.copyWith(clearLastActionError: true));
  }

  /// 切换移动端子页态：由壳层读取，决定收起还是露出顶栏与底部 tab。
  void setMobileSubpage(bool subpage) {
    final current = state.asData?.value;
    if (current == null || current.mobileSubpage == subpage) {
      return;
    }
    state = AsyncData(current.copyWith(mobileSubpage: subpage));
  }

  /// 异步任务提交成功后刷新全局任务摘要徽标。
  void notifyTaskSubmitted() {
    ref.invalidate(activeTaskSummaryProvider);
  }

  Future<T> _runAction<T>(
    FileOperation operation,
    Future<T> Function() action,
  ) async {
    _setBusy(operation, background: _backgroundLoad);
    try {
      final result = await action();
      _clearBusy();
      return result;
    } catch (error) {
      _recordActionError(operation, error);
      _clearBusy();
      rethrow;
    }
  }

  /// 最近本地文件变更的自回声记录：fileId -> 过期时刻。
  /// 后端为每次节点变更（建夹/重命名/删除/恢复/移动/复制/收藏…）记录
  /// FILES 作用域同步事件，事件经实时通道回到本机会触发 FileSyncHandler
  /// 全量刷新；本地动作自身已完成状态收敛，这份“自回落”只会造成列表
  /// 闪烁刷新，须按窗口抑制。其他设备的变更没有本地记录，仍走全量刷新。
  final Map<String, DateTime> _recentFileEchoes = {};

  static const Duration _fileEchoWindow = Duration(seconds: 15);

  /// 登记一次本地文件变更（供实时回声抑制查询）。
  void registerFileEcho(Iterable<String> fileIds) {
    final expiry = DateTime.now().add(_fileEchoWindow);
    for (final fileId in fileIds) {
      _recentFileEchoes[fileId] = expiry;
    }
  }

  /// 判断一批资源是否全部命中本地回声窗口；
  /// 顺带清理过期条目。空集返回 false（保守走刷新）。
  bool matchesRecentFileEchoes(Set<String> fileIds) {
    final now = DateTime.now();
    _recentFileEchoes.removeWhere((_, expiry) => expiry.isBefore(now));
    if (fileIds.isEmpty) {
      return false;
    }
    return fileIds.every(_recentFileEchoes.containsKey);
  }

  /// 静默快操作：不进入 busy 门控（避免 0→1→0 双次全量状态发射造成
  /// 工具栏禁用态闪烁与全列表重建），仅记录失败；成功后的状态更新由
  /// 动作体自身发出（如收藏缓存刷新）。适用于毫秒级本地感知操作。
  Future<void> _runQuietAction(
    FileOperation operation,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      _recordActionError(operation, error);
    }
  }

  void _setBusy(FileOperation operation, {bool background = false}) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        activeActionCount: current.activeActionCount + 1,
        activeOperation: operation,
        clearLastActionError: true,
        backgroundRefresh: background,
      ),
    );
  }

  void _clearBusy() {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    final nextCount =
        current.activeActionCount > 0 ? current.activeActionCount - 1 : 0;
    state = AsyncData(
      current.copyWith(
        activeActionCount: nextCount,
        clearActiveOperationLabel: nextCount == 0,
        backgroundRefresh: nextCount > 0 && current.backgroundRefresh,
      ),
    );
  }

  void _recordActionError(FileOperation operation, Object error) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    final described = describeUserFacingError(error);
    state = AsyncData(
      current.copyWith(
        lastActionError: FileBrowserActionError(
          operation: operation,
          message: described.message,
          code: described.code,
        ),
      ),
    );
  }

  /// 刷新文件列表数据，保留当前分区、目录、筛选条件与页窗。
  ///
  /// 未续载过时只拉当前页（跳页与分页条范围一一对应，目标页越界回退到新的
  /// 末页）；托管态滚动续载后列表已跨多页，再按单页重取会把手上的前几页
  /// 挤掉，因此按已载入条数整窗重取一次。跳页与改每页条数都会先把
  /// `filePage` 归位，不会误判成续载态。
  Future<void> refreshFiles() async {
    await _runAction(FileOperation.refresh, () async {
      final current = state.asData?.value;
      final parentId = current?.parentId;
      final category = current?.fileCategory ?? FileBrowserFileCategory.all;
      final isShared = current?.spaceType == 'SHARED';
      final spaceType = isShared ? 'SHARED' : 'PERSONAL';
      final accumulated =
          current != null &&
          current.filePage > 0 &&
          current.files.length > current.filePageSize;
      final pageSize =
          accumulated ? current.files.length : (current?.filePageSize ?? 10);
      final targetPage = accumulated ? 0 : (current?.filePage ?? 0);

      final result = await _fetchSectionPage(
        (page, size) => _listFilePageForSpace(
          spaceType: spaceType,
          parentId: parentId,
          category: category,
          page: page,
          size: size,
        ),
        page: targetPage,
        size: pageSize,
      );

      final latest = state.asData?.value;
      if (latest != null &&
          (latest.parentId != parentId ||
              latest.spaceType != current?.spaceType ||
              latest.fileCategory != category)) {
        return;
      }

      state = AsyncData(
        _liveOr(current).copyWith(
          files: result.items,
          fileCategory: category,
          filePage: result.page,
          filePageSize: result.size,
          fileTotalElements: result.totalElements,
          fileTotalPages: result.totalPages,
        ),
      );
    });
  }

  /// 按当前分区刷新文件节点列表，不改变导航分区。最近/收藏/回收站
  /// 与主列表一样走分页接口并同步 meta，避免列表与分页条元数据发散；
  /// 滚动续载过的分区整窗重取，不把已经看到的前几页挤掉。
  Future<void> refreshFileNodesForCurrentSection() async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    switch (current.section) {
      case FileManagerSection.recent:
        final window = _reloadWindow(
          loadedCount: current.recentFiles.length,
          meta: current.recentMeta,
        );
        final result = await _fetchSectionPage(
          (page, size) =>
              _repository.listRecentFilesPage(page: page, size: size),
          page: window.page,
          size: window.size,
        );
        final latest = _currentState;
        if (latest != null) {
          _emitState(
            latest.copyWith(
              recentFiles: result.items,
              recentMeta: _metaOfNodePage(result),
            ),
          );
        }
      case FileManagerSection.favorites:
        final window = _reloadWindow(
          loadedCount: current.favoriteFiles.length,
          meta: current.favoritesMeta,
        );
        final result = await _fetchSectionPage(
          (page, size) =>
              _repository.listFavoriteFilesPage(page: page, size: size),
          page: window.page,
          size: window.size,
        );
        final latest = _currentState;
        if (latest != null) {
          _emitState(
            latest.copyWith(
              favoriteFiles: result.items,
              favoritesMeta: _metaOfNodePage(result),
            ),
          );
        }
      case FileManagerSection.recycleBin:
        final window = _reloadWindow(
          loadedCount: current.recycleBin.length,
          meta: current.recycleMeta,
        );
        final spaceType = current.spaceType;
        final result = await _fetchSectionPage(
          (page, size) => _repository.listRecycleBinPage(
            spaceType: spaceType,
            page: page,
            size: size,
          ),
          page: window.page,
          size: window.size,
        );
        final latest = _currentState;
        if (latest != null) {
          _emitState(
            latest.copyWith(
              recycleBin: result.items,
              recycleMeta: _metaOfNodePage(result),
            ),
          );
        }
      default:
        await refreshFiles();
    }
  }

  /// 按页窗拉取分区分页数据；末页条目被删尽导致请求页越界时，回退到
  /// 新的末页重拉，避免分页条停留并展示空页。
  Future<FileNodePage> _fetchSectionPage(
    Future<FileNodePage> Function(int page, int size) fetch, {
    required int page,
    required int size,
  }) async {
    var result = await fetch(page, size);
    if (result.items.isEmpty &&
        result.page > 0 &&
        result.page >= result.totalPages) {
      final lastPage = result.totalPages > 0 ? result.totalPages - 1 : 0;
      result = await fetch(lastPage, size);
    }
    return result;
  }

  /// 按当前分区刷新远端数据，不改变目录、视图模式和筛选条件。
  Future<void> refreshForRealtime() async {
    final current = state.asData?.value;
    if (current == null) return;
    await loadSection(current.section, background: true);
  }

  Future<void> showFiles() async {
    _applySectionOptimistically(FileManagerSection.allFiles);
    await refreshFiles();
  }

  /// 切换个人空间/共享空间。
  Future<void> switchSpace(String newSpaceType) async {
    _clearSelection();
    _clearInspection();
    final navigation = _beginNavigation();
    await _runAction(FileOperation.switchSpace, () async {
      final current = state.asData?.value;
      if (current == null) return;

      final FileNodePage filesPage;
      SharedSpaceUsage? usage;
      // 空间切换回第 0 页，但保留用户已选的每页条数。
      if (newSpaceType == 'SHARED') {
        filesPage = await _repository.listSharedSpaceFilesPage(
          size: current.filePageSize,
        );
        usage = await _repository.getSharedSpaceUsage();
      } else {
        filesPage = await _repository.listFilesPage(size: current.filePageSize);
      }

      if (_isStaleNavigation(navigation)) {
        return;
      }
      state = AsyncData(
        _liveOr(current).copyWith(
          files: filesPage.items,
          parentId: null,
          breadcrumbs: [],
          spaceType: newSpaceType,
          section: FileManagerSection.allFiles,
          sharedSpaceUsage: usage,
          fileCategory: FileBrowserFileCategory.all,
          searchQuery: '',
          filePage: filesPage.page,
          filePageSize: filesPage.size,
          fileTotalElements: filesPage.totalElements,
          fileTotalPages: filesPage.totalPages,
        ),
      );
    });
  }

  Future<void> loadSection(
    FileManagerSection section, {
    bool background = false,
  }) async {
    _backgroundLoad = background;
    try {
      await _loadSectionInner(section);
    } finally {
      _backgroundLoad = false;
    }
  }

  /// 当前分区加载是否处于后台（实时触发）模式，供各 show* 动作读取。
  bool _backgroundLoad = false;

  Future<void> _loadSectionInner(FileManagerSection section) async {
    switch (section) {
      case FileManagerSection.allFiles:
        await showFiles();
      case FileManagerSection.recent:
        await showRecentFiles();
      case FileManagerSection.favorites:
        await showFavoriteFiles();
      case FileManagerSection.recycleBin:
        await showRecycleBin();
      case FileManagerSection.sharedWithMe:
        await showSharedWithMe();
      case FileManagerSection.myShares:
        await showMyShares();
      case FileManagerSection.shareManagement:
        await showShareLinks();
      case FileManagerSection.storageStats:
        await showStorageStats();
      case FileManagerSection.uploadQueue:
        await showUploadQueue();
      case FileManagerSection.sharedSpace:
        await showSharedSpace();
      case FileManagerSection.externalStorage:
        await showExternalStorage();
      case FileManagerSection.importTasks:
        await showImportTasks();
    }
  }

  Future<void> showRecentFiles({int? page, int? size}) async {
    _applySectionOptimistically(FileManagerSection.recent);
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.loadRecent, () async {
      final current = _currentState;
      final meta = current?.recentMeta ?? const FilesSubPageMeta();
      final result = await _repository.listRecentFilesPage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      _emitState(
        _liveOr(current).copyWith(
          recentFiles: result.items,
          recentMeta: _metaOfNodePage(result),
        ),
      );
    });
  }

  Future<void> showFavoriteFiles({int? page, int? size}) async {
    _applySectionOptimistically(FileManagerSection.favorites);
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.loadFavorites, () async {
      final current = _currentState;
      final meta = current?.favoritesMeta ?? const FilesSubPageMeta();
      final result = await _repository.listFavoriteFilesPage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      _emitState(
        _liveOr(current).copyWith(
          favoriteFiles: result.items,
          favoritesMeta: _metaOfNodePage(result),
        ),
      );
    });
  }

  Future<void> showRecycleBin({int? page, int? size}) async {
    _applySectionOptimistically(FileManagerSection.recycleBin);
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.loadRecycleBin, () async {
      final current = _currentState;
      final spaceType = current?.spaceType ?? 'PERSONAL';
      final meta = current?.recycleMeta ?? const FilesSubPageMeta();
      final result = await _repository.listRecycleBinPage(
        spaceType: spaceType,
        page: page ?? 0,
        size: size ?? meta.size,
      );
      _emitState(
        _liveOr(current).copyWith(
          recycleBin: result.items,
          recycleMeta: _metaOfNodePage(result),
        ),
      );
    });
  }

  /// 节点型次分区的滚动续载：取当前页的下一页追加到已载入集合尾部，按节点
  /// id 去重；与主列表 [loadMoreFiles] 同语义。页翻转仍由 `show*` 系列供桌面
  /// 分页条跳页，两种语义并存不互相替换。
  Future<void> _loadMoreNodePage({
    required FileOperation operation,
    required FileManagerSection section,
    required FilesSubPageMeta Function(FileBrowserState state) metaOf,
    required List<FileNode> Function(FileBrowserState state) listOf,
    required Future<FileNodePage> Function(int page, int size) fetch,
    required FileBrowserState Function(
      FileBrowserState state,
      List<FileNode> items,
      FilesSubPageMeta meta,
    )
    emit,
  }) async {
    final current = _currentState;
    if (current == null || current.isBusy || current.section != section) {
      return;
    }
    final meta = metaOf(current);
    // 续载守卫同时看已载入条数与页边界：后者能挡住 totalElements 虚高时
    // 越界请求 page = totalPages, totalPages + 1 的空拉取死循环。
    if (listOf(current).length >= meta.totalElements ||
        meta.page + 1 >= meta.totalPages) {
      return;
    }
    await _runAction(operation, () async {
      final result = await fetch(meta.page + 1, meta.size);
      final latest = _currentState;
      if (latest == null ||
          latest.section != section ||
          metaOf(latest).page != meta.page) {
        return;
      }
      final loaded = listOf(latest);
      final seen = loaded.map((node) => node.id).toSet();
      final merged = <FileNode>[
        ...loaded,
        ...result.items.where((node) => seen.add(node.id)),
      ];
      // 空页说明服务端没有更多可见条目：把总数钳到已载入数量，阻断后续空拉取。
      final effectiveMeta =
          result.items.isEmpty
              ? FilesSubPageMeta(
                page: result.page,
                size: result.size,
                totalElements: merged.length,
                totalPages: result.page + 1,
              )
              : _metaOfNodePage(result);
      _emitState(emit(latest, merged, effectiveMeta));
    });
  }

  /// 最近使用滚动续载。
  Future<void> loadMoreRecentFiles() => _loadMoreNodePage(
    operation: FileOperation.loadRecent,
    section: FileManagerSection.recent,
    metaOf: (state) => state.recentMeta,
    listOf: (state) => state.recentFiles,
    fetch:
        (page, size) => _repository.listRecentFilesPage(page: page, size: size),
    emit:
        (state, items, meta) =>
            state.copyWith(recentFiles: items, recentMeta: meta),
  );

  /// 我的收藏滚动续载。
  Future<void> loadMoreFavoriteFiles() => _loadMoreNodePage(
    operation: FileOperation.loadFavorites,
    section: FileManagerSection.favorites,
    metaOf: (state) => state.favoritesMeta,
    listOf: (state) => state.favoriteFiles,
    fetch:
        (page, size) =>
            _repository.listFavoriteFilesPage(page: page, size: size),
    emit:
        (state, items, meta) =>
            state.copyWith(favoriteFiles: items, favoritesMeta: meta),
  );

  /// 回收站滚动续载：沿用当前空间类型，不跨空间续页。
  Future<void> loadMoreRecycleBin() async {
    final spaceType = _currentState?.spaceType ?? 'PERSONAL';
    await _loadMoreNodePage(
      operation: FileOperation.loadRecycleBin,
      section: FileManagerSection.recycleBin,
      metaOf: (state) => state.recycleMeta,
      listOf: (state) => state.recycleBin,
      fetch:
          (page, size) => _repository.listRecycleBinPage(
            spaceType: spaceType,
            page: page,
            size: size,
          ),
      emit:
          (state, items, meta) =>
              state.copyWith(recycleBin: items, recycleMeta: meta),
    );
  }

  /// 与我共享滚动续载：下一页按 shareId 去重后追加。
  Future<void> loadMoreSharedWithMe() async {
    final current = _currentState;
    final meta = current?.sharedWithMeMeta;
    if (current == null ||
        meta == null ||
        current.isBusy ||
        current.sharedWithMe.length >= meta.totalElements ||
        meta.page + 1 >= meta.totalPages) {
      return;
    }
    await _runAction(FileOperation.loadShared, () async {
      final result = await _repository.listSharedWithMePage(
        page: meta.page + 1,
        size: meta.size,
      );
      final latest = _currentState;
      if (latest == null || latest.sharedWithMeMeta.page != meta.page) {
        return;
      }
      final loaded = latest.sharedWithMe;
      final seen = loaded.map((item) => item.shareId).toSet();
      final merged = <SharedFileItem>[
        ...loaded,
        ...result.items.where((item) => seen.add(item.shareId)),
      ];
      // 空页同样说明没有更多可见分享：钳住总数，避免按虚高的 totalElements 无限续载。
      final effectiveMeta =
          result.items.isEmpty
              ? FilesSubPageMeta(
                page: result.page,
                size: result.size,
                totalElements: merged.length,
                totalPages: result.page + 1,
              )
              : FilesSubPageMeta(
                page: result.page,
                size: result.size,
                totalElements: result.totalElements,
                totalPages: result.totalPages,
              );
      _emitState(
        latest.copyWith(sharedWithMe: merged, sharedWithMeMeta: effectiveMeta),
      );
    });
  }

  Future<void> showSharedWithMe({int? page, int? size}) async {
    _applySectionOptimistically(FileManagerSection.sharedWithMe);
    await _runAction(FileOperation.loadShared, () async {
      final current = _currentState;
      final meta = current?.sharedWithMeMeta ?? const FilesSubPageMeta();
      final result = await _repository.listSharedWithMePage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      _emitState(
        _liveOr(current).copyWith(
          sharedWithMe: result.items,
          sharedWithMeMeta: FilesSubPageMeta(
            page: result.page,
            size: result.size,
            totalElements: result.totalElements,
            totalPages: result.totalPages,
          ),
        ),
      );
    });
  }

  Future<void> showSharedSpace() async {
    _applySectionOptimistically(FileManagerSection.sharedSpace);
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.loadSharedSpace, () async {
      final current = _currentState;
      final usage = await _repository.getSharedSpaceUsage();
      _emitState(
        _liveOr(
          current,
        ).copyWith(sharedSpaceUsage: usage, sharedSpaceBreadcrumbs: []),
      );
    });
  }

  Future<void> openSharedSpaceFolder(FileNode folder) async {
    _clearSelection();
    _clearInspection();
    await _runAction(FileOperation.openSharedFolder, () async {
      final current = _currentState;
      final currentBreadcrumbs = current?.sharedSpaceBreadcrumbs ?? [];
      _emitState(
        _liveOr(
          current,
        ).copyWith(sharedSpaceBreadcrumbs: [...currentBreadcrumbs, folder]),
      );
    });
  }

  Future<void> goToSharedSpaceBreadcrumb(int index) async {
    _clearSelection();
    _clearInspection();
    final current = _currentState;
    final breadcrumbs = current?.sharedSpaceBreadcrumbs ?? [];
    if (index < 0 || index > breadcrumbs.length) return;
    final targetBreadcrumbs = breadcrumbs.sublist(0, index);
    await _runAction(FileOperation.navigateSharedUp, () async {
      _emitState(
        _liveOr(current).copyWith(sharedSpaceBreadcrumbs: targetBreadcrumbs),
      );
    });
  }

  Future<void> moveToSharedSpace(FileNode file) async {
    await _runAction(FileOperation.moveToSharedSpace, () async {
      await _repository.moveToSharedSpace(file.id);
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> moveToPersonalSpace(FileNode file) async {
    await _runAction(FileOperation.moveToPersonalSpace, () async {
      await _repository.moveToPersonalSpace(file.id);
      await refreshFileNodesForCurrentSection();
    });
  }

  Future<void> deleteSharedFile(FileNode file) async {
    await _runAction(FileOperation.deleteSharedFile, () async {
      await _repository.deleteSharedFile(file.id);
      // 删除后必须重拉当前目录，否则已删节点会留在共享空间列表直到手动刷新。
      await refreshFileNodesForCurrentSection();
      final current = _currentState;
      final usage = await _repository.getSharedSpaceUsage();
      _emitState(_liveOr(current).copyWith(sharedSpaceUsage: usage));
    });
  }

  Future<void> showMyShares({int? page, int? size}) async {
    _applySectionOptimistically(FileManagerSection.myShares);
    await _runAction(FileOperation.loadMyShares, () async {
      final current = _currentState;
      final meta = current?.sharesMeta ?? const FilesSubPageMeta();
      final result = await _repository.listMySharesPage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      _emitState(
        _liveOr(current).copyWith(
          myShares: result.items,
          sharesMeta: FilesSubPageMeta(
            page: result.page,
            size: result.size,
            totalElements: result.totalElements,
            totalPages: result.totalPages,
          ),
          shareScopeAll: false,
        ),
      );
    });
  }

  /// 合并分享页的“全部链接”作用域：与我的分享同页共存，
  /// 只切数据域不切 section，避免页面跳转闪烁。
  Future<void> showShareLinks({int? page, int? size}) async {
    _applySectionOptimistically(FileManagerSection.myShares);
    await _runAction(FileOperation.loadShareLinks, () async {
      final current = _currentState;
      final meta = current?.sharesMeta ?? const FilesSubPageMeta();
      // 全部链接与我的分享同端点同 service：直接复用分页查询。
      final result = await _repository.listMySharesPage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      _emitState(
        _liveOr(current).copyWith(
          shareLinks: result.items,
          sharesMeta: FilesSubPageMeta(
            page: result.page,
            size: result.size,
            totalElements: result.totalElements,
            totalPages: result.totalPages,
          ),
          shareScopeAll: true,
        ),
      );
    });
  }

  Future<void> showStorageStats() async {
    _applySectionOptimistically(FileManagerSection.storageStats);
    await _runAction(FileOperation.loadStorageStats, () async {
      final current = _currentState;
      final stats = await _repository.storageStats();
      _emitState(_liveOr(current).copyWith(storageStats: stats));
    });
  }

  Future<void> showUploadQueue({int? page, int? size}) async {
    _applySectionOptimistically(FileManagerSection.uploadQueue);
    await _runAction(FileOperation.loadUploadQueue, () async {
      final current = _currentState;
      final meta = current?.uploadQueueMeta ?? const FilesSubPageMeta();
      final result = await _repository.listUploadQueuePage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      _emitState(
        _liveOr(current).copyWith(
          uploadQueue: result.items,
          uploadQueueMeta: FilesSubPageMeta(
            page: result.page,
            size: result.size,
            totalElements: result.totalElements,
            totalPages: result.totalPages,
          ),
        ),
      );
    });
  }

  Future<void> showExternalStorage() async {
    _applySectionOptimistically(FileManagerSection.externalStorage);
    await _runAction(FileOperation.loadExternalStorage, () async {
      final current = _currentState;
      final externalAccounts = await _repository.listExternalStorages();
      _emitState(_liveOr(current).copyWith(externalAccounts: externalAccounts));
    });
  }

  Future<void> openFolder(FileNode folder) async {
    if (!folder.isFolder) {
      return;
    }
    _clearSelection();
    _clearInspection();
    final navigation = _beginNavigation();
    await _runAction(FileOperation.openFolder, () async {
      final current = state.asData?.value;
      final category = current?.fileCategory ?? FileBrowserFileCategory.all;
      final filesPage = await _listFilePageForSpace(
        spaceType: current?.spaceType ?? 'PERSONAL',
        parentId: folder.id,
        category: category,
        size: current?.filePageSize ?? 10,
      );
      if (_isStaleNavigation(navigation)) {
        return;
      }
      state = AsyncData(
        _liveOr(current).copyWith(
          files: filesPage.items,
          parentId: folder.id,
          breadcrumbs: [...?current?.breadcrumbs, folder],
          section: FileManagerSection.allFiles,
          searchQuery: '',
          fileCategory: category,
          filePage: filesPage.page,
          filePageSize: filesPage.size,
          fileTotalElements: filesPage.totalElements,
          fileTotalPages: filesPage.totalPages,
        ),
      );
    });
  }

  Future<void> goToRoot() async {
    _clearSelection();
    _clearInspection();
    final navigation = _beginNavigation();
    await _runAction(FileOperation.navigateToRoot, () async {
      final current = state.asData?.value;
      final category = current?.fileCategory ?? FileBrowserFileCategory.all;
      final filesPage = await _listFilePageForSpace(
        spaceType: current?.spaceType ?? 'PERSONAL',
        category: category,
        size: current?.filePageSize ?? 10,
      );
      if (_isStaleNavigation(navigation)) {
        return;
      }
      state = AsyncData(
        _liveOr(current).copyWith(
          files: filesPage.items,
          parentId: null,
          breadcrumbs: const [],
          section: FileManagerSection.allFiles,
          searchQuery: '',
          fileCategory: category,
          filePage: filesPage.page,
          filePageSize: filesPage.size,
          fileTotalElements: filesPage.totalElements,
          fileTotalPages: filesPage.totalPages,
        ),
      );
    });
  }

  Future<void> goToParent() async {
    final breadcrumbs = state.asData?.value.breadcrumbs;
    if (breadcrumbs == null || breadcrumbs.isEmpty) {
      return;
    }
    if (breadcrumbs.length == 1) {
      await goToRoot();
      return;
    }
    await goToBreadcrumb(breadcrumbs.length - 2);
  }

  Future<void> goToBreadcrumb(int index) async {
    final current = state.asData?.value;
    if (current == null || index < 0 || index >= current.breadcrumbs.length) {
      return;
    }
    _clearSelection();
    _clearInspection();
    final navigation = _beginNavigation();
    await _runAction(FileOperation.changeDirectory, () async {
      final currentState = state.asData?.value;
      if (currentState == null ||
          index < 0 ||
          index >= currentState.breadcrumbs.length) {
        return;
      }
      final target = currentState.breadcrumbs[index];
      final filesPage = await _listFilePageForSpace(
        spaceType: currentState.spaceType,
        parentId: target.id,
        category: currentState.fileCategory,
        size: currentState.filePageSize,
      );
      if (_isStaleNavigation(navigation)) {
        return;
      }
      state = AsyncData(
        _liveOr(currentState).copyWith(
          files: filesPage.items,
          parentId: target.id,
          breadcrumbs: currentState.breadcrumbs.take(index + 1).toList(),
          section: FileManagerSection.allFiles,
          searchQuery: '',
          filePage: filesPage.page,
          filePageSize: filesPage.size,
          fileTotalElements: filesPage.totalElements,
          fileTotalPages: filesPage.totalPages,
        ),
      );
    });
  }

  Future<void> setFileCategory(FileBrowserFileCategory category) async {
    _clearSelection();
    _clearInspection();
    final current = state.asData?.value;
    if (current != null &&
        (current.section != FileManagerSection.allFiles ||
            current.spaceType == 'SHARED')) {
      // 最近/收藏/回收站与共享空间的分类条件没有服务端参数，列表又已在内存里：
      // 只改过滤条件，既不发请求，也不把用户踢回全部文件。
      state = AsyncData(current.copyWith(fileCategory: category));
      return;
    }
    final navigation = _beginNavigation();
    await _runAction(FileOperation.filterFileType, () async {
      final filesPage = await _listFilePageForSpace(
        spaceType: current?.spaceType ?? 'PERSONAL',
        parentId: current?.parentId,
        category: category,
        size: current?.filePageSize ?? 10,
      );
      if (_isStaleNavigation(navigation)) {
        return;
      }
      state = AsyncData(
        _liveOr(current).copyWith(
          files: filesPage.items,
          fileCategory: category,
          filePage: filesPage.page,
          filePageSize: filesPage.size,
          fileTotalElements: filesPage.totalElements,
          fileTotalPages: filesPage.totalPages,
        ),
      );
    });
  }

  Future<FileNodePage> _listFilePageForSpace({
    required String spaceType,
    required FileBrowserFileCategory category,
    String? parentId,
    int page = 0,
    int size = 10,
  }) {
    if (spaceType == 'SHARED') {
      return _repository.listSharedSpaceFilesPage(
        parentId: parentId,
        page: page,
        size: size,
      );
    }
    return _repository.listFilesPage(
      parentId: parentId,
      category: category.apiValue,
      page: page,
      size: size,
    );
  }

  /// 无感续载：滚动近底时追加主列表下一页（保留当前目录/空间/分类
  /// 上下文）；上下文在请求期间变化则丢弃结果。
  Future<void> loadMoreFiles() async {
    final current = state.asData?.value;
    if (current == null ||
        current.isBusy ||
        current.filePage + 1 >= current.fileTotalPages) {
      return;
    }
    await _runAction(FileOperation.refresh, () async {
      final result = await _listFilePageForSpace(
        spaceType: current.spaceType,
        parentId: current.parentId,
        category: current.fileCategory,
        page: current.filePage + 1,
        size: current.filePageSize,
      );
      final latest = state.asData?.value;
      if (latest == null ||
          latest.parentId != current.parentId ||
          latest.spaceType != current.spaceType ||
          latest.filePage != current.filePage) {
        return;
      }
      state = AsyncData(
        latest.copyWith(
          files: [...latest.files, ...result.items],
          filePage: result.page,
          fileTotalElements: result.totalElements,
          fileTotalPages: result.totalPages,
        ),
      );
    });
  }

  /// 跳转到主列表指定页：refreshFiles 按目标页重放窗口（向前收缩、
  /// 向后扩页），页式导航语义；正在加载或分区不符时忽略。
  Future<void> goToFilePage(int page) async {
    final current = state.asData?.value;
    if (current == null ||
        current.isBusy ||
        page < 0 ||
        page >= current.fileTotalPages ||
        page == current.filePage) {
      return;
    }
    state = AsyncData(current.copyWith(filePage: page));
    await refreshFiles();
  }

  /// 调整主列表每页条数：回到第 0 页重放。
  Future<void> setFilePageSize(int size) async {
    final current = state.asData?.value;
    if (current == null || current.isBusy || size == current.filePageSize) {
      return;
    }
    state = AsyncData(current.copyWith(filePageSize: size, filePage: 0));
    await refreshFiles();
  }
}
