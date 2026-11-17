import 'package:flutter/material.dart';

/// 媒体库首页的影像压色与控件填充。
///
/// 这些色值压在封面照片上，对比由影像自身提供，两极性保持同值，
/// 因此不进入随主题翻转的环境配色表。
abstract final class LibrarySpaceColors {
  /// 横幅左侧主压色渐变：起点到右侧淡出。
  static const Color bannerGradientStart = Color(0xC7050A09);
  static const Color bannerGradientEnd = Color(0x14050A09);

  /// 横幅底部压色，保证标题在亮照片上仍可读。
  static const Color bannerBottomStart = Color(0x8C040807);

  /// 影像上的眉标字色。
  static const Color eyebrowOnImage = Color(0xA1FFFFFF);

  /// 详情面板遮罩。
  static const Color panelScrim = Color(0x80060B0A);

  /// 缩略图底部淡出。
  static const Color thumbnailFadeEnd = Color(0x66000000);

  /// 影像上的半透明控件底。
  static const Color controlFill = Color(0x3DFFFFFF);
}
