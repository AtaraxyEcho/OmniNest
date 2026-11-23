import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:media_kit/media_kit.dart';
import 'package:omninest/core/log/dev_log.dart';

/// 进程内活跃的前台 `media_kit` 播放器注册表与串行释放门控。
///
/// Windows 端 libmpv 播放器若在未先 `stop()` 的状态下并发或延迟销毁，
/// 易在窗口关闭期留下阻塞渲染/音频线程导致进程残留或原生崩溃。
/// 统一通过本模块登记活跃播放器并在退出或组件卸载时串行 `stop() -> dispose()`。
final Set<Player> _activeMediaPlayers = <Player>{};
final Expando<bool> _disposedMediaPlayers = Expando<bool>(
  'disposedMediaPlayer',
);
Future<void> _nativeDisposeGate = Future<void>.value();

const Duration _playerStopTimeout = Duration(milliseconds: 250);
const Duration _playerDisposeTimeout = Duration(milliseconds: 350);

/// 登记一个活跃的前台 `media_kit` 播放器，便于应用退出前统一释放。
void registerActiveMediaPlayer(Player player) {
  if (_disposedMediaPlayers[player] == true) {
    return;
  }
  _activeMediaPlayers.add(player);
}

/// 串行停止并释放单个 `media_kit` 播放器（幂等，重复调用安全忽略）。
Future<void> stopAndDisposeMediaPlayer(Player player) {
  _activeMediaPlayers.remove(player);
  if (_disposedMediaPlayers[player] == true) {
    return Future<void>.value();
  }
  _disposedMediaPlayers[player] = true;
  return _runOnDisposeGate(() async {
    try {
      await player.stop().timeout(_playerStopTimeout);
    } on Object catch (error) {
      if (kDebugMode) {
        devLog('[ActiveMediaPlayers] 释放前停止播放器失败: $error');
      }
    }
    try {
      await player.dispose().timeout(_playerDisposeTimeout);
    } on Object catch (error) {
      if (kDebugMode) {
        devLog('[ActiveMediaPlayers] 释放播放器失败: $error');
      }
    }
  });
}

/// 应用退出前串行停止并释放全部活跃的前台 `media_kit` 播放器。
Future<void> releaseAllActiveMediaPlayersForExit() async {
  final snapshot = List<Player>.of(_activeMediaPlayers);
  _activeMediaPlayers.clear();
  for (final player in snapshot) {
    await stopAndDisposeMediaPlayer(player);
  }
}

Future<T> _runOnDisposeGate<T>(Future<T> Function() operation) {
  final previous = _nativeDisposeGate;
  final completer = Completer<void>();
  _nativeDisposeGate = completer.future;
  return () async {
    await previous;
    try {
      return await operation();
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }();
}
