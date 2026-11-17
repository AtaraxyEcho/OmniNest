import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Now Playing 背景（样例 `NpStyle.tsx` 的 `bg`）：六档逐项对齐，
/// `library` 接桌面已有的服务端壁纸库，`wallId` 记住选中的那一张。
enum DesktopNpBackground { cover, aurora, spectrum, library, gradient, plain }

/// 歌词笔刷（样例 `NpStyle.tsx` 的 5 套颜料）：Snow / Gold / Sakura / Aqua / Neon。
enum DesktopNpBrush { snow, gold, sakura, aqua, neon }

extension DesktopNpBrushColor on DesktopNpBrush {
  Color get color => switch (this) {
    DesktopNpBrush.snow => const Color(0xFFF4F7F5),
    DesktopNpBrush.gold => const Color(0xFFF2D36B),
    DesktopNpBrush.sakura => const Color(0xFFE8A6B8),
    DesktopNpBrush.aqua => const Color(0xFF7DBCC9),
    DesktopNpBrush.neon => const Color(0xFFA99BD8),
  };
}

/// 歌词字号档：样例 `S/M/L = .85/1/1.25`。
const List<double> desktopNpLyricScales = [0.85, 1.0, 1.25];

/// 渐变预设：索引对应面板里的六个色块，0 号跟随强调色。
class DesktopNpPreset {
  const DesktopNpPreset(this.top, this.bottom);

  final Color top;
  final Color bottom;

  static const List<DesktopNpPreset> all = [
    DesktopNpPreset(Color(0xFF2A6F6A), Color(0xFF0B1014)), // Auto（覆盖为强调色）
    DesktopNpPreset(Color(0xFFFF7E5F), Color(0xFF3A1C71)), // Sunset
    DesktopNpPreset(Color(0xFF2193B0), Color(0xFF0B132B)), // Ocean
    DesktopNpPreset(Color(0xFF4F9D3A), Color(0xFF0A1A10)), // Forest
    DesktopNpPreset(Color(0xFFE0568A), Color(0xFF240D2E)), // Rose
    DesktopNpPreset(Color(0xFF3C4147), Color(0xFF080909)), // Mono
  ];
}

@immutable
class DesktopNpStyle {
  const DesktopNpStyle({
    this.background = DesktopNpBackground.cover,
    this.preset = 0,
    this.mask = 0,
    this.blur = 0,
    this.lyricScale = 1,
    this.glow = true,
    this.wordFill = true,
    this.brush = 0,
    this.splitPaint = false,
    this.splitPos = 50,
    this.lowerBrush = 1,
    this.wallId,
  });

  final DesktopNpBackground background;
  final int preset;

  /// `library` 档选中的壁纸 id（样例 `NpStyle.tsx` 的 `wallId`）。
  final String? wallId;

  /// 遮罩暗度 0–80（%），映射到不超过 0.8 的黑层。
  final double mask;

  /// 背景模糊 0–40（sigma）。
  final double blur;

  final double lyricScale;
  final bool glow;

  /// 逐字填充（按当前行播放进度从左向右点亮）。
  final bool wordFill;

  /// 歌词笔刷索引，对应 [DesktopNpBrush]。
  final int brush;

  /// 上下半区分色（样例 `NpStyle.tsx` 的 `Paint.split`）。为真时当前行
  /// 上半用 [brush]、下半用 [lowerBrush]，分界在 [splitPos]%。
  final bool splitPaint;

  /// 上下半区分界位置 5–95（%）。
  final int splitPos;

  /// 下半区笔刷索引。
  final int lowerBrush;

  DesktopNpStyle copyWith({
    DesktopNpBackground? background,
    int? preset,
    double? mask,
    double? blur,
    double? lyricScale,
    bool? glow,
    bool? wordFill,
    int? brush,
    bool? splitPaint,
    int? splitPos,
    int? lowerBrush,
    String? wallId,
  }) {
    return DesktopNpStyle(
      background: background ?? this.background,
      preset: preset ?? this.preset,
      mask: mask ?? this.mask,
      blur: blur ?? this.blur,
      lyricScale: lyricScale ?? this.lyricScale,
      glow: glow ?? this.glow,
      wordFill: wordFill ?? this.wordFill,
      brush: brush ?? this.brush,
      splitPaint: splitPaint ?? this.splitPaint,
      splitPos: splitPos ?? this.splitPos,
      lowerBrush: lowerBrush ?? this.lowerBrush,
      wallId: wallId ?? this.wallId,
    );
  }

  Map<String, Object> toJson() => {
    'bg': background.name,
    'preset': preset,
    'mask': mask,
    'blur': blur,
    'lyricScale': lyricScale,
    'glow': glow,
    'wordFill': wordFill,
    'brush': brush,
    'splitPaint': splitPaint,
    'splitPos': splitPos,
    'lowerBrush': lowerBrush,
    if (wallId != null) 'wallId': wallId!,
  };

  factory DesktopNpStyle.fromJson(Map<String, Object?> json) {
    final bgName = json['bg']?.toString() ?? '';
    return DesktopNpStyle(
      background:
          DesktopNpBackground.values
              .where((v) => v.name == bgName)
              .firstOrNull ??
          DesktopNpBackground.cover,
      preset: (json['preset'] as num?)?.toInt().clamp(0, 5) ?? 0,
      mask: ((json['mask'] as num?)?.toDouble() ?? 0).clamp(0, 80),
      blur: ((json['blur'] as num?)?.toDouble() ?? 0).clamp(0, 40),
      lyricScale:
          (json['lyricScale'] as num?)?.toDouble().clamp(0.85, 1.25) ?? 1,
      glow: json['glow'] != false,
      wordFill: json['wordFill'] != false,
      brush: (json['brush'] as num?)?.toInt().clamp(0, 4) ?? 0,
      splitPaint: json['splitPaint'] == true,
      splitPos: (json['splitPos'] as num?)?.toInt().clamp(5, 95) ?? 50,
      lowerBrush: (json['lowerBrush'] as num?)?.toInt().clamp(0, 4) ?? 1,
      wallId: json['wallId']?.toString(),
    );
  }
}

final desktopNpStyleProvider =
    NotifierProvider<DesktopNpStyleController, DesktopNpStyle>(
      DesktopNpStyleController.new,
    );

/// 设备本地偏好：与桌面外观一致，只落 SharedPreferences。
class DesktopNpStyleController extends Notifier<DesktopNpStyle> {
  static const _key = 'omninest.desktop.npStyle';

  bool _loaded = false;

  @override
  DesktopNpStyle build() => const DesktopNpStyle();

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        state = DesktopNpStyle.fromJson(decoded);
      }
    } on FormatException {
      // 旧版本或手改坏的偏好直接回落到默认，不阻塞播放页。
    }
  }

  Future<void> apply(DesktopNpStyle next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(next.toJson()));
  }

  Future<void> reset() => apply(const DesktopNpStyle());
}
