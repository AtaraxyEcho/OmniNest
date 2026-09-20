import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:omninest/features/video/presentation/widgets/subtitle_parser.dart';

enum MoviePlayerKeyboardAction {
  playPause,
  seekBackward5,
  seekForward5,
  seekBackward10,
  seekForward10,
  volumeUp,
  volumeDown,
  toggleMute,
  toggleSubtitle,
  toggleFullscreen,
  speedDown,
  speedUp,
  cycleAspectRatio,
  previousEpisode,
  nextEpisode,
  escape,
}

/// 将键盘事件映射为播放器操作。
///
/// 桌面 F11 不在此映射：由 app.dart 的 HardwareKeyboard 全局 handler
/// 统一分发无边框全屏，页面 Focus 再处理一次会导致 Windows 上双重 toggle。
MoviePlayerKeyboardAction? resolveMoviePlayerKeyboardAction(
  LogicalKeyboardKey key, {
  required bool shiftPressed,
  required bool isWeb,
}) {
  if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
    return MoviePlayerKeyboardAction.playPause;
  }
  if (key == LogicalKeyboardKey.arrowLeft) {
    return MoviePlayerKeyboardAction.seekBackward5;
  }
  if (key == LogicalKeyboardKey.arrowRight) {
    return MoviePlayerKeyboardAction.seekForward5;
  }
  if (key == LogicalKeyboardKey.keyJ) {
    return MoviePlayerKeyboardAction.seekBackward10;
  }
  if (key == LogicalKeyboardKey.keyL) {
    return MoviePlayerKeyboardAction.seekForward10;
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    return MoviePlayerKeyboardAction.volumeUp;
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    return MoviePlayerKeyboardAction.volumeDown;
  }
  if (key == LogicalKeyboardKey.keyM) {
    return MoviePlayerKeyboardAction.toggleMute;
  }
  if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.keyS) {
    return MoviePlayerKeyboardAction.toggleSubtitle;
  }
  if (key == LogicalKeyboardKey.keyF) {
    // F11 由 app.dart 的 HardwareKeyboard 全局 handler 统一分发。
    // 播放器 Focus 若同时处理 F11，Windows 上会双重 toggle，表现为「按了没反应」。
    return MoviePlayerKeyboardAction.toggleFullscreen;
  }
  if (shiftPressed && key == LogicalKeyboardKey.comma) {
    return MoviePlayerKeyboardAction.speedDown;
  }
  if (shiftPressed && key == LogicalKeyboardKey.period) {
    return MoviePlayerKeyboardAction.speedUp;
  }
  if (key == LogicalKeyboardKey.keyA) {
    return MoviePlayerKeyboardAction.cycleAspectRatio;
  }
  if (shiftPressed && key == LogicalKeyboardKey.keyP) {
    return MoviePlayerKeyboardAction.previousEpisode;
  }
  if (shiftPressed && key == LogicalKeyboardKey.keyN) {
    return MoviePlayerKeyboardAction.nextEpisode;
  }
  if (key == LogicalKeyboardKey.escape) {
    return MoviePlayerKeyboardAction.escape;
  }
  return null;
}

/// 判断播放器操作是否允许按键长按连续触发。
bool isRepeatableMoviePlayerAction(MoviePlayerKeyboardAction action) {
  return switch (action) {
    MoviePlayerKeyboardAction.seekBackward5 ||
    MoviePlayerKeyboardAction.seekForward5 ||
    MoviePlayerKeyboardAction.seekBackward10 ||
    MoviePlayerKeyboardAction.seekForward10 ||
    MoviePlayerKeyboardAction.volumeUp ||
    MoviePlayerKeyboardAction.volumeDown => true,
    _ => false,
  };
}

/// 限制短时间内重复提交播放状态切换。
class MoviePlayerCommandGate {
  MoviePlayerCommandGate({this.cooldown = const Duration(milliseconds: 250)});

  final Duration cooldown;
  DateTime? _lastAcceptedAt;

  bool accept(DateTime now) {
    final lastAcceptedAt = _lastAcceptedAt;
    if (lastAcceptedAt != null && now.difference(lastAcceptedAt) < cooldown) {
      return false;
    }
    _lastAcceptedAt = now;
    return true;
  }
}

/// 将播放器时长格式化为控制栏使用的文本。
String formatMoviePlayerDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

/// 将流式播放 Seek 目标限制在合法范围内。
int clampMovieSeekSeconds(Duration target, int durationSeconds) {
  final targetSeconds = target.inSeconds;
  final upperBound =
      durationSeconds > 0 ? durationSeconds : math.max(0, targetSeconds);
  return targetSeconds.clamp(0, upperBound);
}

/// 判断播放进度是否已进入片尾完成区间。
bool isMoviePlaybackCompleted(int positionSeconds, int durationSeconds) {
  return durationSeconds > 0 && positionSeconds >= durationSeconds - 20;
}

/// 查找当前位置最后一个有效的字幕提示。
/// 使用二分定位上界，再向前找最后一个有效 cue，避免逐条线性扫描。
int findActiveSubtitleCueIndex(List<SubtitleCue> cues, Duration position) {
  final positionMs = position.inMilliseconds;
  if (cues.isEmpty) {
    return -1;
  }
  // 二分：找到首个 startMs > positionMs 的索引，作为搜索上界。
  int low = 0;
  int high = cues.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (cues[mid].startMs <= positionMs) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  // 在上界之前从后往前找最后一个 endMs >= positionMs 的 cue。
  for (var index = low - 1; index >= 0; index--) {
    final cue = cues[index];
    if (positionMs <= cue.endMs) {
      return index;
    }
  }
  return -1;
}
