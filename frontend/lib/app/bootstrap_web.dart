import 'dart:developer';
import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:omninest/core/errors/error_message.dart';

/// JavaScript 层面抑制 CanvasKit engine 断言错误
void suppressCanvasKitErrors() {
  try {
    // ignore: avoid_web_libraries_in_flutter
    final script = web.document.createElement('script');
    script.textContent = '''
      (function() {
        var orig = window.onerror;
        window.onerror = function(msg, src, line, col, err) {
          if (typeof msg === 'string' && (msg.indexOf('_handledContextLostEvent') !== -1 || msg.indexOf('LateInitializationError') !== -1)) {
            return true;
          }
          if (orig) return orig.apply(this, arguments);
          return false;
        };
      })();
    ''';
    // ignore: avoid_web_libraries_in_flutter
    web.document.body?.append(script);
  } catch (_) {}
}

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
