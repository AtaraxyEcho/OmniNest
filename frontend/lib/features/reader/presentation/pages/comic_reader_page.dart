import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/reader/application/reader_comic_service.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';
import 'package:omninest/features/reader/domain/comic_navigation.dart';
import 'package:omninest/features/reader/domain/reader_progress.dart';
import 'package:omninest/features/reader/domain/reader_status_constants.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_reader_view.dart';

/// 漫画阅读页面，读取后端已持久化的 manifest，不在阅读态触发同步解析。
class ComicReaderPage extends ConsumerStatefulWidget {
  const ComicReaderPage({
    required this.itemId,
    this.initialCatalogNodeId,
    super.key,
  });

  final String itemId;

  /// 可选初始目录节点 ID，用于从目录页跳转到指定章节。
  final String? initialCatalogNodeId;

  @override
  ConsumerState<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends ConsumerState<ComicReaderPage> {
  ComicManifest? _manifest;
  int _initialPage = 0;
  double? _initialIntraPageOffset;
  bool _loading = true;
  bool _waitingForParse = false;
  bool _requestInFlight = false;
  bool _leaving = false;
  String? _error;

  Future<void> _loadManifest(ComicManifest manifest) async {
    if (_requestInFlight) {
      return;
    }
    _requestInFlight = true;
    final comicService = ref.read(readerComicServiceProvider);

    try {
      String? importStatus = manifest.importStatus;
      try {
        final detail = await comicService.loadDetail(widget.itemId);
        importStatus = detail.item.importStatus;
      } on Exception {
        importStatus = manifest.importStatus;
      }

      var initialPage = 0;
      if (manifest.totalPages > 0) {
        if (widget.initialCatalogNodeId != null) {
          final idx = resolveComicCatalogStartPage(
            manifest,
            widget.initialCatalogNodeId!,
          );
          if (idx != null) {
            // 目录跳转是"从这个节点的第一页看起"：页内偏移必须一起清零，
            // 否则续读留下的滚动位置会把读者又带回上一次看的那一页。
            initialPage = idx;
            _initialIntraPageOffset = 0.0;
          } else {
            initialPage = await _resolveInitialPage(comicService, manifest);
          }
        } else {
          initialPage = await _resolveInitialPage(comicService, manifest);
        }
      }

      if (!mounted) {
        return;
      }
      final waitingForParse =
          manifest.totalPages == 0 &&
          (importStatus == ReaderImportStatus.pending ||
              importStatus == ReaderImportStatus.parsing);
      setState(() {
        _manifest = manifest;
        _initialPage = initialPage;
        _loading = false;
        _waitingForParse = waitingForParse;
        _error = _resolveManifestError(manifest, importStatus);
      });
    } on Exception {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context);
      setState(() {
        _loading = false;
        _waitingForParse = false;
        _error = l10n.readerComicManifestLoadFailed;
      });
    } finally {
      _requestInFlight = false;
    }
  }

  void _handleBack() {
    if (_leaving || !mounted) {
      return;
    }
    _leaving = true;
    // 详情页的进度与目录高亮来自 readerItemDetailProvider：不失效就还停在进
    // 阅读器之前的那一页，读者以为刚才没读进去。
    ref.invalidate(readerItemDetailProvider(widget.itemId));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // 本页由漫画详情 push 进来：pop 才保得住来路；go 会把整条栈换成
      // 详情页，之后的系统返回落在栈底，表现为直接退出应用。
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/reader/items/${widget.itemId}');
      }
    });
  }

  String? _resolveManifestError(ComicManifest manifest, String? importStatus) {
    if (manifest.totalPages > 0) {
      return null;
    }
    final l10n = AppLocalizations.of(context);
    final failedSource =
        manifest.sources
            .where((source) => source.status == ReaderSourceStatus.failed)
            .firstOrNull;
    final failureReason =
        manifest.parseTask?.errorMessage ?? failedSource?.errorMessage;
    return switch (importStatus) {
      ReaderImportStatus.pending || ReaderImportStatus.parsing => null,
      ReaderImportStatus.failed =>
        failureReason?.trim().isNotEmpty == true
            ? l10n.readerComicParseFailedWithReason(failureReason!.trim())
            : l10n.readerComicParseFailed,
      ReaderImportStatus.partialFailed =>
        failureReason?.trim().isNotEmpty == true
            ? l10n.readerComicPartialFailedWithReason(failureReason!.trim())
            : l10n.readerComicPartialFailed,
      _ => l10n.readerComicEmptyManifest,
    };
  }

  /// 从本地和服务端进度解析初始页码：取两份进度里较新的那一份，再按锚点逐级落位。
  Future<int> _resolveInitialPage(
    ReaderComicService comicService,
    ComicManifest manifest,
  ) async {
    // 服务端详情与本地进度分开取：离线时 loadDetail 抛异常不得跳过 SQLite 里
    // 已经保存的那份进度，否则断网续读永远回到第一页。
    ReaderProgress? serverProgress;
    try {
      final detail = await comicService.loadDetail(widget.itemId);
      serverProgress = detail.progress;
    } on Exception {
      serverProgress = null;
    }
    Map<String, dynamic>? local;
    try {
      local = await ReaderLocalProgress.loadLatest(widget.itemId);
    } on Exception {
      local = null;
    }
    try {
      final restore = resolveComicRestore(
        manifest: manifest,
        serverProgress: serverProgress,
        localProgress: local,
      );
      _initialIntraPageOffset = restore.intraPageOffset;
      return restore.page;
    } on Exception {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manifestMonitor = ref.watch(
      comicManifestMonitorProvider(widget.itemId),
    );
    // 后台解析每 3 秒推一次清单：清单身份没变时不得重跑装配，否则每次轮询
    // 都重算一次初始页码，把读者正在看的那一页顶掉。
    ref.listen(comicManifestMonitorProvider(widget.itemId), (_, next) {
      final manifest = next.asData?.value.manifest;
      if (manifest == null) {
        return;
      }
      final previous = _manifest;
      final firstLoad = previous == null;
      final changed =
          previous == null ||
          previous.manifestVersion != manifest.manifestVersion ||
          previous.totalPages != manifest.totalPages;
      if (!firstLoad && !changed) {
        return;
      }
      unawaited(_loadManifest(manifest));
    });
    if (_loading && manifestMonitor.asData?.value.refreshError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _loading) {
          final l10n = AppLocalizations.of(context);
          setState(() {
            _loading = false;
            _error = l10n.readerComicManifestLoadFailed;
          });
        }
      });
    }
    if (_loading) {
      return Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: AppLoading()),
            SafeArea(
              child: IconButton(
                tooltip: AppLocalizations.of(context).coreBack,
                onPressed: _handleBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
          ],
        ),
      );
    }

    if (_waitingForParse) {
      final task = _manifest?.parseTask;
      final progress = task?.progress ?? 0;
      return Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_stories_rounded, size: 40),
                        const SizedBox(height: 18),
                        Text(
                          AppLocalizations.of(context).readerComicPagesPending,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        LinearProgressIndicator(
                          value: task == null ? null : progress / 100,
                        ),
                        if (task != null) ...[
                          const SizedBox(height: 8),
                          Text('$progress%'),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  tooltip: AppLocalizations.of(context).coreBack,
                  onPressed: _handleBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null || _manifest == null || _manifest!.totalPages == 0) {
      return Scaffold(
        body: AppErrorView(
          message: _error ?? l10n.readerComicEmpty,
          onBack: _handleBack,
          onRetry: () {
            setState(() {
              _loading = true;
              _error = null;
            });
            ref.invalidate(comicManifestMonitorProvider(widget.itemId));
          },
        ),
      );
    }

    return ComicReaderView(
      itemId: widget.itemId,
      manifest: _manifest!,
      initialPageIndex: _initialPage,
      initialIntraPageOffset: _initialIntraPageOffset,
      onBack: _handleBack,
    );
  }
}

/// 恢复位置：本地与服务端进度按记录时刻取较新的一份，再按锚点逐级落位。
///
/// 优先级为稳定页面锚点、来源页码、目录键、同版本页码、进度比例；一份都没有
/// 时回到第一页。离线时 `serverProgress` 是 null，不得因此跳过 SQLite 里那份。
({int page, double intraPageOffset}) resolveComicRestore({
  required ComicManifest manifest,
  ReaderProgress? serverProgress,
  Map<String, dynamic>? localProgress,
}) {
  final anchor = _latestComicAnchor(serverProgress, localProgress);
  if (anchor == null) {
    return (page: 0, intraPageOffset: 0.0);
  }
  final intraPageOffset = anchor.intraPageOffset ?? 0.0;

  int? indexOf(bool Function(ComicPage page) test) {
    final idx = manifest.pages.indexWhere(test);
    return idx >= 0 ? idx : null;
  }

  final byPageId =
      anchor.pageId == null
          ? null
          : indexOf((page) => page.id == anchor.pageId);
  if (byPageId != null) {
    return (page: byPageId, intraPageOffset: intraPageOffset);
  }

  final byFingerprint =
      anchor.pageFingerprint == null
          ? null
          : indexOf(
            (page) =>
                page.fingerprint == anchor.pageFingerprint &&
                (anchor.sourceId == null || page.sourceId == anchor.sourceId),
          );
  if (byFingerprint != null) {
    return (page: byFingerprint, intraPageOffset: intraPageOffset);
  }

  final bySource =
      anchor.sourceId == null || anchor.sourcePageIndex == null
          ? null
          : indexOf(
            (page) =>
                page.sourceId == anchor.sourceId &&
                page.sourcePageIndex == anchor.sourcePageIndex,
          );
  if (bySource != null) {
    return (page: bySource, intraPageOffset: intraPageOffset);
  }

  final byCatalogKey =
      anchor.catalogKey == null
          ? null
          : indexOf((page) => page.catalogKey == anchor.catalogKey);
  if (byCatalogKey != null) {
    return (page: byCatalogKey, intraPageOffset: intraPageOffset);
  }

  final sameManifest =
      anchor.manifestVersion == null ||
      anchor.manifestVersion == manifest.manifestVersion;
  if (sameManifest &&
      anchor.pageIndex != null &&
      anchor.pageIndex! >= 0 &&
      anchor.pageIndex! < manifest.totalPages) {
    return (page: anchor.pageIndex!, intraPageOffset: intraPageOffset);
  }

  if (anchor.progressPercent > 0 && manifest.totalPages > 0) {
    final byPercent =
        ((anchor.progressPercent * manifest.totalPages).ceil() - 1)
            .clamp(0, manifest.totalPages - 1)
            .toInt();
    return (page: byPercent, intraPageOffset: intraPageOffset);
  }

  return (page: 0, intraPageOffset: intraPageOffset);
}

/// 取两份进度里记录时刻更新的那一份；任一侧缺时间戳时相信有戳的那一侧。
_ComicProgressAnchor? _latestComicAnchor(
  ReaderProgress? serverProgress,
  Map<String, dynamic>? localProgress,
) {
  final serverAnchor =
      serverProgress == null
          ? null
          : _ComicProgressAnchor.fromServer(serverProgress);
  final localAnchor =
      localProgress == null
          ? null
          : _ComicProgressAnchor.fromLocal(localProgress);
  if (serverAnchor == null) return localAnchor;
  if (localAnchor == null) return serverAnchor;
  final serverUpdatedAt = serverAnchor.updatedAt;
  final localUpdatedAt = localAnchor.updatedAt;
  if (serverUpdatedAt == null) return localAnchor;
  if (localUpdatedAt == null) return serverAnchor;
  return localUpdatedAt.isAfter(serverUpdatedAt) ? localAnchor : serverAnchor;
}

class _ComicProgressAnchor {
  const _ComicProgressAnchor({
    this.pageId,
    this.pageIndex,
    this.pageFingerprint,
    this.sourceId,
    this.sourcePageIndex,
    this.catalogKey,
    this.manifestVersion,
    this.intraPageOffset,
    this.progressPercent = 0,
    this.updatedAt,
  });

  final String? pageId;
  final int? pageIndex;
  final String? pageFingerprint;
  final String? sourceId;
  final int? sourcePageIndex;
  final String? catalogKey;
  final int? manifestVersion;
  final double? intraPageOffset;
  final double progressPercent;
  final DateTime? updatedAt;

  factory _ComicProgressAnchor.fromServer(dynamic progress) {
    return _ComicProgressAnchor(
      pageId: progress.pageId as String?,
      pageIndex: progress.pageIndex as int?,
      pageFingerprint: progress.pageFingerprint as String?,
      sourceId: progress.sourceId as String?,
      sourcePageIndex: progress.sourcePageIndex as int?,
      catalogKey: progress.catalogKey as String?,
      manifestVersion: progress.manifestVersion as int?,
      intraPageOffset: progress.intraPageOffset as double?,
      progressPercent: (progress.progressPercent as double?) ?? 0,
      updatedAt: progress.updatedAt as DateTime?,
    );
  }

  factory _ComicProgressAnchor.fromLocal(Map<String, dynamic> payload) {
    return _ComicProgressAnchor(
      pageId: payload['pageId']?.toString(),
      pageIndex:
          (payload['pageIndex'] as num?)?.toInt() ??
          (payload['charOffset'] as num?)?.toInt(),
      pageFingerprint: payload['pageFingerprint']?.toString(),
      sourceId: payload['sourceId']?.toString(),
      sourcePageIndex: (payload['sourcePageIndex'] as num?)?.toInt(),
      catalogKey: payload['catalogKey']?.toString(),
      manifestVersion: (payload['manifestVersion'] as num?)?.toInt(),
      intraPageOffset: (payload['intraPageOffset'] as num?)?.toDouble(),
      progressPercent: (((payload['chapterProgress'] as num?)?.toDouble() ?? 0)
          .clamp(0.0, 1.0)),
      updatedAt: DateTime.tryParse(payload['updatedAt']?.toString() ?? ''),
    );
  }
}
