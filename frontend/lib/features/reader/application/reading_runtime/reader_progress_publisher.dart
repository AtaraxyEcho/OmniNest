import 'package:flutter/foundation.dart';

/// 唯一视觉进度发布器（方案 §49-§50 / §106）。
///
/// bookProgressNotifier 在 Scroll Mode 只允许此入口写入；页面内的
/// 防抖重算、refreshBookProgressNow、章节切换等路径都必须经 [publish]，
/// 从代码结构上保证单写者。
class ReaderVisualProgressPublisher {
  ReaderVisualProgressPublisher(this.notifier);

  final ValueNotifier<double> notifier;

  double _lastPublished = 0.0;

  double get lastPublished => _lastPublished;

  void publish(double progress) {
    final next = progress.clamp(0.0, 1.0);
    _lastPublished = next;
    if (notifier.value != next) {
      notifier.value = next;
    }
  }
}
