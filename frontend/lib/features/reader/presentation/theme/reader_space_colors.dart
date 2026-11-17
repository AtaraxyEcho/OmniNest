import 'package:flutter/material.dart';

/// 阅读空间封面与设置面板的固定色。
///
/// 书轨封面是纸色插画，两极性同值；设置面板的滑轨阴影同理，
/// 不随主题翻转。
abstract final class ReaderSpaceColors {
  /// 无封面时的纸封三色轮换：纸色与首字母墨色。
  static const List<(Color, Color)> coverPaperPalette = [
    (Color(0xFFC9B97F), Color(0xFF2B2924)),
    (Color(0xFF8F988D), Color(0xFF161C19)),
    (Color(0xFFC4AEA2), Color(0xFF2B2924)),
  ];

  /// 纸封书脊高光。
  static const Color coverSpineHighlight = Color(0x29FFFFFF);

  /// 设置面板浅态旋钮投影。
  static const Color knobShadow = Color(0x401A1D1B);
}
