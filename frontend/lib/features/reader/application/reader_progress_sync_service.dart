import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';
import 'package:omninest/features/reader/data/reader_api.dart';

/// 阅读进度远端同步与离线降级服务。
class ReaderProgressSyncService {
  const ReaderProgressSyncService(this._api);

  final ReaderApi _api;

  /// 同步阅读进度，远端失败时写入离线队列。
  Future<void> sync({
    required String itemId,
    required int charOffset,
    required double progressPercent,
    required String readingMode,
    String? chapterId,
    String? pageId,
    int? pageIndex,
    String? pageFingerprint,
    String? sourceId,
    int? sourcePageIndex,
    String? catalogKey,
    int? manifestVersion,
    double? intraPageOffset,
    DateTime? clientUpdatedAt,
  }) async {
    try {
      await _api.updateProgress(
        itemId: itemId,
        charOffset: charOffset,
        progressPercent: progressPercent,
        readingMode: readingMode,
        chapterId: chapterId,
        pageId: pageId,
        pageIndex: pageIndex,
        pageFingerprint: pageFingerprint,
        sourceId: sourceId,
        sourcePageIndex: sourcePageIndex,
        catalogKey: catalogKey,
        manifestVersion: manifestVersion,
        intraPageOffset: intraPageOffset,
        clientUpdatedAt: clientUpdatedAt,
      );
    } on Exception {
      await ReaderSyncQueue.enqueueProgress(
        itemId: itemId,
        charOffset: charOffset,
        progressPercent: progressPercent,
        readingMode: readingMode,
        chapterId: chapterId,
        pageId: pageId,
        pageIndex: pageIndex,
        pageFingerprint: pageFingerprint,
        sourceId: sourceId,
        sourcePageIndex: sourcePageIndex,
        catalogKey: catalogKey,
        manifestVersion: manifestVersion,
        intraPageOffset: intraPageOffset,
        clientUpdatedAt: clientUpdatedAt,
      );
    }
  }
}

/// 阅读进度同步服务 Provider。
final readerProgressSyncServiceProvider = Provider<ReaderProgressSyncService>((
  ref,
) {
  return ReaderProgressSyncService(ref.read(readerApiProvider));
});
