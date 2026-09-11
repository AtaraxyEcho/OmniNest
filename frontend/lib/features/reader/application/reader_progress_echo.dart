import 'package:flutter/foundation.dart' show visibleForTesting;

/// 进度回声检测：判断服务端回灌快照是否为本机近期保存的自身回声。
///
/// 本机保存 → 服务端落库 → 详情 provider 刷新，会产生与本机近期保存
/// 内容相同、时间戳略新的记录；不识别就会把刚保存的位置重新施加回
/// UI，表现为内容回跳"刷新"。
///
/// 只记最后一次保存会在"较旧保存的回声晚于较新保存到达"时漏判
/// （实机日志：两次保存差 67 字符，旧回声被误判为跨设备更新回灌），
/// 因此保留近期多次保存的环形记录，与任意一条匹配即视为回声。
class ReaderProgressEchoDetector {
  /// 最多保留的本机保存记录数。
  static const int maxEntries = 8;

  /// 记录保留时长。
  static const Duration retention = Duration(minutes: 5);

  /// 字符偏移匹配容差：连续两次保存的正常推进幅度内视为同一位置。
  static const int charTolerance = 128;

  /// 全书进度匹配容差。
  static const double progressTolerance = 0.004;

  /// 回声到达窗口：保存后该时长内到达的近似快照视为回声。
  static const Duration echoWindow = Duration(seconds: 30);

  final List<_OwnSave> _saves = [];

  /// 记录一次本机保存。
  void note({
    required String chapterId,
    required int charOffset,
    required double progress,
    required DateTime at,
  }) {
    _saves.add(
      _OwnSave(
        chapterId: chapterId,
        charOffset: charOffset,
        progress: progress,
        at: at,
      ),
    );
    final cutoff = at.subtract(retention);
    while (_saves.length > maxEntries) {
      _saves.removeAt(0);
    }
    _saves.removeWhere((s) => s.at.isBefore(cutoff));
  }

  /// 服务端快照是否为本机近期保存的回声。
  bool isEcho({
    required String chapterId,
    required int charOffset,
    required double progress,
    required DateTime at,
  }) {
    for (final own in _saves) {
      if (own.chapterId == chapterId &&
          (own.charOffset - charOffset).abs() <= charTolerance &&
          (own.progress - progress).abs() <= progressTolerance &&
          at.isBefore(own.at.add(echoWindow))) {
        return true;
      }
    }
    return false;
  }

  /// 清空记录（测试用）。
  @visibleForTesting
  void clear() => _saves.clear();
}

class _OwnSave {
  const _OwnSave({
    required this.chapterId,
    required this.charOffset,
    required this.progress,
    required this.at,
  });

  final String chapterId;
  final int charOffset;
  final double progress;
  final DateTime at;
}
