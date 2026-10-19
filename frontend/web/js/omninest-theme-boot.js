// 引擎首帧之前定色。运行期的 BrowserThemeColorBinding 要等第一帧之后才生效，
// 浅色偏好用户在此之前看到的是深色系统栏与深色底。这里只能复现启动读取的
// 规则：设备级偏好优先，缺省跟随系统极性；登录后的远端偏好仍由 Dart 侧覆盖。
//
// 该文件必须是外部脚本：后端 CSP 为 script-src 'self' 'wasm-unsafe-eval'，
// 内联脚本会被浏览器拒绝执行。
(function () {
  var LIGHT = '#e9eee7';
  var DARK = '#0b1110';
  var mode = 'system';
  try {
    // SharedPreferences 的 Web 实现用 json.encode 落盘，字符串带引号。
    var stored =
      window.localStorage.getItem('flutter.appearance.device.theme_mode') ||
      window.localStorage.getItem('flutter.global_theme_mode');
    if (typeof stored === 'string') {
      stored = JSON.parse(stored);
    }
    if (stored === 'light' || stored === 'dark' || stored === 'system') {
      mode = stored;
    }
  } catch (error) {
    // 禁用存储或隐私模式：按系统极性走。
  }
  var prefersLight =
    typeof window.matchMedia === 'function' &&
    window.matchMedia('(prefers-color-scheme: light)').matches;
  var isLight = mode === 'light' || (mode === 'system' && prefersLight);
  var color = isLight ? LIGHT : DARK;
  window.__omninestInitialThemeColor = color;
  document
    .getElementById('omninest-theme-color')
    .setAttribute('content', color);
  if (isLight) {
    document.documentElement.style.setProperty('--omninest-boot-bg', color);
  }
})();
