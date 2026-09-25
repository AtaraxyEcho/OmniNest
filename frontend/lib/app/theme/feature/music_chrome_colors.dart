import 'package:flutter/material.dart';

/// Music 模块 chrome 配色：播放控件、迷你播放器、曲库封面网格与平台账号窗。
///
/// 沉浸播放器主配色见 `MusicImmersivePalette`；此处只承载散落在
/// 控件/卡片上的固定 chrome 色，业务组件不得再写十六进制字面量。
abstract final class MusicChromeColors {
  /// 亮青强调（进度、滑块激活、活跃图标）。
  static const Color tealAccent = Color(0xFF72D6C9);

  /// 略柔的青强调（播放条控件）。
  static const Color tealSoft = Color(0xFF79D6D2);

  /// 深青底（播放条背景）。
  static const Color tealDeep = Color(0xFF28676B);

  /// 深青面板底（滑块轨道、迷你播放器按钮）。
  static const Color tealPanel = Color(0xFF153C43);

  /// 金/米色强调（歌词高亮、封面描边）。
  static const Color gold = Color(0xFFF2D986);

  /// 金描边（封面网格，90% 不透明）。
  static const Color goldBorder = Color(0xE6F4D77E);

  /// 警示金（同步异常图标）。
  static const Color goldWarning = Color(0xFFF0CD76);

  /// 近白前景（播放条文字/图标）。
  static const Color nearWhite = Color(0xFFF7FCFC);

  /// 品牌红（破坏性操作、品牌标识）。
  static const Color brandRed = Color(0xFFC8353D);

  /// 平台品牌红（第三方登录）。
  static const Color platformRed = Color(0xFFEC4141);

  /// 柔红（封面网格破坏性悬停）。
  static const Color redSoft = Color(0xFFFF8F91);

  /// 柔红变体（曲目列表删除）。
  static const Color redSoftAlt = Color(0xFFF28C9A);

  /// 暗红（浅色模式破坏性文字）。
  static const Color redDeep = Color(0xFF9A3037);

  /// 柔红（深色模式破坏性文字）。
  static const Color redMuted = Color(0xFFF28C8C);

  /// 错误红（搜索面板错误提示）。
  static const Color redError = Color(0xFFFFB4AB);

  /// 深色面板底（音量面板、迷你播放器浮层）。
  static const Color panelBackground = Color(0xF00E151B);

  /// 曲库操作条底色。
  static const Color actionBarBg = Color(0xFF1D252A);

  /// 封面网格卡片底色。
  static const Color coverCardBg = Color(0xFF11171B);

  /// 搜索浮层底色。
  static const Color searchOverlayBg = Color(0xF20A1218);

  /// 沉浸遮罩底色。
  static const Color immersiveOverlayBg = Color(0xB812222A);

  /// 滑块未激活轨道。
  static const Color inactiveTrack = Color(0x29FFFFFF);

  /// 现在播放渐变遮罩起点。
  static const Color scrimStart = Color(0x33000000);

  /// 现在播放渐变遮罩终点。
  static const Color scrimEnd = Color(0xB3000000);

  /// 曲目行浅色模式次级文字。
  static const Color rowSubLight = Color(0xFF58605B);

  /// 曲目行深色模式次级文字。
  static const Color rowSubDark = Color(0xFFC4CCC8);

  /// 平台窗占位符灰。
  static const Color placeholder = Color(0xFF8A8A8E);

  /// 平台浅色弹层填充。
  static const Color lightSheetFill = Color(0xF2FFFFFF);

  /// 平台浅色品牌块。
  static const Color lightBrandTile = Color(0xFF17181B);

  /// 平台浅色图标底。
  static const Color lightIconBg = Color(0xFFF7F8F9);
}
