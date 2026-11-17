// CanvasKit 的 WebGL context 丢失时阻止默认行为，再交给引擎标准流程恢复。
// 重复 lost 事件若各自申请恢复，会反复重传全量纹理并推高 GPU 内存，
// 因此兜底恢复必须有界且幂等，并暴露计数供内存排查读取。
(function () {
  var recovering = false;
  var attempts = 0;
  var maxAttempts = 3;
  window.__omninestContextLostCount = 0;
  window.__omninestContextRestoreCount = 0;

  window.addEventListener('webglcontextlost', function (e) {
    e.preventDefault();
    window.__omninestContextLostCount++;
    if (recovering || attempts >= maxAttempts) {
      return;
    }
    recovering = true;
    attempts++;
    setTimeout(function () {
      recovering = false;
      try {
        var canvas = document.querySelector('canvas');
        if (!canvas) {
          return;
        }
        var gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
        if (gl && gl.isContextLost()) {
          var ext = gl.getExtension('WEBGL_lose_context');
          if (ext) {
            ext.restoreContext();
            window.__omninestContextRestoreCount++;
          }
        }
      } catch (err) {
        console.warn('[OmniNest] WebGL context restore failed', err);
      }
    }, 1000 * attempts);
  }, false);

  window.addEventListener('webglcontextrestored', function () {
    recovering = false;
    attempts = 0;
  }, false);
})();
