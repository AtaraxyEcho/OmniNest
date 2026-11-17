import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:omninest/platform/desktop/desktop_deep_link_bridge.dart';
import 'package:omninest/core/log/dev_log.dart';
import 'package:window_manager/window_manager.dart';

export 'package:omninest/platform/desktop/desktop_deep_link_bridge.dart';

/// 桌面单实例回环端口。
///
/// 与 Windows runner `main.cpp` 中 `kOmniNestControlPort` 同值；修改时必须
/// 同步两处，否则 runner 转发与 Dart 监听会失联。
const int kOmniNestSingleInstancePort = 47683;

/// 桌面单实例锁：首个实例占用回环固定端口，后续实例发送激活信号（可带深链）后退出。
///
/// 纯 Dart 实现跨 Windows/Linux/macOS；端口被非 OmniNest 进程占用时放弃
/// 单实例能力照常启动。Windows runner 层另有 Mutex + 同端口转发，负责在
/// Flutter 启动前把命令行交给已有实例。
Future<void> ensureSingleDesktopInstance({
  List<String> arguments = const [],
}) async {
  const port = kOmniNestSingleInstancePort;
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
      devLog('检测到已运行的 OmniNest 实例，已激活主窗口并退出');
      exit(0);
    }
    devLog('单实例端口被其他进程占用，跳过单实例保护');
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

/// 测试入口：解析控制行（激活信号 + 可选深链）。
@visibleForTesting
void handleSingleInstanceControlLine(String line) => _handleControlLine(line);

/// 测试入口：从启动参数提取 `omninest://` 深链。
@visibleForTesting
String? extractDesktopDeepLink(List<String> arguments) =>
    _extractDeepLink(arguments);

/// 测试入口：向指定端口发送激活信号（可带深链）。
@visibleForTesting
Future<bool> forwardSingleInstanceActivate({
  required int port,
  List<String> arguments = const [],
}) => _forwardToRunningInstance(port, arguments);

Future<void> _activateMainWindow() async {
  final debugActivate = debugOverrideActivateMainWindow;
  if (debugActivate != null) {
    debugActivate();
    return;
  }
  try {
    await windowManager.show();
    await windowManager.focus();
  } on Object catch (error) {
    devLog('激活主窗口失败: $error');
  }
}

/// 测试注入：替代 `windowManager` 激活主窗口。
@visibleForTesting
void Function()? debugOverrideActivateMainWindow;

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
