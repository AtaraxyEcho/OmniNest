import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/preferences/preference_sync_service.dart';

const desktopNpStylePreferenceScope = 'music_now_playing';

/// Now Playing 背景（样例 `NpStyle.tsx` 的 `bg`）：六档逐项对齐，
/// 默认 `aurora`，`library` 接壁纸库且仅写 `wallId` 不污染全局壁纸。
enum DesktopNpBackground { aurora, spectrum, library, cover, gradient, plain }

/// 旧版歌词笔刷枚举（保留用于旧 JSON 迁移与兼容引用）。
enum DesktopNpBrush { snow, gold, sakura, aqua, neon }

extension DesktopNpBrushColor on DesktopNpBrush {
  Color get color => switch (this) {
    DesktopNpBrush.snow => const Color(0xFFFFFFFF),
    DesktopNpBrush.gold => const Color(0xFFFFD670),
    DesktopNpBrush.sakura => const Color(0xFFFF9EC0),
    DesktopNpBrush.aqua => const Color(0xFF7FD9FF),
    DesktopNpBrush.neon => const Color(0xFFB583FF),
  };
}

/// 歌词字号档：样例 `S/M/L = .85 / 1 / 1.25`。
const List<double> desktopNpLyricScales = <double>[0.85, 1.0, 1.25];

/// 单个颜料区域（样例 `Zone`）：纯色或垂直渐变（`start -> end`）。
@immutable
class DesktopNpZone {
  const DesktopNpZone({
    required this.gradient,
    required this.start,
    required this.end,
  });

  const DesktopNpZone.solid(Color color)
    : gradient = false,
      start = color,
      end = color;

  const DesktopNpZone.gradient(this.start, this.end) : gradient = true;

  final bool gradient;
  final Color start;
  final Color end;

  Color get resolvedEnd => gradient ? end : start;

  LinearGradient toLinearGradient({double opacity = 1.0}) {
    final op = opacity.clamp(0.0, 1.0);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        start.withValues(alpha: start.a * op),
        resolvedEnd.withValues(alpha: resolvedEnd.a * op),
      ],
    );
  }

  DesktopNpZone copyWith({bool? gradient, Color? start, Color? end}) {
    return DesktopNpZone(
      gradient: gradient ?? this.gradient,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'g': gradient,
    'a': colorToHex(start),
    'b': colorToHex(end),
  };

  factory DesktopNpZone.fromJson(
    Object? raw, {
    DesktopNpZone fallback = const DesktopNpZone.solid(Color(0xFFFFFFFF)),
  }) {
    if (raw is! Map) return fallback;
    final a = parseHexColor(raw['a']?.toString()) ?? fallback.start;
    final b = parseHexColor(raw['b']?.toString()) ?? a;
    final g = raw['g'] == true;
    return DesktopNpZone(gradient: g, start: a, end: g ? b : a);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopNpZone &&
          gradient == other.gradient &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(gradient, start, end);
}

/// 歌词颜料模型（样例 `Paint`）：整行统一或上下分区（`split` + `splitPos`%）。
@immutable
class DesktopNpPaint {
  const DesktopNpPaint({
    required this.split,
    required this.splitPos,
    required this.top,
    required this.bottom,
  });

  const DesktopNpPaint.single(DesktopNpZone zone)
    : split = false,
      splitPos = 50,
      top = zone,
      bottom = zone;

  const DesktopNpPaint.halves({
    required this.top,
    required this.bottom,
    this.splitPos = 50,
  }) : split = true;

  final bool split;
  final int splitPos;
  final DesktopNpZone top;
  final DesktopNpZone bottom;

  Color get primaryColor => top.start;

  LinearGradient toLinearGradient({double opacity = 1.0}) {
    final op = opacity.clamp(0.0, 1.0);
    Color applyOp(Color c) => c.withValues(alpha: c.a * op);
    if (!split) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[applyOp(top.start), applyOp(top.resolvedEnd)],
      );
    }
    final pos = splitPos.clamp(10, 90) / 100.0;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: <double>[0.0, pos, pos, 1.0],
      colors: <Color>[
        applyOp(top.start),
        applyOp(top.resolvedEnd),
        applyOp(bottom.start),
        applyOp(bottom.resolvedEnd),
      ],
    );
  }

  Shader createShader(Rect rect, {double opacity = 1.0}) {
    return toLinearGradient(opacity: opacity).createShader(rect);
  }

  DesktopNpPaint copyWith({
    bool? split,
    int? splitPos,
    DesktopNpZone? top,
    DesktopNpZone? bottom,
  }) {
    return DesktopNpPaint(
      split: split ?? this.split,
      splitPos: splitPos ?? this.splitPos,
      top: top ?? this.top,
      bottom: bottom ?? this.bottom,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'split': split,
    'pos': splitPos,
    'top': top.toJson(),
    'bot': bottom.toJson(),
  };

  factory DesktopNpPaint.fromJson(
    Object? raw, {
    DesktopNpPaint fallback = const DesktopNpPaint.single(
      DesktopNpZone.solid(Color(0xFFFFFFFF)),
    ),
  }) {
    if (raw is! Map) return fallback;
    final top = DesktopNpZone.fromJson(raw['top'], fallback: fallback.top);
    final bot = DesktopNpZone.fromJson(raw['bot'], fallback: top);
    final split = raw['split'] == true;
    final pos = (raw['pos'] as num?)?.round().clamp(10, 90) ?? 50;
    return DesktopNpPaint(
      split: split,
      splitPos: pos,
      top: top,
      bottom: split ? bot : top,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopNpPaint &&
          split == other.split &&
          splitPos == other.splitPos &&
          top == other.top &&
          bottom == other.bottom;

  @override
  int get hashCode => Object.hash(split, splitPos, top, bottom);
}

/// 5 联宽矩形歌词颜料预设（样例 `PAINTS`：Snow / Gold / Sakura / Aqua / Neon）。
@immutable
class DesktopNpPaintPreset {
  const DesktopNpPaintPreset({required this.name, required this.paint});

  final String name;
  final DesktopNpPaint paint;

  static const List<DesktopNpPaintPreset> all = <DesktopNpPaintPreset>[
    DesktopNpPaintPreset(
      name: 'Snow',
      paint: DesktopNpPaint.single(DesktopNpZone.solid(Color(0xFFFFFFFF))),
    ),
    DesktopNpPaintPreset(
      name: 'Gold',
      paint: DesktopNpPaint.halves(
        top: DesktopNpZone.gradient(Color(0xFFFFF3C4), Color(0xFFFFE08A)),
        bottom: DesktopNpZone.gradient(Color(0xFFFFB347), Color(0xFFFF8A3D)),
      ),
    ),
    DesktopNpPaintPreset(
      name: 'Sakura',
      paint: DesktopNpPaint.halves(
        top: DesktopNpZone.solid(Color(0xFFFFF0F5)),
        bottom: DesktopNpZone.gradient(Color(0xFFFFB6D0), Color(0xFFFF7EB0)),
      ),
    ),
    DesktopNpPaintPreset(
      name: 'Aqua',
      paint: DesktopNpPaint.single(
        DesktopNpZone.gradient(Color(0xFFE0FBFF), Color(0xFF6FD6FF)),
      ),
    ),
    DesktopNpPaintPreset(
      name: 'Neon',
      paint: DesktopNpPaint.halves(
        top: DesktopNpZone.gradient(Color(0xFFF6A8FF), Color(0xFFB583FF)),
        bottom: DesktopNpZone.gradient(Color(0xFF7AD7FF), Color(0xFF4F8BFF)),
        splitPos: 45,
      ),
    ),
  ];
}

/// 6 联风格预设（样例 `PRESETS`）：联动背景 + 渐变起止色 + 歌词 `fillPaint`。
@immutable
class DesktopNpPreset {
  const DesktopNpPreset({
    required this.name,
    required this.top,
    required this.bottom,
    required this.isAuto,
    required this.fillPaint,
  });

  final String name;
  final Color top;
  final Color bottom;
  final bool isAuto;
  final DesktopNpPaint fillPaint;

  DesktopNpStyle applyTo(DesktopNpStyle current) {
    if (isAuto) {
      return current.copyWith(
        background: DesktopNpBackground.aurora,
        gradAuto: true,
        fillAuto: true,
        fillPaint: DesktopNpStyle.defaultPaint,
        basePaint: DesktopNpStyle.defaultPaint,
        baseOpacity: 32,
        mask: 0,
        blur: 0,
      );
    }
    return current.copyWith(
      background: DesktopNpBackground.gradient,
      gradAuto: false,
      gradStart: top,
      gradEnd: bottom,
      gradAngle: 180,
      fillAuto: false,
      fillPaint: fillPaint,
    );
  }

  static const List<DesktopNpPreset> all = <DesktopNpPreset>[
    DesktopNpPreset(
      name: 'Auto',
      top: Color(0xFF6F9A93),
      bottom: Color(0xFF0B1014),
      isAuto: true,
      fillPaint: DesktopNpPaint.single(DesktopNpZone.solid(Color(0xFFFFFFFF))),
    ),
    DesktopNpPreset(
      name: 'Sunset',
      top: Color(0xFFFF7E5F),
      bottom: Color(0xFF3A1C71),
      isAuto: false,
      fillPaint: DesktopNpPaint.halves(
        top: DesktopNpZone.gradient(Color(0xFFFFF1C9), Color(0xFFFFD29A)),
        bottom: DesktopNpZone.gradient(Color(0xFFFFA27A), Color(0xFFFF6F91)),
      ),
    ),
    DesktopNpPreset(
      name: 'Ocean',
      top: Color(0xFF2193B0),
      bottom: Color(0xFF0B132B),
      isAuto: false,
      fillPaint: DesktopNpPaint.halves(
        top: DesktopNpZone.solid(Color(0xFFE6FBFF)),
        bottom: DesktopNpZone.gradient(Color(0xFF8FE3FF), Color(0xFF4AA8FF)),
        splitPos: 55,
      ),
    ),
    DesktopNpPreset(
      name: 'Forest',
      top: Color(0xFF4F9D3A),
      bottom: Color(0xFF0A1A10),
      isAuto: false,
      fillPaint: DesktopNpPaint.single(
        DesktopNpZone.gradient(Color(0xFFEFFFD9), Color(0xFFA6E58A)),
      ),
    ),
    DesktopNpPreset(
      name: 'Rose',
      top: Color(0xFFE0568A),
      bottom: Color(0xFF240D2E),
      isAuto: false,
      fillPaint: DesktopNpPaint.halves(
        top: DesktopNpZone.solid(Color(0xFFFFE3EE)),
        bottom: DesktopNpZone.gradient(Color(0xFFFFB3CF), Color(0xFFFF7AA8)),
      ),
    ),
    DesktopNpPreset(
      name: 'Mono',
      top: Color(0xFF3C4147),
      bottom: Color(0xFF080909),
      isAuto: false,
      fillPaint: DesktopNpPaint.single(DesktopNpZone.solid(Color(0xFFFFFFFF))),
    ),
  ];
}

/// 16 字段 Now Playing 外观模型，严格对齐样例 `NpStyle.tsx:26-29` `NP_DEFAULT`。
@immutable
class DesktopNpStyle {
  static const DesktopNpPaint defaultPaint = DesktopNpPaint.single(
    DesktopNpZone.solid(Color(0xFFFFFFFF)),
  );

  const DesktopNpStyle({
    this.background = DesktopNpBackground.aurora,
    this.wallId = 'b-env',
    this.mask = 0,
    this.blur = 0,
    this.gradAuto = true,
    this.gradStart = const Color(0xFF2A6F6A),
    this.gradEnd = const Color(0xFF0B1014),
    this.gradAngle = 180,
    this.wordFill = true,
    this.fillAuto = true,
    this.fillPaint = defaultPaint,
    this.basePaint = defaultPaint,
    this.baseOpacity = 32,
    this.lyricScale = 1.0,
    this.glow = true,
    this.lyricFade = 22,
  });

  /// 1. 背景模式（默认 `aurora`）。
  final DesktopNpBackground background;

  /// 2. 壁纸库所选壁纸 id（默认 `'b-env'`，仅作用于播放页，不修改全局壁纸）。
  final String wallId;

  /// 3. 遮罩暗度 0–80（%）。
  final double mask;

  /// 4. 背景模糊 0–40（px）。
  final double blur;

  /// 5. 渐变是否自动跟随封面色相。
  final bool gradAuto;

  /// 6. 自定义渐变起始色（默认 `#2A6F6A`）。
  final Color gradStart;

  /// 7. 自定义渐变结束色（默认 `#0B1014`）。
  final Color gradEnd;

  /// 8. 自定义渐变角度 0–360°（默认 `180`）。
  final double gradAngle;

  /// 9. 是否开启逐字填充。
  final bool wordFill;

  /// 10. 当前行歌词颜料是否跟随封面色相。
  final bool fillAuto;

  /// 11. 当前行（已唱）双区颜料（`fp`）。
  final DesktopNpPaint fillPaint;

  /// 12. 其余行（未唱底层）双区颜料（`bp`）。
  final DesktopNpPaint basePaint;

  /// 13. 其余行不透明度 8–100（%，默认 `32`）。
  final int baseOpacity;

  /// 14. 歌词字号倍率（0.85 / 1.0 / 1.25）。
  final double lyricScale;

  /// 15. 当前行光晕开关。
  final bool glow;

  /// 16. 歌词上下渐隐高度 0–40（%，默认 `22`）。
  final int lyricFade;

  Color effectiveGradStart(Color hueColor) => gradAuto ? hueColor : gradStart;

  Color effectiveGradEnd(Color hueColor) =>
      gradAuto ? Color.lerp(const Color(0xFF05070A), hueColor, 0.18)! : gradEnd;

  DesktopNpPaint effectiveFillPaint(Color hueColor) {
    if (!fillAuto) return fillPaint;
    final auto = Color.lerp(Colors.white, hueColor, 0.45)!;
    return DesktopNpPaint.single(DesktopNpZone.solid(auto));
  }

  DesktopNpStyle copyWith({
    DesktopNpBackground? background,
    String? wallId,
    double? mask,
    double? blur,
    bool? gradAuto,
    Color? gradStart,
    Color? gradEnd,
    double? gradAngle,
    bool? wordFill,
    bool? fillAuto,
    DesktopNpPaint? fillPaint,
    DesktopNpPaint? basePaint,
    int? baseOpacity,
    double? lyricScale,
    bool? glow,
    int? lyricFade,
  }) {
    return DesktopNpStyle(
      background: background ?? this.background,
      wallId: wallId ?? this.wallId,
      mask: mask ?? this.mask,
      blur: blur ?? this.blur,
      gradAuto: gradAuto ?? this.gradAuto,
      gradStart: gradStart ?? this.gradStart,
      gradEnd: gradEnd ?? this.gradEnd,
      gradAngle: gradAngle ?? this.gradAngle,
      wordFill: wordFill ?? this.wordFill,
      fillAuto: fillAuto ?? this.fillAuto,
      fillPaint: fillPaint ?? this.fillPaint,
      basePaint: basePaint ?? this.basePaint,
      baseOpacity: baseOpacity ?? this.baseOpacity,
      lyricScale: lyricScale ?? this.lyricScale,
      glow: glow ?? this.glow,
      lyricFade: lyricFade ?? this.lyricFade,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'v': 4,
    'bg': background.name,
    'wallId': wallId,
    'mask': mask,
    'blur': blur,
    'gradAuto': gradAuto,
    'g1': colorToHex(gradStart),
    'g2': colorToHex(gradEnd),
    'angle': gradAngle,
    'wordFill': wordFill,
    'fillAuto': fillAuto,
    'fp': fillPaint.toJson(),
    'bp': basePaint.toJson(),
    'baseOp': baseOpacity,
    'size': lyricScale,
    'glow': glow,
    'fade': lyricFade,
  };

  factory DesktopNpStyle.fromJson(Map<String, Object?> json) {
    final bgName = json['bg']?.toString() ?? '';
    final normalizedBg = bgName == 'off' ? 'plain' : bgName;
    final background =
        DesktopNpBackground.values
            .where((v) => v.name == normalizedBg)
            .firstOrNull ??
        DesktopNpBackground.aurora;

    // 旧版 JSON 迁移：若不含 v4 的 `fp`/`bp`，则从旧的 `preset/brush/splitPaint/lowerBrush` 平滑迁移。
    final hasV4 =
        json.containsKey('fp') ||
        json.containsKey('bp') ||
        json.containsKey('gradAuto');

    if (!hasV4 &&
        (json.containsKey('brush') ||
            json.containsKey('preset') ||
            json.containsKey('splitPaint'))) {
      final presetIndex = (json['preset'] as num?)?.toInt().clamp(0, 5) ?? 0;
      final preset = DesktopNpPreset.all[presetIndex];
      final brushIndex = (json['brush'] as num?)?.toInt().clamp(0, 4) ?? 0;
      final lowerIndex = (json['lowerBrush'] as num?)?.toInt().clamp(0, 4) ?? 1;
      final split = json['splitPaint'] == true;
      final splitPos = (json['splitPos'] as num?)?.toInt().clamp(10, 90) ?? 50;
      final topZone = DesktopNpZone.solid(
        DesktopNpBrush.values[brushIndex].color,
      );
      final botZone = DesktopNpZone.solid(
        DesktopNpBrush.values[lowerIndex].color,
      );
      final migratedPaint =
          split
              ? DesktopNpPaint.halves(
                top: topZone,
                bottom: botZone,
                splitPos: splitPos,
              )
              : DesktopNpPaint.single(topZone);
      return DesktopNpStyle(
        background: background,
        wallId: json['wallId']?.toString() ?? 'b-env',
        mask: ((json['mask'] as num?)?.toDouble() ?? 0).clamp(0, 80),
        blur: ((json['blur'] as num?)?.toDouble() ?? 0).clamp(0, 40),
        gradAuto: presetIndex == 0,
        gradStart: presetIndex == 0 ? const Color(0xFF2A6F6A) : preset.top,
        gradEnd: presetIndex == 0 ? const Color(0xFF0B1014) : preset.bottom,
        gradAngle: 180,
        wordFill: json['wordFill'] != false,
        fillAuto: brushIndex == 0 && !split && presetIndex == 0,
        fillPaint: migratedPaint,
        basePaint: defaultPaint,
        baseOpacity: 32,
        lyricScale: ((json['lyricScale'] as num?)?.toDouble() ?? 1.0).clamp(
          0.85,
          1.25,
        ),
        glow: json['glow'] != false,
        lyricFade: 22,
      );
    }

    return DesktopNpStyle(
      background: background,
      wallId:
          (json['wallId']?.toString().isNotEmpty ?? false)
              ? json['wallId']!.toString()
              : 'b-env',
      mask: ((json['mask'] as num?)?.toDouble() ?? 0).clamp(0, 80),
      blur: ((json['blur'] as num?)?.toDouble() ?? 0).clamp(0, 40),
      gradAuto: json['gradAuto'] != false,
      gradStart:
          parseHexColor(json['g1']?.toString()) ?? const Color(0xFF2A6F6A),
      gradEnd: parseHexColor(json['g2']?.toString()) ?? const Color(0xFF0B1014),
      gradAngle: ((json['angle'] as num?)?.toDouble() ?? 180).clamp(0, 360),
      wordFill: json['wordFill'] != false,
      fillAuto: json['fillAuto'] != false,
      fillPaint: DesktopNpPaint.fromJson(json['fp'], fallback: defaultPaint),
      basePaint: DesktopNpPaint.fromJson(json['bp'], fallback: defaultPaint),
      baseOpacity: (json['baseOp'] as num?)?.round().clamp(8, 100) ?? 32,
      lyricScale:
          ((json['size'] ?? json['lyricScale']) as num?)?.toDouble().clamp(
            0.85,
            1.25,
          ) ??
          1.0,
      glow: json['glow'] != false,
      lyricFade: (json['fade'] as num?)?.round().clamp(0, 40) ?? 22,
    );
  }
}

/// 将颜色编码为标准 `#RRGGBB` 大写十六进制字符串。
String colorToHex(Color color) {
  final r = (color.r * 255)
      .round()
      .clamp(0, 255)
      .toRadixString(16)
      .padLeft(2, '0');
  final g = (color.g * 255)
      .round()
      .clamp(0, 255)
      .toRadixString(16)
      .padLeft(2, '0');
  final b = (color.b * 255)
      .round()
      .clamp(0, 255)
      .toRadixString(16)
      .padLeft(2, '0');
  return '#$r$g$b'.toUpperCase();
}

/// 解析 `#RGB` 或 `#RRGGBB` 字符串为不透明 [Color]。
Color? parseHexColor(String? raw) {
  if (raw == null) return null;
  var text = raw.trim();
  if (text.startsWith('#')) {
    text = text.substring(1);
  }
  if (text.length == 3 && RegExp(r'^[0-9a-fA-F]{3}$').hasMatch(text)) {
    text = '${text[0]}${text[0]}${text[1]}${text[1]}${text[2]}${text[2]}';
  }
  if (text.length != 6 || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(text)) {
    return null;
  }
  final value = int.tryParse(text, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

final desktopNpStyleProvider =
    NotifierProvider<DesktopNpStyleController, DesktopNpStyle>(
      DesktopNpStyleController.new,
    );

/// 正在播放页样式控制器：本地 SharedPreferences 快速加载，已认证时异步拉取
/// 服务端 `music_now_playing` 偏好合并，变更时防抖异步推送服务端。
class DesktopNpStyleController extends Notifier<DesktopNpStyle> {
  static const _key = 'omninest.desktop.npStyle';
  static const _syncDebounce = Duration(milliseconds: 300);

  bool _loaded = false;
  String? _activeUserId;
  String? _lastBoundUserId;
  int _loadGeneration = 0;
  Timer? _syncDebounceTimer;
  DesktopNpStyle? _pendingRemoteStyle;

  @override
  DesktopNpStyle build() {
    ref.onDispose(() {
      _syncDebounceTimer?.cancel();
      _syncDebounceTimer = null;
      _pendingRemoteStyle = null;
    });
    try {
      ref.listen(authSessionProvider, (_, next) {
        final userId = next.value?.user?.id;
        unawaited(_bindUser(userId));
      }, fireImmediately: true);
    } on Object {
      // 测试或离线环境未注入认证会话时静默回退本地偏好。
    }
    return const DesktopNpStyle();
  }

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
    await _writeLocal(next);
    _scheduleRemotePatch(next);
  }

  Future<void> reset() => apply(const DesktopNpStyle());

  /// 从远端重新同步正在播放页样式偏好，并保留本地待提交变更。
  Future<void> refreshFromRemote() async {
    final userId = _activeUserId;
    final service = _tryReadSyncService();
    if (userId == null || service == null) return;
    final snapshot = await service.synchronize(
      userId: userId,
      scope: desktopNpStylePreferenceScope,
    );
    if (_activeUserId != userId || snapshot.preferences.isEmpty) return;
    final resolved = DesktopNpStyle.fromJson(snapshot.preferences);
    state = resolved;
    await _writeLocal(resolved);
  }

  Future<void> _bindUser(String? userId) async {
    final previousUserId = _lastBoundUserId;
    _activeUserId = userId;
    final generation = ++_loadGeneration;
    await load();
    if (generation != _loadGeneration || _activeUserId != userId) {
      return;
    }
    if (userId == null) {
      _syncDebounceTimer?.cancel();
      _pendingRemoteStyle = null;
      return;
    }

    final service = _tryReadSyncService();
    if (service == null) {
      return;
    }
    try {
      final snapshot = await service.load(
        userId: userId,
        scope: desktopNpStylePreferenceScope,
      );
      if (generation != _loadGeneration || _activeUserId != userId) {
        return;
      }
      if (snapshot.preferences.isEmpty) {
        final switchedAccount =
            previousUserId != null && previousUserId != userId;
        _lastBoundUserId = userId;
        if (switchedAccount) {
          return;
        }
        await service.patch(
          userId: userId,
          scope: desktopNpStylePreferenceScope,
          changes: Map<String, dynamic>.from(state.toJson()),
        );
        return;
      }
      _lastBoundUserId = userId;
      final resolved = DesktopNpStyle.fromJson(snapshot.preferences);
      state = resolved;
      await _writeLocal(resolved);
    } on Object {
      // 离线或无同步依赖注入时静默保留本地偏好。
    }
  }

  void _scheduleRemotePatch(DesktopNpStyle next) {
    final userId = _activeUserId;
    if (userId == null) {
      return;
    }
    _pendingRemoteStyle = next;
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(_syncDebounce, () {
      unawaited(_flushRemotePatch(userId));
    });
  }

  Future<void> _flushRemotePatch(String userId) async {
    final pending = _pendingRemoteStyle;
    if (_activeUserId != userId || pending == null) {
      return;
    }
    _pendingRemoteStyle = null;
    final service = _tryReadSyncService();
    if (service == null) {
      return;
    }
    try {
      await service.patch(
        userId: userId,
        scope: desktopNpStylePreferenceScope,
        changes: Map<String, dynamic>.from(pending.toJson()),
      );
    } on Object {
      // 离线或远端失败时静默保留本地配置，由 pending 与下次同步收敛。
    }
  }

  PreferenceSyncService? _tryReadSyncService() {
    try {
      return ref.read(preferenceSyncServiceProvider);
    } on Object {
      return null;
    }
  }

  Future<void> _writeLocal(DesktopNpStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(style.toJson()));
  }
}
