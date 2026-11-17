import 'package:flutter/material.dart';
import 'package:omninest/app/theme/control_tokens.dart';

/// 应用品牌 Logo 统一入口：登录页、门户页头、引导页、关于面板与关于
/// 对话框一律经由本组件展示，资源路径与解码尺寸集中在此管理。
///
/// 源图 [assetPath] 为 512px 透明底标记，按展示尺寸的低分辨率解码，
/// 避免整图进入内存。启动图标另用不透明深色底的 `assets/icon/icon.png`，
/// 两者只在各自场景使用。
class BrandLogo extends StatelessWidget {
  const BrandLogo({this.size = 40, this.radius = 12, super.key});

  /// 侧栏品牌尺寸与 [AppControlTokens.sidebarLogo*] 对齐的便捷构造。
  const BrandLogo.sidebar({super.key})
    : size = AppControlTokens.sidebarLogoSize,
      radius = AppControlTokens.sidebarLogoRadius;

  /// 资源文件路径；替换应用内 logo 时仅需覆盖该文件。
  static const String assetPath = 'assets/icon/brand_mark.png';

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
      ),
    );
  }
}
