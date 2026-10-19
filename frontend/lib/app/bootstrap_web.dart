import 'dart:developer';
import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:omninest/core/errors/error_message.dart';

/// CanvasKit 引擎层 JS 报错的白名单由 `web/js/omninest-engine-noise.js` 在
/// 文档解析阶段接管；后端 CSP 禁止内联脚本，Dart 侧不再注入 `<script>`。

/// 等待浏览器字体加载完成，避免首帧中文字符显示为豆腐块
Future<void> waitForFonts() async {
  try {
    final fonts = web.document.fonts;
    await fonts.ready.toDart;
  } catch (e) {
    log('Font readiness check failed', error: e);
  }
}

/// 判断是否为 Flutter Web engine 层的运行时噪音（无需处理）
bool isEngineNoise(Object error) {
  final message = describeUserFacingError(error).message;
  if (message.contains('Non-error') && message.contains('null')) return true;
  if (message.contains('LateInitializationError') &&
      message.contains('_handledContextLostEvent')) {
    return true;
  }
  if (message.contains('Assertion failed') && message.contains('window.dart')) {
    return true;
  }
  if (message.contains('LegacyJavaScriptObject') &&
      message.contains('DioException')) {
    return true;
  }
  return false;
}
