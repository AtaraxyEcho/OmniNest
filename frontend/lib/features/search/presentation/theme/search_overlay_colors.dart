import 'package:flutter/material.dart';

/// 全局搜索命令面板的遮罩与提示片填充。
abstract final class SearchOverlayColors {
  /// 命令面板遮罩：深墨底，避免与工作台背景混在一起。
  static const Color barrier = Color(0x990D1117);

  /// 搜索提示片的实底色与弱化底色。
  static const Color hintTile = Color(0x0F1A1D1B);
  static const Color hintTileSoft = Color(0x0A1A1D1B);
}
