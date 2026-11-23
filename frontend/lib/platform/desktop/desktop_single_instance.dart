import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:omninest/platform/desktop/desktop_deep_link_bridge.dart';
import 'package:omninest/core/log/dev_log.dart';
import 'package:window_manager/window_manager.dart';

export 'package:omninest/platform/desktop/desktop_deep_link_bridge.dart';

/// 桌面单实例回环端口。
///
/// 与 Windows runner `main.cpp` 中 `kActivatePort` 同值；修改时必须
/// 同步两处，否则 runner 转发与 Dart 监听会失联。
const int kOmniNestSingleInstancePort = 47683;

/// 客户端等待对端 `OK` ACK 的超时上限。
const Duration _kSingleInstanceAckTimeout = Duration(milliseconds: 300);

/// 当前进程持有的单实例回环监听套接字，退出时立即释放。
ServerSocket? _instanceServer;

/// 当前进程写入的单实例令牌文件，退出时一并清理。
File? _instanceTokenFile;

/// 当前进程生成的 32 字节 hex 单实例会话令牌（监听成功后写入用户目录令牌文件）。
String? _activeSessionToken;

/// 测试注入：覆盖单实例令牌文件路径。
@visibleForTesting
String? debugOverrideInstanceTokenFilePath;

/// 测试注入：覆盖当前服务端期望的会话令牌。
@visibleForTesting
String? debugOverrideActiveSessionToken;

/// 桌面单实例锁：首个实例占用回环固定端口，后续实例发送带令牌激活信号并等待
/// `OK` ACK 后退出。
///
/// 纯 Dart 实现跨 Windows/Linux/macOS；端口被非 OmniNest 进程占用时（令牌
/// 校验或 `OK` 握手失败）放弃单实例能力照常启动。Windows runner 层另有
/// Mutex + 同端口令牌/ACK 转发，负责在 Flutter 启动前把命令行交给已有实例。
Future<void> ensureSingleDesktopInstance({
  List<String> arguments = const [],
}) async {
  const port = kOmniNestSingleInstancePort;
  try {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    final token = _generateSessionToken();
    _instanceServer = server;
    _activeSessionToken = token;
    _instanceTokenFile = _resolveInstanceTokenFile();
    await _writeInstanceToken(token);
    server.listen((socket) {
      _handleIncomingConnection(socket, expectedToken: token);
    });
  } on SocketException {
    if (await _forwardToRunningInstance(port, arguments)) {
      devLog('检测到已运行的 OmniNest 实例，已激活主窗口并退出');
      exit(0);
    }
    devLog('单实例端口被其他进程占用或握手未通过，跳过单实例保护');
  }
}

/// 退出前立即释放单实例回环端口并删除令牌文件，防止退出窗口期拦截二次启动。
Future<void> closeSingleDesktopInstance() async {
  final server = _instanceServer;
  _instanceServer = null;
  _activeSessionToken = null;
  if (server != null) {
    try {
      await server.close();
    } on Object catch (error) {
      devLog('关闭单实例回环端口失败（忽略继续退出）: $error');
    }
  }
  final tokenFile = _instanceTokenFile ?? _resolveInstanceTokenFile();
  _instanceTokenFile = null;
  if (tokenFile != null) {
    try {
      if (await tokenFile.exists()) {
        await tokenFile.delete();
      }
    } on Object catch (error) {
      devLog('删除单实例令牌文件失败（忽略继续退出）: $error');
    }
  }
}

void _handleIncomingConnection(Socket socket, {required String expectedToken}) {
  var handledFirstLine = false;
  late StreamSubscription<String> sub;
  sub = socket
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(
        (line) {
          if (handledFirstLine) {
            return;
          }
          handledFirstLine = true;
          unawaited(sub.cancel());
          final accepted = _handleControlLine(
            line,
            expectedToken: expectedToken,
          );
          if (!accepted) {
            socket.destroy();
            return;
          }
          unawaited(() async {
            try {
              socket.write('OK\n');
              await socket.flush();
            } on Object {
              // 对端已提前断开时忽略写回异常。
            } finally {
              socket.destroy();
            }
          }());
        },
        onError: (Object _) {
          socket.destroy();
        },
        onDone: () {
          if (!handledFirstLine) {
            socket.destroy();
          }
        },
        cancelOnError: true,
      );
}

bool _handleControlLine(String line, {String? expectedToken}) {
  const activatePrefix = 'OMNINEST_ACTIVATE';
  final trimmed = line.trim();
  if (!trimmed.startsWith(activatePrefix)) {
    return false;
  }
  final effectiveExpected =
      expectedToken ?? debugOverrideActiveSessionToken ?? _activeSessionToken;
  final rest = trimmed.substring(activatePrefix.length).trim();

  if (effectiveExpected != null && effectiveExpected.isNotEmpty) {
    if (rest.isEmpty) {
      return false;
    }
    final firstSpace = rest.indexOf(' ');
    final providedToken =
        firstSpace == -1 ? rest : rest.substring(0, firstSpace);
    if (providedToken != effectiveExpected) {
      return false;
    }
    final deepLinkRaw =
        firstSpace == -1 ? '' : rest.substring(firstSpace + 1).trim();
    unawaited(_activateMainWindow());
    _dispatchDeepLinkIfValid(deepLinkRaw);
    return true;
  }

  // 无会话令牌上下文（纯单测直接调用旧签名）：保持对深链解析的向后兼容。
  unawaited(_activateMainWindow());
  _dispatchDeepLinkIfValid(rest);
  return true;
}

void _dispatchDeepLinkIfValid(String raw) {
  if (raw.isEmpty) {
    return;
  }
  final uri = Uri.tryParse(raw);
  if (uri != null && uri.scheme.toLowerCase() == 'omninest') {
    desktopDeepLinkHandler?.call(uri);
  }
}

/// 生成 32 字节（64 字符）随机十六进制会话令牌。
String _generateSessionToken() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 32; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

File? _resolveInstanceTokenFile() {
  final override = debugOverrideInstanceTokenFilePath;
  if (override != null && override.isNotEmpty) {
    return File(override);
  }
  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) {
      return null;
    }
    return File(
      '$localAppData${Platform.pathSeparator}OmniNest${Platform.pathSeparator}instance.token',
    );
  }
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return null;
  }
  return File('$home/.config/omninest/instance.token');
}

Future<void> _writeInstanceToken(String token) async {
  final file = _instanceTokenFile ?? _resolveInstanceTokenFile();
  if (file == null) {
    return;
  }
  _instanceTokenFile = file;
  try {
    await file.parent.create(recursive: true);
    await file.writeAsString('$token\n', flush: true);
  } on Object catch (error) {
    devLog('写入单实例令牌文件失败: $error');
  }
}

Future<String?> _readInstanceToken() async {
  final file = _resolveInstanceTokenFile();
  if (file == null) {
    return null;
  }
  try {
    if (!await file.exists()) {
      return null;
    }
    final content = (await file.readAsString()).trim();
    return content.isEmpty ? null : content;
  } on Object {
    return null;
  }
}

/// 测试入口：解析控制行（激活信号 + 令牌 + 可选深链）。
@visibleForTesting
bool handleSingleInstanceControlLine(String line, {String? expectedToken}) =>
    _handleControlLine(line, expectedToken: expectedToken);

/// 测试入口：从启动参数提取 `omninest://` 深链。
@visibleForTesting
String? extractDesktopDeepLink(List<String> arguments) =>
    _extractDeepLink(arguments);

/// 测试入口：向指定端口发送带令牌激活信号并等待 `OK` ACK。
@visibleForTesting
Future<bool> forwardSingleInstanceActivate({
  required int port,
  List<String> arguments = const [],
  String? tokenOverride,
}) => _forwardToRunningInstance(port, arguments, tokenOverride: tokenOverride);

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

/// 向已运行实例发送带令牌激活信号（可选深链 URI），等待 300ms 内 `OK` 回复。
/// 返回 false 表示对端不是 OmniNest 或令牌不匹配。
Future<bool> _forwardToRunningInstance(
  int port,
  List<String> arguments, {
  String? tokenOverride,
}) async {
  final token = (tokenOverride ?? await _readInstanceToken())?.trim();
  if (token == null || token.isEmpty) {
    return false;
  }
  Socket? client;
  try {
    client = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: _kSingleInstanceAckTimeout,
    );
    final ackCompleter = Completer<bool>();
    final sub = client
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (!ackCompleter.isCompleted) {
              ackCompleter.complete(line.trim() == 'OK');
            }
          },
          onError: (Object _) {
            if (!ackCompleter.isCompleted) {
              ackCompleter.complete(false);
            }
          },
          onDone: () {
            if (!ackCompleter.isCompleted) {
              ackCompleter.complete(false);
            }
          },
          cancelOnError: true,
        );
    final deepLink = _extractDeepLink(arguments);
    final payload =
        deepLink == null
            ? 'OMNINEST_ACTIVATE $token\n'
            : 'OMNINEST_ACTIVATE $token $deepLink\n';
    client.write(payload);
    await client.flush();
    final acked = await ackCompleter.future.timeout(
      _kSingleInstanceAckTimeout,
      onTimeout: () => false,
    );
    await sub.cancel().catchError((_) {});
    return acked;
  } on Object {
    return false;
  } finally {
    client?.destroy();
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
