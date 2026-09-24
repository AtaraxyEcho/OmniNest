{{flutter_js}}
{{flutter_build_config}}

// 资源基准跟随页面 <base href>（由 flutter build web --base-href 写入），
// 使构建产物既能部署在站点根，也能部署在反代子路径下；无 base 标签时退回根。
const baseHref =
  (document.querySelector('base') && document.querySelector('base').href) ||
  '/';

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: baseHref + 'canvaskit/',
  },
});
