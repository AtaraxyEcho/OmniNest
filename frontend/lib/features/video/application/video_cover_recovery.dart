import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/video/application/movie_controller.dart';

/// 影片封面自愈控制器：state 即重试世代号。
///
/// posterUrl 是带 token/签名的短期地址（2h/6h）；影片中心 provider 常驻
/// 内存，地址过期后海报请求 403，且 CachedNetworkImage 的 provider 相等
/// 性只看 cacheKey，同 key 的 URL 轮换不会重载已失败的流。海报加载失败
/// 时节流上报：刷新影片中心与 dashboard 数据换取现签地址，并递增世代号
/// 供消费方以后缀 cacheKey 强制重试。
class VideoCoverRecoveryController extends Notifier<int> {
  static const Duration _minInterval = Duration(seconds: 8);
  static const Duration _window = Duration(minutes: 5);
  static const int _maxAttempts = 3;

  DateTime? _lastAt;
  final List<DateTime> _attempts = <DateTime>[];

  @override
  int build() => 0;

  /// 海报加载失败上报；节流后触发数据重签与世代递增。
  void reportFailure() {
    final now = DateTime.now();
    _attempts.removeWhere((time) => now.difference(time) > _window);
    if (_attempts.length >= _maxAttempts) {
      return;
    }
    final last = _lastAt;
    if (last != null && now.difference(last) < _minInterval) {
      return;
    }
    _lastAt = now;
    _attempts.add(now);
    state = state + 1;
    // refresh 保留现有视图状态重取数据；dashboard 是 Portal 胶片条
    // 的数据源，一并作废换取现签地址。
    unawaited(ref.read(movieCenterControllerProvider.notifier).refresh());
    ref.invalidate(movieDashboardProvider);
  }
}

final videoCoverRecoveryProvider =
    NotifierProvider<VideoCoverRecoveryController, int>(
      VideoCoverRecoveryController.new,
    );
