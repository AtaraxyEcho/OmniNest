import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:omninest/platform/desktop/desktop_deep_link_bridge.dart';
import 'package:window_manager/window_manager.dart';

export 'package:omninest/platform/desktop/desktop_deep_link_bridge.dart';

/// 桌面单实例锁：首个实例占用回环固定端口，后续实例发送激活信号（可带深链）后退出。
///
/// 纯 Dart 实现跨 Windows/Linux/macOS；端口被非 OmniNest 进程占用时放弃
/// 单实例能力照常启动。
Future<void> ensureSingleDesktopInstance({
  List<String> arguments = const [],
}) async {
  const port = 47683;
  try {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    server.listen((socket) {
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => _handleControlLine(line),
            onError: (Object _) {},
            onDone: () {},
            cancelOnError: true,
          );
    });
  } on SocketException {
    if (await _forwardToRunningInstance(port, arguments)) {
      debugPrint('检测到已运行的 OmniNest 实例，已激活主窗口并退出');
      exit(0);
    }
    debugPrint('单实例端口被其他进程占用，跳过单实例保护');
  }
}

void _handleControlLine(String line) {
  const activatePrefix = 'OMNINEST_ACTIVATE';
  if (!line.startsWith(activatePrefix)) {
    return;
  }
  unawaited(_activateMainWindow());
  final rest = line.substring(activatePrefix.length).trim();
  if (rest.isEmpty) {
    return;
  }
  final uri = Uri.tryParse(rest);
  if (uri != null && uri.scheme.toLowerCase() == 'omninest') {
    desktopDeepLinkHandler?.call(uri);
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

/// 向已运行实例发送激活信号（可选深链 URI）；返回 false 表示对端不是 OmniNest。
Future<bool> _forwardToRunningInstance(int port, List<String> arguments) async {
  Socket? client;
  try {
    client = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 1),
    );
    final deepLink = _extractDeepLink(arguments);
    final payload =
        deepLink == null
            ? 'OMNINEST_ACTIVATE\n'
            : 'OMNINEST_ACTIVATE $deepLink\n';
    client.write(payload);
    await client.flush();
    return true;
  } on Object {
    return false;
  } finally {
    await client?.close().catchError((_) {});
  }
}

String? _extractDeepLink(List<String> arguments) {
  for (final arg in arguments) {
    final trimmed = arg.trim();
    if (trimmed.toLowerCase().startsWith('omninest://')) {
      return trimmed;
    }
  }
  return null;
}
