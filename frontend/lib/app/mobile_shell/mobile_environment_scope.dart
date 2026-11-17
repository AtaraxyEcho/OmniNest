import 'package:flutter/material.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';

/// 环境极性的唯一判定：外观设置（浅色/深色）就是极性源。
///
/// 壁纸不参与判定。设计基准只有一个全局极性开关，壁纸是被极性处理的一方：
/// 暗态把照片压暗，浅态按档降不透明度并叠一层纸色洗色，两态照片都仍透在画面上。
/// 让壁纸亮度覆盖这一档的后果是：只要设了壁纸，"浅色"就是空操作。
MobileEnvPalette mobileEnvPaletteFor(ThemeData theme) {
  return MobileEnvPalette.resolve(theme.brightness);
}

/// 给环境面子树注册当前极性对应的配色表。
///
/// 极性只在这里决定；空间根节点各包一次，避免每面重复 copyWith。
/// `ThemeData.copyWith(extensions:)` 是整体替换，因此必须带上既有扩展，
/// 否则模块调色板会丢。
///
/// 需要恒暗的沉浸媒体面（照片查看器、视频播放器）不走这里，而是在自己的
/// 子树里显式注册 `MobileEnvPalette.dark`。
class MobileEnvironmentScope extends StatelessWidget {
  const MobileEnvironmentScope({
    required this.child,
    this.photographic = false,
    super.key,
  });

  /// 浅态下这一子树是否仍是摄影面。样例只把首页（`.home-space`）留在照片上，
  /// 媒体库/阅读/文件都换成纸面画布；暗态两档同表，此参数只在浅态生效。
  final bool photographic;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final palette = MobileEnvPalette.resolveFor(
      brightness: base.brightness,
      photographic: photographic,
    );
    return Theme(data: base.withEnvPalette(palette), child: child);
  }
}
