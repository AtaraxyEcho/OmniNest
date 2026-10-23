import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/application/reader_preferences_controller.dart';
import 'package:omninest/features/reader/application/reader_progress_sync_service.dart';
import 'package:omninest/features/reader/application/reader_session_recorder.dart';
import 'package:omninest/features/reader/domain/reader_progress.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_shortcuts.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/platform/android/reader_volume_key_service.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDF 阅读页：原生端按页映射解密后的会话文件，Web 端用缓存字节渲染。
///
/// 进度契约：charOffset=当前页（1 起），chapterId 固定 `pdf`，
/// progressPercent = 当前页 / 总页数。
class PdfReaderPage extends ConsumerStatefulWidget {
  const PdfReaderPage({required this.itemId, super.key});

  final String itemId;

  @override
  ConsumerState<PdfReaderPage> createState() => _PdfReaderPageState();
}

/// 恢复位置：精确页码与只能按百分比反推的兜底比例。
typedef _PdfRestoreTarget = ({int page, double? percentFallback});

class _PdfReaderPageState extends ConsumerState<PdfReaderPage>
    with WidgetsBindingObserver {
  String? _error;
  bool _loading = true;

  /// 原生端解密后的会话文件路径，按页映射读取，不把整本 PDF 读进 Dart 堆。
  String? _sessionFilePath;

  /// Web 端没有文件路径，只能持有整本字节。
  Uint8List? _bytes;
  int _currentPage = 1;
  int _totalPages = 0;
  DateTime _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(0);
  final PdfViewerController _viewerController = PdfViewerController();
  final ReaderCommandGate _volumeKeyGate = ReaderCommandGate();
  VoidCallback? _volumeKeyEventCancel;
  bool _volumeKeyPagingPushed = false;
  bool _volumeKeyPagingPreference = true;
  bool _viewerReady = false;

  /// 会话记账：只累计前台活跃时长，切后台挂机不计入阅读统计。
  final DateTime _sessionStart = DateTime.now();
  Duration _accumulatedActive = Duration.zero;
  DateTime? _lastResumedAt;
  bool _sessionRecorded = false;

  /// 退出只走一条通道，且只走一次：连点返回不得重复刷写进度。
  bool _exitStarted = false;

  /// 只有全书百分比时无法在总页数就绪前定页，记录下来等查看器就绪后补定位。
  double? _pendingPercentFallback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastResumedAt = DateTime.now();
    _volumeKeyEventCancel = ReaderVolumeKeyService.instance().addListener(
      _handleVolumeKeyEvent,
    );
    unawaited(_loadVolumeKeyPagingPreference());
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordSession();
    _volumeKeyEventCancel?.call();
    if (_volumeKeyPagingPushed) {
      _volumeKeyPagingPushed = false;
      unawaited(
        ReaderVolumeKeyService.instance().setVolumeKeyPagingEnabled(
          enabled: false,
        ),
      );
    }
    // 句柄由 pdfBookHandleProvider 持有并释放（ref.onDispose 删除明文会话文件），
    // 本页只在 build 中保持订阅，避免 autoDispose 在查看器仍映射文件时删掉它。
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 仅以 paused（切后台、窗口隐藏）作为挂机边界：inactive 在桌面端弹窗或失焦时也会
    // 触发，跟着结算会把正常阅读的时间算没。判据与文本阅读页保持一致。
    if (state == AppLifecycleState.resumed) {
      _lastResumedAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.paused) {
      return;
    }
    final resumedAt = _lastResumedAt;
    if (resumedAt != null) {
      _accumulatedActive += DateTime.now().difference(resumedAt);
      _lastResumedAt = null;
    }
  }

  /// 从阅读偏好加载音量键翻页开关并同步到原生层。
  Future<void> _loadVolumeKeyPagingPreference() async {
    final values = await ref.read(readerPreferencesProvider.future);
    if (!mounted) {
      return;
    }
    _volumeKeyPagingPreference =
        ReaderViewSettings.fromJson(values).volumeKeyPaging;
    _syncVolumeKeyPaging();
  }

  /// 将音量键拦截开关同步到原生层（仅 Android 实际生效）。
  void _syncVolumeKeyPaging() {
    final shouldEnable = isAndroidPlatform && _volumeKeyPagingPreference;
    if (_volumeKeyPagingPushed == shouldEnable) {
      return;
    }
    _volumeKeyPagingPushed = shouldEnable;
    unawaited(
      ReaderVolumeKeyService.instance().setVolumeKeyPagingEnabled(
        enabled: shouldEnable,
      ),
    );
  }

  /// 音量键事件映射为翻页：下键下一页，上键上一页。
  void _handleVolumeKeyEvent(ReaderVolumeKeyDirection direction) {
    if (!mounted || !_viewerReady || _totalPages <= 0) {
      return;
    }
    final target =
        direction == ReaderVolumeKeyDirection.down
            ? _currentPage + 1
            : _currentPage - 1;
    if (target < 1 || target > _totalPages) {
      return;
    }
    if (!_volumeKeyGate.accept()) {
      return;
    }
    unawaited(_viewerController.goToPage(pageNumber: target));
  }

  Future<void> _load() async {
    _viewerReady = false;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final restore = await _resolveRestoreTarget();
      if (!mounted) {
        return;
      }
      // 走缓存句柄而不是整本字节：原生端解密到会话文件后按页映射，
      // 把 100MB 级扫描版 PDF 全量读进 Dart 堆会叠加 PDFium 的 native 拷贝，移动端极易 OOM。
      final handle = await ref.read(
        pdfBookHandleProvider(widget.itemId).future,
      );
      if (!mounted) {
        return;
      }
      final filePath = kIsWeb ? null : await handle.openFilePath();
      final memoryBytes = filePath != null ? null : handle.memoryBytes;
      if (!mounted) {
        return;
      }
      final hasContent = filePath != null || (memoryBytes?.isNotEmpty ?? false);
      if (!hasContent) {
        setState(() {
          _error = AppLocalizations.of(context).readerPdfLoadFailed;
          _loading = false;
        });
        return;
      }
      setState(() {
        _sessionFilePath = filePath;
        _bytes = memoryBytes;
        _currentPage = restore.page;
        _pendingPercentFallback = restore.percentFallback;
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = describeUserFacingError(error).message;
        _loading = false;
      });
    }
  }

  /// 恢复位置：服务端与本地进度按记录时刻取较新的一方，再取其精确页码。
  ///
  /// 两侧都只带百分比时把换算推迟到总页数已知之后，不在这里猜。
  Future<_PdfRestoreTarget> _resolveRestoreTarget() async {
    ReaderProgress? serverProgress;
    try {
      final detail = await ref.read(readerApiProvider).detail(widget.itemId);
      serverProgress = detail.progress;
    } on Exception {
      serverProgress = null;
    }
    final local = await ReaderLocalProgress.loadLatest(widget.itemId);
    final localAt = DateTime.tryParse(local?['updatedAt']?.toString() ?? '');
    final serverAt = serverProgress?.updatedAt;
    final preferLocal =
        local != null &&
        localAt != null &&
        (serverAt == null || localAt.isAfter(serverAt));
    if (preferLocal) {
      final charOffset = _asInt(local['charOffset']);
      final pageIndex = _asInt(local['pageIndex']);
      final percent =
          _asDouble(local['bookProgress']) ??
          _asDouble(local['chapterProgress']);
      final hasExactPage =
          (charOffset != null && charOffset > 0) ||
          (pageIndex != null && pageIndex >= 0);
      if (!hasExactPage) {
        return (page: 1, percentFallback: percent);
      }
      return (
        page: resolvePdfStartPage(
          charOffset: charOffset,
          pageIndex: pageIndex,
          progressPercent: percent,
          totalPages: 0,
        ),
        percentFallback: null,
      );
    }
    if (serverProgress == null) {
      return (page: 1, percentFallback: null);
    }
    final hasExactPage =
        serverProgress.charOffset > 0 || (serverProgress.pageIndex ?? -1) >= 0;
    return (
      page: resolvePdfStartPage(
        charOffset: serverProgress.charOffset,
        pageIndex: serverProgress.pageIndex,
        progressPercent: serverProgress.progressPercent,
        totalPages: 0,
      ),
      percentFallback: hasExactPage ? null : serverProgress.progressPercent,
    );
  }

  /// 查看器就绪：总页数只在这里确定，百分比换算与首次上报都在此后进行。
  ///
  /// 先解析一次文档再交给 PdfViewer 二次解析会把同一份字节读两遍，
  /// 大 PDF 直接双倍占用内存。
  Future<void> _handleViewerReady(
    PdfDocument document,
    PdfViewerController controller,
  ) async {
    if (!mounted) {
      return;
    }
    final totalPages = document.pages.length;
    var currentPage = _currentPage;
    final fallback = _pendingPercentFallback;
    if (fallback != null && fallback > 0 && totalPages > 0) {
      currentPage = (fallback * totalPages).ceil().clamp(1, totalPages);
    }
    if (totalPages > 0) {
      currentPage = currentPage.clamp(1, totalPages);
    }
    setState(() {
      _totalPages = totalPages;
      _currentPage = currentPage;
      _pendingPercentFallback = null;
      // PdfViewerController 在查看器挂载前调用 goToPage 会空断言崩溃，
      // 首帧渲染完成（控制器已 attach）后才放行音量键翻页。
      _viewerReady = true;
    });
    if (currentPage > 1) {
      await controller.goToPage(pageNumber: currentPage);
    }
    await _syncProgress(force: true);
  }

  /// 上报当前页码，并按节流窗口去重。
  ///
  /// 本地进度即时落盘：它是离线与崩溃后的唯一副本，也是下次打开的优先恢复源。
  Future<void> _syncProgress({bool force = false}) async {
    final now = DateTime.now();
    if (!force && now.difference(_lastSyncAt) < const Duration(seconds: 2)) {
      return;
    }
    _lastSyncAt = now;
    final total = _totalPages;
    final bookProgress = total > 0 ? _currentPage / total : 0.0;
    await ReaderLocalProgress.save(
      itemId: widget.itemId,
      chapterProgress: bookProgress,
      bookProgress: total > 0 ? bookProgress : null,
      mode: 'page',
      chapterId: 'pdf',
      charOffset: _currentPage,
      pageIndex: total > 0 ? _currentPage - 1 : null,
      updatedAt: now,
    );
    if (total <= 0) {
      // 总页数未知：上报会写成误导性百分比，只留本地页码。
      return;
    }
    await ref
        .read(readerProgressSyncServiceProvider)
        .sync(
          itemId: widget.itemId,
          charOffset: _currentPage,
          progressPercent: bookProgress,
          readingMode: 'page',
          chapterId: 'pdf',
          pageIndex: _currentPage - 1,
          clientUpdatedAt: now,
        );
  }

  /// 退出是强一致节点：节流窗口内的最后一次翻页必须刷出去。
  Future<void> _finishReading() async {
    _recordSession();
    await _syncProgress(force: true);
  }

  /// 退出阅读器：顶栏返回钮与系统返回共用这一条通道。
  ///
  /// 顶栏钮以前直接 `context.pop()`，PopScope 收到的 `didPop` 为 true 而早退，
  /// 末次翻页进度既不落盘也不上报，详情页还停在进入前的旧读数；深链直入没有
  /// 可弹的层时 `context.pop()` 会抛 GoError，只能回落详情页路由。
  Future<void> _handleExit() async {
    if (_exitStarted || !mounted) {
      return;
    }
    _exitStarted = true;
    // 详情页必须等本次上报落库之后再失效：同一帧立即失效会让详情页重拉到还没
    // 更新的进度，续读指针显示回跳。导航不等上报结果。
    // 失效走容器而不是 ref——本页即将退出，Element 卸载后 ref 不再可用。
    final container = ProviderScope.containerOf(context, listen: false);
    unawaited(
      _finishReading().whenComplete(() {
        container.invalidate(readerItemDetailProvider(widget.itemId));
      }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // 阅读页由详情 push 进来，pop 才保得住来路；深链直入无栈可退时
      // exitDetailRoute 自己兜底，本页不直接写 go（模块页入口用 go 会把
      // 整条栈换掉，之后的系统返回直接退出应用）。
      exitDetailRoute(context, fallbackRoute: '/reader/items/${widget.itemId}');
    });
  }

  void _recordSession() {
    if (_sessionRecorded) {
      return;
    }
    _sessionRecorded = true;
    final resumedAt = _lastResumedAt;
    ReaderSessionRecorder.recordSession(
      itemId: widget.itemId,
      sessionStart: _sessionStart,
      activeReading:
          resumedAt == null
              ? _accumulatedActive
              : _accumulatedActive + DateTime.now().difference(resumedAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 保持句柄订阅：autoDispose provider 在无人监听时会释放句柄并删除明文会话文件，
    // 而查看器可能仍在按页映射该文件。
    ref.watch(pdfBookHandleProvider(widget.itemId));
    if (_loading) {
      return Scaffold(body: Center(child: AppLoading()));
    }
    if (_error != null || (_sessionFilePath == null && _bytes == null)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.readerPdfTitle)),
        body: AppErrorView(
          message: _error ?? l10n.readerPdfLoadFailed,
          onRetry: _load,
        ),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        await _handleExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.readerPdfPageIndicator(_currentPage, _totalPages)),
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => unawaited(_handleExit()),
          ),
        ),
        body: _buildViewerBody(),
      ),
    );
  }

  /// 渲染主体：原生端按页映射会话文件，Web 端回退到内存字节。
  Widget _buildViewerBody() {
    final params = PdfViewerParams(
      onViewerReady: (document, controller) {
        unawaited(_handleViewerReady(document, controller));
      },
      onPageChanged: (pageNumber) {
        if (pageNumber == null) {
          return;
        }
        setState(() => _currentPage = pageNumber);
        unawaited(_syncProgress());
      },
    );
    final filePath = _sessionFilePath;
    if (filePath != null) {
      return PdfViewer.file(
        filePath,
        controller: _viewerController,
        initialPageNumber: _currentPage,
        params: params,
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return AppErrorView(
        message: AppLocalizations.of(context).readerPdfDataNotReady,
      );
    }
    return PdfViewer.data(
      bytes,
      sourceName: 'reader-${widget.itemId}',
      controller: _viewerController,
      initialPageNumber: _currentPage,
      params: params,
    );
  }
}

/// 恢复页码：精确页码优先，其次页索引，最后才按全书比例反推。
///
/// 百分比是浮点舍入后的派生量，页数越多偏差越大；只有两者都缺失时才用它兜底。
/// [totalPages] 为 0 表示总页数未知，此时不做钳制（精确页码本身不依赖它）。
int resolvePdfStartPage({
  required int? charOffset,
  required int? pageIndex,
  required double? progressPercent,
  required int totalPages,
}) {
  if (charOffset != null && charOffset > 0) {
    return totalPages > 0 ? charOffset.clamp(1, totalPages) : charOffset;
  }
  if (pageIndex != null && pageIndex >= 0) {
    final page = pageIndex + 1;
    return totalPages > 0 ? page.clamp(1, totalPages) : page;
  }
  if (totalPages <= 0 || progressPercent == null || progressPercent <= 0) {
    return 1;
  }
  return (progressPercent * totalPages).ceil().clamp(1, totalPages);
}

int? _asInt(dynamic value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  _ => null,
};

double? _asDouble(dynamic value) => switch (value) {
  double() => value,
  num() => value.toDouble(),
  _ => null,
};
