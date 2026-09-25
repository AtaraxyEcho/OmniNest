import 'package:flutter/material.dart';

/// 视觉编辑调色盘预设色板与色相条。
///
/// 属用户可选全色相工具色，不进入 `app/theme` 禁紫扫描范围。
abstract final class MusicVisualSwatchColors {
  /// 调色盘弹窗底色。
  static const Color dialogBg = Color(0xFF111A20);

  /// 白灰系预设。
  static const Color white = Color(0xFFFFFFFF);
  static const Color silverLight = Color(0xFFDCE6E8);
  static const Color silver = Color(0xFFA8B8BD);
  static const Color silverMuted = Color(0xFF8DA2A7);

  /// 黑金系预设。
  static const Color goldSoft = Color(0xFFF2D986);
  static const Color goldMid = Color(0xFFD9B36C);
  static const Color goldDeep = Color(0xFFB08D57);

  /// 暖色系预设。
  static const Color amber = Color(0xFFF2C55C);
  static const Color peach = Color(0xFFF0A46B);
  static const Color coral = Color(0xFFE87878);
  static const Color rose = Color(0xFFDD4A4A);
  static const Color pink = Color(0xFFE97FA9);

  /// 冷色系预设。
  static const Color teal = Color(0xFF72D6C9);
  static const Color green = Color(0xFF31C27C);
  static const Color sage = Color(0xFF83C982);
  static const Color sky = Color(0xFF58B7D9);
  static const Color azure = Color(0xFF4A90D9);
  static const Color indigo = Color(0xFF6F92E8);
  static const Color violet = Color(0xFFA78BE8);

  /// 预设色板：白灰、黑金、暖色、冷色四组。
  static const List<Color> presets = <Color>[
    white,
    silverLight,
    silver,
    silverMuted,
    goldSoft,
    goldMid,
    goldDeep,
    amber,
    peach,
    coral,
    rose,
    pink,
    teal,
    green,
    sage,
    sky,
    azure,
    indigo,
    violet,
  ];

  /// 色相条端点（HSV 全色相环，首尾闭合）。
  static const Color hueRed = Color(0xFFFF0000);
  static const Color hueYellow = Color(0xFFFFFF00);
  static const Color hueGreen = Color(0xFF00FF00);
  static const Color hueCyan = Color(0xFF00FFFF);
  static const Color hueBlue = Color(0xFF0000FF);
  static const Color hueMagenta = Color(0xFFFF00FF);

  /// 色相条渐变停点。
  static const List<Color> hueStops = <Color>[
    hueRed,
    hueYellow,
    hueGreen,
    hueCyan,
    hueBlue,
    hueMagenta,
    hueRed,
  ];
}
