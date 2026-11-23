import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/route/app_route_surface.dart';

/// 路由内容槽的环境底策略：壳层自持页与不透明沉浸页直接透传，其余按模块套环境面。
Widget routeSurface(String path, Widget child) {
  if (_shellOwnedPaths.contains(path) || _opaqueImmersivePaths.contains(path)) {
    return child;
  }

  // 移动壳层按全局环境模式继承（媒体 ambient/阅读 focus/其余 utility）；
  // 桌面端保持原有语义：照片/阅读静态快照、影视与系统页实底
  // （影视不透明底同时规避 Impeller 合成对角亮缝）。
  return AppRouteSurface.environmental(
    owner: 'route:$path',
    routePath: path,
    child: child,
  );
}

const Set<String> _shellOwnedPaths = <String>{
  '/portal',
  '/library',
  '/files',
  '/music',
  '/reader',
  '/reader/bookshelf',
  '/reader/stats',
  '/reader/admin',
  '/search',
};

/// 自带不透明画布/纸色底的沉浸式路由，跳过外层 `RouteEnvironmentSurface`，
/// 避免转场每帧额外叠加主题色底或触发双重合成。
const Set<String> _opaqueImmersivePaths = <String>{
  '/music/now-playing',
  '/reader/items/:itemId/chapters/:chapterId',
  '/reader/comics/:itemId/read',
  '/reader/pdfs/:itemId/read',
};
