import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/reader/application/reader_comic_service.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';
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
          final idx = manifest.pages.indexWhere(
            (page) => page.catalogNodeId == widget.initialCatalogNodeId,
          );
          initialPage =
              idx >= 0
                  ? idx
                  : await _resolveInitialPage(comicService, manifest);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
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

  /// 从本地和服务端进度解析初始页码，优先级为稳定页面锚点、来源页码、目录键、同版本页码、进度比例。
  Future<int> _resolveInitialPage(
    ReaderComicService comicService,
    ComicManifest manifest,
  ) async {
    try {
      final detail = await comicService.loadDetail(widget.itemId);
      final progress = detail.progress;
      final local = await ReaderLocalProgress.loadLatest(widget.itemId);
      final anchor = _latestAnchor(progress, local);
      if (anchor == null) return 0;

      _initialIntraPageOffset = anchor.intraPageOffset;

      if (anchor.pageId != null) {
        final idx = manifest.pages.indexWhere(
          (page) => page.id == anchor.pageId,
        );
        if (idx >= 0) {
          return idx;
        }
      }

      if (anchor.pageFingerprint != null) {
        final idx = manifest.pages.indexWhere(
          (page) =>
              page.fingerprint == anchor.pageFingerprint &&
              (anchor.sourceId == null || page.sourceId == anchor.sourceId),
        );
        if (idx >= 0) {
          return idx;
        }
      }

      if (anchor.sourceId != null && anchor.sourcePageIndex != null) {
        final idx = manifest.pages.indexWhere(
          (page) =>
              page.sourceId == anchor.sourceId &&
              page.sourcePageIndex == anchor.sourcePageIndex,
        );
        if (idx >= 0) {
          return idx;
        }
      }

      if (anchor.catalogKey != null) {
        final idx = manifest.pages.indexWhere(
          (page) => page.catalogKey == anchor.catalogKey,
        );
        if (idx >= 0) {
          return idx;
        }
      }

      final sameManifest =
          anchor.manifestVersion == null ||
          anchor.manifestVersion == manifest.manifestVersion;
      if (sameManifest &&
          anchor.pageIndex != null &&
          anchor.pageIndex! >= 0 &&
          anchor.pageIndex! < manifest.totalPages) {
        return anchor.pageIndex!;
      }

      if (anchor.progressPercent > 0) {
        return (((anchor.progressPercent * manifest.totalPages).ceil()) - 1)
            .clamp(0, manifest.totalPages - 1)
            .toInt();
      }
    } on Exception {
      return 0;
    }
    return 0;
  }

  _ComicProgressAnchor? _latestAnchor(
    dynamic serverProgress,
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manifestMonitor = ref.watch(
      comicManifestMonitorProvider(widget.itemId),
    );
    ref.listen(comicManifestMonitorProvider(widget.itemId), (_, next) {
      final manifest = next.asData?.value.manifest;
      if (manifest != null) {
        unawaited(_loadManifest(manifest));
      }
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
            const Positioned.fill(child: AppLoading.simple()),
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
