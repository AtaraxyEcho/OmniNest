import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 阅读页书签与书架操作逻辑。
mixin ReaderViewPageLibraryActionsMixin on ConsumerState<ReaderViewPage> {
  bool get bookmarkBusy;
  set bookmarkBusy(bool value);
  bool get bookshelfBusy;
  set bookshelfBusy(bool value);
  bool get isInBookshelf;
  set isInBookshelf(bool value);
  String get itemId;
  double get bookProgress;

  ReaderProgressSnapshot? buildProgressSnapshot({double? progressOverride});
  Future<void> checkBookmarkState();

  /// 切换书签状态。
  Future<void> toggleBookmark(
    ReaderItemDetail detail,
    ReaderChapterContent content,
  ) async {
    if (bookmarkBusy) return;
    setState(() => bookmarkBusy = true);
    final l10n = AppLocalizations.of(context);
    final dataManager = ref.read(readerDataManagerProvider);
    String msg;
    try {
      final existing =
          (await dataManager.loadBookmarks(
            itemId,
          )).where((b) => b.readerItemId == itemId).toList();
      if (existing.isNotEmpty) {
        await dataManager.deleteBookmark(existing.first.id);
        msg = l10n.readerBookmarkRemoved;
      } else {
        final snapshot = buildProgressSnapshot();
        await dataManager.createBookmark(
          itemId: itemId,
          charOffset: snapshot?.charOffset ?? 0,
          progressPercent: bookProgress,
        );
        msg = l10n.readerBookmarkAdded;
      }
      await checkBookmarkState();
    } on Exception catch (e) {
      if (kDebugMode) {
        readerDebugLog('ReaderView: bookmark operation failed: $e');
      }
      msg = l10n.readerBookmarkFailed;
    } finally {
      if (mounted) setState(() => bookmarkBusy = false);
    }
    if (!mounted) return;
    showReaderSnackBar(context, msg);
  }

  /// 切换书架状态。
  Future<void> toggleBookshelf(ReaderItemDetail detail) async {
    if (bookshelfBusy) return;
    setState(() => bookshelfBusy = true);
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .toggleBookshelf(itemId);
      if (mounted) {
        setState(() => isInBookshelf = !isInBookshelf);
        final msg =
            isInBookshelf
                ? l10n.readerAddedToBookshelf
                : l10n.readerRemovedFromBookshelf;
        showReaderSnackBar(context, msg);
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        readerDebugLog('ReaderView: bookshelf operation failed: $e');
      }
      if (mounted) {
        showReaderSnackBar(context, l10n.readerOperationFailed);
      }
    } finally {
      if (mounted) setState(() => bookshelfBusy = false);
    }
  }
}
