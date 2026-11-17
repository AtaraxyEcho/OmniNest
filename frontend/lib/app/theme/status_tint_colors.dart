import 'package:flutter/material.dart';

/// 警示/危险状态的淡底与描边。
///
/// 用于状态丸与条件条，两极性保持同值；前景色仍走
/// [MobileEnvPalette.statusWarning]/[MobileEnvPalette.statusDanger]。
abstract final class StatusTintColors {
  static const Color warningFill = Color(0x1FD18A34);
  static const Color warningBorder = Color(0x47D18A34);
  static const Color dangerFill = Color(0x1FDA5050);
  static const Color dangerInk = Color(0xFFB95F5F);
}
