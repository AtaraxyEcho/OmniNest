// 抑制 CanvasKit 引擎层的 JS 侧报错：WebGL 上下文丢失后的 _handledContextLostEvent
// 与 LateInitializationError 属于已知噪声，Dart 侧的 FlutterError/PlatformDispatcher
// 处理器覆盖不到它们（那两个回调只收 Dart 异常）。
//
// 默认静默；将 window.OMNINEST_LOG_ENGINE_NOISE = true 可在 console 保留被吞消息，
// 便于排查是否误伤真实回归。
//
// 该文件必须是外部脚本：后端 CSP 为 script-src 'self' 'wasm-unsafe-eval'，
// 由 Dart 注入内联 script.textContent 会被浏览器拒绝执行。
(function () {
  var orig = window.onerror;
  window.onerror = function (msg, src, line, col, err) {
    var isNoise =
      typeof msg === 'string' &&
      (msg.indexOf('_handledContextLostEvent') !== -1 ||
        msg.indexOf('LateInitializationError') !== -1);
    if (isNoise) {
      if (window.OMNINEST_LOG_ENGINE_NOISE) {
        console.warn('[omninest-engine-noise]', msg);
      }
      return true;
    }
    if (orig) return orig.apply(this, arguments);
    return false;
  };
})();
