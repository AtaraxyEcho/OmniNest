import 'package:flutter/material.dart';
import 'package:omninest/app/theme/control_tokens.dart';

/// 应用品牌 Logo 统一入口：登录页、门户页头、引导页、关于面板与关于
/// 对话框一律经由本组件展示，资源路径与解码尺寸集中在此管理。
///
/// 源图 [assetPath] 为 2048px 启动图标源文件，按展示尺寸的低分辨率
/// 解码，避免整图进入内存。
class BrandLogo extends StatelessWidget {
  const BrandLogo({this.size = 40, this.radius = 12, super.key});

  /// 侧栏品牌尺寸与 [AppControlTokens.sidebarLogo*] 对齐的便捷构造。
  const BrandLogo.sidebar({super.key})
    : size = AppControlTokens.sidebarLogoSize,
      radius = AppControlTokens.sidebarLogoRadius;

  /// 资源文件路径；替换正式 logo 时仅需覆盖该文件。
  static const String assetPath = 'assets/icon/icon.png';

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
