import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_progress_sync_service.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDF 阅读页：经 file-ticket 拉取字节后由 pdfrx 渲染。
///
/// 进度契约：charOffset=当前页（1 起），chapterId 固定 `pdf`，
/// progressPercent = 当前页 / 总页数。
class PdfReaderPage extends ConsumerStatefulWidget {
  const PdfReaderPage({required this.itemId, super.key});

  final String itemId;

  @override
  ConsumerState<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends ConsumerState<PdfReaderPage> {
  String? _error;
  bool _loading = true;
  Uint8List? _bytes;
  int _currentPage = 1;
  int _totalPages = 0;
  DateTime _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(readerApiProvider);
      final detail = await api.detail(widget.itemId);
      final initialProgress =
          (detail.progress?.progressPercent ?? 0).clamp(0, 1).toDouble();
      final bytes = await api.downloadFileBytes(widget.itemId, itemType: 'PDF');
      if (!mounted) {
        return;
      }
      final document = await PdfDocument.openData(
        bytes,
        sourceName: 'reader-${widget.itemId}',
      );
      final totalPages = document.pages.length;
      await document.dispose();
      if (!mounted) {
        return;
      }
      final startPage =
          totalPages <= 0
              ? 1
              : (initialProgress * totalPages).ceil().clamp(1, totalPages);
      setState(() {
        _bytes = bytes;
        _totalPages = totalPages;
        _currentPage = startPage;
        _loading = false;
      });
      await _syncProgress(force: true);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _syncProgress({bool force = false}) async {
    final total = _totalPages;
    if (total <= 0 || !mounted) {
      return;
    }
    final now = DateTime.now();
    if (!force && now.difference(_lastSyncAt) < const Duration(seconds: 2)) {
      return;
    }
    _lastSyncAt = now;
    await ref
        .read(readerProgressSyncServiceProvider)
        .sync(
          itemId: widget.itemId,
          charOffset: _currentPage,
          progressPercent: _currentPage / total,
          readingMode: 'page',
          chapterId: 'pdf',
          pageIndex: _currentPage - 1,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return Scaffold(body: Center(child: AppLoading.detail()));
    }
    if (_error != null || _bytes == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.readerPdfTitle)),
        body: AppErrorView(
          message: _error ?? l10n.readerPdfLoadFailed,
          onRetry: _load,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.readerPdfPageIndicator(_currentPage, _totalPages)),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: PdfViewer.data(
        _bytes!,
        sourceName: 'reader-${widget.itemId}',
        initialPageNumber: _currentPage,
        params: PdfViewerParams(
          onPageChanged: (pageNumber) {
            if (pageNumber == null) {
              return;
            }
            setState(() => _currentPage = pageNumber);
            unawaited(_syncProgress());
          },
        ),
      ),
    );
  }
}
