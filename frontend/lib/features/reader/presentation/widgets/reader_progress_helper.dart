import 'dart:async';

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
      if (backupSavedAt.compareTo(localSavedAt) > 0) {
        localPayload = {
          'chapterId': backup['chapterId'],
          'charOffset': backup['charOffset'],
          'chapterProgress': backup['chapterProgress'],
          'mode': 'scroll',
          'updatedAt': backupSavedAt,
        };
        unawaited(
          ReaderLocalProgress.save(
            itemId: itemId,
            chapterProgress:
                (backup['chapterProgress'] as num?)?.toDouble() ?? 0,
            mode: 'scroll',
            chapterId: chapterId,
            charOffset: (backup['charOffset'] as num?)?.toInt() ?? 0,
          ),
        );
        ReaderProgressBackupWeb.clear(itemId);
        if (kDebugMode) {
          readerDebugLog(
            'ProgressLoad: used localStorage backup, synced to SQLite',
          );
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
