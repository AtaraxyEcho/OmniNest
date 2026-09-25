// 防止 CanvasKit WebGL context lost 导致崩溃
// 当 GPU 资源被浏览器回收时，阻止默认行为并尝试恢复
window.addEventListener('webglcontextlost', function(e) {
  e.preventDefault();
  console.warn('[OmniNest] WebGL context lost, attempting recovery...');
  setTimeout(function() {
    var canvas = document.querySelector('canvas');
    if (canvas) {
      var gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
      if (gl && gl.isContextLost()) {
        var ext = gl.getExtension('WEBGL_lose_context');
        if (ext) ext.restoreContext();
      }
    }
  }, 1000);
}, false);
