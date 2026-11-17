import 'package:flutter/material.dart';

/// 曲目色相 → 展示色（样例 `Music.tsx:132` 的 `--hue`）。
///
/// 样例在曲目数据里直接给出 0-359 的 HSV hue，`.focus::before`、
/// `.deck-aura`、`.np-orb` 都从 `--hue` 取色。后端 `music_tracks.hue`
/// 尚未由扫描任务回填时为 null，此时回落到主题强调色；**禁止**用 id 哈希
/// 派生色相，那会撞进紫色域或产出荧光色，违反视觉优先原则。
Color desktopTrackHue(int? hue, Color fallback) {
  if (hue == null) {
    return fallback;
  }
  return HSVColor.fromAHSV(
    1,
    hue.clamp(0, 359).toDouble(),
    0.55,
    0.92,
  ).toColor();
}
