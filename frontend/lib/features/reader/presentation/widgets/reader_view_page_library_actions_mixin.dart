import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
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
  String get currentChapterId;
  double? get bookProgress;

  ReaderProgressSnapshot? buildProgressSnapshot({double? progressOverride});
  Future<void> checkBookmarkState();

  /// 切换当前章节的书签状态。
  Future<void> toggleBookmark(
    ReaderItemDetail detail,
    ReaderChapterContent content,
  ) async {
    if (bookmarkBusy) return;
    setState(() => bookmarkBusy = true);
    final l10n = AppLocalizations.of(context);
    final dataManager = ref.read(readerDataManagerProvider);
    final snapshot = buildProgressSnapshot();
    final chapterId = (snapshot?.chapterId ?? currentChapterId).trim();
    final charOffset = snapshot?.charOffset ?? 0;
    String msg;
    try {
      final bookmarks = await dataManager.loadBookmarks(itemId);
      final existing =
          bookmarks
              .where(
                (b) =>
                    b.readerItemId == itemId &&
                    bookmarkAtChapter(
                      b,
                      chapterId: chapterId.isEmpty ? null : chapterId,
                      charOffset: charOffset,
                    ),
              )
              .toList();
      if (existing.isNotEmpty) {
        for (final bookmark in existing) {
          await dataManager.deleteBookmark(bookmark.id);
        }
        msg = l10n.readerBookmarkRemoved;
      } else {
        await dataManager.createBookmark(
          itemId: itemId,
          chapterId: chapterId.isEmpty ? null : chapterId,
          charOffset: charOffset,
          // 全书口径未知时记 0，不把章内比例写成全书百分比。
          progressPercent: bookProgress ?? 0,
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
    // 无 activity:write 的角色：明确提示无权限，不触发远端请求。
    if (!ref.read(userCapabilitiesProvider).canManageOwnActivity) {
      showReaderSnackBar(context, AppLocalizations.of(context).errorForbidden);
      return;
    }
    setState(() => bookshelfBusy = true);
    final l10n = AppLocalizations.of(context);
    try {
      final result = await ref
          .read(readerCenterControllerProvider.notifier)
          .toggleBookshelf(itemId);
      if (mounted) {
        // 以服务端返回为准，本地取反会在状态过期时与服务端脱节。
        setState(() => isInBookshelf = result.addedToBookshelf);
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
