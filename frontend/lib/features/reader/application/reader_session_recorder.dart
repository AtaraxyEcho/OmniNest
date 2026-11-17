import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 阅读会话记录工具。
///
/// 记录阅读时长，先写入统一同步队列，再由后台刷新同步后端。
/// 从 reader_view_page.dart 提取。
class ReaderSessionRecorder {
  ReaderSessionRecorder._();

  /// 记录阅读会话。
  ///
  /// 会话只进入 ReaderSyncQueue，避免 SharedPreferences 与同步队列双写。
  /// [activeReading] 为前台活跃阅读时长（剔除切后台挂机），由调用方
  /// 通过生命周期边界累积；[sessionStart] 仅作为会话起点与幂等键素材。
  static void recordSession({
    required String itemId,
    required DateTime sessionStart,
    required Duration activeReading,
  }) {
    final now = DateTime.now();
    final duration = activeReading.inSeconds;
    if (duration < 10) return;

    final clientSessionId =
        '$itemId-${sessionStart.toUtc().microsecondsSinceEpoch}-${now.toUtc().microsecondsSinceEpoch}';
    unawaited(
      _enqueueSession(
        clientSessionId: clientSessionId,
        itemId: itemId,
        startedAt: sessionStart.toUtc().toIso8601String(),
        endedAt: now.toUtc().toIso8601String(),
        durationSeconds: duration,
      ),
    );
  }

  static Future<void> _enqueueSession({
    required String clientSessionId,
    required String itemId,
    required String startedAt,
    required String endedAt,
    required int durationSeconds,
  }) async {
    try {
      await ReaderSyncQueue.enqueueSessionCreate(
        clientSessionId: clientSessionId,
        itemId: itemId,
        startedAt: startedAt,
        endedAt: endedAt,
        durationSeconds: durationSeconds,
      );
    } catch (e) {
      // 队列未初始化等Error同样不能击穿退出路径：会话记录失败仅记录
      // 调试日志，等待下一次会话补录。
      if (kDebugMode) {
        readerDebugLog('ReaderSessionRecorder: session enqueue failed: $e');
      }
    }
  }
}
