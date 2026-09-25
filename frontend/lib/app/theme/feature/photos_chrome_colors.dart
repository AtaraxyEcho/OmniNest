import 'package:flutter/material.dart';

/// 相册查看器 chrome 配色：信息面板、幻灯片遮罩、面板宿主与分享面板。
abstract final class PhotosChromeColors {
  /// 玻璃面板底色（近黑）。
  static const Color panelFill = Color(0xF00A0A0A);

  /// 白色叠层 8%（信息行分隔线）。
  static const Color white14 = Color(0x14FFFFFF);

  /// 白色叠层 15%（分隔/边框/底轨）。
  static const Color white12 = Color(0x12FFFFFF);

  /// 白色叠层 35%。
  static const Color white30 = Color(0x4DFFFFFF);

  /// 白色叠层 40%（图标按钮）。
  static const Color white40 = Color(0x66FFFFFF);

  /// 白色叠层 60%（信息行标签）。
  static const Color white59 = Color(0x59FFFFFF);

  /// 白色叠层 60%（信息面板胶囊前景）。
  static const Color white99 = Color(0x99FFFFFF);

  /// 白色叠层 75%（信息行数值）。
  static const Color whiteC0 = Color(0xC0FFFFFF);

  /// 白色叠层 90%（进度条前景）。
  static const Color whiteE6 = Color(0xE6FFFFFF);

  /// 白色叠层 92%（画廊遮罩）。
  static const Color whiteEB = Color(0xEBFFFFFF);

  /// 黑色遮罩 72%（幻灯片渐变端）。
  static const Color scrimB8 = Color(0xB8000000);

  /// 黑色遮罩 18%。
  static const Color scrim2E = Color(0x2E000000);

  /// 黑色遮罩 50%。
  static const Color scrim80 = Color(0x80000000);

  /// 黑色阴影 40%。
  static const Color shadow66 = Color(0x66000000);

  /// 分享面板深底。
  static const Color sharePanelBg = Color(0xFF1C1C1C);
}

/// 分享目标品牌色（系统/第三方渠道按钮）。
abstract final class ShareBrandColors {
  /// 微信绿。
  static const Color wechat = Color(0xFF07C160);

  /// 系统蓝。
  static const Color systemBlue = Color(0xFF007AFF);

  /// 系统灰。
  static const Color systemGray = Color(0xFF8E8E93);
}
