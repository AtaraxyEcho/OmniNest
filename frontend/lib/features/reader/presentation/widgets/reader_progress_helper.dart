import 'package:flutter/foundation.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_progress_backup.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 进度加载工具方法。
///
/// 从 reader_view_page.dart 提取的纯函数，不依赖 State。
class ReaderProgressHelper {
  ReaderProgressHelper._();

  /// 加载本地进度，返回最新的快照。
  static Future<ReaderProgressSnapshot?> loadLocalProgress({
    required String itemId,
    required String chapterId,
  }) async {
    var localPayload = await ReaderLocalProgress.load(itemId, chapterId);

    // Web 平台：检查 localStorage 备份
    final backup = ReaderProgressBackupWeb.load(itemId);
    if (backup != null &&
        (backup['chapterId']?.toString() ?? '') == chapterId) {
      final backupSavedAt = backup['savedAt']?.toString() ?? '';
      final localSavedAt = localPayload?['updatedAt']?.toString() ?? '';
      if (preferCrashBackup(
        backupSavedAt: backupSavedAt,
        localUpdatedAt: localSavedAt,
      )) {
        final backupCharOffset = (backup['charOffset'] as num?)?.toInt() ?? 0;
        final backupChapterProgress =
            (backup['chapterProgress'] as num?)?.toDouble() ?? 0;
        final backupManifestVersion =
            (backup['manifestVersion'] as num?)?.toInt();
        localPayload = {
          'chapterId': backup['chapterId'],
          'charOffset': backupCharOffset,
          'chapterProgress': backupChapterProgress,
          'mode': 'scroll',
          'manifestVersion': backupManifestVersion,
          'updatedAt': backupSavedAt,
        };
        // 先落 SQLite 再清备份：备份是唯一崩溃副本，写入失败时就地保留，
        // 否则清早了会把这份进度永久丢掉。
        try {
          await ReaderLocalProgress.save(
            itemId: itemId,
            chapterProgress: backupChapterProgress,
            mode: 'scroll',
            chapterId: chapterId,
            charOffset: backupCharOffset,
            manifestVersion: backupManifestVersion,
            // 崩溃副本的备份时刻就是它的记录时刻；重新打戳会把这份陈旧读数
            // 伪装成刚读的，进而压过服务端更新的位置。
            updatedAt: DateTime.tryParse(backupSavedAt),
          );
          ReaderProgressBackupWeb.clear(itemId);
          if (kDebugMode) {
            readerDebugLog(
              'ProgressLoad: used localStorage backup, synced to SQLite',
            );
          }
        } on Exception catch (error) {
          if (kDebugMode) {
            readerDebugLog(
              'ProgressLoad: backup sync failed, keeping backup: $error',
            );
          }
        }
      }
    }

    if (kDebugMode) {
      readerDebugLog(
        'ProgressLoad: chapterId=$chapterId, '
        'localPayload=${localPayload != null ? "found" : "null"}'
        '${localPayload != null ? ", progress=${localPayload['chapterProgress']}, charOffset=${localPayload['charOffset']}" : ""}',
      );
    }

    if (localPayload != null) {
      return ReaderProgressSnapshot.fromLocal(localPayload);
    }

    // loadLatest 可能返回其他章节的进度，只在匹配当前章节时使用
    final latest = await ReaderLocalProgress.loadLatest(itemId);
    if (kDebugMode) {
      readerDebugLog(
        'ProgressLoad Fallback: latest=${latest != null ? "found" : "null"}'
        '${latest != null ? ", chapterId=${latest['chapterId']}, progress=${latest['chapterProgress']}, charOffset=${latest['charOffset']}" : ""}',
      );
    }
    if (latest != null &&
        (latest['chapterId']?.toString() ?? '') == chapterId) {
      return ReaderProgressSnapshot.fromLocal(latest);
    }

    if (kDebugMode) {
      readerDebugLog('ProgressLoad RESULT: null');
    }
    return null;
  }
}

/// 崩溃备份是否比本地 SQLite 行更新。
///
/// 两侧都按时刻比较：备份自 2026-10-09 起带时区写出，但历史值与 drift 读回的
/// 本地无时区串仍会相遇，字符串比较会把"同一时刻的两种写法"判成新旧。
/// 备份时间戳解析不出来时不采信它（本地行是唯一可证的事实时就地保留），
/// 本地行缺时间戳则备份直接胜出。
bool preferCrashBackup({
  required String? backupSavedAt,
  required String? localUpdatedAt,
}) {
  final backupAt = DateTime.tryParse(backupSavedAt ?? '');
  if (backupAt == null) {
    return false;
  }
  final localAt = DateTime.tryParse(localUpdatedAt ?? '');
  return localAt == null || backupAt.isAfter(localAt);
}
