import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:omninest/core/log/dev_log.dart';

/// Web 平台 localStorage 备份（同步 API）。
///
/// 存储内容仅含阅读进度元数据（chapterId、charOffset、chapterProgress、savedAt），
/// 不包含书签正文、批注文本或笔记内容。清理策略：每本书一个 key（`omninest_progress_{itemId}`），
/// 删除书籍进度时调用 [clear]；SQLite 中的 ReaderLocalStorage 为主存储，localStorage 仅为
/// Web 端防崩溃/刷新的同步备份，恢复后同步回 SQLite 并可清除。
class ReaderProgressBackupWeb {
  static const _prefix = 'omninest_progress_';

  static void save({
    required String itemId,
    required String chapterId,
    required int charOffset,
    required double chapterProgress,
  }) {
    try {
      final key = '$_prefix$itemId';
      final data = jsonEncode({
        'chapterId': chapterId,
        'charOffset': charOffset,
        'chapterProgress': chapterProgress,
        'savedAt': DateTime.now().toIso8601String(),
      });
      web.window.localStorage.setItem(key, data);
    } on Exception catch (error) {
      devLog('ReaderProgressBackupWeb: save failed for $itemId: $error');
    }
  }

  static Map<String, dynamic>? load(String itemId) {
    try {
      final key = '$_prefix$itemId';
      final data = web.window.localStorage.getItem(key);
      if (data == null || data.isEmpty) return null;
      return jsonDecode(data) as Map<String, dynamic>;
    } on Exception catch (error) {
      devLog('ReaderProgressBackupWeb: load failed for $itemId: $error');
      return null;
    }
  }

  static void clear(String itemId) {
    try {
      web.window.localStorage.removeItem('$_prefix$itemId');
    } on Exception catch (error) {
      devLog('ReaderProgressBackupWeb: clear failed for $itemId: $error');
    }
  }
}
