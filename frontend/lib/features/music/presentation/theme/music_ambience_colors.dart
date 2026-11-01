import 'package:flutter/material.dart';

/// 音乐沉浸播放器背景的两团环境光晕。
///
/// 属于播放器自己的视觉语言，不随全局主题扩展变化；玫瑰色落在紫色域，
/// 因此按禁紫规范留在功能层而不是 app/theme。
abstract final class MusicAmbienceColors {
  static const Color rose = Color(0x597E4880);
  static const Color teal = Color(0x57396469);
}
