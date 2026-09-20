import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';

/// 封面加载失败自愈控制器。
///
/// 照片列表中的 coverUrl 是带签名的短期 URL；Web 端无磁盘缓存，
/// 内存缓存被挤出的格子会拿旧 URL 重新请求并 403。这里在缩略图
/// 加载失败时按节流策略触发一次实时合并刷新，让后端现签的 URL
/// 替换列表中的旧对象。连续失败有次数上限，避免后端异常时形成
/// “错误→刷新→再错误”的循环。
class PhotoCoverRecoveryController extends Notifier<int> {
  static const Duration _minInterval = Duration(seconds: 8);
  static const int _maxAttempts = 3;
  static const Duration _attemptWindow = Duration(minutes: 5);

  DateTime? _lastAttemptAt;
  int _attempts = 0;

  @override
  int build() => 0;

  /// 缩略图加载失败时上报；按节流窗口决定是否触发恢复刷新。
  void reportFailure() {
    final now = DateTime.now();
    final last = _lastAttemptAt;
    if (last == null || now.difference(last) > _attemptWindow) {
      _attempts = 0;
    }
    if (_attempts >= _maxAttempts) {
      return;
    }
    if (last != null && now.difference(last) < _minInterval) {
      return;
    }
    _lastAttemptAt = now;
    _attempts += 1;
    state = _attempts;
    unawaited(_recover());
  }

  Future<void> _recover() async {
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .refreshForRealtime();
    } on Exception catch (error) {
      // 恢复刷新失败不重试：到达次数上限前下一次失败上报会再触发。
      if (kDebugMode) {
        debugPrint('PhotoCoverRecovery: refresh failed: $error');
      }
    }
  }
}

final photoCoverRecoveryProvider =
    NotifierProvider<PhotoCoverRecoveryController, int>(
      PhotoCoverRecoveryController.new,
    );
