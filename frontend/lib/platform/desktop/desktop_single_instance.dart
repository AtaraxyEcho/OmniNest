import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面单实例锁：首个实例占用回环固定端口，后续实例发送激活信号后退出。
///
/// 纯 Dart 实现跨 Windows/Linux/macOS；端口被非 OmniNest 进程占用时放弃
/// 单实例能力照常启动。已知限制：极快连续启动可能落在首实例监听建立前，
/// 两个实例均可成为主实例（真互斥需 OS 级锁，后续按需加强）。
Future<void> ensureSingleDesktopInstance() async {
  const port = 47683;
  try {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    server.listen((socket) {
      socket.drain<void>().catchError((_) {});
      _activateMainWindow();
    });
  } on SocketException {
    if (await _activateRunningInstance(port)) {
      debugPrint('检测到已运行的 OmniNest 实例，已激活主窗口并退出');
      exit(0);
    }
    debugPrint('单实例端口被其他进程占用，跳过单实例保护');
  }
}

Future<void> _activateMainWindow() async {
  try {
    await windowManager.show();
    await windowManager.focus();
  } on Object catch (error) {
    debugPrint('激活主窗口失败: $error');
  }
}

/// 向已运行实例发送激活信号；返回 false 表示对端不是 OmniNest。
Future<bool> _activateRunningInstance(int port) async {
  Socket? client;
  try {
    client = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 1),
    );
    client.add('OMNINEST_ACTIVATE'.codeUnits);
    await client.flush();
    return true;
  } on Object {
    return false;
  } finally {
    await client?.close().catchError((_) {});
  }
}
