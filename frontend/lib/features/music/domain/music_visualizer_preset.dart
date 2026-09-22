/// 桌面播放详情页的三种布局预设：居左/居中/居右。
///
/// 布局决定主视觉（封面卡组）与歌词列的构图关系——居左时卡组在左、
/// 歌词列在右；居中时卡组居中扇形展开、歌词列居中收窄。
/// 领域层不依赖 Flutter，仅由坐标枚举表达构图。
enum PortalMusicLayout { left, center, right }

/// 歌词区域的呈现形态：滚动歌词（连续列表跟随当前行）或多行歌词（固定窗口）。
///
/// 形态属于设备级偏好（`MusicLocalPreferenceStore`），不进入跨端同步的视觉设置。
/// 排列规则按形态而非端：滚动歌词桌面端文本居左、移动端居中，多行歌词两端
/// 一律文本居中。
enum PortalLyricLayoutMode { scroll, multiline }

/// 歌词颜色画法：纯色或上下渐变（渐变时取两个颜色）。
enum LyricPaintMode { solid, verticalGradient }

/// 整段歌词字号的取值范围（px）。
const int _minLyricFontSizePx = 12;
const int _maxLyricFontSizePx = 32;

/// 多行形态在读行字号的取值范围（px）。
const int _minCurrentFontSizePx = 16;
const int _maxCurrentFontSizePx = 48;

/// 单个歌词颜色的取值：画法 + 两端颜色。
///
/// 领域层不依赖 Flutter，颜色以 ARGB 整数保存；纯色时 [secondary] 等于
/// [primary]。字段保持标量而不是列表，const 构造器才能由参数直接构造
///（const 列表的元素必须是常量，不能是构造参数）。
class LyricPaint {
  const LyricPaint({
    required this.mode,
    required this.primary,
    required this.secondary,
  });

  const LyricPaint.solid(int color)
    : mode = LyricPaintMode.solid,
      primary = color,
      secondary = color;

  const LyricPaint.vertical(int top, int bottom)
    : mode = LyricPaintMode.verticalGradient,
      primary = top,
      secondary = bottom;

  factory LyricPaint.fromJson(Map<String, dynamic>? json, LyricPaint fallback) {
    if (json == null) {
      return fallback;
    }
    final mode =
        json['mode'] == 'verticalGradient'
            ? LyricPaintMode.verticalGradient
            : LyricPaintMode.solid;
    final raw = json['colors'];
    final colors = <int>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is num) {
          colors.add(entry.toInt());
        }
      }
    }
    if (colors.isEmpty) {
      return fallback;
    }
    if (mode == LyricPaintMode.verticalGradient) {
      return LyricPaint.vertical(
        colors.first,
        colors.length > 1 ? colors[1] : colors.first,
      );
    }
    return LyricPaint.solid(colors.first);
  }

  final LyricPaintMode mode;

  /// 纯色值或渐变上色。
  final int primary;

  /// 渐变下色（纯色时等于 [primary]）。
  final int secondary;

  bool get isGradient => mode == LyricPaintMode.verticalGradient;

  /// 参与渲染的颜色序列：纯色 1 个、上下渐变 2 个。
  List<int> get colors =>
      isGradient ? <int>[primary, secondary] : <int>[primary];

  LyricPaint copyWith({LyricPaintMode? mode, int? primary, int? secondary}) {
    return LyricPaint(
      mode: mode ?? this.mode,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'mode':
        mode == LyricPaintMode.verticalGradient ? 'verticalGradient' : 'solid',
    'colors': colors,
  };

  /// 值相等：用于判断用户是否改过默认色（默认纯白回落样例色）。
  @override
  bool operator ==(Object other) =>
      other is LyricPaint &&
      other.mode == mode &&
      other.primary == primary &&
      other.secondary == secondary;

  @override
  int get hashCode => Object.hash(mode, primary, secondary);
}

class PortalLyricVisualSettings {
  const PortalLyricVisualSettings({
    required this.enabled,
    required this.translationEnabled,
    required this.wordFillEnabled,
    required this.fontSizePx,
    required this.currentFontSizePx,
    required this.inactiveOpacity,
    required this.visibleLines,
    required this.lineSpacing,
    required this.currentPaint,
    required this.inactivePaint,
    required this.breathingEnabled,
    required this.offsetMs,
    required this.focusAnchor,
    required this.focusBandEnabled,
    required this.layout,
    this.activeLineBackgroundEnabled = true,
    this.activeFontScale = 1,
    this.inactiveFontScale = 1,
  });

  factory PortalLyricVisualSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return defaults;
    }
    return PortalLyricVisualSettings(
      enabled: json['enabled'] as bool? ?? true,
      translationEnabled:
          json['translationEnabled'] as bool? ?? defaults.translationEnabled,
      wordFillEnabled:
          json['wordFillEnabled'] as bool? ?? defaults.wordFillEnabled,
      fontSizePx: _normalizeFontSizePx(
        json['fontSizePx'],
        legacyPreset: json['fontSize'],
        fallback: defaults.fontSizePx,
        min: _minLyricFontSizePx,
        max: _maxLyricFontSizePx,
      ),
      currentFontSizePx: _normalizeFontSizePx(
        json['currentFontSizePx'],
        legacyScale: json['currentFontScale'],
        fallback: defaults.currentFontSizePx,
        min: _minCurrentFontSizePx,
        max: _maxCurrentFontSizePx,
      ),
      inactiveOpacity: _readDouble(
        json['inactiveOpacity'],
        defaults.inactiveOpacity,
      ),
      visibleLines: _normalizeLyricVisibleLines(json['visibleLines']),
      lineSpacing:
          _readDouble(
            json['lineSpacing'],
            defaults.lineSpacing,
          ).clamp(0.75, 1.65).toDouble(),
      currentPaint: _readCurrentPaint(json),
      inactivePaint: _readInactivePaint(json),
      breathingEnabled: json['breathingEnabled'] as bool? ?? true,
      offsetMs:
          (json['offsetMs'] as num?)?.toInt().clamp(-1000, 1000) ??
          defaults.offsetMs,
      focusAnchor:
          _readDouble(
            json['focusAnchor'],
            defaults.focusAnchor,
          ).clamp(0.35, 0.65).toDouble(),
      focusBandEnabled:
          json['focusBandEnabled'] as bool? ?? defaults.focusBandEnabled,
      layout: _parseLayout(json['layout'], legacyPosition: json['position']),
      // 在读行底衬背景（样例的黑色高亮带）开关，默认开启。
      activeLineBackgroundEnabled:
          json['activeLineBackgroundEnabled'] as bool? ?? true,
      activeFontScale:
          _readDouble(
            json['activeFontScale'],
            defaults.activeFontScale,
          ).clamp(0.6, 1.6).toDouble(),
      inactiveFontScale:
          _readDouble(
            json['inactiveFontScale'],
            defaults.inactiveFontScale,
          ).clamp(0.6, 1.6).toDouble(),
    );
  }

  /// 在读色（当前行）读取顺序：v7 `currentPaint` → v6 `readPaint` →
  /// 旧三色模型的当前行色（含渐变开关）。
  static LyricPaint _readCurrentPaint(Map<String, dynamic> json) {
    final paint = _readMap(json['currentPaint'] ?? json['readPaint']);
    if (paint != null) {
      return LyricPaint.fromJson(paint, defaults.currentPaint);
    }
    final legacyActive = _readColorValue(
      json['activeColorValue'] ?? json['textColorValue'],
      defaults.currentPaint.primary,
    );
    if (json['gradientEnabled'] == true) {
      return LyricPaint.vertical(
        _readColorValue(json['gradientTopColorValue'], legacyActive),
        _readColorValue(json['gradientBottomColorValue'], legacyActive),
      );
    }
    return LyricPaint.solid(legacyActive);
  }

  /// 非当前句色读取顺序：v7 `inactivePaint` → v6 `unreadPaint` →
  /// 旧三色模型的未读色。
  static LyricPaint _readInactivePaint(Map<String, dynamic> json) {
    final paint = _readMap(json['inactivePaint'] ?? json['unreadPaint']);
    if (paint != null) {
      return LyricPaint.fromJson(paint, defaults.inactivePaint);
    }
    return LyricPaint.solid(
      _readColorValue(json['unreadColorValue'], defaults.inactivePaint.primary),
    );
  }

  static const defaults = PortalLyricVisualSettings(
    enabled: true,
    // 译文行默认显示：平台返回独立译文时在原文下方渲染。
    translationEnabled: true,
    // 逐字填充默认开启：仅当平台实际返回词级数据（网易云 yrc）时生效，
    // 无词级数据的行始终整行读色。
    wordFillEnabled: true,
    // 字号以 px 表达（主流方案）：整段歌词 18px，多行形态在读行 30px。
    fontSizePx: 18,
    currentFontSizePx: 30,
    // 非当前句（已唱行与未唱行）统一按透明度压暗，主流默认半透明白。
    inactiveOpacity: 0.5,
    visibleLines: 3,
    lineSpacing: 1,
    // 两色模型（主流）：当前行满亮白色，其余行半透明白。
    currentPaint: LyricPaint.solid(0xFFFFFFFF),
    inactivePaint: LyricPaint.solid(0xFFFFFFFF),
    breathingEnabled: true,
    // 歌词时间轴校准默认 0：不做偏移，行为与历史一致。
    offsetMs: 0,
    // 焦点行锚点默认 0.44：略高于正中，与顶部标题的间距更协调（主流区间）。
    focusAnchor: 0.44,
    focusBandEnabled: false,
    // 桌面播放详情页默认布局居左：卡组在左、歌词列在右（用户确认的默认构图）。
    layout: PortalMusicLayout.left,
  );

  static const mineradioClassic = defaults;

  final bool enabled;

  /// 译文行显示开关：关闭时译文行不渲染，行槽预留相应减少。
  final bool translationEnabled;

  /// 逐字填充开关（仅滚动歌词形态）：关闭后即使平台返回词级数据，
  /// 在读行也整行用读色，不做逐字推进。
  final bool wordFillEnabled;

  /// 整段歌词字号（px，两种形态的所有歌词行都用它）。
  final int fontSizePx;

  /// 多行形态在读行字号（px）：滚动形态所有行同号，不使用该值。
  final int currentFontSizePx;

  /// 非当前句（已唱行与未唱行）的透明度。
  final double inactiveOpacity;
  final int visibleLines;
  final double lineSpacing;

  /// 在读色（含画法）：只作用于当前播放行。
  final LyricPaint currentPaint;

  /// 非当前句色（含画法）：已唱行与未唱行共用。
  final LyricPaint inactivePaint;
  final bool breathingEnabled;

  /// 歌词时间轴校准（毫秒）：正值表示歌词比音频晚，用于修正 LRC 时间戳偏差。
  final int offsetMs;

  /// 焦点行锚点：当前行在视口中的垂直位置（0.5 为正中，越小越靠上）。
  final double focusAnchor;

  /// 焦点带高亮：在焦点行后叠一层低强度横向提亮。
  final bool focusBandEnabled;

  /// 桌面播放详情页布局预设：居左/居中/居右（仅桌面沉浸舞台消费，
  /// 移动端播放页不使用该字段）。
  final PortalMusicLayout layout;

  /// 在读行底衬背景（样例的黑色高亮带）开关：关闭后只保留左侧强调条。
  final bool activeLineBackgroundEnabled;

  /// 在读行文字缩放（乘在样例字号上）：1.0 为样例原值。
  final double activeFontScale;

  /// 未读行文字缩放（乘在样例字号上）：1.0 为样例原值。
  final double inactiveFontScale;

  PortalLyricVisualSettings copyWith({
    bool? enabled,
    bool? translationEnabled,
    bool? wordFillEnabled,
    int? fontSizePx,
    int? currentFontSizePx,
    double? inactiveOpacity,
    int? visibleLines,
    double? lineSpacing,
    LyricPaint? currentPaint,
    LyricPaint? inactivePaint,
    bool? breathingEnabled,
    int? offsetMs,
    double? focusAnchor,
    bool? focusBandEnabled,
    PortalMusicLayout? layout,
    bool? activeLineBackgroundEnabled,
    double? activeFontScale,
    double? inactiveFontScale,
  }) {
    return PortalLyricVisualSettings(
      enabled: enabled ?? this.enabled,
      translationEnabled: translationEnabled ?? this.translationEnabled,
      wordFillEnabled: wordFillEnabled ?? this.wordFillEnabled,
      fontSizePx: fontSizePx ?? this.fontSizePx,
      currentFontSizePx: currentFontSizePx ?? this.currentFontSizePx,
      inactiveOpacity: inactiveOpacity ?? this.inactiveOpacity,
      visibleLines: visibleLines ?? this.visibleLines,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      currentPaint: currentPaint ?? this.currentPaint,
      inactivePaint: inactivePaint ?? this.inactivePaint,
      breathingEnabled: breathingEnabled ?? this.breathingEnabled,
      offsetMs: offsetMs ?? this.offsetMs,
      focusAnchor: focusAnchor ?? this.focusAnchor,
      focusBandEnabled: focusBandEnabled ?? this.focusBandEnabled,
      layout: layout ?? this.layout,
      activeLineBackgroundEnabled:
          activeLineBackgroundEnabled ?? this.activeLineBackgroundEnabled,
      activeFontScale: activeFontScale ?? this.activeFontScale,
      inactiveFontScale: inactiveFontScale ?? this.inactiveFontScale,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'translationEnabled': translationEnabled,
      'wordFillEnabled': wordFillEnabled,
      'fontSizePx': fontSizePx,
      'currentFontSizePx': currentFontSizePx,
      'inactiveOpacity': inactiveOpacity,
      'visibleLines': visibleLines,
      'lineSpacing': lineSpacing,
      'currentPaint': currentPaint.toJson(),
      'inactivePaint': inactivePaint.toJson(),
      'breathingEnabled': breathingEnabled,
      'offsetMs': offsetMs,
      'focusAnchor': focusAnchor,
      'focusBandEnabled': focusBandEnabled,
      'layout': layout.name,
      'activeLineBackgroundEnabled': activeLineBackgroundEnabled,
      'activeFontScale': activeFontScale,
      'inactiveFontScale': inactiveFontScale,
    };
  }
}

class PortalGlassPlayerSettings {
  const PortalGlassPlayerSettings({
    required this.enabled,
    required this.volumeEnabled,
    required this.progressEnabled,
  });

  factory PortalGlassPlayerSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return defaults;
    }
    // 旧版本存有 audioBarEnabled/audioBarStyle 字段：音频条已整体移除，
    // 这些键被静默忽略，不再进入设置模型。
    return PortalGlassPlayerSettings(
      enabled: json['enabled'] as bool? ?? true,
      volumeEnabled: json['volumeEnabled'] as bool? ?? true,
      progressEnabled: json['progressEnabled'] as bool? ?? true,
    );
  }

  static const defaults = PortalGlassPlayerSettings(
    enabled: true,
    volumeEnabled: true,
    progressEnabled: true,
  );

  final bool enabled;
  final bool volumeEnabled;
  final bool progressEnabled;

  PortalGlassPlayerSettings copyWith({
    bool? enabled,
    bool? volumeEnabled,
    bool? progressEnabled,
  }) {
    return PortalGlassPlayerSettings(
      enabled: enabled ?? this.enabled,
      volumeEnabled: volumeEnabled ?? this.volumeEnabled,
      progressEnabled: progressEnabled ?? this.progressEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'volumeEnabled': volumeEnabled,
      'progressEnabled': progressEnabled,
    };
  }
}

class PortalMusicVisualizerSettings {
  const PortalMusicVisualizerSettings({
    required this.lyrics,
    required this.player,
    this.deckEnabled = true,
  });

  factory PortalMusicVisualizerSettings.fromJson(Map<String, dynamic>? json) {
    // 旧 schema 的 spectrum / coverElements / coverParticles 键不再读取：
    // 频响与封面元素（含原始封面）已整体移除，载入时静默丢弃。
    return PortalMusicVisualizerSettings(
      lyrics: PortalLyricVisualSettings.fromJson(_readMap(json?['lyrics'])),
      player: PortalGlassPlayerSettings.fromJson(_readMap(json?['player'])),
      deckEnabled: json?['deckEnabled'] as bool? ?? true,
    );
  }

  static const defaults = PortalMusicVisualizerSettings(
    lyrics: PortalLyricVisualSettings.defaults,
    player: PortalGlassPlayerSettings.defaults,
  );

  final PortalLyricVisualSettings lyrics;
  final PortalGlassPlayerSettings player;

  /// 沉浸页封面堆叠卡片（含其下方音频参数胶囊）显隐。
  final bool deckEnabled;

  PortalMusicVisualizerSettings copyWith({
    PortalLyricVisualSettings? lyrics,
    PortalGlassPlayerSettings? player,
    bool? deckEnabled,
  }) {
    return PortalMusicVisualizerSettings(
      lyrics: lyrics ?? this.lyrics,
      player: player ?? this.player,
      deckEnabled: deckEnabled ?? this.deckEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'lyrics': lyrics.toJson(),
      'player': player.toJson(),
      'deckEnabled': deckEnabled,
    };
  }
}

class PortalMusicVisualizerPreferences {
  const PortalMusicVisualizerPreferences({
    this.schemaVersion = currentSchemaVersion,
    this.visual = PortalMusicVisualizerSettings.defaults,
  });

  static const int currentSchemaVersion = 15;

  factory PortalMusicVisualizerPreferences.fromJson(Map<String, dynamic> json) {
    final visual = _readMap(json['visual']) ?? _readLegacyVisual(json);
    return PortalMusicVisualizerPreferences(
      schemaVersion: currentSchemaVersion,
      visual: PortalMusicVisualizerSettings.fromJson(visual),
    );
  }

  final int schemaVersion;
  final PortalMusicVisualizerSettings visual;

  PortalMusicVisualizerPreferences copyWith({
    int? schemaVersion,
    PortalMusicVisualizerSettings? visual,
  }) {
    return PortalMusicVisualizerPreferences(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      visual: visual ?? this.visual,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'visual': visual.toJson(),
    };
  }
}

Map<String, dynamic>? _readLegacyVisual(Map<String, dynamic> json) {
  final selectedId = json['selectedPresetId']?.toString();
  final customPresets = json['customPresets'];
  if (selectedId == null || customPresets is! List) {
    return null;
  }
  for (final item in customPresets) {
    if (item is Map<String, dynamic> && item['id']?.toString() == selectedId) {
      return item;
    }
  }
  return null;
}

double _readDouble(Object? value, double fallback) {
  return value is num ? value.toDouble() : fallback;
}

int _normalizeLyricVisibleLines(Object? value) {
  final lines = (value as num?)?.toInt() ?? 3;
  return lines.clamp(1, 9).toInt();
}

int _readColorValue(Object? value, int fallback) {
  return value is num ? value.toInt() : fallback;
}

/// 读取布局预设；旧字段 `position`（v10，歌词列位置语义）按镜像迁移：
/// 旧"歌词居左"=卡组居右，旧"歌词居右"=卡组居左，居中不变。
PortalMusicLayout _parseLayout(Object? value, {Object? legacyPosition}) {
  if (value == null && legacyPosition != null) {
    return switch (legacyPosition.toString()) {
      'left' => PortalMusicLayout.right,
      'right' => PortalMusicLayout.left,
      _ => PortalMusicLayout.center,
    };
  }
  return PortalMusicLayout.values.firstWhere(
    (layout) => layout.name == value?.toString(),
    orElse: () => PortalMusicLayout.left,
  );
}

/// 读取 px 字号；缺失时按旧字段迁移：
/// 档位名（v9 ontSize）→ px，比例（v8 及更早 currentFontScale）→ px。
int _normalizeFontSizePx(
  Object? value, {
  Object? legacyPreset,
  Object? legacyScale,
  required int fallback,
  required int min,
  required int max,
}) {
  if (value is num) {
    return value.toInt().clamp(min, max);
  }
  final preset = legacyPreset?.toString();
  if (preset != null) {
    final migrated = switch (preset) {
      'small' => 16,
      'large' => 20,
      'extraLarge' => 22,
      _ => 18,
    };
    return migrated.clamp(min, max);
  }
  if (legacyScale is num) {
    // 旧模型：基准 19.5px × 1.59 的在读放大 × 比例 → 迁移到 px。
    return (19.5 * 1.59 * legacyScale.toDouble()).round().clamp(min, max);
  }
  return fallback;
}

Map<String, dynamic>? _readMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}
